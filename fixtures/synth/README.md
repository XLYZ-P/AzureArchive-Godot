# `fixtures/synth/` —— qa-dev 合成夹具

本目录是 **QA 测试专用**的合成数据，不是 AA 真实工程。全部文件由
`python3 tests/make_fixtures.py` **确定性生成**（无时间戳/随机数），可重复生成；
`generated.json` 记录每个产物的 SHA-256，`tests/test_synth_fixtures.gd` 会逐字节校验，
防止夹具被手改后测试变成「假绿」。

## 怎么生成 / 校验

```bash
cd /root/workspace/aa-godot
python3 tests/make_fixtures.py           # 生成（覆盖）全部夹具
python3 tests/make_fixtures.py --check   # 只校验：重新生成到临时目录并逐字节比对现有夹具
bash scripts/test.sh -- --only=synth_fixtures   # 跑夹具自校验用例
```

> 注意：本机 Godot 的导入器（`--import`/`--editor`）会崩（RC=134），
> 所以夹具里的 PNG/WAV 都是**原始文件**，测试运行时用
> `addons/aa_resources/raw_loader.gd`（`Image.load`/`AudioStreamWAV.load_from_file`）直接加载，
> 不依赖 `.import` 产物。PNG 用 Python 标准库 `zlib+struct` 手工写（不依赖 PIL）。

## 产物清单

| 路径 | 是什么 | 谁在用 |
|---|---|---|
| `smoke.aap` | 合成小工程：入口 + 3 行台词（`#wait;5000` / `#bgshake` / `[size]` `[颜色]` `[ruby]` 内联标记）+ 2 选项选择节点 + 2 分支各 1 行 + Ending 出口。6 节点 / 6 行 ScriptData（含 `Exit.NeScriptDirty`）。 | player_smoke、editor_smoke、aap round-trip、resources |
| `smoke_fast.aap` | 同结构但**无 `#wait`/无额外指令**，供播放器没有 `instant_mode` 时的快速兜底 | player_smoke 兜底 |
| `pack/` | 最小 **aa_pack**（pack-dev 定稿布局）：`catalog.json` 元数据 + `manifest.json` + `bgs/`（红/蓝两张纯色背景）+ `bgm/synth_bgm.wav` + `sounds/SE_QA_01.wav` + `popups/synth_popup.png` + `characters/QA_HERO/`（PNG 立绘 + 头像） | resources（安装/优先级/角色/音频/弹出图） |
| `overrides/` | 全局 overrides 夹具：同名背景 `synth_bg` 为**绿色** + manifest | resources 覆盖优先级（中层） |
| `project_local/` | 工程本地同名文件夹夹具：同名背景 `synth_bg` 为**蓝色** + manifest | resources 覆盖优先级（最高层） |
| `generated.json` | 生成清单：版本、xxh32 参考向量、全部产物的 SHA-256 | test_synth_fixtures 可重复生成校验 |

### 三层覆盖颜色约定（test_resources 依赖）

| 层 | 文件 | 颜色 | 语义 |
|---|---|---|---|
| aa_pack（最低） | `pack/bgs/synth_bg.png` | 红 `#DC2828` | 包内资源 |
| `overrides/`（中） | `overrides/bgs/synth_bg.png` | 绿 `#28C828` | 全局覆盖 |
| 工程本地文件夹（最高） | `project_local/bgs/synth_bg.png` | 蓝 `#2828DC` | 工程内覆盖 |

## 合成 `.aap` 的格式约束（为什么它「合法」）

严格遵循 `docs/spec/aap.md` 与 `docs/DESIGN.md` §4（生成器里 `validate_aap()` 自查）：

- UTF-8 无 BOM、紧凑 Newtonsoft.Json、带 `$type`、字段顺序固定；
- 顶层 `$type = ProjectData, Assembly-CSharp`，`nodes` 用 `List\`1[[NodeData...]]` 包装；
- 四类节点 `EntryNodeData` / `ScriptNodeData` / `SelectionNodeData` / `ExitNodeData`，
  公共字段 `Guid, ConnectionsTo, X, Y` 在各自节点字段之后；
- 入口 Guid 全 0 且恰好一个；`ConnectionsTo` 出边目标都存在；
- `ScriptData` 17 字段严格顺序；`characters` 恒 6 项，槽 0 为无立绘说话槽，
  槽 1 站 `QA_HERO`，`startingPos == 槽下标`，上一行 `endingPos == 下一行 startingPos`；
- `selectionTexts` 固定 16 槽，未用补 `""`，`ConnectionsTo` 条数 = 选项数（2）；
- `bgName = xxHash32(UTF-8(bgFriendlyName), seed=0)`（`synth_bg` → `3927605985`）；
- 出口是 `IsEnding=true` 的 Ending，`NeScriptDirty` 是完整 ScriptData。

## 已知取舍

- 背景/BGM/音效都是**程序化纯色/正弦波占位**，只为 headless 断言（颜色/可解码/可加载），
  不代表真实美术。
- `smoke.aap` 里故意放了 `#wait;5000`；播放器测试用 `set_instant_mode(true)` 跳过等待，
  如果 runtime 没有 instant 模式请改用 `smoke_fast.aap`。
- 夹具只服务测试；正式运行数据请放 `user://aa_data/`（见 `AAResources`）。
