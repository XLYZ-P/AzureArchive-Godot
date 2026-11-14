# aa_player —— AzureArchive 剧情播放器运行时

> 写作用域：`addons/aa_player/`、`scenes/player/`（runtime-dev）
> 契约：`docs/DESIGN.md` §5.3；数据模型 §4；格式权威 `docs/spec/*.md`。

把 `.aap` 工程编译结果（`PlayScript`）演出来：背景/过渡、5 个立绘槽、
BGM/SE/语音、对话框打字机、内联标记、选项、额外指令、出口 Ending/未完待续，
带 AUTO/快进/历史记录。**没有官方资源包也能完整播放**：缺贴图/音频一律用程序化占位素材。

---

## 1. 快速开始

### 目录界面（Lead 的 scenes/main）

```gdscript
var p := load("res://scenes/player/Player.tscn").instantiate()
add_child(p)
p.setup_from_path("user://aa_data/projects/xxx.aap")   # 或 p.setup(aap_project)
p.finished.connect(...)                                # 播放到出口节点
p.request_exit.connect(func(): p.queue_free())         # 用户点退出/Esc
p.play()
```

### 独立演示（双击 .aap 直接看）

```bash
# 直接播放真实样本（headless 也可以跑，但看不到画面）
scripts/godot.sh --quit-after 30 res://scenes/player/player_standalone.tscn
# 有 X11/xvfb 时看实际演出：
xvfb-run -a -s "-screen 0 1920x1080x24" \
  /opt/godot/Godot_v4.7.2-stable_linux.arm64 --path . --rendering-driver opengl3 \
  --script scripts/shot_player.gd -- --project=res://fixtures/aap/sample_kei_01.aap \
  --out=/tmp/p.png --advance=10
```

### headless 自测（qa 的用法）

```gdscript
var p = load("res://scenes/player/Player.tscn").instantiate()
get_root().add_child(p)
await process_frame
p.setup_from_path("res://fixtures/aap/sample_kei_01.aap")
p.set_instant_mode(true)          # 打字机/过渡/#wait 全部瞬时
p.play()
await process_frame
var r := p.debug_run_to_finish(8000, 0)   # 自动推进并默认选第 0 个选项
print(r)   # {finished:true, reason:"to_be_continued", steps, lines:169, choices:5, texts:[...]}
```

---

## 2. 操作键位

| 输入 | 作用 |
|---|---|
| 鼠标左键 / 空格 / 回车 | 推进：打字中→瞬间补全；等待中→下一行；`#wait` 计时→跳过 |
| 数字键 `1`–`9` | 选择选项（等价鼠标点按钮） |
| `A` | 切换 AUTO 自动播放 |
| 按住 `Ctrl` | 快进（台词瞬间显示、停下即推进） |
| `H` / 鼠标滚轮上 | 打开/关闭对话历史（backlog，回看不改剧情状态） |
| `Esc` | 关闭历史 / 退出播放器（发 `request_exit`） |
| `F8` | 调试信息（当前 guid、行号、行计数） |
| 右上角按钮 | 历史 / AUTO / 快进 / 退出（支持 `#hidemenu`/`#showmenu` 隐藏恢复） |

---

## 3. API（`class_name AaPlayer extends Control`）

| 成员 | 说明 |
|---|---|
| `setup(project: Variant)` | 接受 `AapProject` / `PlayScript` / 已归一化 PlayData 字典 |
| `setup_from_path(path: String)` | 优先用 `aa_core.AapProject.load_from_file` + `compile()`；core 不可用时用内置解析器兜底 |
| `play()` | 从头开始播放（重新初始化舞台/音频/历史） |
| `jump_to(guid: String)` | 跳到指定节点 guid 继续播 |
| `advance()` | 一次「点击推进」（headless 交互测试用） |
| `choose(index: int)` | 选择第 index 个选项（0 起） |
| `set_instant_mode(v: bool)` / `is_instant_mode()` | headless 加速模式：无打字机/过渡/等待动画 |
| `debug_run_to_finish(max_steps := 6000, choice_index := 0) -> Dictionary` | 自动跑到出口，返回 `{finished, reason, steps, lines, choices, texts, project}` |
| `is_finished()` / `is_waiting_choice()` / `is_waiting_click()` / `get_current_guid()` / `get_current_line_index()` / `get_play_data()` | 状态查询 |
| `set_auto(bool)` / `toggle_auto()` / `set_fast_forward(bool)` | 自动播放控制（编辑器预览可用） |
| `signal finished` | 播放到出口节点（Ending / To be continued / 流程结束） |
| `signal request_exit` | 用户要求退出（外层负责 `queue_free`） |

内部模块（全部 `class_name`，可单独复用）：

| 文件 | 类 | 职责 |
|---|---|---|
| `interpreter.gd` | `AaInterpreter` | 逐行状态机：WAIT_CLICK / WAIT_TIMER / CHOICE / DONE，发 `line_started/choice_requested/exit_reached/finished` |
| `stage.gd` | `AaStage` | 背景（跨溶解/黑场/白场近似）、5 立绘槽、弹出图、屏幕文字、特效、菜单显隐、背景名小字 |
| `character_view.gd` | `AaCharacterView` | 单个立绘槽：进出场/走位/表情/高亮/形状/气泡/动作/中弹闪白 |
| `dialogue_box.gd` | `AaDialogueBox` | 姓名牌 + 昵称 + 打字机 + 语音同步 + 继续指示 |
| `choice_overlay.gd` | `AaChoiceOverlay` | 居中选项按钮 |
| `backlog.gd` | `AaBacklog` | 对话历史（可滚动，不修改剧情状态） |
| `auto_play.gd` | `AaAutoPlay` | AUTO/快进的计时逻辑 |
| `audio_bus.gd` | `AaAudioBus` | BGM（循环/淡入淡出/999=静音）/ SE 池 / Voice 单轨 |
| `aap_mock.gd` | `AaAapMock` | `.aap` 兜底解析 + 归一化 PlayData + core PlayScript 适配 + 合成演示剧本 |
| `res_provider.gd` | `AaResProvider` | 资源薄包装：AaResContext 优先，项目目录/manifest 兜底，再缺返回 null（舞台用占位） |
| `text_util.gd` | `AaText` | 额外指令解析、内联标记→BBCode、枚举/过渡名称（优先 aa_core） |
| `placeholder_art.gd` | `AaArt` | 程序化占位素材（背景渐变/人形剪影/弹出图/径向特效）与字体缓存 |

---

## 4. 支持的指令 / 内联标记矩阵

额外指令来自 `ScriptData.additionalPrompt`（多条用 `\n` 分隔），栏位指令的 `N` 是数组下标 1–5。

| 指令 | 状态 | 实现 |
|---|---|---|
| `#wait;毫秒` | ✅ | 解释器计时等待（覆盖气泡/动作默认等待） |
| `#bgshake` | ✅ | 背景+立绘层随机抖动（Tween 近似） |
| `#fx;AronaTouch` | ✅ 占位 | 青色同心圆 + 文字占位，无真实粒子 |
| `#zmc;模式;X,Y;缩放系数;持续时间` | ✅ | 背景平移缩放，`缩放=3160/系数`；AA 屏幕空间 Y 上正已换算 |
| `#st;[X,Y];模式;字号;` | ✅ | 屏幕左对齐文字，`instant/smooth/serial`；文案取该行 `text` |
| `#stm;[X,Y];模式;字号;` | ✅ | 同上，居中 |
| `#clearST` | ✅ | 清除所有屏幕文字 |
| `#N;fx;{shot}` | ✅ | 该槽白闪+抖动；占位枪声音效 |
| `#N;m<结束位置>` | ✅ | 走位（Tween 位移到目标槽 x） |
| `#N;hide` | ✅ | 该槽退场并清空 |
| `#N;al\|ar\|a` | ✅ | 进场：右入/左入/原地淡入 |
| `#N;dl\|dr\|d` | ✅ | 退场：左退/右退/淡出 |
| `#hidemenu` / `#showmenu` | ✅ | 隐藏/恢复右上菜单 |
| 未知指令 | ✅ 忽略 | 不崩溃、不中断播放 |

**自动推导**（.aap 里没有显式指令时，播放器按编译器规则从每行 `characters` 推导）：
`startingPos != endingPos` → 走位；上一行有人本行空 → `hide`；`appear != 0` → 进场；
`emoticon >= 0` → 气泡；`action > 0` → 动作；`shapeOverride` → 剪影/变暗/特写；
`highlightedSlotNums` + `speakerSlotNum` → 高亮/变暗。

内联标记（`text` 字段，转成 Godot RichTextLabel BBCode）：

| AA 写法 | 状态 |
|---|---|
| `[RRGGBB]文字[-]` / `[RRGGBBAA]` | ✅ 颜色 |
| `[size=N]文字[/size]`（60=原大小） | ✅ 字号 |
| `[ruby=注音]文字[/ruby]` | ✅ 近似：正文后小字注音 |
| `[b]/[i]/[u]/[s]/[sup]/[sub]` | ✅ |
| `[a0]`–`[f9]` 透明度 | ✅ 近似 |
| 嵌套/未知标记 | ✅ 容错（未知按字面显示） |

动作：`1 greeting / 2 falldownl / 3 falldownr / 4 stiff / 5 shake / 6 jump / 7 hophop`
（位移+旋转+抖动 Tween 近似，附占位音效）。形状：`1 sig`（暗色剪影）、`2 black`（变暗）、`4 closeup`（放大）。
气泡：`0–19` 映射为中文符号（怒筋/叽喳/沉默/惊叹/爱心/音符/…），优先取 `AaEnums.EMOTICONS`。

出口：`ExitNodeData.IsEnding` → `Ending` + `EndText`；`NeHeader/NeTitle` → `未完待续`；
`NeScriptDirty.text`（可能是 `Header;Title`）→ 结局卡补充文字。结束发 `finished`。

---

## 5. 与 core / resources 的对接

- **数据**：`setup_from_path` 先尝试 `res://addons/aa_core/aap_project.gd` 的
  `load_from_file()` → `AapProject.compile()` → `AaAapMock.from_core_project()` 归一化成
  PlayData 字典（`{start_guid, units:{guid:{kind,lines,connections,selection_texts,exit...}}}`）。
  PlayNode 的 **kind 常量与播放器不同**，适配层用 `PlayNode.kind_name` 字符串映射
  （entry/script/choice/exit），并读取 `options[i].text/target_guid`、`ne_header/ne_title`。
  core 不可用时退回 `AaAapMock.from_file()` 自己解析 `.aap`（$type 四类节点 + 16 槽选项）。
- **等待/枚举**：优先用 core 的 `AaScriptLine.effective_wait_ms()`、`AaEnums.TRANSITIONS`、
  `BG_EFFECTS`、`EMOTICONS`（`AaText` 用 `get_script_constant_map()` 动态桥接，core 缺项时用内置兜底表）。
- **资源**：`AAResources.make_context()` → `AaResContext`，经 `AaResProvider` 读取
  角色/背景/BGM/SE/语音/弹出图；`AaCharacterAsset.has_portrait_data()==false`（native/placeholder 模式）
  时不用资源层的半透明占位小图，改用播放器自己的清晰人形剪影 + 名字。
  没有 context 时读项目目录 `bgs/ sounds/ voices/ characters/` + 同名 `*.manifest.json`。
- **AUTO/语音**：语音长度决定打字速度（语音播完≈台词打完）；AUTO 停留 = 语音时长或文本长度估算。
- **TODO（后续增强）**：
  1. 接入 `AaScriptLine.derive_stage_events(prev) / derive_environment(prev) / build_events(prev)`
     替换播放器内联推导（当前推导规则与 core 一致，已用 169 行样本对账）；
  2. 用 `PlayScript.entry_title/entry_header` 做开场标题卡；
  3. 过渡表现细化（Swipe 滑动、Circle 圆形遮罩、Noise 噪点 shader）；
  4. Spine 骨骼动画运行时（现在静态帧/占位）；`halo_01/02` 叠加；
  5. 设置项（文字速度/音量/AUTO 延迟）持久化到 `AAResources` settings；
  6. 存档/读档（当前只支持从头播/跳节点）。

---

## 6. 已知限制

- **无 Spine 运行时**：官方立绘包不可直接渲染，原生角色显示程序化剪影 + 名字；自定义 PNG 立绘可正常显示。
- **官方资源包未安装时**：背景=按名字哈希生成的渐变占位，BGM/SE/语音静默（不报错）。
- `transition` 的 Swipe/Noise/Circle 用遮罩近似；Crossfade 用双背景溶解；
  `bgEffect` 用径向光线占位 + 名称小字。
- 表情 `faceId` 只对带多表情图的自定义 PNG 立绘生效；占位模式下不改变外观（避免误导）。
- 屏幕文字坐标已按 AA 约定（中心原点、宽 2960、**Y 上正**）换算；不同宽高比屏幕等比缩放。
- 选择节点以 `ConnectionsTo` 数量为准；`selectionTexts` 的 16 槽空项会显示「选项 N」兜底。
- 结局卡出现后点击「返回」发 `request_exit`，不自动销毁（由外层释放）。

## 7. 自测

```bash
# 播放器专项（qa 维护）
bash scripts/test.sh -- --only=player_smoke
# 全量
bash scripts/test.sh
# 冒烟跑主场景（无 ERROR 即通过）
scripts/godot.sh --quit-after 5
# 语法检查单个脚本
scripts/godot.sh --check-only --script res://addons/aa_player/player.gd
```

注：新增/改名 `class_name` 后必须 `python3 scripts/gen_class_cache.py`（`scripts/godot.sh` 会自动做）。
