#!/usr/bin/env bash
# 打包发布 zip（Python 标准库实现，不依赖 zip 命令）
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
exec python3 "$ROOT/scripts/package_release.py"
