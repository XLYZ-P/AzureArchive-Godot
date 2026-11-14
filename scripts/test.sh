#!/usr/bin/env bash
# 跑全量 headless 测试。会自动刷新 class_name 全局缓存。
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 1
python3 scripts/gen_class_cache.py
exec scripts/godot.sh --script tests/run_all.gd "$@"
