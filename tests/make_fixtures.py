#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""tests/make_fixtures.py —— 可重复生成 qa-dev 的合成夹具 `fixtures/synth/`。

用法：
    cd /root/workspace/aa-godot
    python3 tests/make_fixtures.py            # 生成（覆盖）全部合成夹具
    python3 tests/make_fixtures.py --check    # 只校验：重新生成到临时目录，逐字节比对现有夹具
    python3 tests/make_fixtures.py --quiet    # 少打印

生成内容（全部确定性，无时间戳/随机数，可重复生成）：
    fixtures/synth/
    ├── smoke.aap            合成小工程：入口 + 3 行台词（含 #wait 与内联标记）+ 2 选项选择
    │                        + 两个分支各 1 行 + Ending 出口（共 6 节点 / 5 行 ScriptData）
    ├── smoke_fast.aap       同结构但无 #wait / 无额外指令，供播放器 smoke 的快速路径兜底
    ├── pack/                最小 aa_pack（pack-dev 定稿布局，见 fixtures/synth/README.md）
    │   ├── catalog.json     包元数据
    │   ├── manifest.json    AA 兼容覆盖登记（可选）
    │   ├── bgs/synth_bg.png             纯色背景（这里用红色，供覆盖优先级测试）
    │   ├── bgm/synth_bgm.wav            0.2s 正弦波
    │   ├── sounds/SE_QA_01.wav          0.1s 正弦波
    │   ├── popups/synth_popup.png       纯色弹出图
    │   └── characters/QA_HERO/00.png + 00-avatar.png
    ├── overrides/           全局 overrides 夹具（synth_bg.png 为绿色 + manifest.json）
    ├── project_local/       工程本地同名文件夹夹具（synth_bg.png 为蓝色 + manifest.json）
    └── generated.json       生成清单：每个文件的 SHA-256 + xxh32 参考向量
                             （test_synth_fixtures.gd 用它验证夹具未被手改 / 可重复生成）

关键格式事实（来自 docs/DESIGN.md §4、docs/spec/aap.md、真实样本 sample_kei_01.aap）：
  * `.aap` 是 UTF-8 无 BOM 的 Newtonsoft.Json 紧凑 JSON，带 `$type`，**字段顺序有语义**；
  * `bgName = xxh32(utf8(bgFriendlyName), seed=0)`（无符号 32 位）；
  * `characters` 恒 6 项：0 = 无立绘说话槽，1–5 = 可见站位；`startingPos == 数组下标`；
  * 选择节点 `selectionTexts` 固定 16 槽，未用补 ""；`ConnectionsTo[i]` 对应第 i 个选项；
  * Entry 节点 Guid 必须全 0。

PNG 用标准库 zlib + struct 手工写，不依赖 PIL（本机也没有）；WAV 用标准库 wave。
"""

import hashlib
import json
import math
import os
import shutil
import struct
import sys
import tempfile
import wave
import zlib

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SYNTH_DIR = os.path.join(ROOT, 'fixtures', 'synth')
GENERATOR_VERSION = 2

# ---------------------------------------------------------------------------
# xxHash32（seed=0）参考实现：与 addons/aa_core/xxhash32.gd 交叉验证，
# 用来算合成工程的 bgName / PreviewBgName（不能查表，必须真算）。
# ---------------------------------------------------------------------------
P1, P2, P3, P4, P5 = 2654435761, 2246822519, 3266489917, 668265263, 374761393
M32 = 0xFFFFFFFF


def _rotl(x, r):
    return ((x << r) | (x >> (32 - r))) & M32


def _u32(data, off):
    return struct.unpack_from('<I', data, off)[0]


def xxh32(data, seed=0):
    """标准 xxh32，返回 0..2^32-1。"""
    b = bytes(data)
    n = len(b)
    off = 0
    if n >= 16:
        v1 = (seed + P1 + P2) & M32
        v2 = (seed + P2) & M32
        v3 = seed & M32
        v4 = (seed - P1) & M32
        while off <= n - 16:
            v1 = (_rotl((v1 + _u32(b, off) * P2) & M32, 13) * P1) & M32
            off += 4
            v2 = (_rotl((v2 + _u32(b, off) * P2) & M32, 13) * P1) & M32
            off += 4
            v3 = (_rotl((v3 + _u32(b, off) * P2) & M32, 13) * P1) & M32
            off += 4
            v4 = (_rotl((v4 + _u32(b, off) * P2) & M32, 13) * P1) & M32
            off += 4
        h = (_rotl(v1, 1) + _rotl(v2, 7) + _rotl(v3, 12) + _rotl(v4, 18)) & M32
    else:
        h = (seed + P5) & M32
    h = (h + n) & M32
    while off <= n - 4:
        h = (_rotl((h + _u32(b, off) * P3) & M32, 17) * P4) & M32
        off += 4
    while off < n:
        h = (_rotl((h + b[off] * P5) & M32, 11) * P1) & M32
        off += 1
    h ^= h >> 15
    h = (h * P2) & M32
    h ^= h >> 13
    h = (h * P3) & M32
    h ^= h >> 16
    return h & M32


def bg_id(name):
    """AA 约定：空背景 -> 0。"""
    if not name:
        return 0
    return xxh32(name.encode('utf-8'), 0)


# ---------------------------------------------------------------------------
# 二进制素材生成（标准库）
# ---------------------------------------------------------------------------
def write_png(path, width, height, rgba):
    """写一张纯色 RGBA PNG（zlib+struct 手工实现，不依赖 PIL）。"""
    r, g, b, a = rgba
    row = bytes([0]) + bytes([r, g, b, a]) * width  # 每行 filter=0 + 像素
    raw = row * height

    def chunk(tag, data):
        return (struct.pack('>I', len(data)) + tag + data
                + struct.pack('>I', zlib.crc32(tag + data) & M32))

    ihdr = struct.pack('>IIBBBBB', width, height, 8, 6, 0, 0, 0)  # 8bit RGBA
    payload = (b'\x89PNG\r\n\x1a\n'
               + chunk(b'IHDR', ihdr)
               + chunk(b'IDAT', zlib.compress(raw, 9))
               + chunk(b'IEND', b''))
    _write_bytes(path, payload)


def write_wav(path, seconds, freq, rate=22050, amp=0.35):
    """写 16-bit PCM 单声道 WAV（标准库 wave）。"""
    os.makedirs(os.path.dirname(path), exist_ok=True)
    n = int(seconds * rate)
    frames = bytearray()
    for i in range(n):
        # 首尾淡入淡出，避免爆音
        env = min(1.0, i / max(1, rate // 100), (n - i) / max(1, rate // 100))
        sample = int(amp * 32767 * env * math.sin(2 * math.pi * freq * i / rate))
        frames += struct.pack('<h', sample)
    tmp = path + '.tmp'
    with wave.open(tmp, 'wb') as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(rate)
        w.writeframes(bytes(frames))
    os.replace(tmp, path)


def _write_bytes(path, data):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, 'wb') as f:
        f.write(data)


def _write_json(path, obj, compact=True):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    if compact:
        text = json.dumps(obj, ensure_ascii=False, separators=(',', ':'))
    else:
        text = json.dumps(obj, ensure_ascii=False, indent=2)
    with open(path, 'w', encoding='utf-8', newline='') as f:
        f.write(text)


# ---------------------------------------------------------------------------
# .aap 构造器：严格按 AA（Newtonsoft.Json）字段顺序拼 dict
# ---------------------------------------------------------------------------
T_PACK = 'Assembly-CSharp'
T_PROJECT = 'ProjectData, Assembly-CSharp'
T_NODES = ('System.Collections.Generic.List`1[[NodeData, Assembly-CSharp]], '
           'mscorlib')
T_ENTRY = 'EntryNodeData, Assembly-CSharp'
T_SCRIPT = 'ScriptNodeData, Assembly-CSharp'
T_CHOICE = 'SelectionNodeData, Assembly-CSharp'
T_EXIT = 'ExitNodeData, Assembly-CSharp'
T_SCRIPT_DATA = 'ScriptData, Assembly-CSharp'
T_CHARACTER = 'ScriptData+CharacterRecordData, Assembly-CSharp'
T_CHAR_LIST = ('System.Collections.Generic.List`1[[ScriptData+CharacterRecordData, '
               'Assembly-CSharp]], mscorlib')
T_SCRIPT_LIST = ('System.Collections.Generic.List`1[[ScriptData, Assembly-CSharp]], '
                 'mscorlib')
T_GUID_LIST = ('System.Collections.Generic.List`1[[System.Guid, mscorlib]], '
               'mscorlib')
T_INT_LIST = ('System.Collections.Generic.List`1[[System.Int32, mscorlib]], '
              'mscorlib')
T_STRING_LIST = ('System.Collections.Generic.List`1[[System.String, mscorlib]], '
                 'mscorlib')

ZERO_GUID = '00000000-0000-0000-0000-000000000000'
# 合成工程固定 GUID（确定性，便于断言）
G_SCRIPT_A = '11111111-1111-4111-8111-111111111111'
G_CHOICE = '22222222-2222-4222-8222-222222222222'
G_BRANCH_A = '33333333-3333-4333-8333-333333333333'
G_BRANCH_B = '44444444-4444-4444-8444-444444444444'
G_EXIT = '55555555-5555-4555-8555-555555555555'

# 合成素材命名（与 pack/catalog.json、overrides、project_local 保持一致）
BG_NAME = 'synth_bg'
BG_NAME_ALT = 'synth_bg_alt'
BGM_KEY = 'synth_bgm'
SOUND_NAME = 'SE_QA_01'
POPUP_NAME = 'synth_popup'
CHAR_ID = 'QA_HERO'
CHAR_DISPLAY = '测试角色'


def character(name='', face='00', start=0, end=0, emoticon=-1, action=0,
              appear=0, shape=0):
    """ScriptData+CharacterRecordData（字段顺序严格）。"""
    return {
        '$type': T_CHARACTER,
        'name': name,
        'faceId': face,
        'startingPos': start,
        'endingPos': end,
        'emoticon': emoticon,
        'action': action,
        'effect': 0,
        'appear': appear,
        'shapeOverride': shape,
    }


def empty_chars():
    """恒 6 项：0 = 无立绘说话槽，1–5 = 可见站位。"""
    return [character() for _ in range(6)]


def script_data(text='', bg_friendly='', bgm=999, sound='', voice='',
                additional='', chars=None, speaker=0, highlight=None,
                transition=0, popup='', bg_effect=0, place='',
                is_dialog=True, selection_group=0):
    """一行 ScriptData（字段顺序 = AA 原文件顺序）。"""
    if chars is None:
        chars = empty_chars()
    return {
        '$type': T_SCRIPT_DATA,
        'text': text,
        'popup': popup,
        'bgEffect': bg_effect,
        'bgName': bg_id(bg_friendly) if bg_friendly else 0,
        'bgFriendlyName': bg_friendly,
        'sound': sound,
        'voice': voice,
        'transition': transition,
        'bgmId': bgm,
        'selectionGroup': selection_group,
        'additionalPrompt': additional,
        'characters': {'$type': T_CHAR_LIST, '$values': chars},
        'speakerSlotNum': speaker,
        'highlightedSlotNums': {'$type': T_INT_LIST, '$values': highlight or []},
        'isDialogScript': is_dialog,
        'placeText': place,
    }


def conn_list(guids):
    return {'$type': T_GUID_LIST, '$values': list(guids)}


def node_entry(title, header, connections, x=0.0, y=0.0):
    return {
        '$type': T_ENTRY,
        'Title': title,
        'Header': header,
        'Guid': ZERO_GUID,
        'ConnectionsTo': conn_list(connections),
        'X': float(x),
        'Y': float(y),
    }


def node_script(rows, node_name, guid, connections, x=0.0, y=0.0):
    return {
        '$type': T_SCRIPT,
        'Scripts': {'$type': T_SCRIPT_LIST, '$values': rows},
        'NodeName': node_name,
        'Guid': guid,
        'ConnectionsTo': conn_list(connections),
        'X': float(x),
        'Y': float(y),
    }


def node_choice(texts, connections, guid, x=0.0, y=0.0):
    slots = list(texts) + [''] * (16 - len(texts))
    assert len(slots) == 16, 'selectionTexts 必须固定 16 槽'
    return {
        '$type': T_CHOICE,
        'selectionTexts': {'$type': T_STRING_LIST, '$values': slots},
        'Guid': guid,
        'ConnectionsTo': conn_list(connections),
        'X': float(x),
        'Y': float(y),
    }


def node_exit(is_ending, end_text, ne_header, ne_title, ne_script, guid,
              connections=None, x=0.0, y=0.0):
    return {
        '$type': T_EXIT,
        'IsEnding': bool(is_ending),
        'EndText': end_text,
        'NeHeader': ne_header,
        'NeTitle': ne_title,
        'NeScriptDirty': ne_script,
        'Guid': guid,
        'ConnectionsTo': conn_list(connections or []),
        'X': float(x),
        'Y': float(y),
    }


def project_data(project_name, preview_bg, nodes):
    return {
        '$type': T_PROJECT,
        'ProjectName': project_name,
        'PreviewBgName': preview_bg,
        'PreviewHeader': None,
        'PreviewTitle': None,
        'nodes': {'$type': T_NODES, '$values': nodes},
    }


# ---------------------------------------------------------------------------
# 合成工程 smoke.aap / smoke_fast.aap
# ---------------------------------------------------------------------------
def hero_chars(appear=0, start=1, end=1, face='00', emoticon=-1, action=0,
               shape=0, speaker=0):
    """一行里槽位 1 站着 QA_HERO；槽 0 可选为无立绘说话槽。"""
    chars = empty_chars()
    chars[1] = character(CHAR_ID, face, start, end, emoticon, action, appear, shape)
    return chars


def build_smoke_project(fast=False):
    """构造合成小工程。fast=True 时去掉 #wait（供无 instant_mode 的播放器兜底）。"""
    # --- 第 1 行：旁白 + 内联 size/color + #wait；含音效
    line1 = script_data(
        text='合成工程开始。[size=200]放大[/size]与[FF0000]红色[-]测试。',
        bg_friendly=BG_NAME,
        bgm=999,
        sound=SOUND_NAME,
        additional='' if fast else '#wait;5000',
        chars=empty_chars(),
        speaker=0,
    )
    # --- 第 2 行：QA_HERO 首次登场（appear=3）说话 + 注音
    line2 = script_data(
        text='第一句台词，带[ruby=zhùyīn]注音[/ruby]标记。',
        bg_friendly=BG_NAME,
        bgm=999,
        chars=hero_chars(appear=3, start=1, end=1),
        speaker=1,
        highlight=[1],
    )
    # --- 第 3 行：同一角色继续说话 + #bgshake（fast 版去掉）
    line3 = script_data(
        text='第二句台词，然后就要做选择了。',
        bg_friendly=BG_NAME,
        bgm=999,
        additional='' if fast else '#bgshake',
        chars=hero_chars(appear=0, start=1, end=1),
        speaker=1,
        highlight=[1],
    )
    script_a = node_script(
        [line1, line2, line3],
        '01',
        G_SCRIPT_A,
        [G_CHOICE],
        x=0.0, y=-200.7629,
    )
    choice = node_choice(
        ['向右走', '向左走'],
        [G_BRANCH_A, G_BRANCH_B],
        G_CHOICE,
        x=0.0, y=-466.897644,
    )
    # 分支各自 1 行，角色继续留在槽 1
    branch_a = node_script(
        [script_data(
            text='你向右走了。',
            bg_friendly=BG_NAME,
            bgm=999,
            chars=hero_chars(start=1, end=1),
            speaker=1,
            highlight=[1],
        )],
        '02',
        G_BRANCH_A,
        [G_EXIT],
        x=-292.149261, y=-798.73584,
    )
    branch_b = node_script(
        [script_data(
            text='你向左走了。',
            bg_friendly=BG_NAME,
            bgm=999,
            chars=hero_chars(start=1, end=1),
            speaker=1,
            highlight=[1],
        )],
        '03',
        G_BRANCH_B,
        [G_EXIT],
        x=290.845917, y=-798.73584,
    )
    ne_script = script_data(text='', bg_friendly='', bgm=0)
    exit_node = node_exit(
        True,
        '—— 合成冒烟测试结束 ——',
        'QA',
        '下一话',
        ne_script,
        G_EXIT,
        x=0.0, y=-1037.65674,
    )
    entry = node_entry('合成冒烟', 'QA', [G_SCRIPT_A], x=0.0, y=0.0)
    return project_data('QA-Smoke', bg_id(BG_NAME),
                        [entry, script_a, choice, branch_a, branch_b, exit_node])


# ---------------------------------------------------------------------------
# 校验器：生成后自查字段顺序 / 图连通性（防止生成器自身写错）
# ---------------------------------------------------------------------------
EXPECT_TOP = ['$type', 'ProjectName', 'PreviewBgName', 'PreviewHeader',
              'PreviewTitle', 'nodes']
EXPECT_ENTRY = ['$type', 'Title', 'Header', 'Guid', 'ConnectionsTo', 'X', 'Y']
EXPECT_SCRIPT = ['$type', 'Scripts', 'NodeName', 'Guid', 'ConnectionsTo', 'X', 'Y']
EXPECT_CHOICE = ['$type', 'selectionTexts', 'Guid', 'ConnectionsTo', 'X', 'Y']
EXPECT_EXIT = ['$type', 'IsEnding', 'EndText', 'NeHeader', 'NeTitle',
               'NeScriptDirty', 'Guid', 'ConnectionsTo', 'X', 'Y']
EXPECT_SCRIPT_DATA = ['$type', 'text', 'popup', 'bgEffect', 'bgName',
                      'bgFriendlyName', 'sound', 'voice', 'transition', 'bgmId',
                      'selectionGroup', 'additionalPrompt', 'characters',
                      'speakerSlotNum', 'highlightedSlotNums',
                      'isDialogScript', 'placeText']
EXPECT_CHAR = ['$type', 'name', 'faceId', 'startingPos', 'endingPos',
               'emoticon', 'action', 'effect', 'appear', 'shapeOverride']


def validate_aap(path, expect_nodes=None, expect_lines=None):
    """读回生成文件，校验关键格式契约；返回统计 dict。"""
    with open(path, encoding='utf-8') as f:
        raw = f.read()
    assert not raw.startswith('\ufeff'), '不能有 BOM'
    p = json.loads(raw)
    assert list(p.keys()) == EXPECT_TOP, f'顶层字段顺序错: {list(p.keys())}'
    assert p['$type'] == T_PROJECT
    nodes = p['nodes']['$values']
    guids = [n['Guid'] for n in nodes]
    assert len(set(guids)) == len(guids), 'Guid 重复'
    entry_count = sum(1 for n in nodes if n['$type'] == T_ENTRY)
    assert entry_count == 1, '必须恰好 1 个入口'
    entry = [n for n in nodes if n['$type'] == T_ENTRY][0]
    assert entry['Guid'] == ZERO_GUID, '入口 Guid 必须全 0'
    lines = 0
    bgs = set()
    for n in nodes:
        t = n['$type']
        if t == T_ENTRY:
            assert list(n.keys()) == EXPECT_ENTRY, 'Entry 字段顺序错'
        elif t == T_SCRIPT:
            assert list(n.keys()) == EXPECT_SCRIPT, 'Script 节点字段顺序错'
            for row in n['Scripts']['$values']:
                lines += 1
                assert list(row.keys()) == EXPECT_SCRIPT_DATA, 'ScriptData 字段顺序错'
                chars = row['characters']['$values']
                assert len(chars) == 6, 'characters 必须 6 项'
                starts = []
                for idx, c in enumerate(chars):
                    assert list(c.keys()) == EXPECT_CHAR, 'CharacterRecord 字段顺序错'
                    if idx == 0:
                        continue  # 槽 0 是无立绘说话槽，不参与站位
                    if c['name']:
                        assert c['startingPos'] == idx, (
                            f'槽 {idx} 角色 {c["name"]} startingPos 应等于下标')
                        starts.append(c['startingPos'])
                assert len(starts) == len(set(starts)), '同一行 startingPos 必须两两不同'
                if row['bgFriendlyName']:
                    bgs.add(row['bgFriendlyName'])
                    assert row['bgName'] == bg_id(row['bgFriendlyName']), 'bgName 哈希错'
        elif t == T_CHOICE:
            assert list(n.keys()) == EXPECT_CHOICE, 'Selection 字段顺序错'
            assert len(n['selectionTexts']['$values']) == 16, '选择节点必须 16 槽'
        elif t == T_EXIT:
            assert list(n.keys()) == EXPECT_EXIT, 'Exit 字段顺序错'
            assert list(n['NeScriptDirty'].keys()) == EXPECT_SCRIPT_DATA, 'NeScriptDirty 字段顺序错'
            lines += 1  # NeScriptDirty 也是一行 ScriptData
        # 连通性
        for target in n['ConnectionsTo']['$values']:
            assert target in set(guids), f'连线目标不存在: {target}'
    if expect_nodes is not None:
        assert len(nodes) == expect_nodes, f'节点数 {len(nodes)} != {expect_nodes}'
    if expect_lines is not None:
        assert lines == expect_lines, f'ScriptData 行数 {lines} != {expect_lines}'
    return {'nodes': len(nodes), 'lines': lines, 'bgs': sorted(bgs)}


# ---------------------------------------------------------------------------
# aa_pack / overrides / project_local 夹具
# ---------------------------------------------------------------------------
def write_pack(out_dir):
    """最小 aa_pack（布局与 pack-dev 定稿一致，见 fixtures/synth/README.md）。"""
    write_png(os.path.join(out_dir, 'bgs', 'synth_bg.png'), 32, 32, (220, 40, 40, 255))
    write_png(os.path.join(out_dir, 'bgs', 'synth_bg_alt.png'), 32, 32, (40, 40, 220, 255))
    write_png(os.path.join(out_dir, 'popups', 'synth_popup.png'), 48, 24, (240, 200, 60, 255))
    write_png(os.path.join(out_dir, 'characters', CHAR_ID, '00.png'), 64, 96, (120, 180, 240, 255))
    write_png(os.path.join(out_dir, 'characters', CHAR_ID, '00-avatar.png'), 24, 24, (120, 180, 240, 255))
    write_wav(os.path.join(out_dir, 'bgm', 'synth_bgm.wav'), 0.2, 330.0)
    write_wav(os.path.join(out_dir, 'sounds', 'SE_QA_01.wav'), 0.1, 880.0)
    catalog = {
        'format': 'aa_pack',
        'format_version': 1,
        'id': 'synth_pack',
        'name': 'QA 合成最小包',
        'version': '1.0.0',
        'author': 'qa-dev',
        'description': 'tests/make_fixtures.py 生成的 headless 测试夹具，勿用于生产',
        'game': 'AzureArchive',
        'bgs': [
            {'name': 'synth_bg', 'file': 'bgs/synth_bg.png', 'category': '合成'},
            {'name': 'synth_bg_alt', 'file': 'bgs/synth_bg_alt.png', 'category': '合成'},
        ],
        'bgm': [{'key': BGM_KEY, 'file': 'bgm/synth_bgm.wav', 'title': '合成 BGM'}],
        'sounds': [{'name': SOUND_NAME, 'file': 'sounds/SE_QA_01.wav'}],
        'popups': [{'name': POPUP_NAME, 'file': 'popups/synth_popup.png'}],
        'characters': [{
            'identifier': CHAR_ID,
            'display_name': CHAR_DISPLAY,
            'nickname': '测试部',
            'dir': 'characters/QA_HERO',
            'portrait_mode': 'png',
            'face_files': {'00': '00.png'},
            'small_portrait': '00-avatar.png',
        }],
        'voices': [],
        'fonts': [],
        'bg_effects': [],
        'native_characters': [],
    }
    _write_json(os.path.join(out_dir, 'catalog.json'), catalog)
    manifest = {
        'CharacterOverrides': [{
            'Identifier': CHAR_ID,
            'Name': CHAR_DISPLAY,
            'Nickname': '测试部',
            'CharacterReference': None,
            'OriginalIdentifier': None,
            'SpinePortraitPath': None,
            'SmallPortraitPath': 'characters/QA_HERO/00-avatar.png',
        }],
        'VoiceOverrides': [],
        'PopupOverrides': ['popups/synth_popup.png'],
        'SoundOverrides': ['sounds/SE_QA_01.wav'],
        'BgOverrides': ['bgs/synth_bg.png', 'bgs/synth_bg_alt.png'],
        'BgmOverrides': [],
    }
    _write_json(os.path.join(out_dir, 'manifest.json'), manifest)


def write_overrides(out_dir):
    """全局 overrides：同名 synth_bg 用绿色（优先级应高于 pack）。"""
    write_png(os.path.join(out_dir, 'bgs', 'synth_bg.png'), 32, 32, (40, 200, 40, 255))
    manifest = {
        'CharacterOverrides': [],
        'VoiceOverrides': [],
        'PopupOverrides': [],
        'SoundOverrides': [],
        'BgOverrides': ['bgs/synth_bg.png'],
        'BgmOverrides': [],
    }
    _write_json(os.path.join(out_dir, 'manifest.json'), manifest)


def write_project_local(out_dir):
    """工程本地同名文件夹：同名 synth_bg 用蓝色（优先级最高）。"""
    write_png(os.path.join(out_dir, 'bgs', 'synth_bg.png'), 32, 32, (40, 40, 220, 255))
    manifest = {
        'CharacterOverrides': [],
        'VoiceOverrides': [],
        'PopupOverrides': [],
        'SoundOverrides': [],
        'BgOverrides': ['bgs/synth_bg.png'],
        'BgmOverrides': [],
    }
    _write_json(os.path.join(out_dir, 'manifest.json'), manifest)


# ---------------------------------------------------------------------------
# 生成 / 校验入口
# ---------------------------------------------------------------------------
def generate_all(base_dir=SYNTH_DIR):
    """在 base_dir 生成全部夹具；返回 {相对路径: 绝对路径}。"""
    os.makedirs(base_dir, exist_ok=True)
    files = {}

    def emit(rel):
        return os.path.join(base_dir, rel)

    # 1) .aap 合成工程
    smoke = build_smoke_project(fast=False)
    smoke_fast = build_smoke_project(fast=True)
    for rel, proj in (('smoke.aap', smoke), ('smoke_fast.aap', smoke_fast)):
        _write_json(emit(rel), proj)
        files[rel] = emit(rel)
    # 立即自查
    stats = validate_aap(emit('smoke.aap'), expect_nodes=6, expect_lines=6)
    # 6 节点 = 入口 + 1 台词节点 + 1 选择 + 2 分支 + 1 出口
    # 6 行 = 3 行正文 + 2 行分支 + 1 行 Exit.NeScriptDirty
    assert stats['lines'] == 6, stats

    # 2) aa_pack
    write_pack(emit('pack'))
    for rel in ('pack/catalog.json', 'pack/manifest.json',
                'pack/bgs/synth_bg.png', 'pack/bgs/synth_bg_alt.png',
                'pack/popups/synth_popup.png',
                'pack/characters/QA_HERO/00.png',
                'pack/characters/QA_HERO/00-avatar.png',
                'pack/bgm/synth_bgm.wav', 'pack/sounds/SE_QA_01.wav'):
        files[rel] = emit(rel)

    # 3) overrides / project_local
    write_overrides(emit('overrides'))
    write_project_local(emit('project_local'))
    for rel in ('overrides/manifest.json', 'overrides/bgs/synth_bg.png',
                'project_local/manifest.json', 'project_local/bgs/synth_bg.png'):
        files[rel] = emit(rel)

    # 4) generated.json：内容哈希清单（用于 test_synth_fixtures 校验可重复生成）
    file_hashes = {}
    for rel in sorted(files):
        with open(files[rel], 'rb') as f:
            file_hashes[rel] = hashlib.sha256(f.read()).hexdigest()
    generated = {
        'generator': 'tests/make_fixtures.py',
        'generator_version': GENERATOR_VERSION,
        'note': '由 python3 tests/make_fixtures.py 确定性生成；test_synth_fixtures.gd 校验哈希',
        'xxh32_vectors': {
            '': 0,
            'synth_bg': bg_id(BG_NAME),
            'synth_bg_alt': bg_id(BG_NAME_ALT),
            'BG_RuinUndergroundPassage': bg_id('BG_RuinUndergroundPassage'),
        },
        'files': file_hashes,
    }
    _write_json(emit('generated.json'), generated, compact=False)
    files['generated.json'] = emit('generated.json')
    return files


def check_reproducible():
    """重新生成到临时目录，逐字节比对 fixtures/synth 下由生成器产出的文件。"""
    tmp = tempfile.mkdtemp(prefix='aa_fixtures_')
    try:
        generate_all(tmp)
        bad = []
        # generated.json 里列出了全部产物（含自身不列），逐个比对
        with open(os.path.join(tmp, 'generated.json'), encoding='utf-8') as f:
            generated = json.load(f)
        for rel in generated['files']:
            cur = os.path.join(SYNTH_DIR, rel)
            new = os.path.join(tmp, rel)
            if not os.path.exists(cur):
                bad.append(f'{rel}: 缺失')
                continue
            with open(cur, 'rb') as f1, open(new, 'rb') as f2:
                if f1.read() != f2.read():
                    bad.append(f'{rel}: 内容不同（夹具被手改或生成器不确定）')
        cur_gen = os.path.join(SYNTH_DIR, 'generated.json')
        if os.path.exists(cur_gen):
            with open(cur_gen, encoding='utf-8') as f1, \
                    open(os.path.join(tmp, 'generated.json'), encoding='utf-8') as f2:
                if f1.read() != f2.read():
                    bad.append('generated.json: 内容不同')
        else:
            bad.append('generated.json: 缺失')
        # 检查是否有多余文件（不在清单里 = 手放的文件，提示但不一定错）
        extra = []
        for dirpath, _dirnames, filenames in os.walk(SYNTH_DIR):
            for fn in filenames:
                full = os.path.join(dirpath, fn)
                rel = os.path.relpath(full, SYNTH_DIR).replace(os.sep, '/')
                if rel == 'generated.json' or rel == 'README.md':
                    continue
                if rel not in generated['files']:
                    extra.append(rel)
        if bad:
            print('[make_fixtures --check] 不一致：')
            for b in bad:
                print('  -', b)
            return 1
        if extra:
            print('[make_fixtures --check] 警告：存在未在生成清单中的文件：', extra)
        print(f'[make_fixtures --check] OK：{len(generated["files"])} 个产物逐字节一致')
        return 0
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


def main(argv):
    if '--check' in argv:
        return check_reproducible()
    quiet = '--quiet' in argv
    files = generate_all()
    if not quiet:
        stats = validate_aap(os.path.join(SYNTH_DIR, 'smoke.aap'))
        print(f'[make_fixtures] 生成 {len(files)} 个文件 -> {SYNTH_DIR}')
        print(f'[make_fixtures] smoke.aap: {stats["nodes"]} 节点 / {stats["lines"]} 行 ScriptData'
              f' / 背景 {stats["bgs"]}')
        print(f'[make_fixtures] bgName({BG_NAME}) = {bg_id(BG_NAME)}')
        print('[make_fixtures] 下一步：bash scripts/test.sh -- --only=synth_fixtures')
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
