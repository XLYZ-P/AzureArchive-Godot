#!/usr/bin/env python3
"""构建 Windows 版：Godot 4.7.2 官方模板 exe + 我们自制的 PCK（单文件自包含）。

为什么不用 `godot --export-release`：本机（Android proot aarch64）Godot 的 editor/导出器
初始化时会 glibc double free 崩溃（--import/--editor/--export 全崩），因此改用：
  1. `scripts/pack_project.gd` 用引擎内置 PCKPacker 打包 game.pck（不需要 editor）；
  2. 直接把 PCK 追加到官方 release 模板 exe 末尾，写 Godot 的自包含 PCK 页脚
     `[pck bytes][u64 pck_size][magic "GDPC"]`（见 godot/core/io/file_access_pack.cpp）。
"""
import struct
import sys
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TPL_DIR = os.path.expanduser("~/.local/share/godot/export_templates/4.7.2.stable")
EXE_TPL = os.path.join(TPL_DIR, "windows_release_x86_64.exe")
PCK = os.path.join(ROOT, "build", "game.pck")
OUT = os.path.join(ROOT, "build", "windows", "AzureArchiveGodot.exe")
MAGIC = 0x43504447  # "GDPC"


def main() -> int:
    for p in (EXE_TPL, PCK):
        if not os.path.exists(p):
            print(f"[win] 缺少文件: {p}", file=sys.stderr)
            return 1
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    exe = open(EXE_TPL, "rb").read()
    pck = open(PCK, "rb").read()
    with open(OUT, "wb") as f:
        f.write(exe)
        f.write(pck)
        f.write(struct.pack("<Q", len(pck)))
        f.write(struct.pack("<I", MAGIC))
    # 回读校验页脚
    d = open(OUT, "rb").read()
    end = len(d)
    assert struct.unpack_from("<I", d, end - 4)[0] == MAGIC
    ds = struct.unpack_from("<Q", d, end - 12)[0]
    assert ds == len(pck)
    assert d[end - 12 - ds:end - 12 + 4][:4] == b"GDPC"
    print(f"[win] OK -> {OUT} ({os.path.getsize(OUT)/1048576:.1f} MB, pck {len(pck)/1048576:.1f} MB)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
