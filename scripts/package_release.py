#!/usr/bin/env python3
"""打包发布 zip（纯标准库，无需 zip 命令）。排除 .git/.godot/缓存/中间截图。"""
import os
import sys
import time
import zipfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_DIR = os.environ.get("OUT_DIR", "/sdcard/Download/DSH-Go")
STAMP = time.strftime("%Y%m%d")
NAME = f"AzureArchive-Godot-复刻-{STAMP}.zip"
ZIP = os.path.join(OUT_DIR, NAME)

EXCLUDE_DIRS = {".git", ".godot", "__pycache__", "shots", ".pytest_cache", "build"}
EXCLUDE_FILES = {"last_result.json", ".DS_Store"}


def should_skip(rel: str) -> bool:
    parts = rel.split("/")
    if any(p in EXCLUDE_DIRS for p in parts[:-1]):
        return True
    if parts[0] in EXCLUDE_DIRS:
        return True
    if parts[-1] in EXCLUDE_FILES:
        return True
    return False


def main() -> int:
    os.makedirs(OUT_DIR, exist_ok=True)
    count = 0
    total = 0
    with zipfile.ZipFile(ZIP, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as zf:
        for dirpath, dirnames, filenames in os.walk(ROOT):
            dirnames[:] = sorted(d for d in dirnames if d not in EXCLUDE_DIRS)
            for fn in sorted(filenames):
                if fn in EXCLUDE_FILES:
                    continue
                p = os.path.join(dirpath, fn)
                rel = os.path.relpath(p, ROOT).replace(os.sep, "/")
                if should_skip(rel):
                    continue
                try:
                    zf.write(p, rel)
                    count += 1
                    total += os.path.getsize(p)
                except OSError as e:
                    print(f"  skip {rel}: {e}")
    print(f"[package] {count} 个文件，原始大小 {total/1048576:.1f} MB")
    print(f"[package] -> {ZIP} ({os.path.getsize(ZIP)/1048576:.1f} MB)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
