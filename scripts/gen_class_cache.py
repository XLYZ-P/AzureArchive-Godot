#!/usr/bin/env python3
"""扫描 res:// 下的 .gd，生成 .godot/global_script_class_cache.cfg。

本机 headless 环境没有编辑器做全局类扫描，GDScript 里的 class_name 全局解析
依赖这个缓存文件（Godot 4.7 的 ProjectSettings::get_global_class_list），
缺少 is_abstract/is_tool 字段的条目会被引擎跳过。运行测试/游戏前必须生成。
"""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RE_CLASS = re.compile(r'^\s*class_name\s+([A-Za-z_][A-Za-z0-9_]*)', re.M)
RE_EXTENDS = re.compile(r'^\s*extends\s+([A-Za-z_][A-Za-z0-9_.]*)', re.M)
RE_TOOL = re.compile(r'^\s*@tool\b', re.M)
RE_ABSTRACT = re.compile(r'^\s*@abstract\b', re.M)

SKIP_DIRS = {'.godot', '.git', '__pycache__', 'tmp'}


def collect():
    out = []
    for dirpath, dirnames, filenames in os.walk(ROOT):
        dirnames[:] = [d for d in dirnames if d not in SKIP_DIRS]
        for fn in sorted(filenames):
            if not fn.endswith('.gd'):
                continue
            p = os.path.join(dirpath, fn)
            rel = os.path.relpath(p, ROOT).replace(os.sep, '/')
            try:
                text = open(p, encoding='utf-8').read()
            except OSError:
                continue
            m = RE_CLASS.search(text)
            if not m:
                continue
            cls = m.group(1)
            ext = RE_EXTENDS.search(text)
            base = ext.group(1) if ext else 'RefCounted'
            out.append({
                'base': base,
                'class': cls,
                'icon': '',
                'language': 'GDScript',
                'path': 'res://' + rel,
                'is_abstract': bool(RE_ABSTRACT.search(text)),
                'is_tool': bool(RE_TOOL.search(text)),
            })
    return out


def to_cfg(entries):
    lines = ['list=[']
    for i, e in enumerate(entries):
        comma = ',' if i < len(entries) - 1 else ''
        lines.append('{')
        lines.append(f'"base": &"{e["base"]}",')
        lines.append(f'"class": &"{e["class"]}",')
        lines.append(f'"icon": "{e["icon"]}",')
        lines.append(f'"language": &"{e["language"]}",')
        lines.append(f'"path": "{e["path"]}",')
        lines.append(f'"is_abstract": {"true" if e["is_abstract"] else "false"},')
        lines.append(f'"is_tool": {"true" if e["is_tool"] else "false"}')
        lines.append('}' + comma)
    lines.append(']')
    return '\n'.join(lines) + '\n'


def main():
    entries = collect()
    os.makedirs(os.path.join(ROOT, '.godot'), exist_ok=True)
    dest = os.path.join(ROOT, '.godot', 'global_script_class_cache.cfg')
    with open(dest, 'w', encoding='utf-8') as f:
        f.write(to_cfg(entries))
    if '--quiet' not in sys.argv:
        print(f'[gen_class_cache] {len(entries)} 个 class_name -> {dest}')
    return 0


if __name__ == '__main__':
    sys.exit(main())
