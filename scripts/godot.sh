#!/usr/bin/env bash
# 统一 Godot 入口（本机 headless）。会自动刷新 class_name 全局缓存。
GODOT="${GODOT_BIN:-/opt/godot/Godot_v4.7.2-stable_linux.arm64}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 1
python3 scripts/gen_class_cache.py --quiet >/dev/null 2>&1
export GODOT_SILENCE_ROOT_WARNING=1
exec "$GODOT" --headless --path . "$@"
