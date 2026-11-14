# aa_core —— AzureArchive 格式核心层

纯 GDScript（Godot 4.7）实现的 AA 格式核心：`.aap` 工程读写、节点/行模型、
`compile()` 编译成播放器可执行数据、`#额外指令` 与 `[内联标记]` 解析、xxHash32、完整枚举表。

> 本目录**只依赖 Godot 内置类**，不依赖 `aa_resources` / `aa_player` / `aa_editor`。
> 所有类都有 `class_name`，其他模块直接按类名使用（headless 下先跑
> `python3 scripts/gen_class_cache.py`，或统一用 `scripts/godot.sh`）。

## 文件

| 文件 | 类 | 说明 |
|---|---|---|
| `aap_project.gd` | `AapProject` | `.aap` 顶层工程：load/save/to_json_text、节点增删、连线、校验、`compile()` |
| `aap_node.gd` | `AapNode` | 四种节点（Entry/Script/Choice/Exit）模型，AA 字段顺序、未知字段保留、float32 坐标 |
| `script_line.gd` | `AaScriptLine` | `ScriptData`（一行对白/环境），`characters` 恒 6 项，自动等待规则 |
| `character_record.gd` | `AaCharacterRecord` | `CharacterRecordData`（一个立绘槽的状态） |
| `play_script.gd` | `PlayScript` | 编译产物（guid -> `PlayNode`），可序列化为 `.aac` JSON 缓存 |
| `play_node.gd` | `PlayNode` | 可执行节点：行序列 / 选项跳转表 / 出口类型 + 兼容字段 |
| `aap_compiler.gd` | `AapCompiler` | 节点图 -> PlayScript（`AapProject.compile()` 内部实现） |
| `command_parser.gd` | `AaCommands` | `#额外指令`、`[内联标记]`、`to_bbcode`、`strip_inline`、参数结构化 |
| `xxhash32.gd` | `AaHash` | xxHash32（seed=0）与 `bg_id(friendly_name)` |
| `enums.gd` | `AaEnums` | 表情/动作/进出场/立绘效果 + **过渡 61 条 / 背景效果 26 条**完整表 |
| `aap_json.gd` | `AaJson` | Newtonsoft `$type` 常量、容错读取、**自写有序 JSON 序列化**（浮点精度/整数区分） |
| `guid_util.gd` | `AaGuid` | UUID v4 生成 / 校验（AA 用小写 36 字符 `D` 格式） |

## 快速上手

```gdscript
# 读工程
var project := AapProject.load_from_file("res://fixtures/aap/sample_kei_01.aap")
print(project.project_name, " ", project.nodes.size(), " 节点")

# 入口 / 节点 / 行
var entry := project.get_entry()            # Guid 全 0 的 EntryNodeData
var node := project.find_node(entry.connections[0])
print(node.node_name, " 行数=", node.scripts.size())
for line in node.scripts:
    print(line.speaker_name(), "：", line.plain_text())
    print("  背景=", line.bg_friendly_name, " id=", line.bg_name)
    print("  过渡=", AaEnums.transition_zh(line.transition))
    print("  背景效果=", AaEnums.bg_effect_zh(line.bg_effect))
    print("  指令=", line.get_commands())
    print("  自动等待=", line.effective_wait_ms())

# 存盘（紧凑单行 JSON、无 BOM，与 AA 风格一致；也可 to_json_text(true) 缩进调试）
project.save_to_file("user://copy.aap")
```

**round-trip 保证**：`load -> to_json_text -> load` 后**字段顺序与值完全一致**
（`$type` 字符串逐字节一致；JSON null 保留；X/Y 原始 double 精度保留；未知字段/未知节点原样写回）。

### 新建 / 编辑 / 连线

```gdscript
# 默认 = 入口节点 + 一个空脚本节点（含 1 条空行）并连好线，保存后即可被 AA 打开
var project := AapProject.create("新工程")
# 只要入口节点：AapProject.create_empty("新工程")

var s1 := project.add_node(AapProject.NODE_SCRIPT, Vector2(0, -400))
var line := AaScriptLine.make_empty()          # 自动生成 voice GUID、bgmId=999
line.text = "你好"
line.bg_friendly_name = "BG_Black"
line.bg_name = AaHash.bg_id(line.bg_friendly_name)
s1.scripts.append(line)

var exit_node := project.add_node(AapProject.NODE_EXIT, Vector2(0, -600))
exit_node.is_ending = true
project.connect_nodes(project.get_entry(), s1)
project.connect_nodes(s1, exit_node)
print(project.validate())                      # 人类可读的问题列表

# Choice 节点：每条出边 = 一个选项（selection_texts 固定 16 槽；连到同一目标多次也允许）
var choice := project.add_node(AapProject.NODE_CHOICE)
project.connect_nodes(choice, s1)
choice.set_selection_text(0, "选项一")
```

### 编译并交给播放器（PlayScript / PlayNode API 清单）

`AapProject.compile()` 返回 `PlayScript`：节点按 guid 铺平（Script 的 `scripts` 合并成行序列），
选项跳转表与出口类型都已就绪。

**PlayScript 字段/方法**

| 成员 | 说明 |
|---|---|
| `start_guid: String` | 起点（入口 guid；坏工程退化为第一个节点） |
| `project_name: String` | 工程名 |
| `entry_title / entry_header: String` | 入口节点的 Title / Header（标题卡用，来自 EntryNodeData） |
| `nodes: Dictionary` | guid -> `PlayNode` |
| `warnings: Array` | 编译期问题（坏连线/不可达/重复 guid/多出边…，不影响播放） |
| `project: AapProject` | 源工程（可为 null，`.aac` 反序列化后为 null） |
| `get_node(guid) -> PlayNode` | 取节点，不存在返回 null |
| `get_start_node() / get_node_count() / all_nodes() / is_empty()` | 遍历辅助 |
| `first_exit_node() -> PlayNode` | 第一个出口 |
| `to_dict() / from_dict() / to_json_text()` | `.aac` JSON 缓存 |
| `save_to_file(path) / load_from_file(path)` | `.aac` 缓存读写（静态 load） |

**PlayNode 字段/方法**

| 成员 | 说明 |
|---|---|
| `guid: String`、`pos: Vector2` | 节点 guid / 编辑器坐标（调试用） |
| `kind: int` | `PlayNode.KIND_ENTRY / KIND_SCRIPT / KIND_CHOICE / KIND_EXIT`（0/1/2/3） |
| `kind_name: String` | `"entry"/"script"/"choice"/"exit"`（字符串判别，跨模块不用比 kind 常量） |
| `lines: Array` | SCRIPT：要顺序播放的 `AaScriptLine` 列表（引用原对象，只读） |
| `next_guid: String` | ENTRY/SCRIPT：播完去哪（`""` = 流程结束） |
| `options: Array` | CHOICE：`PlayNode.Choice` 列表（`index/text/target_guid/valid`） |
| `exit_type: int` | EXIT：`EXIT_ENDING / EXIT_TO_BE_CONTINUED / EXIT_NEXT_EPISODE` |
| `end_text: String` | EXIT：Ending 的结束语（EndText） |
| `ne_header / ne_title: String` | EXIT：下一话衔接（`#nextepisode;Header;Title` 推导） |
| `ne_line: AaScriptLine` | EXIT：NeScriptDirty（结局画面背景/BGM） |
| `ne_text: String` | EXIT：NeScriptDirty.text（`[实]` 可为 ""/`"Header;Title"`/`"工程名;标题"`） |
| `connections / selection_texts / is_ending / ne_script` | 兼容字段（给 duck-type 适配层），编译时由 `sync_compat()` 同步 |
| `is_entry()/is_script()/is_choice()/is_exit()/is_terminal()` | 判别 |
| `line_count()/get_line(i)/valid_options()/find_option_by_target(guid)` | 查询 |
| `display_text() -> String` | EXIT 要显示的文字（EndText / NeTitle / NeText 的优先级） |

播放推进伪代码：

```gdscript
var script := project.compile()
var node := script.get_start_node()
while node != null:
    match node.kind:
        PlayNode.KIND_ENTRY:
            node = script.get_node(node.next_guid)
        PlayNode.KIND_SCRIPT:
            for line in node.lines:
                ... # 播放一行（背景/BGM/立绘/打字机/额外指令/等待，见下）
            node = script.get_node(node.next_guid)
        PlayNode.KIND_CHOICE:
            ... # 展示 node.options[i].text，玩家选择后：
            node = script.get_node(node.options[chosen].target_guid)
        PlayNode.KIND_EXIT:
            ... # node.exit_type + node.display_text() + node.ne_line
            node = null
print(script.warnings)
```

> `.aac` 是本项目自己的 JSON 编译缓存格式，**不是** AA 的 `.aas`（FlatBuffers，不解析）。

### 额外指令（additionalPrompt）

```gdscript
for cmd in AaCommands.parse_extra(line.additional_prompt):   # Array[AaCommands.ExtraCommand]
    # cmd.name: 小写规范化名；cmd.args: PackedStringArray；cmd.raw / cmd.slot / cmd.fx
    match cmd.name:
        AaCommands.CMD_WAIT:   wait(AaCommands.wait_ms(cmd))
        AaCommands.CMD_ST:     var st := AaCommands.parse_screen_text(cmd)   # pos/mode/font_size
        AaCommands.CMD_ZMC:    var z := AaCommands.parse_zmc(cmd)            # mode/center/scale/duration
        AaCommands.CMD_FX:     ... # cmd.slot >= 0 时是 #N;fx;{shot}；否则 fx=...
        AaCommands.CMD_NEXT_EPISODE: var ne := AaCommands.parse_next_episode(cmd)
```

支持的指令：`#wait;毫秒`、`#bgshake`、`#fx;AronaTouch`、`#zmc;模式;X,Y;系数;时长`、
`#st;[X,Y];模式;字号;`、`#stm;...`、`#clearST`、`#hidemenu`、`#showmenu`、
`#nextepisode;Header;Title`、`#N;fx;{shot}`、`#N;m 4`（也兼容 `#N;m4`）、`#N;hide`、
`#N;al|ar|a|dl|dr|d`、`#N;em;[재잘]`、`#N;h`、`#N;closeup`、`#N;jump`，
以及编译器生成的 `#na;` / `#title;` / `#place;` / `#continued`。未知指令原样保留（`name` 为小写原文）。

### 编译器自动指令推导（`.aap` 直接播放必需）

`.aap` 里**不存** `#N;m<K>`（走位）、`#N;hide`（切镜头隐藏）、`#N;<al|ar|a|dl|dr|d>`（进出场）、
`#N;em;<符号>`、`#N;jump`、`#N;closeup`、`#N;h`（高亮）、`#na`（旁白）等自动指令——
它们由 AA 编译 `.aas` 时从 `characters` 字段推导（docs/spec/commands.md §3）。
直接解释 `.aap` 的播放器必须自己算，`AaScriptLine` 已提供现成推导（按行推进时传入上一行）：

```gdscript
# 1) 舞台状态事件（顺序 = AA 求值顺序：进出场 → 隐藏 → 走位 → 气泡/动作/特写/高亮 → 旁白）
for e in line.derive_stage_events(prev_line):   # prev_line 为 null 表示首次播放
    match e["kind"]:
        "appear":    ... # e.slot, e.token(al/ar/a/dl/dr/d)
        "hide":      ... # e.slot
        "move":      ... # e.slot, e.value(=endingPos)
        "emoticon":  ... # e.slot, e.value(=-1 无/0 怒筋...), e.token(原生符号)
        "action":    ... # e.slot, e.value, e.token(greeting/.../jump)
        "closeup":   ... # e.slot
        "highlight": ... # e.slot（顺序不保证升序）
        "narration": ... # 旁白行
# 2) 环境变化（与上一行对比）：背景/过渡/背景效果/BGM/音效/弹出图/地点
var env := line.derive_environment(prev_line)
#    keys: bg_changed, bg_name, bg_friendly_name, transition, transition_changed,
#          bg_effect, bg_effect_changed, bgm_changed, bgm_id, bgm_muted, sound,
#          popup, popup_cleared, place_text
# 3) 等待：作者 #wait 覆盖自动；都没有返回 -1（= 等玩家点击/自动）
var wait_ms := line.derive_wait_ms()
# 4) 懒人版：直接拿有序事件列表（舞台事件 → environment → command → text → wait）
for ev in line.build_events(prev_line):
    ... # ev["kind"]，见 script_line.gd 注释
```

播放器只需按行推进（Script 节点内顺序、跨节点时把上一节点最后一行作为 `prev`），
就能看到走位/隐藏/进出场/气泡/自动停顿。**不要把自动指令写回 `.aap`**（写回等于覆盖，AA 会重复处理）。

**自动等待**（AA 编译器行为，HaloCue 134 组配对实测）：有气泡 → 2500ms；
否则有位移/进出场/动作 → 1500ms；都没有 → 0。作者写的 `#wait` 是**覆盖**不是叠加。

```gdscript
line.auto_wait_ms()        # 0 / 1500 / 2500
line.explicit_wait_ms()    # 作者 #wait 的值；没有 -1
line.effective_wait_ms()   # 显式覆盖自动；都没有 0
line.screen_text_command() # #st/#stm（屏幕文字内容就是 line.text）
```

### 内联标记（text）

```gdscript
var bb := AaCommands.to_bbcode(line.text)            # 给 RichTextLabel
var plain := AaCommands.strip_inline(line.text)      # backlog / 日志
var runs := AaCommands.parse_inline(line.text)       # 结构化 run 列表（编辑器/注音叠字用）
var pairs := AaCommands.ruby_pairs(line.text)        # [{text, ruby}]
```

| AA 写法 | 转换结果 |
|---|---|
| `[size=200]…[/size]` | `[font_size=N]`，N = round(AA值 × base / 60)（AA 的 60 = 原大小，默认 base=48；传 60 可 1:1） |
| `[FF0000]…[-]` / `[FF0000AA]…[-]` / `[aa00cc]…[-]` | `[color=#RRGGBB(AA)]…[/color]` |
| `[ruby=拼音]…[/ruby]` | `…（拼音）`（Godot 无原生注音；`ruby_pairs()` 可取结构化注音对自行叠加） |
| `[b] [i] [u] [s]` | 同名 BBCode 透传 |
| `[sup] [sub]`、`[两位数]`透明度 | 标签丢弃、文字保留（RichTextLabel 无对应效果） |
| 无法识别的 `[xxx]` | 原文保留，BBCode 里转义为 `[lb]…[rb]` |

`to_bbcode` 用**标签栈**输出：正确嵌套原样保留；**交叉嵌套**（如 `[size=100][FF0000]红[/size][-]`）
会先关闭中间标签再重新打开，保证产物是配平合法的 BBCode（RichTextLabel 不会把 `[/font_size]`
当字面文字）；未闭合的标签在结尾自动补闭合，多余的闭合标签忽略。（原 Q-004 已修复）

### 枚举 / 哈希

```gdscript
AaHash.xxh32(bytes, 0) -> int          # 标准 xxHash32，返回无符号 32 位
AaHash.bg_id("BG_RuinUndergroundPassage") == 3558049603

AaEnums.emoticon_zh(0)                 # "怒筋"（EMOTICONS: symbol/zh/en/keynote）
AaEnums.appear_token(3)                # "a"
AaEnums.shape_zh(5)                    # "剪影（通讯）+特写"（位掩码 1/2/4 可组合）
AaEnums.transition_zh(4004024664)      # "交叉渐变 1000ms"（61 条完整表）
AaEnums.transition_resolve("淡入淡出 2000")  # -> 2482233134（中文简写/英文名/数字 ID 都收）
AaEnums.bg_effect_zh(3134544579)       # "枪战"（26 条完整表）
AaEnums.bg_effect_resolve("集中线")     # -> 3550865647
```

- 过渡表来自 HaloCue 逆向的 `tables.TRANSITION`：`id -> {name(AA英文名), zh, group, duration(总时长ms), fade_in, fade_out}`，
  中文名是按分组+时长推导的显示名；`transition_resolve()` 支持 `"淡入淡出 2000"`、`"交叉渐变 500"`、`"Fade 1500 >> 1500"`、`"噪点"`、纯数字 ID。
- 背景效果表来自 `tables.BGEFFECT`：`id -> {name(资源名 UI_FX_<name>), zh(中文别名)}`。
- 已按 `docs/spec/enums.md` 校准背景效果中文名（如 `红滤镜（无背景）`/`闪电（含音效）`/`向右滚动 1.0`）。
- 另有 `FACE_IDS` / `FACE_SEMANTICS`（00 default/01 normal/…/06 depressed）/`FACE_ALIAS`（官方拼写错误归一化）
  与 `face_zh()`、`SLOT_LABELS`/`slot_label()`、`BGM_MUTE(999)`。

## 与其他模块的对接

- **Player**：`AapProject.load_from_file()` 后 `project.compile()` 得到 `PlayScript`，按上面的推进伪代码执行。
  旧适配层（`aap_mock.from_play_script()`）可直接消费 `nodes/start_guid`；注意 `kind` 用
  `PlayNode.KIND_*`（0=Entry,1=Script,2=Choice,3=Exit），或直接用 `kind_name` 字符串判别，
  **不要**混用其它模块自己的 kind 常量。`lines` 是 `AaScriptLine` 对象，字段 snake_case。
- **Editor**：`AaEditorBackend` 动态加载本目录脚本的路径/类名/方法均已对齐；
  `create()` 默认给「入口 + 空脚本节点」，`to_json_text(true)` 缩进版可做预览。
- **QA**：直接写类名即可（走 `scripts/godot.sh` 自动生成 class cache）。注意真实样本的
  `bgName` 是 **165/170 命中**，5 行 `BG_CS_Millenium_01_c` 是权威规格里记录的官方历史脏数据
  （stored=2434566677，computed=2177189307），不是实现 bug；`project.check_bg_ids()` 有明细。

## 自测

core-dev 自测脚本（736 项断言，临时脚本不入库）覆盖：真实样本 17 节点/170 行解析、round-trip
（含字段顺序、`$type` 逐字节、null、X/Y 精度）、bgName 校验、指令全覆盖、内联标记、枚举全表、
自动等待、增删连线（含重复连线）/校验、编译（选项跳转/出口三态/`#nextepisode`/`ne_text`）、`.aac` 序列化。

```bash
cd /root/workspace/aa-godot
scripts/godot.sh --script /tmp/test_core.gd
```

## 已知限制 / TODO

1. **过渡/背景效果表**：英文名/ID 与中文名已按 `docs/spec/enums.md` 校准。
   背景效果表本身仍不完整（规格记录 36 工程里有 1 个未收录 ID `2245459904`），未知 ID 安全降级为
   “未知过渡(id)”/“未知背景效果(id)”；`bgmId` 没有名称对照表（只有 999=静音）。
2. **样本历史脏数据**：`BG_CS_Millenium_01_c` 的 5 行 `bgName` 与 `xxh32(bgFriendlyName)` 不一致
   （stored=2434566677 / computed=2177189307，规格记录 8259/8268，AA 里对应“背景变黑”老 bug）。
   读工程**不自动改**；需要修时显式调用 `project.repair_bg_ids()`。
3. `Vector2` 是 float32，而 `.aap` 的 X/Y 是 C# float：解析后 `pos` 是 float32 近似，
   但序列化时用解析保留的原始 double 字面量（`pos` 未被编辑器改动时），round-trip 不丢精度；
   新建/拖动后的坐标按 float32 最短表示写回。
4. `selectionGroup` 非 0 的语义无样本（全 0）；AA 1.0 的 Auto 选项字段无文档，未知字段会原样保留但不参与编译。
5. 不解析 `.aas`（FlatBuffers 无 schema）；`.aac` 是本项目的 JSON 缓存格式。
6. `AapNode.pos` 是画布坐标，运行时不影响播放；编辑器保存后 AA 会按自己的布局重排（未实测）。
