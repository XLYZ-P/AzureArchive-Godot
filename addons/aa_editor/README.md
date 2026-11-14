# addons/aa_editor —— AzureArchive 节点式剧情编辑器

Godot 4.7.2 / 纯 GDScript 实现的 AA 可视化剧情编辑器：**GraphEdit 节点图 + 侧边检查器 + 资源选择器**，
读写 AA 的 `.aap` 工程（Newtonsoft `$type` JSON，字段顺序与 AA 一致，UTF-8 无 BOM）。

场景入口：`scenes/editor/Editor.tscn`（根 `Control` 挂 `editor.gd`）。
目录界面（Lead 的 `scenes/main/`）的用法：

```gdscript
var ed = load("res://scenes/editor/Editor.tscn").instantiate()
add_child(ed)
ed.request_exit.connect(func(): ed.queue_free())
ed.open_project_file("user://aa_data/projects/xxx.aap")   # 或 ed.new_project()
```

> 本机（Android proot aarch64）headless 下 `--import` 会崩溃（DESIGN §10），所以：
> `.tscn` 里**没有任何贴图/字体/音频 ext_resource**；CJK 字体在运行时用
> `AaRawLoader.load_font("res://assets/fonts/wqy-zenhei-extracted.ttf")` 加载后写进 Theme。

---

## 1. 文件结构

| 文件 | 作用 |
|---|---|
| `editor.gd` | `class_name AaEditor extends Control`：主界面（工具栏/三栏布局/状态栏）、打开/保存/新建/编译/播放预览、撤销重做、自动保存、快捷键 |
| `graph_view.gd` | `class_name AaGraphView extends GraphEdit`：四种节点渲染 + 连线/剪断/删除/拖动/缩放平移/双击；节点工厂拖放落点 |
| `graph_view` 内部 | 选择节点每个选项一个右侧出端口，最后一个「＋ 新选项」端口用于新增选项（AA：选项数 = 出边数，可重复连线） |
| `node_factory.gd` | `class_name AaNodeFactory`：左侧节点工厂面板（入口/脚本/选择/出口） |
| `node_factory_button.gd` | `class_name AaPaletteButton`：可拖拽的节点工厂按钮（`_get_drag_data` 提供 `aa_node_type`） |
| `inspector/inspector_panel.gd` | `class_name AaInspectorPanel`：右侧检查器（脚本/选择/出口/入口/工程属性） |
| `pickers/picker_dialog.gd` | `class_name AaPickerDialog`：资源选择器（角色/背景/BGM/音效/弹出图/语音） |
| `backend.gd` | `class_name AaEditorBackend`：数据层桥接。**优先用 `aa_core` 的 AapProject/AapNode/AaScriptLine/AaEnums/AaHash**；core 半成品或不可用时自动回退到 `model/fallback_project.gd` |
| `editor_enums.gd` | UI 下拉表（表情/动作/进出场/形状/过渡/背景效果）的本地兜底；core 的 `AaEnums` 可用时优先 |
| `model/fallback_*.gd` | fallback 版 `.aap` 模型（与 AA 完全兼容的读写：`$type`、字段顺序、null 保留、float32 坐标 round-trip 字节一致）；仅当 `aa_core` 不可用时使用 |

数据流：

```
Editor.tscn ──> AaEditor ──> AaEditorBackend ──> aa_core: AapProject / AapNode / AaScriptLine ...
                                  │
                                  └─(core 不可用)─> model/fallback_project.gd
```

---

## 2. 对外 API（目录界面 / headless 测试）

`AaEditor`（Editor.tscn 根节点）：

```gdscript
open_project_file(path: String) -> bool     # 打开 .aap；成功后自动 zoom-to-fit
open(project, path := "") -> bool           # 直接装载一个 AapProject
new_project() -> bool                       # 新建（core 可用时走 create_empty，只有入口节点）
get_project()                               # 当前 AapProject
add_node(node_type: int, pos := Vector2.ZERO) -> String   # 返回新节点 guid；脚本节点默认带 1 条空脚本
connect_nodes(from_guid: String, to_guid: String, option_index := -1) -> bool
delete_node(guid: String) -> bool           # 入口/有出边/有入边的节点拒绝删除并给状态提示
save() -> bool                              # 有路径按路径存；路径为空或 res:// 时存到数据目录
save_as(path: String) -> bool               # 指定路径保存（自动补 .aap 后缀）
compile()                                   # 返回 core 的 PlayScript（可空）
undo() / redo() -> bool
is_dirty() -> bool
get_current_path() -> String
get_graph() / get_inspector()               # 测试/高级用法
select_node(guid)                           # 等价双击节点

signal request_exit                          # 「返回」按钮
signal request_play(project)                 # 「播放预览」
signal project_saved(path)
```

`request_exit` 有外部监听时由外层负责销毁界面；没有监听时自动切回 `scenes/main/Main.tscn`（不存在则退出）。

---

## 3. 键位 / 鼠标操作

| 操作 | 方式 |
|---|---|
| 创建节点 | 从左侧「节点工厂」把按钮**拖到画布**；或**单击**按钮在视野中心创建 |
| 移动节点 | 左键拖动节点（松手写回 `.aap` 的 X/Y） |
| 平移视角 | 左键拖动空白画布（另外中键拖动/滚动条也可） |
| 缩放视角 | 鼠标滚轮；或工具栏「－ / ＋ / 适应」 |
| 连线 | **右键从节点上半部分拖到目标**（从入端反向拖）或下半部分拖出（从出端）；也可左键从端口拖 |
| 断开单条连线 | 右键在空白处拖动划红线，松手剪断与红线相交的连线 |
| 删除节点 | 选中后按 `Delete`（入口节点 / 仍有连线的节点会被拒绝并提示） |
| 打开检查器 | 双击节点（或单击选中，右侧检查器自动切换） |
| 选择节点加选项 | 从选择节点右侧「＋ 新选项」端口拖一条线到目标；同一目标可重复连接（AA 支持） |
| 保存 | `Ctrl+S`；另存为 `Ctrl+Shift+S` |
| 打开 | `Ctrl+O` |
| 新建 | `Ctrl+N` |
| 撤销 / 重做 | `Ctrl+Z` / `Ctrl+Y`（或 `Ctrl+Shift+Z`） |
| 编译 | `Ctrl+B`（工具栏「编译」） |
| 播放预览 | `F5`（编译后实例化 `scenes/player/Player.tscn`；播放器未就绪时只编译并提示） |
| 返回 | 工具栏「返回」/ `Esc`（预览中 Esc = 退出预览） |

---

## 4. 检查器覆盖的 `.aap` 字段

### 脚本节点（ScriptNodeData）
- `NodeName`
- 脚本列表：＋添加（在选中项后插入，继承上一行的背景/BGM/过渡环境字段）、−删除、↑上移、↓下移、⧉复制
- 选中脚本 `ScriptData`：
  - `text`（多行，支持 AA 内联标记 `[size=]`/`[RRGGBB]`/`[ruby=]`）
  - `additionalPrompt`（多行 `#` 指令，每行一条）
  - `characters[6]`：6 个栏位按钮切换；每栏
    `name` / `faceId` / `startingPos` / `endingPos` / `appear` / `action` / `emoticon` /
    `shapeOverride`（**位掩码多选**：1=sig 剪影、2=black 变暗、4=closeup 特写，可组合）
  - 环境：`bgFriendlyName`（选择背景时自动用 `AaHash.xxh32` 写 `bgName`）、`bgEffect`、`transition`、
    `bgmId`（选择 BGM / 一键静音 999）、`popup`、`sound`、`voice`、`placeText`
  - 高级：`speakerSlotNum`、`highlightedSlotNums`（逗号分隔）、`isDialogScript`、`selectionGroup`、
    `bgName` 与 `bgFriendlyName` 一致性显示 + 「重算 bgName」按钮

### 选择节点（SelectionNodeData）
- 选项文本（数量 = `ConnectionsTo` 条数，写 `selectionTexts[i]`；固定 16 槽）
- 每条选项可单独「断开」（同步删除对应选项文本）
- 同一目标重复连线按 AA 语义保留；`selectionTexts` 里多余的旧文案不会被清空（容错）

### 出口节点（ExitNodeData）
- `IsEnding`、`EndText` / `NeHeader`、`NeTitle`（按类型切换显示）
- `NeScriptDirty` 的 `text`、`additionalPrompt`、`bgFriendlyName`（自动算 `bgName`）、`bgmId`

### 入口节点（EntryNodeData）
- `Header`（序号）、`Title`（标题）；只填标题会隐藏序号（AA 规则）
- 入口唯一不可删，Guid 恒全 0，X/Y 恒 0

### 未选中节点 = 工程属性
- `ProjectName`、`PreviewBgName`（封面背景，选择器写 id）、`PreviewHeader`、`PreviewTitle`
- 节点/脚本行/连线统计、「校验工程结构」（调 core `AapProject.validate()`）

---

## 5. 资源选择器（pickers）

`AaPickerDialog` 从 `AAResources.make_context(...)` 的 `AaResContext` 取列表：

| 类型 | 数据源 | 返回 |
|---|---|---|
| 角色 | `get_characters()`（含自定义角色 / 占位角色，显示名+Identifier） | `String` Identifier |
| 背景 | `get_bg_entries()`（带缩略图） | `{id, name}`，选择后写 `bgFriendlyName` 并 `bgName = AaHash.bg_id(name)` |
| BGM | `get_bgm_entries()`（显示名+数字 id；999=静音按钮） | `int` bgmId |
| 音效 | `get_sound_entries()` | `String` |
| 弹出图 | `get_popup_entries()`（带缩略图） | `String` |
| 语音 | `get_voice_entries()`（guid + 台词提示；无此 API 时退回 manifest VoiceOverrides） | `String` guid |

- 资源层未就绪（`AAResources` 不存在 / `make_context()` 返回 null）或列表为空时**不阻塞**：
  顶部输入框可以手动输入任何 ID / 名称（对应 AA 自定义资源场景），列表同时支持输入内容筛选。
- 自定义 BGM 没有数字 ID 时会提示改用手动输入。

---

## 6. 保存 / 撤销 / 自动保存

- 保存走 `AapProject.save_to_file()`（core）→ AA 兼容字段顺序、紧凑 JSON、float32 坐标按最短表示；
  **读入未改动的节点会保留原始 double 字面量**，`fixtures/aap/sample_kei_01.aap` 打开后另存可做到字节级一致（headless 已验证）。
- 撤销/重做：JSON 快照（结构操作强制入栈；属性编辑 900ms 内同 tag 合并），上限 80 步，
  覆盖节点增删、连线/断开、属性编辑、节点拖动。
- 自动保存：默认**关**；勾选后每 60 秒若有修改且当前路径不是 `res://` 就静默保存。
- 打开 `res://` 下的工程后按「保存」不会覆盖源文件，而是存到数据目录 `user://aa_data/projects/<工程名>.aap`。

---

## 7. 已实现 / 未实现（TODO）

已实现：
- 四类节点渲染、节点工厂拖拽/单击创建、坐标写回、入口唯一与不可删、带连线节点不可删提示；
- 右键拖拽连线（含入端反向连）、右键划红线剪断、左键平移、滚轮缩放、工具栏缩放/总览；
- 选择节点「每选项一出端口 + ＋新选项端口」、重复连到同一目标、选项文本增删同步；
- 检查器覆盖 DESIGN §4 全部 ScriptData 字段 + 选择/出口/入口字段 + 工程属性；
- 资源选择器 6 类 + 手动输入兜底；
- 新建/打开/保存/另存、编译（core `compile()` + `validate()` 告警）、播放预览（有 Player.tscn 时）、
  撤销/重做、自动保存开关、脏标记/路径/统计状态栏、快捷键；
- headless 可驱动 API（qa `tests/test_editor_smoke.gd` 51 断言 PASS）。

未实现 / 后续可加：
- 节点复制/粘贴、框选批量移动、节点分组/注释框（GraphFrame）；
- 检查器里的台词富文本实时预览（当前只显示纯文本；播放器侧由 runtime-dev 渲染内联标记）；
- 选择节点 16 槽的“隐形槽位管理 UI”（AA 本身也只按出边数编辑）；
- 自动保存的冲突恢复（只做保存，不做崩溃恢复）；
- 多语言界面（目前中文）。

---

## 8. 自测方法（本机 headless）

```bash
cd /root/workspace/aa-godot
# 注意：必须用 scripts/godot.sh（会先刷新 class_name 缓存），不要裸调二进制
cat > /tmp/editor_check.gd <<'EOF'
extends SceneTree
func _initialize() -> void:
    var e = load("res://scenes/editor/Editor.tscn").instantiate()
    get_root().add_child(e)
    await process_frame
    print("OPEN=", e.open_project_file("res://fixtures/aap/sample_kei_01.aap"))
    await process_frame
    print("SAVE=", e.save_as("/tmp/check.aap"))
    var p = load("res://addons/aa_core/aap_project.gd").load_from_file("/tmp/check.aap")
    print("nodes=", p.nodes.size())
    quit(0)
EOF
scripts/godot.sh --script /tmp/editor_check.gd
```

完整用例：`scripts/godot.sh --script tests/run_all.gd -- --only=editor_smoke`。
视觉检查（本机有 xvfb）：`xvfb-run -a -s "-screen 0 1920x1080x24" <godot> --path . --script scripts/screenshot.gd -- --scene=res://scenes/editor/Editor.tscn --out=/tmp/editor.png`
