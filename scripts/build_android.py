#!/usr/bin/env python3
"""构建 Android APK（不依赖 godot --export / apktool 重建，全部手工完成）。

背景：本机（Android proot aarch64）Godot 的 editor/导出器初始化即崩溃；Ubuntu 的 aapt v1
又无法重编译现代 aapt2 生成的 resources.arsc。因此采用"原地打补丁"方案：
  1. 官方 android_release.apk 模板里替换品牌图标（webp，同路径）；
  2. 直接重建 AXML 字符串池，只改 package 名（class 名保持原样，dex 不动）；
  3. 直接重建 resources.arsc 全局字符串池，把 app 名从 godot-project-name* 改成 AzureArchive Godot；
  4. 注入 assets/assets.sparsepck = build/game.pck（引擎 Android 端会加载这个路径）；
  5. apksigner 自签（v1+v2）。
"""
import os
import struct
import subprocess
import sys
import zipfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TPL_DIR = os.path.expanduser("~/.local/share/godot/export_templates/4.7.2.stable")
TEMPLATE_APK = os.path.join(TPL_DIR, "android_release.apk")
PCK = os.path.join(ROOT, "build", "game.pck")
BUILD = os.path.join(ROOT, "build", "android")
UNSIGNED = os.path.join(BUILD, "unsigned.apk")
OUT = os.path.join(BUILD, "AzureArchive-Godot.apk")
KEYSTORE = os.path.join(BUILD, "aa-release.keystore")
KS_PASS, KS_ALIAS = "azurearchive", "azurearchive"
NEW_PKG = "com.nextarchive.alll"
APP_NAME = "AzureArchive Godot"

ICON_BG = (16, 35, 63, 255)
ICON_FG = (127, 212, 255, 255)
ICON_WHITE = (255, 255, 255, 255)


# ---------------------------------------------------------------- 图标
def draw_icon(size: int, padding: float = 0.0, mono: bool = False, bg_solid: bool = True):
    from PIL import Image, ImageDraw
    s = size
    img = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    if bg_solid:
        d.rounded_rectangle([0, 0, s - 1, s - 1], radius=int(s * 0.22), fill=ICON_BG)
    t = 1.0 - 2 * padding
    color = ICON_WHITE if mono else ICON_FG
    pts = [(0.5, 0.10), (0.94, 0.90), (0.78, 0.90), (0.5, 0.28),
           (0.22, 0.90), (0.06, 0.90)]
    d.polygon([((x * t + padding) * s, (y * t + padding) * s) for x, y in pts], fill=color)
    cx, cy, r = 0.5, 0.50, 0.075
    d.ellipse([((cx - r) * t + padding) * s, ((cy - r) * t + padding) * s,
               ((cx + r) * t + padding) * s, ((cy + r) * t + padding) * s],
              fill=(ICON_BG if mono else ICON_WHITE))
    return img


def icon_files():
    from PIL import Image
    out = {}
    sizes = {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}
    for dens, px in sizes.items():
        out[f"res/mipmap-{dens}-v4/icon.webp"] = draw_icon(px)
        out["res/mipmap/icon.webp"] = draw_icon(px)
        out[f"res/mipmap-{dens}-v4/icon_foreground.webp"] = draw_icon(432, padding=0.16, bg_solid=False)
        out["res/mipmap/icon_foreground.webp"] = draw_icon(432, padding=0.16, bg_solid=False)
        out[f"res/mipmap-{dens}-v4/icon_background.webp"] = Image.new("RGBA", (432, 432), ICON_BG)
        out["res/mipmap/icon_background.webp"] = Image.new("RGBA", (432, 432), ICON_BG)
        out[f"res/mipmap-{dens}-v4/icon_monochrome.webp"] = draw_icon(432, padding=0.22, mono=True, bg_solid=False)
        out["res/mipmap/icon_monochrome.webp"] = draw_icon(432, padding=0.22, mono=True, bg_solid=False)
    out["res/drawable/splash_icon.webp"] = draw_icon(512)
    return out


def webp_bytes(img) -> bytes:
    import io
    b = io.BytesIO()
    img.save(b, "WEBP", lossless=True)
    return b.getvalue()


# ------------------------------------------------ 对齐 ZIP 写入器
def write_aligned_apk(path: str, entries: list) -> None:
    """自写 ZIP 写入器：对未压缩条目（尤其 resources.arsc）做 4 字节对齐。

    Android 11+ 安装 targetSdk>=30 的 APK 时强制要求 resources.arsc 以 STORED 方式存放
    且数据偏移 4 字节对齐（否则 INSTALL_PARSE_FAILED 报 -124）。Python zipfile 不支持
    对齐，zipalign 又不可用时只能自己算 local header 的 extra field 填充。
    entries: [(name, data, method, align)]
    """
    import zlib
    entries = list(entries)
    with open(path, "wb") as out:
        central = []
        offset = 0
        for name, data, method, align in entries:
            nb = name.encode("utf-8")
            if method == 0:
                comp = data
            else:
                co = zlib.compressobj(9, zlib.DEFLATED, -15)
                comp = co.compress(data) + co.flush()
            crc = zlib.crc32(data) & 0xffffffff
            extra = b""
            if align > 1:
                base = offset + 30 + len(nb)
                need = (align - (base % align)) % align
                if need and need < 4:
                    need += align
                if need:
                    extra = struct.pack("<HH", 0x9999, need - 4) + b"\x00" * (need - 4)
            lh = struct.pack("<IHHHHHIIIHH", 0x04034B50, 20, 0x0800, method, 0, 0,
                             crc, len(comp), len(data), len(nb), len(extra))
            data_off = offset + 30 + len(nb) + len(extra)
            if align > 1:
                assert data_off % align == 0, (name, data_off, align)
            out.write(lh)
            out.write(nb)
            out.write(extra)
            out.write(comp)
            central.append((nb, method, crc, len(comp), len(data), offset, extra))
            offset = out.tell()
        cd_off = offset
        for nb, method, crc, csize, usize, loff, extra in central:
            ch = struct.pack("<IHHHHHHIIIHHHHHII", 0x02014B50, 20, 20, 0x0800, method,
                             0, 0, crc, csize, usize, len(nb), len(extra), 0, 0, 0, 0, loff)
            out.write(ch)
            out.write(nb)
            out.write(extra)
        cd_size = out.tell() - cd_off
        out.write(struct.pack("<IHHHHIIH", 0x06054B50, 0, 0, len(central), len(central),
                              cd_size, cd_off, 0))


def needed_align(name: str) -> int:
    if name == "resources.arsc":
        return 4
    return 1


# ------------------------------------------------ 字符串池（AXML / ARSC 通用）
def read_pool(d, off):
    ctype, hsz, size = struct.unpack_from("<HHI", d, off)
    assert ctype == 1, f"not string pool at {off}: {hex(ctype)}"
    count, style_count, flags, strings_start, styles_start = struct.unpack_from("<5I", d, off + 8)
    utf8 = bool(flags & 0x100)
    offs = [struct.unpack_from("<I", d, off + hsz + 4 * i)[0] for i in range(count)]

    def rd(o):
        p = off + strings_start + o
        if utf8:
            n = d[p]; p += 1
            if n & 0x80:
                n = ((n & 0x7f) << 8) | d[p]; p += 1
            nb = d[p]; p += 1
            if nb & 0x80:
                nb = ((nb & 0x7f) << 8) | d[p]; p += 1
            return d[p:p + nb].decode("utf-8", "replace")
        n = struct.unpack_from("<H", d, p)[0]
        if n & 0x8000:
            n2 = struct.unpack_from("<H", d, p + 2)[0]; p += 4; n = ((n & 0x7fff) << 16) | n2
        else:
            p += 2
        return d[p:p + 2 * n].decode("utf-16-le", "replace")

    return [rd(o) for o in offs], utf8, hsz


def build_pool(strings, utf8=True):
    count = len(strings)
    hsz = 28
    data = bytearray()
    offsets = []
    def put_len(n):
        if n > 0x7f:
            return bytes([(n >> 8) | 0x80, n & 0xff])
        return bytes([n])

    for s in strings:
        offsets.append(len(data))
        if utf8:
            b = s.encode("utf-8")
            data += put_len(len(b)) + put_len(len(b)) + b + b"\x00"
        else:
            b = s.encode("utf-16-le")
            if len(s) > 0x7fff:
                data += struct.pack("<HH", 0x8000 | (len(s) >> 16), len(s) & 0xffff)
            else:
                data += struct.pack("<H", len(s))
            data += b + b"\x00\x00"
    strings_start = hsz + 4 * count
    pad = (4 - (strings_start % 4)) % 4
    total = strings_start + len(data)
    end_pad = (4 - (total % 4)) % 4
    header = struct.pack("<HHI5I", 1, hsz, total + end_pad,
                         count, 0, 0x100 if utf8 else 0, strings_start, 0)
    offs = b"".join(struct.pack("<I", o) for o in offsets)
    return header + offs + b"\x00" * pad + bytes(data) + b"\x00" * end_pad


def patch_axml_manifest(d: bytes) -> bytes:
    """AXML: 重建字符串池，把精确等于 com.godot.game 的字符串改成新包名。其余不动。"""
    xml_type, xml_hsz, xml_size = struct.unpack_from("<HHI", d, 0)
    assert xml_type == 0x0003, hex(xml_type)
    strings, utf8, hsz = read_pool(d, xml_hsz)
    pool_size = struct.unpack_from("<I", d, xml_hsz + 4)[0]
    changed = 0
    for i, s in enumerate(strings):
        if s == "com.godot.game":
            strings[i] = NEW_PKG
            changed += 1
    print(f"[android] AXML 字符串池 {len(strings)} 条，替换 package 名称 {changed} 处")
    new_pool = build_pool(strings, utf8)
    rest = d[xml_hsz + pool_size:]
    new_xml = bytearray(struct.pack("<HHI", xml_type, xml_hsz, 0)) + new_pool + rest
    struct.pack_into("<I", new_xml, 4, len(new_xml))
    return bytes(new_xml)


def patch_arsc(d: bytes) -> bytes:
    """ARSC: 重建全局字符串池（第一个 chunk），把 godot-project-name* 改成应用名。"""
    t_type, t_hsz, t_size, pkg_count = struct.unpack_from("<HHII", d, 0)
    assert t_type == 0x0002
    pool_off = t_hsz
    strings, utf8, hsz = read_pool(d, pool_off)
    pool_size = struct.unpack_from("<I", d, pool_off + 4)[0]
    changed = 0
    for i, s in enumerate(strings):
        if s == "godot-project-name" or s.startswith("godot-project-name-"):
            strings[i] = APP_NAME
            changed += 1
    print(f"[android] ARSC 全局字符串池 {len(strings)} 条，替换应用名 {changed} 处")
    new_pool = build_pool(strings, utf8)
    rest = d[pool_off + pool_size:]
    out = bytearray(d[:t_hsz]) + new_pool + rest
    struct.pack_into("<I", out, 4, len(out))
    return bytes(out)


# ---------------------------------------------------------------- 主流程
def run(cmd):
    print("+", " ".join(cmd))
    r = subprocess.run(cmd)
    if r.returncode != 0:
        raise SystemExit(f"命令失败 rc={r.returncode}: {cmd}")


def main() -> int:
    for p in (TEMPLATE_APK, PCK):
        if not os.path.exists(p):
            print(f"[android] 缺少文件: {p}", file=sys.stderr)
            return 1
    os.makedirs(BUILD, exist_ok=True)
    icons = icon_files()
    zin = zipfile.ZipFile(TEMPLATE_APK)
    if os.path.exists(UNSIGNED):
        os.remove(UNSIGNED)
    replaced = 0
    keep_abis = os.environ.get("ANDROID_ABIS", "arm64-v8a").split(",")
    kept_abis = set()
    out_entries = []
    for info in zin.infolist():
        name = info.filename
        if name.startswith("lib/"):
            abi = name.split("/")[1]
            if abi not in keep_abis:
                continue
            kept_abis.add(abi)
        data = zin.read(name)
        if name == "AndroidManifest.xml":
            data = patch_axml_manifest(data)
        elif name == "resources.arsc":
            data = patch_arsc(data)
        elif name in icons:
            data = webp_bytes(icons[name])
            replaced += 1
        out_entries.append((name, data, info.compress_type, needed_align(name)))
    out_entries.append(("assets/assets.sparsepck", open(PCK, "rb").read(), 0, 1))
    write_aligned_apk(UNSIGNED, out_entries)
    print(f"[android] 图标替换 {replaced} 个，保留 ABI: {sorted(kept_abis)}，注入 assets/assets.sparsepck（对齐 ZIP 写入）-> {UNSIGNED}")
    if not os.path.exists(KEYSTORE):
        run(["keytool", "-genkeypair", "-keystore", KEYSTORE, "-alias", KS_ALIAS,
             "-keyalg", "RSA", "-keysize", "2048", "-validity", "10000",
             "-storepass", KS_PASS, "-keypass", KS_PASS,
             "-dname", "CN=AzureArchive Godot, OU=Fan Replica, O=Foxxlight Fan, C=CN"])
    if os.path.exists(OUT):
        os.remove(OUT)
    run(["apksigner", "sign", "--ks", KEYSTORE, "--ks-pass", f"pass:{KS_PASS}",
         "--key-pass", f"pass:{KS_PASS}", "--ks-key-alias", KS_ALIAS,
         "--min-sdk-version", "24", "--v1-signing-enabled", "true",
         "--v2-signing-enabled", "true", "--out", OUT, UNSIGNED])
    run(["apksigner", "verify", "--verbose", OUT])
    print(f"[android] OK -> {OUT} ({os.path.getsize(OUT)/1048576:.1f} MB)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
