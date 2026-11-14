#!/usr/bin/env bash
# 一键构建 Windows + Android（+ 本机 Linux 验证版）。
# 依赖：Godot 4.7.2 模板已装到 ~/.local/share/godot/export_templates/4.7.2.stable/
#       apt: apksigner keytool(jre) python3-pil；build/game.pck 由 pack_project.gd 生成。
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
GODOT="${GODOT_BIN:-/opt/godot/Godot_v4.7.2-stable_linux.arm64}"
OUT_DIR="${OUT_DIR:-/sdcard/Download/DSH-Go/AA-Godot-builds}"

echo "== 1/4 生成 class_name 缓存 =="
python3 scripts/gen_class_cache.py

echo "== 2/4 打包 game.pck（PCKPacker） =="
GODOT_SILENCE_ROOT_WARNING=1 "$GODOT" --headless --path . --script scripts/pack_project.gd -- --out="$ROOT/build/game.pck" | tail -2

echo "== 3/4 Windows（模板 exe + 自包含 PCK） =="
python3 scripts/build_windows.py

echo "== 4/4 Android（模板 APK + 品牌补丁 + assets.sparsepck + 自签） =="
python3 scripts/build_android.py

echo "== 附带 Linux arm64 验证版 =="
mkdir -p build/linux
cp ~/.local/share/godot/export_templates/4.7.2.stable/linux_release.arm64 build/linux/AzureArchiveGodot
chmod +x build/linux/AzureArchiveGodot
cp build/game.pck build/linux/AzureArchiveGodot.pck

echo "== 拷贝产物到 $OUT_DIR =="
mkdir -p "$OUT_DIR"
cp build/windows/AzureArchiveGodot.exe "$OUT_DIR/"
cp build/android/AzureArchive-Godot.apk "$OUT_DIR/"
cp build/linux/AzureArchiveGodot "$OUT_DIR/AzureArchiveGodot-linux-arm64"
cp build/linux/AzureArchiveGodot.pck "$OUT_DIR/AzureArchiveGodot-linux-arm64.pck"
ls -lh "$OUT_DIR"
