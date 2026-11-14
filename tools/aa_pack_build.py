#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""生成合成 aa_pack fixture：fixtures/pack/synth_pack/（纯标准库，无第三方依赖）。

产物（可直接被 Godot 侧 AaResContext 加载，也可用于 qa 的 test_resources.gd）：
  fixtures/pack/synth_pack/
    catalog.json          # aa_pack 元数据（背景/BGM/音效/弹出图/角色/语音/原生角色表）
    manifest.json         # AA 兼容覆盖表（角色别名示例，可选）
    bgs/*.png             # 纯 Python zlib+struct 手写 PNG（渐变/图案）
    bgm/*.wav             # 正弦波 WAV（wave 模块）
    sounds/*.wav
    popups/*.png
    characters/<id>/      # PNG 多表情立绘 + -avatar.png；另有 Spine 演示目录
    voices/<guid>.ogg|wav # 有 ffmpeg 时转 OGG（贴 AA 原生格式），否则 WAV
    ui/*.png
  fixtures/pack/synth_pack.zip  # 同内容的 zip（用于 install_pack 的 zip 路径测试）

设计约束：
  - **不依赖 PIL**：PNG 用 zlib + struct 手写；
  - 可重复运行：所有内容由固定参数生成（zip 使用固定时间戳）；
  - 不联网、不调用 Godot。

用法：
  python3 tools/aa_pack_build.py                 # 生成目录 + zip
  python3 tools/aa_pack_build.py --no-zip        # 只生成目录
  python3 tools/aa_pack_build.py --out path/to/pack
"""

from __future__ import annotations

import argparse
import json
import math
import os
import shutil
import struct
import subprocess
import sys
import tempfile
import wave
import zipfile
import zlib
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DEFAULT_OUT = ROOT / "fixtures" / "pack" / "synth_pack"
PACK_ID = "synth_pack"
PACK_NAME = "Synthetic Demo Pack（合成资源包）"
PACK_VERSION = "1.0.0"

# 语音 GUID 与 fixtures/aap/sample_kei_01.aap 中实际用到的前几个 GUID 对齐，
# 这样用合成包加载真实样例工程时也能解析出语音（便于集成测试）。
VOICE_GUIDS = [
    "421e3665-33e2-4c36-90a1-8747e2b9db28",
    "82897c82-cc14-455d-b127-9dc13ee377ee",
    "ee3a8b2d-abfc-45a1-bf64-da1f075617a3",
]


# ---------------------------------------------------------------------------
# 纯 Python PNG 写入（zlib + struct；不依赖 PIL）
# ---------------------------------------------------------------------------

PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"


def _png_chunk(tag: bytes, data: bytes) -> bytes:
    return (
        struct.pack(">I", len(data))
        + tag
        + data
        + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)
    )


def write_png(path: Path, width: int, height: int, rows, color_type: int = 2) -> None:
    """写 PNG。rows: 可迭代对象，每项是 bytes（RGB=3B/px 或 RGBA=4B/px）。"""
    channels = 3 if color_type == 2 else 4
    expected = width * channels
    raw = bytearray()
    count = 0
    for row in rows:
        if len(row) != expected:
            raise ValueError(f"row {count} 长度 {len(row)} != {expected}")
        raw.append(0)  # filter type: None
        raw.extend(row)
        count += 1
    if count != height:
        raise ValueError(f"行数 {count} != 高度 {height}")
    ihdr = struct.pack(">IIBBBBB", width, height, 8, color_type, 0, 0, 0)
    payload = (
        PNG_SIGNATURE
        + _png_chunk(b"IHDR", ihdr)
        + _png_chunk(b"IDAT", zlib.compress(bytes(raw), 9))
        + _png_chunk(b"IEND", b"")
    )
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(payload)


def _clamp(value: float, low: float = 0.0, high: float = 255.0) -> int:
    return int(max(low, min(high, value)))


def _lerp(a: float, b: float, t: float) -> float:
    return a + (b - a) * t


def _hex_rgb(value: str) -> tuple[int, int, int]:
    value = value.lstrip("#")
    return (int(value[0:2], 16), int(value[2:4], 16), int(value[4:6], 16))


def gradient_png(path: Path, width: int, height: int, top: str, bottom: str,
                 stripes: bool = False, sun: bool = False) -> None:
    """纵向渐变 + 可选斜条纹 + 可选"太阳"圆。背景色/构图由固定参数决定。"""
    c0 = _hex_rgb(top)
    c1 = _hex_rgb(bottom)
    rows = []
    for y in range(height):
        t = y / max(1, height - 1)
        base = (
            _clamp(_lerp(c0[0], c1[0], t)),
            _clamp(_lerp(c0[1], c1[1], t)),
            _clamp(_lerp(c0[2], c1[2], t)),
        )
        row = bytearray()
        for x in range(width):
            r, g, b = base
            if stripes and ((x + y) // 48) % 2 == 0:
                r = _clamp(r * 0.86)
                g = _clamp(g * 0.86)
                b = _clamp(b * 0.86)
            if sun:
                cx, cy, radius = width * 0.72, height * 0.32, min(width, height) * 0.16
                dx = (x - cx) / radius
                dy = (y - cy) / radius
                if dx * dx + dy * dy <= 1.0:
                    r, g, b = _clamp(r + 90), _clamp(g + 70), _clamp(b + 20)
            row.extend((r, g, b))
        rows.append(bytes(row))
    write_png(path, width, height, rows, color_type=2)


def solid_png(path: Path, width: int, height: int, color: str, border: str | None = None) -> None:
    c = _hex_rgb(color)
    b = _hex_rgb(border) if border else None
    rows = []
    for y in range(height):
        row = bytearray()
        for x in range(width):
            if b is not None and (x < 6 or y < 6 or x >= width - 6 or y >= height - 6):
                row.extend(b)
            else:
                row.extend(c)
        rows.append(bytes(row))
    write_png(path, width, height, rows, color_type=2)


def _mix(rgb: tuple[int, int, int], other: tuple[int, int, int], t: float) -> tuple[int, int, int]:
    return (
        _clamp(_lerp(rgb[0], other[0], t)),
        _clamp(_lerp(rgb[1], other[1], t)),
        _clamp(_lerp(rgb[2], other[2], t)),
    )


def character_png(path: Path, face: str, width: int = 160, height: int = 320) -> None:
    """RGBA 占位角色立绘：头部椭圆 + 躯干梯形 + 底部色带，不同表情换色。"""
    palette = {
        "00": (86, 156, 214),
        "01": (214, 146, 86),
        "02": (150, 200, 120),
        "03": (200, 120, 180),
        "12": (120, 180, 200),
        "99": (180, 180, 180),
        "halo_01": (250, 220, 120),
        "halo_02": (140, 220, 250),
    }
    tint = palette.get(face, (150, 150, 150))
    body = tint + (150,)   # 半透明
    edge = _mix(tint, (255, 255, 255), 0.35) + (220,)
    rows = []
    cx = width * 0.5
    head_cy = height * 0.24
    head_rx = width * 0.19
    head_ry = height * 0.14
    for y in range(height):
        row = bytearray()
        for x in range(width):
            px = (0, 0, 0, 0)
            dx = (x - cx) / head_rx
            dy = (y - head_cy) / head_ry
            if dx * dx + dy * dy <= 1.0:
                px = body
            torso_top = head_cy + head_ry * 1.25
            if y >= torso_top:
                t = (y - torso_top) / max(1.0, height - torso_top)
                half_w = _lerp(width * 0.36, width * 0.46, t)
                if abs(x - cx) <= half_w:
                    px = body
                    if abs(abs(x - cx) - half_w) < 1.5:
                        px = edge
            if y >= height * 0.94:
                px = tint + (70,)
            if face in ("halo_01", "halo_02") and 0 <= y < height * 0.12:
                ring = abs(math.hypot((x - cx) / (width * 0.30), (y - height * 0.06) / (height * 0.05)) - 1.0)
                if ring < 0.35:
                    px = (250, 240, 160, 200) if face == "halo_01" else (170, 235, 250, 200)
            row.extend(px)
        rows.append(bytes(row))
    write_png(path, width, height, rows, color_type=6)


# ---------------------------------------------------------------------------
# WAV（wave 模块，正弦波）
# ---------------------------------------------------------------------------

def write_wave(path: Path, frequency: float, seconds: float, sample_rate: int = 22050,
               amplitude: float = 0.25, fade: float = 0.02) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    frames = int(sample_rate * seconds)
    fade_frames = max(1, int(sample_rate * fade))
    data = bytearray()
    for i in range(frames):
        env = 1.0
        if i < fade_frames:
            env = i / fade_frames
        elif i > frames - fade_frames:
            env = (frames - i) / fade_frames
        value = int(32767 * amplitude * env * math.sin(2 * math.pi * frequency * i / sample_rate))
        data.extend(struct.pack("<h", max(-32768, min(32767, value))))
    with wave.open(str(path), "wb") as handle:
        handle.setnchannels(1)
        handle.setsampwidth(2)
        handle.setframerate(sample_rate)
        handle.writeframes(bytes(data))


def maybe_convert_ogg(wav_path: Path) -> Path:
    """有 ffmpeg 时把 WAV 转成 OGG Vorbis（AA 原生语音格式）；失败保留 WAV。"""
    ffmpeg = shutil.which("ffmpeg")
    if not ffmpeg:
        return wav_path
    ogg_path = wav_path.with_suffix(".ogg")
    try:
        result = subprocess.run(
            [ffmpeg, "-y", "-loglevel", "error", "-i", str(wav_path),
             "-c:a", "libvorbis", "-q:a", "3", str(ogg_path)],
            capture_output=True, timeout=120,
        )
    except (OSError, subprocess.SubprocessError):
        return wav_path
    if result.returncode != 0 or not ogg_path.is_file() or ogg_path.stat().st_size == 0:
        return wav_path
    wav_path.unlink(missing_ok=True)
    return ogg_path


# ---------------------------------------------------------------------------
# 角色 / Spine 演示
# ---------------------------------------------------------------------------

def build_characters(out: Path) -> list[dict]:
    characters = []

    # 1) PNG 多表情角色 kai
    kai_dir = out / "characters" / "kai"
    kai_faces = ["00", "01", "02", "03", "12", "99"]
    for face in kai_faces:
        character_png(kai_dir / f"{face}.png", face)
    character_png(kai_dir / "kai-avatar.png", "00", width=96, height=96)
    characters.append({
        "identifier": "kai",
        "display_name": "凯（合成）",
        "nickname": "特殊现象调查部",
        "dir": "characters/kai",
        "portrait_mode": "png",
        "face_files": {face: f"characters/kai/{face}.png" for face in kai_faces},
        "small_portrait": "characters/kai/kai-avatar.png",
    })

    # 2) PNG 表情 + 光环角色 yuzu
    yuzu_dir = out / "characters" / "yuzu"
    yuzu_faces = ["00", "03"]
    for face in yuzu_faces:
        character_png(yuzu_dir / f"{face}.png", face)
    character_png(yuzu_dir / "halo_01.png", "halo_01")
    character_png(yuzu_dir / "yuzu-avatar.png", "03", width=96, height=96)
    characters.append({
        "identifier": "yuzu",
        "display_name": "柚（合成）",
        "nickname": "游戏开发部",
        "dir": "characters/yuzu",
        "portrait_mode": "png",
        "face_files": {face: f"characters/yuzu/{face}.png" for face in yuzu_faces + ["halo_01"]},
        "small_portrait": "characters/yuzu/yuzu-avatar.png",
    })

    # 3) Spine 演示角色（资源层不解析骨骼，但必须能识别 .skel/.atlas 并优雅降级）
    spine_dir = out / "characters" / "spine_demo"
    spine_dir.mkdir(parents=True, exist_ok=True)
    (spine_dir / "spine_demo.atlas").write_text(
        "spine_demo.png\n"
        "size: 256,512\n"
        "format: RGBA8888\n"
        "filter: Linear,Linear\n"
        "repeat: none\n"
        "00_default\n"
        "  rotate: false\n"
        "  xy: 0, 0\n"
        "  size: 256, 512\n"
        "  orig: 256, 512\n"
        "  offset: 0, 0\n"
        "  index: -1\n",
        encoding="utf-8",
    )
    # .skel 是二进制格式；这里只放占位字节，资源层不应解析它（Spine 运行时后续接入）
    (spine_dir / "spine_demo.skel").write_bytes(b"AA_SPINE_PLACEHOLDER\x00\x01" + bytes(range(64)))
    character_png(spine_dir / "spine_demo.png", "00", width=160, height=320)
    character_png(spine_dir / "spine_demo-avatar.png", "00", width=96, height=96)
    characters.append({
        "identifier": "spine_demo",
        "display_name": "Spine 演示（合成）",
        "nickname": "占位骨骼",
        "dir": "characters/spine_demo",
        "portrait_mode": "spine",
        "spine_base": "characters/spine_demo/spine_demo",
        "small_portrait": "characters/spine_demo/spine_demo-avatar.png",
    })

    # 4) 无立绘角色（只有名字/昵称）
    characters.append({
        "identifier": "narrator",
        "display_name": "旁白（合成）",
        "nickname": "",
        "dir": "",
        "portrait_mode": "none",
    })
    return characters


NATIVE_CHARACTERS = [
    {"key": "모모이", "display_name": "桃井", "nickname": "游戏开发部"},
    {"key": "미도리", "display_name": "绿", "nickname": "游戏开发部"},
    {"key": "케이", "display_name": "凯", "nickname": "特殊现象调查部"},
    {"key": "아리스", "display_name": "爱丽丝", "nickname": "游戏开发部"},
]


# ---------------------------------------------------------------------------
# 主流程
# ---------------------------------------------------------------------------

def build(out: Path) -> dict:
    if out.exists():
        shutil.rmtree(out)
    (out / "bgs").mkdir(parents=True, exist_ok=True)
    (out / "bgm").mkdir(parents=True, exist_ok=True)
    (out / "sounds").mkdir(parents=True, exist_ok=True)
    (out / "popups").mkdir(parents=True, exist_ok=True)
    (out / "voices").mkdir(parents=True, exist_ok=True)
    (out / "ui").mkdir(parents=True, exist_ok=True)

    bgs = [
        {"name": "BG_SynthSunset", "file": "bgs/BG_SynthSunset.png", "category": "合成背景"},
        {"name": "BG_SynthRoom", "file": "bgs/BG_SynthRoom.png", "category": "合成背景"},
        {"name": "BG_SynthNight", "file": "bgs/BG_SynthNight.png", "category": "合成背景"},
    ]
    gradient_png(out / "bgs" / "BG_SynthSunset.png", 720, 405, "#ff9a56", "#6a3d9a", sun=True)
    gradient_png(out / "bgs" / "BG_SynthRoom.png", 720, 405, "#8fd3ff", "#2b5d8a", stripes=True)
    gradient_png(out / "bgs" / "BG_SynthNight.png", 720, 405, "#101a33", "#03050c")
    character_png(out / "ui" / "icon_synth.png", "00", width=96, height=96)

    bgm = []
    for key, freq in [("Theme_Synth_01", 440.0), ("Theme_Synth_02", 523.25), ("Theme_Synth_03", 329.63)]:
        wav = out / "bgm" / f"{key}.wav"
        write_wave(wav, freq, 1.0)
        bgm.append({"key": key, "file": f"bgm/{key}.wav", "title": f"合成 BGM {key}"})

    sounds = []
    for key, freq, sec in [
        ("SE_Synth_Click", 880.0, 0.08),
        ("SE_Synth_Chime", 1046.5, 0.35),
        ("SE_Synth_Beep", 660.0, 0.12),
    ]:
        wav = out / "sounds" / f"{key}.wav"
        write_wave(wav, freq, sec)
        sounds.append({"name": key, "file": f"sounds/{key}.wav"})

    popups = []
    for name, color, border in [
        ("popup_synth_01", "#2e86de", "#ffffff"),
        ("popup_synth_02", "#e17055", "#ffeaa7"),
    ]:
        solid_png(out / "popups" / f"{name}.png", 320, 180, color, border)
        popups.append({"name": name, "file": f"popups/{name}.png", "category": "合成弹出图"})

    voices = []
    for index, guid in enumerate(VOICE_GUIDS):
        wav = out / "voices" / f"{guid}.wav"
        write_wave(wav, 300.0 + index * 60.0, 0.4, amplitude=0.18)
        final = maybe_convert_ogg(wav)
        voices.append({
            "guid": guid,
            "file": f"voices/{final.name}",
            "text": f"合成语音示例 {index + 1}",
        })

    characters = build_characters(out)

    catalog = {
        "format": "aa_pack",
        "format_version": 1,
        "id": PACK_ID,
        "name": PACK_NAME,
        "version": PACK_VERSION,
        "author": "pack-dev (aa-godot)",
        "description": "纯 Python 生成的合成 aa_pack fixture：渐变背景、正弦波 BGM/音效/语音、占位角色 PNG、Spine 占位目录。",
        "game": "AzureArchive",
        "bgs": bgs,
        "bgm": bgm,
        "sounds": sounds,
        "popups": popups,
        "characters": characters,
        "voices": voices,
        "fonts": [],
        "ui": [{"name": "icon_synth", "file": "ui/icon_synth.png"}],
        "bg_effects": [
            {"name": "SynthSparkle", "type": "placeholder", "params": {"color": "#ffd166", "duration": 1.2}},
        ],
        "native_characters": NATIVE_CHARACTERS,
    }
    (out / "catalog.json").write_text(
        json.dumps(catalog, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    # AA 兼容 manifest：角色别名示例（Identifier → 原生角色引用）
    manifest = {
        "CharacterOverrides": [
            {"Identifier": "01", "Name": "绿", "Nickname": "游戏开发部",
             "CharacterReference": "미도리", "OriginalIdentifier": None,
             "SpinePortraitPath": None, "SmallPortraitPath": None},
            {"Identifier": "02", "Name": "桃井", "Nickname": "游戏开发部",
             "CharacterReference": "모모이", "OriginalIdentifier": None,
             "SpinePortraitPath": None, "SmallPortraitPath": None},
            {"Identifier": "00", "Name": "？？？", "Nickname": "未知",
             "CharacterReference": "케이", "OriginalIdentifier": None,
             "SpinePortraitPath": None, "SmallPortraitPath": None},
        ],
        "VoiceOverrides": [f"voices/{voice['file'].split('/')[-1]}" for voice in voices],
        "PopupOverrides": [popup["file"] for popup in popups],
        "SoundOverrides": [sound["file"] for sound in sounds],
        "BgOverrides": [bg["file"] for bg in bgs],
        "BgEffectOverrides": [],
        "BgSpineOverrides": [],
        "BgmOverrides": [bgm_item["file"] for bgm_item in bgm],
    }
    (out / "manifest.json").write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    return {
        "out": out,
        "bgs": len(bgs),
        "bgm": len(bgm),
        "sounds": len(sounds),
        "popups": len(popups),
        "characters": len(characters),
        "voices": len(voices),
        "voice_ext": Path(voices[0]["file"]).suffix,
    }


def make_zip(pack_dir: Path, zip_path: Path) -> int:
    if zip_path.exists():
        zip_path.unlink()
    files = sorted(p for p in pack_dir.rglob("*") if p.is_file())
    with zipfile.ZipFile(zip_path, "w", compression=zipfile.ZIP_DEFLATED) as archive:
        for path in files:
            rel = path.relative_to(pack_dir).as_posix()
            info = zipfile.ZipInfo(rel, date_time=(2024, 1, 1, 0, 0, 0))
            info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = 0o644 << 16
            archive.writestr(info, path.read_bytes())
    return len(files)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="生成合成 aa_pack fixture（纯标准库）")
    parser.add_argument("--out", default=str(DEFAULT_OUT), help="输出目录")
    parser.add_argument("--no-zip", action="store_true", help="不生成 zip")
    args = parser.parse_args(argv)

    out = Path(args.out).resolve()
    info = build(out)
    print(f"[aa_pack_build] 生成 {out}")
    print(f"  bgs={info['bgs']} bgm={info['bgm']} sounds={info['sounds']} "
          f"popups={info['popups']} characters={info['characters']} voices={info['voices']}"
          f"（语音格式 {info['voice_ext']}）")
    if not args.no_zip:
        zip_path = out.parent / (out.name + ".zip")
        count = make_zip(out, zip_path)
        print(f"[aa_pack_build] 生成 {zip_path}（{count} 个文件）")
    print("[aa_pack_build] OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
