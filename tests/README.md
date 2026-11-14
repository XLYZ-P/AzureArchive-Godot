# `tests/` —— headless 测试套件（qa-dev）

AzureArchive Godot 复刻的**唯一验收入口**：纯 GDScript、`extends SceneTree`、headless 运行，
全绿是合并门槛。本文说明怎么跑、怎么加用例、当前覆盖矩阵与缺口。

---

## 1. 怎么跑

### 推荐：`scripts/test.sh`（自动刷新 class_name 缓存）

```bash
cd /root/workspace/aa-godot
bash scripts/test.sh                                # 全量
bash scripts/test.sh -- --only=xxhash               # 只跑名字含 xxhash 的用例
bash scripts/test.sh -- --only=fixtures,resources   # 多个过滤（子串匹配，OR）
bash scripts/test.sh -- --list                      # 列出所有用例
bash scripts/test.sh -- --timeout=240000            # 全局超时（毫秒，默认 180000）
echo $?                                             # 0 = 全绿；1 = 有 FAIL/超时
```

> **本机环境限制**（docs/DESIGN.md §10/§11）：
> - `--import` / `--editor` 会崩（glibc double free，RC=134），**禁止运行**；
> - 没有编辑器扫描时 `class_name` 全局解析依赖 `.godot/global_script_class_cache.cfg`，
>   所以必须先 `python3 scripts/gen_class_cache.py`（`scripts/test.sh` 已自动做）；
> - `.tscn`/测试**不得**依赖 `.import` 产物，贴图/字体/音频用 `AaRawLoader` 运行时加载。

### 兼容裸命令（不经过 scripts/test.sh）

```bash
/opt/godot/Godot_v4.7.2-stable_linux.arm64 --headless --path . \
  --script tests/run_all.gd -- --only=xxhash
```

`run_all.gd` 检测到 class_name 缓存为空时会自动执行 `scripts/gen_class_cache.py`
并**重启一次自身**再跑测试（`bootstrap`）。仍推荐 `scripts/test.sh`，输出更干净。

### 结果文件

每轮结果同时写入 `tests/last_result.json`（时间、每用例状态/断言数/失败详情/耗时），
便于逐轮对比与机器读取。退出码：**只要有 FAIL 或超时就是 1**；SKIP/PENDING 不算失败
（但里程碑验收要求 PENDING 归零）。

---

## 2. 目录与文件

```
tests/
├── run_all.gd               # SceneTree 入口：聚合用例、PASS/FAIL/SKIP/PENDING、退出码、--only
├── framework.gd             # 轻量断言框架：assert_eq/true/contains/eq_deep/...（带 文件:行号）
├── test_fixtures.gd         # 真实样本 .aap 静态结构契约（零业务依赖）
├── test_class_cache.gd      # class_name 缓存 / AaRawLoader / autoload AAResources 环境自检
├── test_xxhash.gd           # AaHash.xxh32 向量 + 真实样本 170 行 bgName 全量
├── test_aap_roundtrip.gd    # .aap 载入→序列化→再载入（含 5 个真实样本参数化）
├── test_commands.gd         # #额外指令 + [内联标记] → BBCode/纯文本
├── test_core_extras.gd      # 枚举表/自动等待/新建工程/错误处理/JSON 转义
├── test_synth_fixtures.gd   # fixtures/synth 自校验（可重复生成/合法/三色覆盖夹具）
├── test_resources.gd        # AAResources：数据根/aa_pack/overrides 优先级/缺资源占位
├── test_player_smoke.gd     # 实例化播放器跑合成工程到结局
├── test_editor_smoke.gd     # 实例化编辑器：新建→加节点→连线→保存→重载
├── test_main_integration.gd # 目录界面用户路径：列表→播放真实样本→编辑器→关闭
├── make_fixtures.py         # 生成 fixtures/synth/ 全部合成夹具（确定性、可 --check）
├── last_result.json         # 最近一轮结果（生成物）
├── README.md                # 本文件
└── REPORT.md                # 每轮验收报告 / 已知问题清单 / 阻塞项
```

用例一律只改 `tests/`，夹具只改 `fixtures/synth/`；**不要**改别人模块。发现 bug → 写
`REPORT.md` 的 Q-00x + `send_message` 给对应 owner 和 lead。

---

## 3. 用例与覆盖矩阵

11 个用例（`bash scripts/test.sh -- --list`）：

| 用例 | 覆盖 | 依赖模块 | 未就绪时 |
|---|---|---|---|
| `fixtures` | 真实样本 17 节点/170 行/字段顺序/`$type`/16 槽/6 槽/图连通性/UTF-8 无 BOM | 无（只读 JSON） | 直接 FAIL（夹具是仓库资产） |
| `class_cache` | 全局类缓存存在/不陈旧/可 load；AaRawLoader 读文本/JSON/字体；autoload 生效 | Lead 基础设施 | 直接 FAIL（环境问题） |
| `xxhash` | xxh32 已知向量（含 16/17/31/100 字节、seed、UTF-8、二进制）；样本 170 行 bgName（165 命中 + 5 行 AA 历史脏数据 allowlist） | aa_core::AaHash | PENDING |
| `aap_roundtrip` | 载入/序列化/再载入 深度+字段顺序相等；未知字段与未知节点类型保留；save/reload 幂等；`check_bg_ids/repair_bg_ids`；`compile()` 结构；**5 个真实样本参数化** | aa_core::AapProject 等 | PENDING |
| `commands` | `#wait/#bgshake/#fx/#zmc/#st/#stm/#clearST/#hidemenu/#showmenu/#N;fx/#N;m/#N;hide/#N;al|ar|a|dl|dr|d/#nextepisode`；多行/未知/空；结构化解析；`[size]/[颜色]/[ruby]/[b]…` 嵌套、转义；RichTextLabel 实渲染 | aa_core::AaCommands | PENDING |
| `core_extras` | 枚举表规模与查询/中文解析；自动等待规则（2500/1500/显式覆盖）；create/create_empty；last_error；选择节点重复连线；JSON 转义；duplicate_line | aa_core | PENDING |
| `synth_fixtures` | 合成 smoke.aap 合法性与内容；`generated.json` SHA-256 可重复生成；aa_pack 布局；PNG/WAV 可解码；三色覆盖夹具 | 无（只读夹具） | 直接 FAIL（CI 资产） |
| `resources` | set_data_root/ensure_layout/get_projects；install_pack（目录+zip）/uninstall；**pack < overrides < 工程本地** 三色优先级；get_bg_by_id；manifest 读写/overlay；缺资源占位不崩（含 aa_pack 缺失） | aa_resources | PENDING |
| `player_smoke` | Player.tscn 实例化；setup_from_path/setup(AapProject)；instant+advance+choose 到结局；finished 信号；内联标记对话框渲染；debug_run_to_finish；坏路径不崩 | aa_player | PENDING |
| `editor_smoke` | Editor.tscn 实例化；new_project；add_node/connect_nodes；save_as(/tmp)→AapProject 重载深度+字段顺序一致；打开真实样本 17 节点；undo/redo；compile | aa_editor | PENDING |
| `main_integration` | **用户真实路径**：Main.tscn 实例化 → 临时数据根 + 拷入真实样本 → `refresh()` 列表 1 项 → `_on_play()` → overlay 出现 Player → instant 跑到结局（170 行/5 选择）→ `_close_overlay()` → `_on_edit()` → Editor 打开 17 节点 → 关闭 | Lead scenes/main + player + editor | PENDING |

### 框架能力（`framework.gd`）

- 断言：`ok/is_true/is_false/is_null/not_null/eq/ne/almost_eq/gt/gte/lt/lte/in_range/
  contains/not_contains/eq_keys/eq_deep/eq_deep_ordered`，失败自动带 `文件:行号`；
- 模块就绪探测：`load_script/need/need_methods/has_global_class/first_method/call_first/
  prop/const_of/static_call`；
- 异步推进：`await ctx.advance_frames(n)`、`await ctx.wait_seconds(s)`（播放器/编辑器测试用）。

---

## 4. 怎么加一个新用例

1. 新建 `tests/test_xxx.gd`：

```gdscript
extends RefCounted
## 一句话说明这个用例守护什么契约（对应 docs/DESIGN.md / docs/spec 哪一节）。
const Fw = preload("res://tests/framework.gd")

func run(ctx: Fw.Ctx) -> void:
    # 依赖模块未就绪：need() 自动标记 PENDING 并 return（不要 FAIL）
    var S := ctx.need("res://addons/aa_core/aap_project.gd", "core-dev")
    if S == null:
        return
    ctx.eq(AapProject.create("x").nodes.size(), 2, "create() 默认 2 节点")

    # 需要等帧的用例直接 await（run 可以是 async）
    # await ctx.advance_frames(3)
```

2. 在 `run_all.gd` 的 `CASES` 里注册 `{name, path, desc}`。
3. 先跑 `bash scripts/test.sh -- --only=xxx`，绿了再跑全量。
4. 规则：
   - **FAIL 只用于「模块已存在但不满足契约」**；模块还没写 → `ctx.pending("等待 xxx：...")`；
     环境性不适用（如引擎缺某能力）→ `ctx.skip("原因")`；
   - 一个用例至少 1 条断言，否则 run_all 判 FAIL（防脚本中途报错假绿）；
   - 不要 mock 掉被测模块；真实依赖用 fakes 时写清注释；
   - 优先用真实样本 `fixtures/aap/*` 与合成 `fixtures/synth/*`，不要内嵌大 JSON；
   - 断言“已知 AA 脏数据”时用 allowlist，不要要求 100%（见 `xxhash`）。

### 合成夹具

```bash
python3 tests/make_fixtures.py           # 重新生成 fixtures/synth/
python3 tests/make_fixtures.py --check   # 校验可重复生成（逐字节）
```

详见 `fixtures/synth/README.md`。

---

## 5. 当前缺口 / TODO（随模块推进更新）

| 缺口 | 说明 |
|---|---|
| Spine 立绘 | 只走 PNG/静态帧兜底；`AaCharacterAsset` 的 spine 分支未做资源级断言（缺真实 Spine 夹具） |
| 音频真实播放 | headless 下只断言「能加载/占位静音」，未断言混音/音量/循环点 |
| 语音 | 合成包没有 voices；`get_voice()` 缺资源占位已断言，正常语音未覆盖（缺 ogg 夹具） |
| 编辑器交互 | 只覆盖 API 层（新建/加节点/连线/保存/重载/undo/redo），GraphEdit 拖拽/检查器控件交互未覆盖（headless 不便） |
| 目录界面交互 | `main_integration` 覆盖列表→播放→编辑→关闭主路径；数据目录切换、导入资源包/工程、载入内置示例等对话框（FileDialog）未覆盖 |
| 播放器表现层 | 只断言「到结局/文本/信号」；立绘走位、transition 视觉、backlog 内容未断言 |
| `.aac` 编译缓存 | roundtrip 做了轻量 from_dict，未覆盖 `save_to_file/load_from_file`（可按 core API 补） |
| 真 AA `.aas` | 明确非目标（FlatBuffers 无 schema） |

已知问题（Q-00x）与逐轮验收记录见 `tests/REPORT.md`。
