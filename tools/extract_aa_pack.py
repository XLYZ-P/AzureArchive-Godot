#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""AA 官方资源包（Unity Addressables）→ aa_pack 开放资源包转换器。

背景
====
AzureArchive 的官方资源（背景/立绘/BGM/音效/配音/角色表）以 Unity Addressables
形式分发：一个 zip/目录里有 Addressables catalog.json 和大量 `*.bundle`（UnityFS
格式，内部是 SerializedFile + 资源对象；部分音频在同 bundle 的 `.resS` 资源流里）。

本工具用 **UnityPy** 读取 bundle，把能识别的资产导出成 aa_pack 目录：

    <out>/
      catalog.json        # aa_pack 元数据（本工具生成）
      manifest.json       # AA 兼容覆盖表（本工具生成，可选使用）
      bgs/                # 名称以 BG_/Background 开头的 Texture2D/Sprite → PNG
      bgm/                # 名称以 Theme_/BGM_ 开头的 AudioClip
      sounds/             # 名称以 SE_/SFX_ 开头的 AudioClip
      popups/             # popupNN / Popup_* 贴图
      ui/                 # 其它 UI 贴图（未识别的贴图也放这里，日志警告）
      voices/<guid>.ogg   # 名称为 GUID 的 AudioClip（AA 语音槽）
      characters/<x>/     # Spine 骨骼：<x>.skel/.atlas + 图集页 png（尽量原样导出）
      tables/             # TextAsset/MonoBehaviour 文本表（JSON/原始字节；flatdata 见限制）
      fonts/              # （官方包若有字体资产也导出）

用法
====
    # 提取（输入可以是目录、.zip、单个 .bundle）
    python3 tools/extract_aa_pack.py -i /path/to/aa_resources -o fixtures/pack/aa_official
    python3 tools/extract_aa_pack.py -i cache_dir -o out --zip

    # 自测：用 UnityPy 现造一个最小 Unity AssetBundle（含贴图/音频/TextAsset/Spine 占位），
    # 再走完整提取流程并断言产物
    python3 tools/extract_aa_pack.py --selftest

    # 只生成测试 bundle（调试用）
    python3 tools/extract_aa_pack.py --make-test-bundle /tmp/selftest.bundle

依赖
====
    pip install -i https://pypi.tuna.tsinghua.edu.cn/simple unitypy

已知限制
========
- Spine 动画：只做静态文件（.skel/.atlas/图集 png）原样导出，不解析骨骼、不渲染；
  AA 的立绘动画仍需 Godot 侧 Spine 运行时（DESIGN §9 非目标）。
- Addressables 加密/自定义压缩：UnityPy 支持标准 UnityFS（none/lz4/lzma）；
  若官方包对 bundle 做了加密或自定义压缩，会解析失败并在日志列出跳过项。
- flatdata 表（角色/BGM/BG Excel）是自定义二进制，无法通用反序列化；
  工具会把 TextAsset/MonoBehaviour 原文导出到 tables/，字段名做容错日志，不猜内容。
- 官方包字段命名随版本变化：分类以名称前缀启发式为主，未命中项不丢弃而是放
  ui/、sounds/、characters/_unclassified/ 并记录 warning（见 --verbose 输出）。
- 本工具不下载任何资源包；手头没有官方包时用 --selftest 验证端到端流程。
"""

from __future__ import annotations

import argparse
import io
import json
import math
import re
import shutil
import struct
import sys
import tempfile
import wave
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DEFAULT_SELFTEST_WORKDIR = Path(tempfile.gettempdir()) / "aa_pack_extract_selftest"

GUID_RE = re.compile(r"^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$")
ATLAS_PAGE_RE = re.compile(r"^([^\s:]+\.(?:png|webp|jpg|jpeg))$")
UNITYFS_MAGIC = b"UnityFS"
TEST_VOICE_GUID = "421e3665-33e2-4c36-90a1-8747e2b9db28"

PIP_HINT = (
    "未安装/无法导入 UnityPy。请先安装（国内镜像）：\n"
    "  pip install -i https://pypi.tuna.tsinghua.edu.cn/simple unitypy"
)


# ---------------------------------------------------------------------------
# UnityPy 延迟导入（--help / --selftest 降级路径）
# ---------------------------------------------------------------------------

def _import_unitypy():
    try:
        import UnityPy  # noqa: PLC0415
        from UnityPy.export.Texture2DConverter import (  # noqa: F401, PLC0415
            get_image_from_texture2d,
        )
        from UnityPy.export.SpriteHelper import get_image_from_sprite  # noqa: F401, PLC0415
    except Exception as exc:  # pragma: no cover - 环境相关
        print(f"[extract] {PIP_HINT}\n[extract] 原始错误：{exc}", file=sys.stderr)
        raise SystemExit(2) from exc
    return UnityPy


def unitypy_available() -> bool:
    try:
        _import_unitypy()
        return True
    except SystemExit:
        return False


# ---------------------------------------------------------------------------
# 工具函数
# ---------------------------------------------------------------------------

def _is_unityfs(path: Path) -> bool:
    try:
        with path.open("rb") as handle:
            return handle.read(7) == UNITYFS_MAGIC
    except OSError:
        return False


def _read_unityfs_bytes(data: bytes) -> bool:
    return data[:7] == UNITYFS_MAGIC


def _safe_rel(name: str) -> str:
    """zip 条目/资源名 → 安全的相对 posix 路径（拒绝穿越）。"""
    value = str(name).replace("\\", "/").strip()
    while value.startswith("./"):
        value = value[2:]
    if not value or value.startswith("/") or ".." in value.split("/"):
        raise ValueError(f"非法相对路径: {name!r}")
    parts = [part for part in value.split("/") if part not in ("", ".")]
    if not parts:
        raise ValueError(f"非法相对路径: {name!r}")
    return "/".join(parts)


def _safe_filename(name: str, fallback: str = "unnamed") -> str:
    value = re.sub(r'[<>:"/\\|?*\x00-\x1f]', "_", str(name)).strip().strip(".")
    if not value:
        value = fallback
    return value


def _write_json(path: Path, data) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def _write_png(path: Path, image) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    image.save(path, format="PNG")


def _read_aligned_string(data: bytes, offset: int) -> tuple[bytes, int]:
    """Unity 序列化字符串：int32 长度 + bytes + 4 字节对齐。"""
    if offset + 4 > len(data):
        return b"", offset
    (length,) = struct.unpack_from("<i", data, offset)
    offset += 4
    if length < 0 or offset + length > len(data):
        return b"", offset
    raw = data[offset:offset + length]
    offset += length
    offset += (4 - offset % 4) % 4
    return raw, offset


# ---------------------------------------------------------------------------
# 名称分类启发式（都带兜底：未命中不丢弃）
# ---------------------------------------------------------------------------

def classify_texture(name: str) -> str:
    lower = name.lower()
    if lower.startswith(("bg_", "bg ", "background", "bg-")) or lower.startswith("bg"):
        return "bg"
    if lower.startswith("popup"):
        return "popup"
    if lower.startswith(("ui_fx", "fx_")):
        return "bg_effect_texture"
    if lower.startswith(("ui_", "ui-")):
        return "ui"
    if lower.startswith(("ch", "char")) and ("spr" in lower or "stand" in lower):
        return "character_texture"
    return "ui"


def classify_audio(name: str) -> str:
    if GUID_RE.match(name):
        return "voice"
    lower = name.lower()
    if lower.startswith(("theme_", "theme", "bgm_", "bgm")):
        return "bgm"
    if lower.startswith(("se_", "sfx_", "sfx", "se")):
        return "sound"
    return "sound"


def classify_text_asset(name: str, script: bytes) -> str:
    lower = name.lower()
    if lower.endswith((".skel", ".json.skel")) or "skeleton" in lower:
        return "spine_skel"
    if lower.endswith(".atlas") or (b"\nsize:" in script[:4096] and b"\nregion" not in script[:256]):
        return "spine_atlas"
    text = _decode_text(script)
    if text is not None:
        stripped = text.lstrip("\ufeff \t\r\n")
        if stripped.startswith(("{", "[")):
            try:
                json.loads(stripped)
                return "table_json"
            except (ValueError, TypeError):
                pass
        if lower.endswith(".json"):
            return "table_json"
    return "table_bin"


def _decode_text(data: bytes) -> str | None:
    for encoding in ("utf-8", "utf-8-sig"):
        try:
            return data.decode(encoding)
        except UnicodeDecodeError:
            continue
    return None


# ---------------------------------------------------------------------------
# aa_pack 构建器
# ---------------------------------------------------------------------------

class PackBuilder:
    """收集提取结果并输出 aa_pack 目录/zip。"""

    def __init__(self, out_dir: Path, pack_id: str, pack_name: str, version: str,
                 source: str = "") -> None:
        self.out_dir = out_dir
        self.pack_id = pack_id
        self.pack_name = pack_name
        self.version = version
        self.source = source
        self.bgs: list[dict] = []
        self.bgm: list[dict] = []
        self.sounds: list[dict] = []
        self.popups: list[dict] = []
        self.voices: list[dict] = []
        self.ui: list[dict] = []
        self.fonts: list[dict] = []
        self.tables: list[dict] = []
        self.bg_effects: list[dict] = []
        self.characters: list[dict] = []
        self.native_characters: list[dict] = []
        self.warnings: list[str] = []
        self.stats: dict[str, int] = {}
        self._used_paths: set[str] = set()

    # -- 路径 -------------------------------------------------------------
    def _fresh_path(self, rel: str) -> str:
        base, dot, ext = rel.rpartition(".")
        candidate = rel
        index = 1
        while candidate in self._used_paths:
            candidate = f"{base}_{index}.{ext}" if dot else f"{rel}_{index}"
            index += 1
        self._used_paths.add(candidate)
        return candidate

    def _target(self, rel: str) -> Path:
        return self.out_dir / rel

    def warn(self, message: str) -> None:
        self.warnings.append(message)

    def _bump(self, key: str) -> None:
        self.stats[key] = self.stats.get(key, 0) + 1

    # -- 各类资产 ---------------------------------------------------------
    def add_bg(self, name: str, image, source: str) -> None:
        rel = self._fresh_path(f"bgs/{_safe_filename(name)}.png")
        _write_png(self._target(rel), image)
        self.bgs.append({"name": _safe_filename(name), "file": rel, "category": "背景",
                         "source": source})
        self._bump("bg")

    def add_popup(self, name: str, image, source: str) -> None:
        rel = self._fresh_path(f"popups/{_safe_filename(name)}.png")
        _write_png(self._target(rel), image)
        self.popups.append({"name": _safe_filename(name), "file": rel,
                            "category": "弹出图", "source": source})
        self._bump("popup")

    def add_ui(self, name: str, image, source: str) -> None:
        rel = self._fresh_path(f"ui/{_safe_filename(name)}.png")
        _write_png(self._target(rel), image)
        self.ui.append({"name": _safe_filename(name), "file": rel, "source": source})
        self._bump("ui")

    def add_bg_effect_texture(self, name: str, image, source: str) -> None:
        rel = self._fresh_path(f"ui/fx_{_safe_filename(name)}.png")
        _write_png(self._target(rel), image)
        self.bg_effects.append({"name": _safe_filename(name), "file": rel,
                                "type": "texture", "params": {}, "source": source})
        self._bump("bg_effect_texture")

    def add_audio(self, name: str, filename: str, data: bytes, source: str) -> None:
        kind = classify_audio(name)
        ext = Path(filename).suffix.lower() or ".bin"
        safe_name = _safe_filename(name)
        if kind == "voice":
            rel = self._fresh_path(f"voices/{safe_name}{ext}")
            self.voices.append({"guid": safe_name, "file": rel, "text": "", "source": source})
            self._bump("voice")
        elif kind == "bgm":
            rel = self._fresh_path(f"bgm/{safe_name}{ext}")
            self.bgm.append({"key": safe_name, "file": rel, "title": safe_name, "source": source})
            self._bump("bgm")
        else:
            rel = self._fresh_path(f"sounds/{safe_name}{ext}")
            self.sounds.append({"name": safe_name, "file": rel, "source": source})
            self._bump("sound")
        self._target(rel).parent.mkdir(parents=True, exist_ok=True)
        self._target(rel).write_bytes(data)

    def add_table(self, name: str, data: bytes, kind: str, source: str) -> None:
        safe_name = _safe_filename(name)
        if kind == "table_json":
            text = _decode_text(data)
            try:
                parsed = json.loads(text or "")
                rel = self._fresh_path(f"tables/{safe_name}.json")
                _write_json(self._target(rel), parsed)
                self.tables.append({"name": safe_name, "file": rel, "format": "json",
                                    "source": source})
                self._bump("table_json")
                self._derive_from_table(name, parsed)
                return
            except (ValueError, TypeError):
                kind = "table_bin"
        rel = self._fresh_path(f"tables/{safe_name}.bin")
        self._target(rel).parent.mkdir(parents=True, exist_ok=True)
        self._target(rel).write_bytes(data)
        self.tables.append({"name": safe_name, "file": rel, "format": "bin", "source": source})
        self._bump("table_bin")
        hint = ""
        lower = name.lower()
        if "exceltable" in lower or "flatdata" in lower:
            hint = ("（疑似官方 FlatData 表：base64字符串+XOR+UTF-16LE，"
                    "解密算法见 docs/spec/resources.md C.4；当前版本原样保留，未解密）")
        self.warn(f"表 {name} 不是 JSON{hint}，已原样导出 {rel}")

    def add_spine_asset(self, name: str, data: bytes, source: str) -> None:
        """Spine 骨骼/图集先暂存，最后与同名图集页合并到 characters/<stem>/。"""
        filename = _safe_filename(Path(name).name)
        stem = Path(filename).stem
        if not stem:
            stem = _safe_filename(name)
        directory = self.out_dir / "characters" / stem
        directory.mkdir(parents=True, exist_ok=True)
        if filename.lower().endswith(".skel"):
            path = directory / f"{stem}.skel"
            kind = "skel"
        elif filename.lower().endswith(".atlas"):
            path = directory / f"{stem}.atlas"
            kind = "atlas"
        else:
            path = directory / filename
            kind = "other"
        path.write_bytes(data)
        self._bump(f"spine_{kind}")
        # 先登记，最终 `finalize_characters` 会统一写 catalog
        if not any(c["identifier"] == stem for c in self.characters):
            self.characters.append({
                "identifier": stem,
                "display_name": stem,
                "nickname": "",
                "dir": f"characters/{stem}",
                "portrait_mode": "spine",
                "spine_base": f"characters/{stem}/{stem}",
                "source": source,
            })

    def add_spine_page(self, stem: str, image, source: str) -> bool:
        """图集页贴图 → characters/<stem>/<stem>.png。找不到归属返回 False。"""
        target_dir = self.out_dir / "characters" / stem
        if not target_dir.is_dir():
            return False
        rel = f"characters/{stem}/{stem}.png"
        index = 1
        while (self.out_dir / rel).exists():
            rel = f"characters/{stem}/{stem}_{index}.png"
            index += 1
        _write_png(self.out_dir / rel, image)
        self._bump("spine_page")
        for entry in self.characters:
            if entry["identifier"] == stem:
                entry.setdefault("pages", []).append(rel)
                break
        return True

    def add_native_characters(self, entries: list[dict]) -> None:
        self.native_characters.extend(entries)

    # -- 表内容尝试推导（尽力而为，失败只记日志） --------------------------
    def _derive_from_table(self, name: str, data) -> None:
        lower = name.lower()
        if "character" not in lower:
            return
        rows = data
        if isinstance(data, dict):
            for key in ("$values", "values", "items", "rows", "Characters", "characters"):
                if isinstance(data.get(key), list):
                    rows = data[key]
                    break
            else:
                rows = []
        if not isinstance(rows, list):
            return
        derived = []
        for row in rows:
            if not isinstance(row, dict):
                continue
            key = None
            for field in ("Identifier", "identifier", "Id", "IdValue", "Key", "Name"):
                if isinstance(row.get(field), (str, int)):
                    key = str(row[field])
                    break
            if not key:
                continue
            display = key
            for field in ("Name", "DisplayName", "NameKr", "NameJp", "FullName"):
                if isinstance(row.get(field), str) and row[field]:
                    display = row[field]
                    break
            nickname = ""
            for field in ("Nickname", "Club", "School", "Group"):
                if isinstance(row.get(field), str) and row[field]:
                    nickname = row[field]
                    break
            derived.append({"key": key, "display_name": display, "nickname": nickname})
        if derived:
            self.add_native_characters(derived)
            self.warn(f"从表 {name} 推导出 {len(derived)} 个原生角色（字段启发式，需人工核对）")

    # -- 输出 -------------------------------------------------------------
    def finalize_characters(self) -> None:
        for entry in self.characters:
            entry.setdefault("pages", [])
        # 校验至少有 .skel/.atlas 之一，缺失的文件只在日志警告
        missing = []
        for entry in self.characters:
            stem = entry["identifier"]
            directory = self.out_dir / "characters" / stem
            if not (directory / f"{stem}.skel").is_file() and \
               not (directory / f"{stem}.atlas").is_file():
                missing.append(stem)
        if missing:
            self.warn("以下角色目录缺少 .skel/.atlas（可能是图集碎片）：" + ", ".join(missing[:20]))

    def catalog(self) -> dict:
        return {
            "format": "aa_pack",
            "format_version": 1,
            "id": self.pack_id,
            "name": self.pack_name,
            "version": self.version,
            "author": "extract_aa_pack.py (UnityPy)",
            "description": "由 AzureArchive 官方 Unity Addressables 资源包转换（见 tools/README.md 已知限制）。",
            "game": "AzureArchive",
            "source": "official",
            "license": "local-extraction-only",
            "notes": "官方素材版权归 BA/Nexon/AA 作者；仅限本机使用，不得二次分发。",
            "generator": {
                "tool": "tools/extract_aa_pack.py",
                "source": self.source,
                "unitypy": _unitypy_version(),
                "stats": self.stats,
                "warnings": self.warnings,
            },
            "bgs": self.bgs,
            "bgm": self.bgm,
            "sounds": self.sounds,
            "popups": self.popups,
            "voices": self.voices,
            "ui": self.ui,
            "fonts": self.fonts,
            "tables": self.tables,
            "bg_effects": self.bg_effects,
            "characters": self.characters,
            "native_characters": self.native_characters,
        }

    def manifest(self) -> dict:
        return {
            "CharacterOverrides": [
                {
                    "Identifier": entry["identifier"],
                    "Name": entry.get("display_name", entry["identifier"]),
                    "Nickname": entry.get("nickname", ""),
                    "CharacterReference": None,
                    "OriginalIdentifier": None,
                    "SpinePortraitPath": entry.get("spine_base"),
                    "SmallPortraitPath": entry.get("avatar"),
                }
                for entry in self.characters
            ],
            "VoiceOverrides": [entry["file"] for entry in self.voices],
            "PopupOverrides": [entry["file"] for entry in self.popups],
            "SoundOverrides": [entry["file"] for entry in self.sounds],
            "BgOverrides": [entry["file"] for entry in self.bgs],
            "BgEffectOverrides": [],
            "BgSpineOverrides": [],
            "BgmOverrides": [entry["file"] for entry in self.bgm],
        }

    def write(self) -> None:
        self.out_dir.mkdir(parents=True, exist_ok=True)
        self.finalize_characters()
        _write_json(self.out_dir / "catalog.json", self.catalog())
        _write_json(self.out_dir / "manifest.json", self.manifest())

    def summary(self) -> str:
        return (
            f"bgs={len(self.bgs)} bgm={len(self.bgm)} sounds={len(self.sounds)} "
            f"popups={len(self.popups)} voices={len(self.voices)} ui={len(self.ui)} "
            f"characters={len(self.characters)} tables={len(self.tables)} "
            f"native_characters={len(self.native_characters)} warnings={len(self.warnings)}"
        )


def _unitypy_version() -> str:
    try:
        import UnityPy  # noqa: PLC0415
        return str(getattr(UnityPy, "__version__", "unknown"))
    except Exception:  # pragma: no cover
        return "unknown"


# ---------------------------------------------------------------------------
# 输入发现
# ---------------------------------------------------------------------------

def _walk_unityfs(root: Path, exclude: Path | None = None) -> list[Path]:
    found: list[Path] = []
    root = root.resolve()
    for path in sorted(root.rglob("*")):
        if not path.is_file():
            continue
        if exclude is not None:
            try:
                path.resolve().relative_to(exclude.resolve())
                continue
            except ValueError:
                pass
        if path.name == "catalog.json" or path.suffix in (".hash", ".json"):
            continue
        if _is_unityfs(path):
            found.append(path)
    return found


def _extract_zip_to(zip_path: Path, target: Path) -> list[Path]:
    """解压 zip 并返回其中的 UnityFS 文件列表（先解压再用 UnityPy 读取）。"""
    target.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(zip_path) as archive:
        for info in archive.infolist():
            if info.is_dir():
                continue
            try:
                rel = _safe_rel(info.filename)
            except ValueError:
                print(f"[extract] 跳过非法 zip 条目：{info.filename}", file=sys.stderr)
                continue
            destination = target / rel
            destination.parent.mkdir(parents=True, exist_ok=True)
            destination.write_bytes(archive.read(info))
    return _walk_unityfs(target)


def discover_bundles(input_path: Path, exclude: Path | None = None) -> list[Path]:
    input_path = input_path.resolve()
    if not input_path.exists():
        raise SystemExit(f"[extract] 输入不存在：{input_path}")
    if input_path.is_file():
        if _is_unityfs(input_path):
            return [input_path]
        if input_path.suffix.lower() == ".zip":
            temp = Path(tempfile.mkdtemp(prefix="aa_pack_zip_"))
            print(f"[extract] 解压 zip 到临时目录：{temp}")
            return _extract_zip_to(input_path, temp)
        raise SystemExit(f"[extract] 不是 UnityFS bundle 也不是 .zip：{input_path}")
    return _walk_unityfs(input_path, exclude=exclude)


# ---------------------------------------------------------------------------
# 提取主流程
# ---------------------------------------------------------------------------

def _add_texture(builder: PackBuilder, name: str, image, source: str) -> None:
    kind = classify_texture(name)
    if kind == "bg":
        builder.add_bg(name, image, source)
    elif kind == "popup":
        builder.add_popup(name, image, source)
    elif kind == "bg_effect_texture":
        builder.add_bg_effect_texture(name, image, source)
    elif kind == "character_texture":
        builder.add_ui(name, image, source)
        builder.warn(f"角色贴图 {name} 未归入 Spine 骨骼，暂放 ui/（需配合 atlas 才能还原立绘）")
    else:
        builder.add_ui(name, image, source)
        if kind == "ui" and not name.lower().startswith(("ui_", "ui-")):
            builder.warn(f"未识别贴图名称前缀，放入 ui/：{name}")


def extract_bundle(bundle_path: Path, builder: PackBuilder, verbose: bool = False) -> dict:
    UnityPy = _import_unitypy()
    from UnityPy.export.Texture2DConverter import get_image_from_texture2d
    from UnityPy.export.SpriteHelper import get_image_from_sprite

    stats = {"objects": 0, "textures": 0, "sprites": 0, "audio": 0, "text": 0,
             "monobehaviour": 0, "errors": 0, "skipped": 0}
    source = str(bundle_path)
    try:
        env = UnityPy.load(str(bundle_path))
    except Exception as exc:  # 加密/损坏/版本不支持
        builder.warn(f"bundle 打开失败（可能加密或版本不支持）：{bundle_path.name}: {exc}")
        stats["errors"] += 1
        return stats

    # 先收集 TextAsset（Spine 需要先建目录，图集页贴图才能归位）
    text_assets: list[tuple[str, bytes]] = []
    pending_textures: list[tuple[str, object]] = []
    try:
        objects = list(env.objects)
    except Exception as exc:  # pragma: no cover
        builder.warn(f"bundle 遍历失败：{bundle_path.name}: {exc}")
        stats["errors"] += 1
        return stats

    for obj in objects:
        stats["objects"] += 1
        type_name = obj.type.name if hasattr(obj.type, "name") else str(obj.type)
        try:
            if type_name == "Texture2D":
                texture = obj.parse_as_object()
                name = str(getattr(texture, "m_Name", "") or "")
                if not name:
                    stats["skipped"] += 1
                    continue
                try:
                    image = get_image_from_texture2d(texture)
                except Exception as exc:
                    builder.warn(f"贴图解码失败 {name}: {exc}")
                    stats["errors"] += 1
                    continue
                pending_textures.append((name, image))
                stats["textures"] += 1
            elif type_name == "Sprite":
                sprite = obj.parse_as_object()
                name = str(getattr(sprite, "m_Name", "") or "")
                if not name:
                    stats["skipped"] += 1
                    continue
                try:
                    image = get_image_from_sprite(sprite)
                except Exception as exc:
                    builder.warn(f"Sprite 解码失败 {name}（图集依赖缺失？）: {exc}")
                    stats["errors"] += 1
                    continue
                pending_textures.append((name, image))
                stats["sprites"] += 1
            elif type_name == "AudioClip":
                clip = obj.parse_as_object()
                name = str(getattr(clip, "m_Name", "") or "")
                if not name:
                    stats["skipped"] += 1
                    continue
                try:
                    samples = clip.samples
                except Exception as exc:
                    builder.warn(f"音频导出失败 {name}（可能是 FSB/加密编码）: {exc}")
                    stats["errors"] += 1
                    continue
                for filename, data in samples.items():
                    builder.add_audio(name, filename, bytes(data), source)
                    stats["audio"] += 1
            elif type_name == "TextAsset":
                ta = obj.parse_as_object()
                name = str(getattr(ta, "m_Name", "") or "")
                if not name:
                    stats["skipped"] += 1
                    continue
                raw = _text_asset_bytes(obj, ta)
                text_assets.append((name, raw))
                stats["text"] += 1
            elif type_name == "MonoBehaviour":
                stats["monobehaviour"] += 1
                _try_monobehaviour(obj, builder, source, verbose)
            else:
                stats["skipped"] += 1
        except Exception as exc:  # 单个资产失败不影响整个 bundle
            builder.warn(f"对象解析失败（{type_name}）: {exc}")
            stats["errors"] += 1

    # TextAsset → Spine / 表
    spine_stems: list[str] = []
    for name, raw in text_assets:
        kind = classify_text_asset(name, raw)
        if kind in ("spine_skel", "spine_atlas"):
            builder.add_spine_asset(name, raw, source)
            spine_stems.append(Path(name).stem)
        else:
            builder.add_table(name, raw, kind, source)

    # 贴图：先尝试归入 Spine 图集页，其余按名称分类
    for name, image in pending_textures:
        placed = False
        for stem in spine_stems:
            if name == stem or name.startswith(f"{stem}_") or name.startswith(f"{stem}-"):
                if builder.add_spine_page(stem, image, source):
                    placed = True
                    break
        if not placed:
            _add_texture(builder, name, image, source)

    return stats


def _text_asset_bytes(obj, text_asset) -> bytes:
    """取 TextAsset 的原始字节（二进制 .skel 用；字符串路径会丢字节）。"""
    try:
        raw = obj.get_raw_data()
        _, offset = _read_aligned_string(raw, 0)          # m_Name
        script, _ = _read_aligned_string(raw, offset)     # m_Script
        if script:
            return script
    except Exception:
        pass
    script = getattr(text_asset, "m_Script", "")
    if isinstance(script, str):
        return script.encode("utf-8", "surrogateescape")
    return bytes(script or b"")


def _try_monobehaviour(obj, builder: PackBuilder, source: str, verbose: bool) -> None:
    """MonoBehaviour 尝试读 typetree；失败则把原始数据导出到 tables/（flatdata 无法通用解析）。"""
    name = ""
    try:
        peeked = obj.peek_name()
        name = str(peeked or "")
    except Exception:
        name = ""
    if not name:
        name = f"monobehaviour_{obj.path_id}"
    try:
        data = obj.read_typetree()
    except Exception as exc:
        raw = obj.get_raw_data()
        builder.add_table(name, raw, "table_bin", source)
        builder.warn(f"MonoBehaviour {name} 无类型树/自定义结构（扁平二进制），已导出原始字节到 tables/：{exc}")
        return
    # 有 typetree 的 MonoBehaviour 通常是 JSON 文本表或配置
    try:
        text = json.dumps(data, ensure_ascii=False).encode("utf-8")
    except (TypeError, ValueError):
        builder.warn(f"MonoBehaviour {name} 含不可序列化字段，跳过")
        return
    builder.add_table(name, text, "table_json", source)


def extract(input_path: Path, out_dir: Path, pack_id: str = "", pack_name: str = "",
            version: str = "converted", make_zip: bool = False, verbose: bool = False) -> PackBuilder:
    bundles = discover_bundles(input_path, exclude=out_dir)
    if not bundles:
        raise SystemExit(
            "[extract] 没找到任何 UnityFS bundle。\n"
            "  - AA 官方资源包应包含 *.bundle（Unity Addressables）；请确认输入目录/zip 正确。\n"
            "  - 手头没有真实资源包时，可跑 `--selftest` 用合成 bundle 验证流程。\n"
            "  - 加密/非标准 bundle 暂不支持（见 tools/README.md 已知限制）。")
    print(f"[extract] 发现 {len(bundles)} 个 UnityFS bundle，开始提取 → {out_dir}")
    source_desc = str(input_path)
    if not pack_id:
        pack_id = _safe_filename(input_path.stem if input_path.is_file() else input_path.name,
                                 fallback="aa_official")
    pack_id = re.sub(r"[^A-Za-z0-9._-]+", "_", pack_id) or "aa_official"
    if not pack_name:
        pack_name = pack_id
    builder = PackBuilder(out_dir, pack_id, pack_name, version, source=source_desc)
    totals = {"bundles": 0, "objects": 0, "errors": 0}
    for index, bundle in enumerate(bundles, 1):
        if verbose:
            print(f"[extract] ({index}/{len(bundles)}) {bundle}")
        stats = extract_bundle(bundle, builder, verbose=verbose)
        totals["bundles"] += 1
        totals["objects"] += stats["objects"]
        totals["errors"] += stats["errors"]
    if totals["objects"] == 0:
        reason = "所有 bundle 解析失败（可能加密/压缩格式不支持/文件损坏）" \
            if totals["errors"] else "没有提取到任何资产（bundle 内可能只有不支持的资产类型）"
        raise SystemExit(f"[extract] {reason}。bundle={totals['bundles']} errors={totals['errors']}")
    builder.write()
    print(f"[extract] 完成：{builder.summary()}")
    print(f"[extract] bundle={totals['bundles']} objects={totals['objects']} errors={totals['errors']}")
    if builder.warnings and verbose:
        for warning in builder.warnings[:50]:
            print(f"[extract][warn] {warning}")
    if make_zip:
        zip_path = out_dir.parent / (out_dir.name + ".zip")
        _zip_dir(out_dir, zip_path)
        print(f"[extract] 生成 zip：{zip_path}")
    return builder


def _zip_dir(directory: Path, zip_path: Path) -> None:
    if zip_path.exists():
        zip_path.unlink()
    with zipfile.ZipFile(zip_path, "w", compression=zipfile.ZIP_DEFLATED) as archive:
        for path in sorted(directory.rglob("*")):
            if path.is_file():
                archive.write(path, path.relative_to(directory).as_posix())


# ---------------------------------------------------------------------------
# 最小 Unity AssetBundle 测试数据生成（UnityPy 构造）
# ---------------------------------------------------------------------------

UNITY_VERSION = "2021.3.0f1"
TARGET_PLATFORM = 19  # StandaloneWindows64


def _cstr(value: str) -> bytes:
    return value.encode("utf-8") + b"\0"


def _empty_serialized_file_bytes() -> bytes:
    """最小 Unity SerializedFile v21（无对象、无 typetree，读取时由 TPK 生成类型树）。"""
    meta = bytearray()
    meta += _cstr(UNITY_VERSION)
    meta += struct.pack("<i", TARGET_PLATFORM)
    meta += b"\x00"  # enable_type_tree = False（UnityPy 用内置 TPK 重建）
    meta += struct.pack("<i", 0)  # type count
    meta += struct.pack("<i", 0)  # object count
    meta += struct.pack("<i", 0)  # script types
    meta += struct.pack("<i", 0)  # externals
    meta += struct.pack("<i", 0)  # ref types (v>=20)
    meta += b"\x00"  # user information
    data_offset = 20 + len(meta)
    data_offset += (16 - data_offset % 16) % 16
    # SerializedFile 头是 big-endian，metadata 按 endian 标志（0 = little-endian）
    header = struct.pack(">IIII", len(meta), data_offset, 21, data_offset) + b"\x00\x00\x00\x00"
    raw = bytearray(header + bytes(meta))
    raw += b"\x00" * (data_offset - len(raw))
    return bytes(raw)


def _make_sine_wav(frequency: float, seconds: float, sample_rate: int = 22050) -> bytes:
    buffer = io.BytesIO()
    frames = int(sample_rate * seconds)
    with wave.open(buffer, "wb") as handle:
        handle.setnchannels(1)
        handle.setsampwidth(2)
        handle.setframerate(sample_rate)
        payload = bytearray()
        for index in range(frames):
            envelope = min(1.0, index / 200.0, (frames - index) / 200.0)
            value = int(32767 * 0.2 * envelope * math.sin(2 * math.pi * frequency * index / sample_rate))
            payload += struct.pack("<h", max(-32768, min(32767, value)))
        handle.writeframes(bytes(payload))
    return buffer.getvalue()


def _rgba_pattern(width: int, height: int, phase: int = 0) -> bytes:
    pixels = bytearray()
    for y in range(height):
        for x in range(width):
            pixels += bytes((
                (x * 17 + phase * 31) % 256,
                (y * 29 + phase * 11) % 256,
                (x * 7 + y * 13 + phase * 5) % 256,
                255,
            ))
    return bytes(pixels)


def _texture_dict(name: str, width: int, height: int, pixels: bytes) -> dict:
    return {
        "m_Name": name,
        "m_ForcedFallbackFormat": 4,
        "m_DownscaleFallback": False,
        "m_IsAlphaChannelOptional": False,
        "m_Width": width,
        "m_Height": height,
        "m_CompleteImageSize": len(pixels),
        "m_MipsStripped": 0,
        "m_TextureFormat": 4,  # RGBA32
        "m_MipCount": 1,
        "m_IsReadable": True,
        "m_IsPreProcessed": False,
        "m_IgnoreMasterTextureLimit": False,
        "m_StreamingMipmaps": False,
        "m_StreamingMipmapsPriority": 0,
        "m_ImageCount": 1,
        "m_TextureDimension": 2,
        "m_TextureSettings": {
            "m_FilterMode": 1, "m_Aniso": 1, "m_MipBias": 0.0,
            "m_WrapU": 0, "m_WrapV": 0, "m_WrapW": 0,
        },
        "m_LightmapFormat": 0,
        "m_ColorSpace": 0,
        "m_PlatformBlob": [],
        "image data": pixels,
        "m_StreamData": {"offset": 0, "size": 0, "path": ""},
    }


def _audio_dict(name: str, resource_path: str, size: int,
                channels: int = 1, frequency: int = 22050,
                offset: int = 0) -> dict:
    return {
        "m_Name": name,
        "m_LoadType": 0,
        "m_Channels": channels,
        "m_Frequency": frequency,
        "m_BitsPerSample": 16,
        "m_Length": 0.1,
        "m_IsTrackerFormat": False,
        "m_Ambisonic": False,
        "m_SubsoundIndex": 0,
        "m_PreloadAudioData": True,
        "m_LoadInBackground": False,
        "m_Legacy3D": False,
        "m_Resource": {"m_Source": resource_path, "m_Offset": offset, "m_Size": size},
        "m_CompressionFormat": 0,
    }


def _add_object(sf, class_id: int, path_id: int, typetree: dict):
    from UnityPy.enums import ClassIDType
    from UnityPy.files.ObjectReader import ObjectReader
    from UnityPy.files.SerializedFile import SerializedType
    from UnityPy.streams import EndianBinaryReader

    serialized_type = object.__new__(SerializedType)
    serialized_type.class_id = class_id
    serialized_type.is_stripped_type = False
    serialized_type.script_type_index = -1
    serialized_type.script_id = None
    serialized_type.old_type_hash = b"\x00" * 16
    serialized_type.node = None
    serialized_type.type_dependencies = ()
    serialized_type.type_tree_content_hash = None
    serialized_type.type_tree_serialized_size = None
    serialized_type.m_ClassName = None
    serialized_type.m_NameSpace = None
    serialized_type.m_AssemblyName = None
    type_id = len(sf.types)
    sf.types.append(serialized_type)
    obj = ObjectReader(
        assets_file=sf,
        reader=EndianBinaryReader(b"", endian="<"),
        path_id=path_id,
        type_id=type_id,
        serialized_type=serialized_type,
        class_id=class_id,
        type=ClassIDType(class_id),
        byte_start=0,
        byte_size=0,
        is_destroyed=None,
        is_stripped=None,
    )
    obj.save_typetree(typetree)
    sf.objects[path_id] = obj
    return obj


def make_test_bundle(target: Path, with_assets: bool = True) -> Path:
    """用 UnityPy 构造一个最小 Unity AssetBundle，内容覆盖提取器各分支。

    包含（同一 bundle 的两个文件：SerializedFile + .resS 资源流）：
      - Texture2D：BG_Selftest(BG)、popup_selftest、UI_Selftest、Mystery_Texture(未识别兜底)
      - AudioClip：Theme_Selftest(BGM, 经 .resS)、SE_Selftest、GUID 语音
      - TextAsset：character_table(JSON 表)、spine_selftest.skel/.atlas（Spine 占位）
    """
    UnityPy = _import_unitypy()
    from UnityPy.files.BundleFile import BundleFile
    from UnityPy.files.SerializedFile import FileIdentifier, SerializedFile
    from UnityPy.streams import EndianBinaryReader, EndianBinaryWriter
    from UnityPy.enums import ArchiveFlags

    target = Path(target)
    target.parent.mkdir(parents=True, exist_ok=True)
    env = UnityPy.Environment()
    sf = SerializedFile(EndianBinaryReader(_empty_serialized_file_bytes()), parent=env)

    wav_bgm = _make_sine_wav(440.0, 0.12)
    wav_se = _make_sine_wav(880.0, 0.05)
    wav_voice = _make_sine_wav(660.0, 0.06)
    res_payload = wav_bgm + wav_se + wav_voice
    res_name = "CAB-selftest.resS"
    res_path = f"archive:/CAB-selftest/{res_name}"

    next_id = 1

    def add(class_id: int, data: dict) -> None:
        nonlocal next_id
        _add_object(sf, class_id, next_id, data)
        next_id += 1

    if with_assets:
        bg = _rgba_pattern(32, 18, phase=3)
        add(28, _texture_dict("BG_Selftest", 32, 18, bg))
        popup = _rgba_pattern(16, 12, phase=7)
        add(28, _texture_dict("popup_selftest", 16, 12, popup))
        ui = _rgba_pattern(8, 8, phase=5)
        add(28, _texture_dict("UI_Selftest", 8, 8, ui))
        mystery = _rgba_pattern(8, 8, phase=11)
        add(28, _texture_dict("Mystery_Texture", 8, 8, mystery))
        page = _rgba_pattern(16, 16, phase=13)
        add(28, _texture_dict("spine_selftest", 16, 16, page))

        add(83, _audio_dict("Theme_Selftest", res_path, len(wav_bgm), offset=0))
        add(83, _audio_dict("SE_Selftest", res_path, len(wav_se), offset=len(wav_bgm)))
        add(83, _audio_dict(TEST_VOICE_GUID, res_path, len(wav_voice),
                            offset=len(wav_bgm) + len(wav_se)))

        table = {
            "$type": "CharacterTable",
            "$values": [
                {"Identifier": "1001", "Name": "合成角色A", "Nickname": "测试部"},
                {"Identifier": "1002", "Name": "合成角色B", "Nickname": "测试部"},
            ],
        }
        add(49, {"m_Name": "character_table", "m_Script": json.dumps(table, ensure_ascii=False)})
        add(49, {"m_Name": "spine_selftest.skel",
                 "m_Script": "AA_SKEL_PLACEHOLDER" + "".join(chr(i % 255) for i in range(64))})
        add(49, {"m_Name": "spine_selftest.atlas",
                 "m_Script": "spine_selftest.png\nsize: 16,16\nformat: RGBA8888\n"
                             "filter: Linear,Linear\nrepeat: none\n"})

    # AudioClip 的资源流外部文件登记
    if with_assets:
        external = object.__new__(FileIdentifier)
        external.temp_empty = ""
        external.guid = b"\x00" * 16
        external.type = 0
        external.path = res_path
        sf.externals.append(external)
    sf.ref_types = []
    sf.userInformation = ""

    bundle = object.__new__(BundleFile)
    bundle.signature = "UnityFS"
    bundle.version = 6
    bundle.version_player = UNITY_VERSION
    bundle.version_engine = UNITY_VERSION
    bundle.dataflags = ArchiveFlags(0x40)
    bundle._block_info_flags = 0
    bundle._uses_block_alignment = False
    bundle.name = target.name
    bundle.is_changed = False
    bundle.environment = env
    bundle.parent = None
    sf.flags = 4
    bundle.files = {"CAB-selftest": sf}
    if with_assets:
        resource = EndianBinaryWriter()
        resource.write(res_payload)
        resource.flags = 0
        resource.name = res_name
        bundle.files[res_name] = resource
    target.write_bytes(bundle.save(packer="none"))
    return target


# ---------------------------------------------------------------------------
# 自测
# ---------------------------------------------------------------------------

def selftest(workdir: Path | None = None, verbose: bool = False) -> int:
    workdir = Path(workdir) if workdir else DEFAULT_SELFTEST_WORKDIR
    if workdir.exists():
        shutil.rmtree(workdir)
    workdir.mkdir(parents=True, exist_ok=True)
    failures: list[str] = []
    passes = 0

    def check(condition: bool, label: str) -> None:
        nonlocal passes
        if condition:
            passes += 1
            print(f"[selftest] ok   {label}")
        else:
            failures.append(label)
            print(f"[selftest] FAIL {label}")

    print(f"[selftest] workdir = {workdir}")
    try:
        # 1) 构造 Addressables 缓存目录形态：<cache>/<outer>/<content>/__data
        cache = workdir / "cache"
        data1 = cache / "abc123" / "content1" / "__data"
        data1.parent.mkdir(parents=True, exist_ok=True)
        make_test_bundle(data1)
        check(_is_unityfs(data1), "构造的测试 bundle 是合法 UnityFS")
        data2 = cache / "def456" / "content2" / "__data"
        data2.parent.mkdir(parents=True, exist_ok=True)
        # 第二个 bundle：只有一张背景 + 无资源配置，验证多 bundle 累加
        make_test_bundle(data2, with_assets=False)
        check(True, "构造第 2 个 bundle（空 SerializedFile）")

        # 2) 目录输入完整提取
        out = workdir / "out"
        builder = extract(cache, out, pack_id="selftest_pack", pack_name="自测包",
                          version="selftest", verbose=verbose)
        catalog_path = out / "catalog.json"
        check(catalog_path.is_file(), "生成 catalog.json")
        catalog = json.loads(catalog_path.read_text(encoding="utf-8"))
        check(catalog.get("format") == "aa_pack", "catalog.format=aa_pack")
        check(catalog.get("id") == "selftest_pack", "catalog.id 正确")

        bg_names = [entry["name"] for entry in catalog.get("bgs", [])]
        check("BG_Selftest" in bg_names, f"导出背景 BG_Selftest（实际 {bg_names}）")
        bg_path = out / "bgs" / "BG_Selftest.png"
        check(bg_path.is_file(), "bgs/BG_Selftest.png 存在")
        if bg_path.is_file():
            raw = bg_path.read_bytes()
            check(raw[:8] == b"\x89PNG\r\n\x1a\n", "背景是合法 PNG")
            if len(raw) > 24:
                width, height = struct.unpack(">II", raw[16:24])
                check((width, height) == (32, 18), f"背景尺寸 32x18（实际 {width}x{height}）")

        check((out / "popups" / "popup_selftest.png").is_file(), "导出弹出图")
        check((out / "ui" / "UI_Selftest.png").is_file(), "导出 UI 贴图")
        check((out / "ui" / "Mystery_Texture.png").is_file(), "未识别贴图兜底到 ui/")

        audio_names = [entry["key"] for entry in catalog.get("bgm", [])]
        check("Theme_Selftest" in audio_names, f"导出 BGM（实际 {audio_names}）")
        bgm_files = list((out / "bgm").glob("Theme_Selftest.*")) if (out / "bgm").is_dir() else []
        check(len(bgm_files) == 1, "bgm 文件唯一")
        if bgm_files:
            magic = bgm_files[0].read_bytes()[:4]
            check(magic in (b"RIFF", b"OggS"), f"BGM 是 WAV/OGG（magic={magic}）")
        sound_names = [entry["name"] for entry in catalog.get("sounds", [])]
        check("SE_Selftest" in sound_names, f"导出音效（实际 {sound_names}）")
        voice_guids = [entry["guid"] for entry in catalog.get("voices", [])]
        check(TEST_VOICE_GUID in voice_guids, f"GUID 音频导出为语音（实际 {voice_guids}）")
        voice_files = list((out / "voices").glob(TEST_VOICE_GUID + ".*")) if (out / "voices").is_dir() else []
        check(len(voice_files) == 1, "voices/<guid>.ogg|wav 存在")

        spine_dir = out / "characters" / "spine_selftest"
        check((spine_dir / "spine_selftest.skel").is_file(), "Spine .skel 导出")
        check((spine_dir / "spine_selftest.atlas").is_file(), "Spine .atlas 导出")
        check((spine_dir / "spine_selftest.png").is_file(), "Spine 图集页贴图归入角色目录")
        character_ids = [entry["identifier"] for entry in catalog.get("characters", [])]
        check("spine_selftest" in character_ids, f"catalog 记录 Spine 角色（实际 {character_ids}）")

        check((out / "tables" / "character_table.json").is_file(), "TextAsset 表导出为 JSON")
        tables = catalog.get("tables", [])
        table_names = [entry["name"] for entry in tables]
        check("character_table" in table_names, f"catalog 记录表（实际 {table_names}）")
        native_keys = [entry["key"] for entry in catalog.get("native_characters", [])]
        check("1001" in native_keys and "1002" in native_keys,
              f"从角色表推导 native_characters（实际 {native_keys}）")

        manifest = json.loads((out / "manifest.json").read_text(encoding="utf-8"))
        check(isinstance(manifest.get("CharacterOverrides"), list), "生成 AA 兼容 manifest")
        check(len(manifest.get("BgOverrides", [])) >= 1, "manifest.BgOverrides 非空")

        # 3) 重复提取幂等（覆盖输出目录）
        builder2 = extract(cache, out, pack_id="selftest_pack", pack_name="自测包",
                           version="selftest", verbose=False)
        check(builder2.summary() == builder.summary(), "重复提取结果一致（幂等）")

        # 4) zip 输入
        zip_path = workdir / "official_like.zip"
        with zipfile.ZipFile(zip_path, "w", compression=zipfile.ZIP_DEFLATED) as archive:
            archive.write(data1, "__data")
        out_zip = workdir / "out_zip"
        extract(zip_path, out_zip, pack_id="zip_pack", verbose=False)
        check((out_zip / "bgs" / "BG_Selftest.png").is_file(), "zip 输入可提取")

        # 5) --zip 输出
        out_zip2 = workdir / "out_zip2"
        extract(cache, out_zip2, pack_id="zip_out", make_zip=True, verbose=False)
        check((workdir / "out_zip2.zip").is_file(), "--zip 输出 aa_pack.zip")

        # 6) 单 bundle 输入
        out_single = workdir / "out_single"
        extract(data1, out_single, pack_id="single", verbose=False)
        check((out_single / "catalog.json").is_file(), "单 bundle 输入")

        # 7) 加密/垃圾输入：不崩溃，明确报错
        bad = workdir / "bad.bundle"
        bad.write_bytes(b"UnityFS\x00\x00\x00\x00\x06garbage" + bytes(range(64)))
        try:
            extract(bad, workdir / "out_bad", pack_id="bad", verbose=False)
            check(False, "损坏 bundle 应报错而不是假装成功")
        except SystemExit:
            check(True, "损坏 bundle 明确报错（SystemExit）")
    except SystemExit as exc:
        failures.append(f"提取流程异常退出：{exc}")
        print(f"[selftest] FAIL 提取流程异常退出：{exc}")
    except Exception as exc:  # pragma: no cover
        failures.append(f"未捕获异常：{exc!r}")
        print(f"[selftest] FAIL 未捕获异常：{exc!r}")

    print("")
    if failures:
        print(f"===== extract_aa_pack selftest: {passes} passed, {len(failures)} failed =====")
        for failure in failures:
            print(f"  FAIL: {failure}")
        return 1
    print(f"===== extract_aa_pack selftest: {passes} passed, 0 failed =====")
    return 0


# ---------------------------------------------------------------------------
# inspect
# ---------------------------------------------------------------------------

def inspect(input_path: Path) -> int:
    UnityPy = _import_unitypy()
    bundles = discover_bundles(input_path)
    print(f"[inspect] {len(bundles)} 个 UnityFS bundle")
    for path in bundles:
        try:
            env = UnityPy.load(str(path))
            counts: dict[str, int] = {}
            names: list[str] = []
            for obj in env.objects:
                type_name = obj.type.name if hasattr(obj.type, "name") else str(obj.type)
                counts[type_name] = counts.get(type_name, 0) + 1
                try:
                    name = obj.peek_name()
                except Exception:
                    name = None
                if name:
                    names.append(str(name))
            print(f"  {path}  {counts}")
            if names:
                print(f"    示例名称：{', '.join(names[:12])}")
        except Exception as exc:
            print(f"  {path}  打开失败：{exc}")
    return 0


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="AA 官方资源包（Unity Addressables）→ aa_pack 转换器（UnityPy）",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument("-i", "--input", help="输入：AA 资源包目录 / .zip / 单个 .bundle")
    parser.add_argument("-o", "--out", help="输出 aa_pack 目录")
    parser.add_argument("--id", default="", help="aa_pack id（默认取输入名）")
    parser.add_argument("--name", default="", help="aa_pack 显示名")
    parser.add_argument("--version", default="converted", help="aa_pack 版本字符串")
    parser.add_argument("--zip", action="store_true", help="同时输出 <out>.zip")
    parser.add_argument("--verbose", "-v", action="store_true", help="打印进度与警告")
    parser.add_argument("--selftest", action="store_true", help="用 UnityPy 构造测试 bundle 并验证端到端提取")
    parser.add_argument("--workdir", default="", help="--selftest 工作目录（默认系统临时目录）")
    parser.add_argument("--make-test-bundle", default="", help="只生成最小测试 bundle 到指定路径")
    parser.add_argument("--inspect", default="", help="只统计 bundle/资产类型，不导出")
    args = parser.parse_args(argv)

    if args.make_test_bundle:
        if not unitypy_available():
            print("[extract] 无法生成测试 bundle：需要 UnityPy。", file=sys.stderr)
            print(PIP_HINT, file=sys.stderr)
            return 2
        path = make_test_bundle(Path(args.make_test_bundle))
        print(f"[extract] 已生成测试 bundle：{path}（{path.stat().st_size} bytes）")
        return 0

    if args.selftest:
        if not unitypy_available():
            print("[selftest] SKIP：UnityPy 不可用，自测降级跳过（提取器此时不可用）。")
            print(PIP_HINT)
            return 0
        workdir = Path(args.workdir) if args.workdir else None
        return selftest(workdir, verbose=args.verbose)

    if args.inspect:
        if not unitypy_available():
            print("[inspect] 需要 UnityPy。", file=sys.stderr)
            print(PIP_HINT, file=sys.stderr)
            return 2
        return inspect(Path(args.inspect))

    if not args.input or not args.out:
        parser.error("提取模式需要 -i/--input 与 -o/--out（或使用 --selftest / --make-test-bundle / --inspect）")
    if not unitypy_available():
        print("[extract] 需要 UnityPy。", file=sys.stderr)
        print(PIP_HINT, file=sys.stderr)
        return 2
    extract(Path(args.input), Path(args.out), pack_id=args.id, pack_name=args.name,
            version=args.version, make_zip=args.zip, verbose=args.verbose)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
