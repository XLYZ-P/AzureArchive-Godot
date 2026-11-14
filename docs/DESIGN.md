# AzureArchive · Godot 复刻 设计契约（v1）

> 本文件是团队的唯一架构契约。所有模块按此实现；要改契约先和 Lead 说。
> 目标：用 **Godot 4.7.2 / 纯 GDScript** 复刻 AzureArchive（AA）——一个面向《蔚蓝档案》的
> 可视化剧情编辑器 + 剧情播放器，**完整支持 AA 的项目文件 `.aap` 与资源包/自定义资源格式**。
>
> 官方格式资料见 `docs/spec/`（由 format-researcher 产出，权威来源）：
> - `docs/spec/aap.md` —— `.aap` 工程 JSON 全字段
> - `docs/spec/resources.md` —— 数据目录 / manifest.json / 官方资源包（Unity Addressables）
> - `docs/spec/commands.md` —— `#额外指令` 与 `[内联标记]` 规范
> - `docs/spec/enums.md` —— 表情/动作/进出场/过渡/背景效果等枚举

---

## 1. 技术约束

| 项 | 决定 |
|---|---|
| 引擎 | Godot **4.7.2**（headless 二进制 `/opt/godot/Godot_v4.7.2-stable_linux.arm64`） |
| 语言 | 纯 GDScript（`class_name` + typed），**不引入 C#/GDExtension**，保证 Android 也能导出 |
| 依赖 | 运行时零第三方依赖；Spine 立绘先走「atlas 静态帧 + PNG 立绘」兜底，动画作为可选增强层 |
| 分辨率 | 设计分辨率 1920×1080，`canvas_items` 拉伸；AA 逻辑坐标：**屏幕宽固定 2960 单位**，原点在中心，X 右正、**Y 上正**（Unity 屏幕坐标约定；见 docs/spec/commands.md §1.2） |
| 中文字体 | `assets/fonts/` 内置 CJK 字体（默认 WenQuanYi Zen Hei），用 Theme 统一引用，可替换 |
| 测试 | `godot --headless --path . --script tests/run_all.gd` 全绿是合并门槛 |

## 2. 目录结构与写作用域（严禁越界）

```
aa-godot/
├── project.godot                 # Lead
├── docs/DESIGN.md                # Lead（本文件）
├── docs/spec/                    # format-researcher
├── addons/aa_core/               # core-dev：.aap 模型/读写/编译/指令解析/xxhash/枚举
├── addons/aa_resources/          # pack-dev：数据目录、manifest、overrides、aa_pack、资源解析
├── addons/aa_player/             # runtime-dev：播放器运行时（舞台/对话框/选项/特效/音频）
├── addons/aa_editor/             # editor-dev：节点图编辑器 + 检查器 + 存盘
├── scenes/main/                  # Lead：目录界面（工程/存档列表、模式切换）
├── scenes/player/                # runtime-dev
├── scenes/editor/                # editor-dev
├── assets/                       # Lead（主题/字体/图标/占位图），其他模块只读
├── fixtures/                     # aap/（researcher）、pack/（pack-dev）、synth/（qa-dev）
├── tools/                        # pack-dev：Python UnityPy 提取器 / fixture 生成脚本
└── tests/                        # qa-dev：headless 测试
```

规则：
1. 只改自己作用域内的文件；跨模块调用只走下面声明的 API。
2. 新增公共类/方法 = 改契约：先在群里（send_message 给 lead）说明，Lead 更新本文件。
3. 不要运行全仓库替换/格式化；不要动别人的 `.tscn`。
4. 每个模块自带 `README.md` 说明自己实现了什么、还有哪些 TODO（中文）。

## 3. 数据流

```
projects/xxx.aap ──AapProject.load──> 文档模型 ──AapCompiler──> PlayScript ──> Player 播放
        ▲                                   │
        └──── Editor（GraphEdit 节点图）◄────┘
数据根目录（可切换为 AA 真实 data/ 目录）
  projects/  saves/  overrides/  assets/  settings/  packs/<id>/（我们转换后的 aa_pack）
        │
        ▼
AAResources：加载 manifest（全局 overrides + 本地同名文件夹 + 已安装 aa_pack）→ 资源解析（角色/背景/BGM/音效/弹出图/语音）
```

## 4. `.aap` 格式（真实样本实测，`fixtures/aap/Kei-初遇.aap`，294KB / 17 节点 / 170 行）

- 编码：UTF-8 **无 BOM** 的 Newtonsoft.Json JSON，带 `$type`，字段顺序有语义（AA 写出时保持顺序）。
- 顶层：
```jsonc
{ "$type": "ProjectData, Assembly-CSharp",
  "ProjectName": "Kei-初遇",
  "PreviewBgName": 3558049603,          // int，背景 ID = xxHash32(utf8(friendlyName), 0)
  "PreviewHeader": "Kei",               // string|null
  "PreviewTitle": "初遇",               // string|null
  "nodes": { "$type": "System.Collections.Generic.List`1[[NodeData, Assembly-CSharp]], mscorlib",
             "$values": [ /* 节点，顺序=编辑器里的节点顺序 */ ] } }
```
- 四种节点（`$type` 判别），公共字段顺序 `Guid, ConnectionsTo, X, Y`：
  | 类型 | 关键字段（顺序） |
  |---|---|
  | `EntryNodeData, Assembly-CSharp` | `Title, Header` + 公共；**Guid 必须全 0**，每个工程恰好 1 个 |
  | `ScriptNodeData, Assembly-CSharp` | `Scripts`（List`1[[ScriptData…]]）, `NodeName` + 公共 |
  | `SelectionNodeData, Assembly-CSharp` | `selectionTexts`（List`1[[System.String…]]，**固定 16 项**，未用补 ""） + 公共；`ConnectionsTo[i]` 对应第 i 个选项 |
  | `ExitNodeData, Assembly-CSharp` | `IsEnding`(bool), `EndText`(str), `NeHeader`, `NeTitle`, `NeScriptDirty`(ScriptData) + 公共 |
- `ConnectionsTo`：`{"$type":"System.Collections.Generic.List`1[[System.Guid, mscorlib]], mscorlib","$values":["<guid>",…]}`，出边列表。
- `X`,`Y`：编辑器画布坐标（C# float32 精度）。**AA 坐标系 Y 向上为正**（入口在 (0,0)，出口在 Y≈-4000~-13428 = 下方）。屏幕空间指令（`#zmc`/`#st`/`#stm`）同一约定：原点在屏幕中心、X 右正、Y 上正、宽 2960 逻辑单位。
- `ScriptData` 字段顺序（**严格**）：
  `text, popup, bgEffect, bgName, bgFriendlyName, sound, voice, transition, bgmId, selectionGroup, additionalPrompt, characters, speakerSlotNum, highlightedSlotNums, isDialogScript, placeText`
  - `bgName` = xxHash32(`bgFriendlyName`, seed=0)（`""` 背景时 bgName/bgFriendlyName 均为空/0）
  - `characters` 恒 6 项：下标 0 = 无立绘说话槽，1–5 = 可见站位；`CharacterRecordData` 字段顺序
    `name, faceId, startingPos, endingPos, emoticon, action, effect, appear, shapeOverride`
  - `speakerSlotNum`/`highlightedSlotNums` 也是槽位下标；`highlightedSlotNums` 是 List`1[[System.Int32…]]
  - `additionalPrompt`：`#` 指令，多条用 `\n` 分隔
- 枚举/编译规则：见 `docs/spec/`。核心硬约束：
  1. 同一行各角色 `startingPos` 两两不同，且等于 `characters` 数组下标；
  2. 上一行留场角色本行必须 `startingPos == 上一行 endingPos`，离场用 `#N;hide` 编译语义；
  3. 选择节点选项数 = `ConnectionsTo` 条数（`selectionTexts` 保留 16 槽）。
- `.aas`：AA 的编译产物是 **FlatBuffers 二进制**（无公开 schema，暂不解析）。本复刻直接播放 `.aap`；
  自有编译缓存用 `.aac`（JSON，`PlayScript` 序列化），仅作性能缓存，不是 AA 格式。

## 5. 核心 API 契约

### 5.1 `addons/aa_core/`（core-dev）

所有类都要 `class_name`，可被其他模块直接实例化。

```gdscript
# aap_project.gd
class_name AapProject extends RefCounted
const NODE_ENTRY := 0; NODE_SCRIPT := 1; NODE_CHOICE := 2; NODE_EXIT := 3
var project_name: String
var preview_bg_name: int
var preview_header: Variant      # String 或 null
var preview_title: Variant
var nodes: Array                  # Array[AapNode]
static func load_from_file(path: String) -> AapProject
static func load_from_string(text: String) -> AapProject
func save_to_file(path: String) -> Error
func to_json_text(pretty := true) -> String
func get_entry() -> AapNode
func find_node(guid: String) -> AapNode
func add_node(node_type: int, pos := Vector2.ZERO) -> AapNode
func remove_node(node: AapNode) -> bool
func connect_nodes(from: AapNode, to: AapNode) -> bool     # choice: 追加一个选项
func disconnect_nodes(from: AapNode, to: AapNode, option_index := -1) -> bool
func compile() -> PlayScript

# aap_node.gd
class_name AapNode extends RefCounted
var node_type: int
var guid: String
var connections: PackedStringArray
var pos: Vector2
var node_name: String                     # Script
var scripts: Array                        # Array[AaScriptLine]（Script）
var title: String; var header: String      # Entry
var selection_texts: Array                # PackedStringArray（Choice，16 槽）
var is_ending: bool; var end_text: String  # Exit
var ne_header: String; var ne_title: String; var ne_script: AaScriptLine
static func make(node_type: int, pos := Vector2.ZERO) -> AapNode
static func from_dict(d: Dictionary) -> AapNode
func to_dict() -> Dictionary               # 按 AA 字段顺序输出

# script_line.gd / character_record.gd
class_name AaScriptLine extends RefCounted   # 字段见 §4，snake_case；额外 parsed 缓存
class_name AaCharacterRecord extends RefCounted
func is_empty() -> bool

# play_script.gd
class_name PlayScript extends RefCounted
var start_guid: String
var nodes: Dictionary                      # guid -> PlayNode
class_name PlayNode ...                    # 或内部字典，由 core-dev 定，需暴露：
func get_node(guid: String) -> PlayNode
# Player 只依赖 PlayScript/PlayNode 读取执行数据

# aap_compiler.gd
class_name AapCompiler  # 或 AapProject.compile() 内部实现
# 负责把节点图扁平成可执行序列：行级合并（同一 ScriptNode 的 scripts 顺序播放）、
# 选项跳转表、出口节点（Ending / To be continued / #nextepisode）

# xxhash32.gd
class_name AaHash
static func xxh32(data: PackedByteArray, seed := 0) -> int
static func bg_id(friendly_name: String) -> int

# enums.gd
class_name AaEnums
const EMOTICONS := {...}   # int -> {symbol, zh, keynote}
const ACTIONS := {...}     # int -> {id, zh}
const APPEAR := {...}      # int -> {id, zh}
const SHAPES := {...}      # 1 sig / 2 black / 4 closeup
const TRANSITIONS := {...} # int -> name（以 format-researcher 的 tables 为准）
const BG_EFFECTS := {...}

# command_parser.gd
class_name AaCommands
class ExtraCommand: name, args, raw, slot, fx   # 用内部 class 或 Dictionary，需文档说明
static func parse_extra(prompt: String) -> Array        # 支持 "\n" 与多指令
static func parse_inline(text: String) -> Array         # 富文本 run：[size][color][ruby] 等
static func to_bbcode(text: String) -> String           # 给 RichTextLabel 用
static func strip_inline(text: String) -> String
```

要求：解析器对未知字段/未知 `$type` **容错保留**（round-trip 不丢数据）；序列化时字段顺序与 AA 一致；
所有单元测试由 qa-dev 写在 `tests/`，core-dev 配合提供可测 API。

### 5.2 `addons/aa_resources/`（pack-dev）

autoload：`AAResources`（`aa_resources.gd`，在 project.godot 注册）。

```gdscript
# 数据根目录
var data_root: String                      # 默认 "user://aa_data"
func set_data_root(path: String) -> void
func ensure_layout() -> void               # 创建 projects/saves/overrides/assets/packs/settings
func get_projects() -> Array[Dictionary]   # [{name, path, category, modified}]
func get_saves() -> Array[Dictionary]

# 资源上下文（播放/编辑一个工程时）
func make_context(project_path := "", save_path := "") -> AaResContext
class AaResContext:
    func get_character(id: String) -> AaCharacterAsset
    func get_characters() -> Array[AaCharacterAsset]
    func get_bg(friendly_name: String) -> Texture2D
    func get_bg_by_id(bg_id: int) -> Texture2D
    func get_bg_entries() -> Array                 # [{id, name, texture, category}]
    func get_bgm(key: Variant) -> AudioStream      # key: id(int) 或 name(String)
    func get_bgm_entries() -> Array
    func get_sound(name: String) -> AudioStream
    func get_sound_entries() -> Array
    func get_popup(name: String) -> Texture2D
    func get_popup_entries() -> Array
    func get_voice(guid: String) -> AudioStream
    func get_bg_effect(name: String) -> Variant    # 至少返回可播的占位/粒子
    func get_manifest() -> AaManifest

# manifest（manifest.json）读写
class_name AaManifest extends RefCounted
# 字段：character_overrides, voice_overrides, popup_overrides, sound_overrides,
#       bg_overrides, bg_effect_overrides, bg_spine_overrides, bgm_overrides
func load_from_file(path) / save_to_file(path)
func overlay(local: AaManifest) -> void

# aa_pack（转换后的开放资源包；布局见 docs/spec/resources.md）
func install_pack(path: String) -> Error        # 支持 .zip 与文件夹；解压到 packs/<id>/
func get_packs() -> Array[Dictionary]           # [{id, name, version, path, manifest}]
func uninstall_pack(id: String) -> Error
```

覆盖优先级（低→高）：aa_pack < `overrides/`（全局） < `projects|<saves>/<同名文件夹>/`（本地）。
资源 ID 约定：角色 `Identifier`（自定义）或原生角色名（如 `白子`/`모모이`/`shiroko` 均需可查）；
背景用 `bgFriendlyName`（如 `BG_MainOffice`，自定义背景 = 文件名 stem）；BGM 名如 `Theme_12`，`999` = 静音；
音效名如 `SE_Typing_01`；弹出图 = 文件名 stem；语音 = `voice` GUID → `<本地文件夹>/voices/<guid>.ogg`。

### 5.3 `addons/aa_player/`（runtime-dev）

`scenes/player/Player.tscn`（根 `Control`，脚本 `addons/aa_player/player.gd`）：

```gdscript
class_name AaPlayer extends Control
func setup(project: AapProject) -> void      # 或 setup_from_path(path)
func play() -> void
func jump_to(guid: String) -> void
signal finished
signal request_exit
# 内部：AaInterpreter（逐行推进）、AaStage（背景/立绘/特效/屏幕文字/弹出图）、
#       AaDialogueBox（姓名/台词/打字机/语音）、AaChoiceOverlay、AaBacklog、AaAutoPlay
```

MVP 必须支持：
- 背景（切换 + `transition` 淡入淡出/溶解等，至少 fade/cut）、BGM/SE、语音播放；
- 5 立绘槽 + 说话槽：进出场（appear）、走位（startingPos→endingPos）、表情（faceId）、高亮/变暗、
  气泡 emoticon、动作 action（至少 greeting/jump/falldown 的位移/抖动近似）、形状 shapeOverride（sig/black/closeup 用 modulate/scale 近似）；
- 对话框：打字机、姓名、`[size]/[color]/[ruby]` 内联标记、点击继续、自动/快进、对话历史（backlog）；
- 选项（SelectionNodeData）：居中按钮、键盘 1-9、跳转到对应 guid；
- 出口：Ending / To be continued / `#nextepisode` 场景衔接；
- 额外指令：`#wait`、`#bgshake`、`#fx;AronaTouch`（占位）、`#zmc`、`#st/#stm/#clearST`、`#hidemenu/#showmenu`、`#N;fx;{shot}`、`#N;m N`、`#N;hide`、`#N;al|ar|a|dl|dr|d`；
- 竖屏/横屏自适应（按 1920×1080 设计，等比缩放）。
- 角色资源缺失时：显示占位（半透明剪影 + 名字），不崩溃。

## 6. 编辑器（`addons/aa_editor/`，editor-dev）

`scenes/editor/Editor.tscn`：GraphEdit 画布 + 侧边检查器 + 顶部工具栏。
- 节点：入口（唯一、不可删）、脚本、选择、出口；GraphNode 外观区分类型；右键/拖拽连线；
- 检查器：脚本节点（脚本列表增删、选中脚本的 角色/环境/对话/额外指令 编辑，含预览占位）；
  选择节点（选项文本，数量=出边数）；出口节点（Ending/未完待续/下回预告）；入口节点（序号/标题）；
- 资源选择器：角色/背景/BGM/音效/弹出图/语音，从 `AAResources` 的 context 取；
- 保存/另存为 `.aap`（字段顺序与 AA 一致）；新建工程；导入工程；编译 → `PlayScript` → 可选直接播放；
- 撤销/重做（至少节点增删与连线）、自动保存开关（默认关）。
- 双击工程/存档的目录界面的入口在 Lead 的 `scenes/main/`，editor-dev 提供 `Editor.open(project:AapProject, path:String)`。

## 7. 测试与验收（qa-dev 主导）

- `tests/run_all.gd`：纯 headless，包含
  1. `test_aap_roundtrip.gd`：读 `fixtures/aap/Kei-初遇.aap` → `to_json_text()` → 再解析 → 深度相等（字段顺序+值），
     并断言 `$type` 字符串、节点数、选择节点 16 槽、bgName==xxh32(friendly)；
  2. `test_xxhash.gd`：已知向量 + 样本里 170 行 bgName 全量校验；
  3. `test_commands.gd`：指令解析/内联标记；
  4. `test_resources.gd`：合成 aa_pack + overrides 覆盖优先级；
  5. `test_player_smoke.gd`：加载合成工程跑剧本到结尾（headless，用假资源/1 帧推进）；
  6. `test_editor_smoke.gd`：新建工程→加节点→连线→保存→重载。
- 运行：`cd /root/workspace/aa-godot && /opt/godot/Godot_v4.7.2-stable_linux.arm64 --headless --import && ... --script tests/run_all.gd`
- 合成 fixture 生成脚本放 `tools/`（qa-dev 写 `tools/make_fixtures.py`，pack-dev 提供 aa_pack 生成器）。

## 8. 里程碑（Lead 按此验收）

| M | 内容 | 负责人 |
|---|---|---|
| M1 | 格式规范 + fixtures 就绪；工程能 headless 打开 | researcher / Lead |
| M2 | `aa_core` 全绿 round-trip；`aa_resources` 能列出/解析本地 overrides 与 syn 合成包 | core / pack |
| M3 | 播放器能完整播放 `Kei-初遇.aap`（无官方资源包时用占位素材）+ 合成示例工程 | runtime |
| M4 | 编辑器能新建/打开/编辑/保存 `.aap`（与 AA 双向兼容） | editor |
| M5 | 全量测试绿 + 真资源包转换工具（UnityPy）+ 文档/示例交付 | qa / pack / Lead |

## 9. 已知非目标（近期）

- 不解析 AA `.aas`（FlatBuffers 无公开 schema）；不 1:1 还原 BA 官方 Addressables 资源包（用 Python 转换工具桥接）；
- 不做 Spine 骨骼动画完整运行时（先静态帧 + PNG 立绘；接口预留 `AaSpineProvider`）；
- 不实现联网资源下载/账号/官网功能。

---

## 10. 【补充·重要】headless 环境限制（Lead 实测）

本机（Android proot aarch64）Godot 4.7.2 的 **`--import` / `--editor` 会崩溃**（`double free or corruption`，RC=134）。
因此：

1. **测试和 headless 运行不得依赖导入器（.import）产物**。`res://` 下的贴图/字体/音频 **禁止** 写成 `.tscn` 的
   `ext_resource`；`.tscn` 里只引用脚本和内建控件，素材一律运行时从原始文件加载（或程序化生成）。
2. 运行时加载统一用 `addons/aa_resources/raw_loader.gd`（`class_name AaRawLoader`，Lead 已提供）：
   `read_text / read_json / load_texture / load_font / load_audio`。内部用 `Image.load()`、
   `FontFile.load_dynamic_font()`、`AudioStreamOggVorbis/MP3/WAV.load_from_file()`，绕过导入器。
   已实测：SVG 贴图、TTF 字体、脚本、JSON 在纯 headless 下都能加载。
3. 测试入口一律 SceneTree 脚本：`godot --headless --path . --script tests/run_all.gd`；
   冒烟跑主场景用 `godot --headless --path . --quit-after N`。**不要跑 `--import`**。
4. 用编辑器打开工程时导入器正常工作，不影响设计；只是不能作为本机 CI 的依赖。
5. 字体：`assets/fonts/wqy-zenhei-extracted.ttf`（16MB，中文可用）；UI 通过 `AaRawLoader.load_font` 加载后
   `add_theme_font_override("font", ...)`。需要全局主题时由各场景根节点运行时构建。

## 11. 【补充】class_name 全局解析与 class cache（Lead 实测，所有成员必须遵守）

本机 headless 没有编辑器扫描，**GDScript 的 `class_name` 全局解析依赖**
`res://.godot/global_script_class_cache.cfg`（Godot 4.7 的 `ProjectSettings::get_global_class_list()`，
条目必须有 `base/class/icon/language/path/is_abstract/is_tool` 七个字段，缺一个就会被引擎跳过）。

- Lead 提供了生成器：`python3 scripts/gen_class_cache.py`（扫描所有 .gd 的 `class_name`/`extends`）。
- **统一用 `scripts/godot.sh <args>` 跑 Godot**（它会先自动生成缓存再执行）：
  ```bash
  cd /root/workspace/aa-godot
  scripts/godot.sh --script /tmp/xxx.gd          # 跑测试脚本
  scripts/godot.sh --quit-after 5                 # 冒烟跑主场景
  ```
  也可以 `python3 scripts/gen_class_cache.py && /opt/godot/... --headless --path . ...`（等价）。
- 新增/重命名 `class_name` 后必须重新生成缓存，否则其它脚本解析报
  `Identifier "Xxx" not declared in the current scope`。
- `scripts/test.sh` 固定跑 `tests/run_all.gd`（qa-dev 维护）。
