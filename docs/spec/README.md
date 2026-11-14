# AA（AzureArchive）格式规范总索引

本目录是 Godot 4 复刻版 **AzureArchive（剧情播放器 + 编辑器）** 的格式与行为规范。
目标：让 core / runtime / editor / pack 开发者**照文档就能写出正确实现**，
并且兼容真实 AA 工程与 AA 官方资源包。

## 文档清单

| 文档 | 内容 | 主要读者 |
|---|---|---|
| [`aap.md`](aap.md) | `.aap` 工程 JSON 完整结构：顶层 `ProjectData`、四类节点、`ScriptData` 17 字段、`CharacterRecordData`、6 角色槽/16 选项槽、Guid/连线/坐标、`bgName=xxHash32`、序列化写回规则、最小工程模板 | core（解析/序列化）、editor |
| [`commands.md`](commands.md) | 脚本指令规范：额外指令（`#wait/#bgshake/#fx/#zmc/#st/#stm/#clearST/#hidemenu/#showmenu/#N;fx;{shot}`）、编译器自动指令（`#N;m/#N;hide/#N;al|ar|a|dl|dr|d/#N;em;/#N;h/#nextepisode/…`）、自动等待、内联标记（`[size]/[RRGGBB]/[ruby]`）、坐标系统、一行演出求值顺序 | runtime（解释器）、editor（指令编辑）、compiler |
| [`resources.md`](resources.md) | 资源与资源包：AA 数据目录、`manifest.json` 全字段（含 Spine/别名/"???" 三种角色覆盖）、Spine 与 PNG 立绘命名规范、`voices.txt`、**官方资源包 = Unity Addressables**（catalog/缓存/FlatData 表/加密、UnityPy 提取方案与限制）、`aa_pack` 开放格式（目录 + `catalog.json` schema） | editor（自定义资源）、pack（提取器）、runtime（素材加载） |
| [`enums.md`](enums.md) | 枚举与 ID 表：emoticon 0–19、action 1–7、appear 1–6、shapeOverride 位掩码、faceId 命名、**transition 61 条 ID 表**、**bgEffect 26 条 ID 表**、bgmId（999=静音）、槽位常量、数据驱动 vs 近似的实现建议 | core（`AaEnums`）、runtime、editor（下拉框） |

按阅读顺序建议：`aap.md` → `enums.md` → `commands.md` → `resources.md`。

## 真实样本（`fixtures/aap/`）

36 个真实工程中选取 5 个（来源、URL、sha256 见 [`fixtures/aap/SOURCES.md`](../../fixtures/aap/SOURCES.md)）：

| 样本 | 覆盖点 |
|---|---|
| `sample_kei_01.aap` + manifest | 17 节点、5 个选择节点、分支合并、`CharacterReference` 别名 |
| `sample_kei_02_multi_branch.aap` + manifest + voices | 多选项 + **重复连线**、`BgOverrides`/`SoundOverrides`、`#wait/#hidemenu/#stm/#N;fx;{shot}` |
| `sample_keiend_03_ending.aap` + manifest + voices | `IsEnding`/`EndText` 结局、`#nextepisode` 来源字段 |
| `sample_kei_04_small.aap` + manifest + voices | 4 节点最小样本，适合单测 |
| `sample_kei_05_large.aap` + manifest + voices | 130+ 节点、760KB，枚举覆盖面最广 |

校验：`cd fixtures/aap && sha256sum -c SOURCES.sha256`。

## 证据等级约定

| 标记 | 含义 |
|---|---|
| `[实]` | 对 36 个真实 `.aap`、8268 条 ScriptData、49608 条角色记录的统计复算（脚本可复现） |
| `[官]` | 官方文档 `research/aa-docs/`（aadoc.foxxlight.top 全文转储，34 篇） |
| `[三]` | 第三方逆向 HaloCue：139 工程 / 18932 台词验证，源码留档 `research/halocue/` |
| `[推]` | 推测，文档中写明依据与风险，不当作已确认结论 |

统计口径见 `aap.md` 附录 A；三张 ID 表来源见 `enums.md` §13。

## 复刻版实现要点（TL;DR）

1. `.aap` 是 **UTF-8 无 BOM、单行 minified JSON**，`$type` 必须是每个对象第一个键；
   四类节点与 17 字段 `ScriptData` 的字段顺序照 `aap.md` 抄，**入口 Guid 全 0**、
   **`characters` 恒 6 项**、**`selectionTexts` 恒 16 项**。
2. 选择节点：**选项数 = `ConnectionsTo` 长度**（不是文案数），连线可重复；选项 i 的文字 =
   `selectionTexts[i]`、目标 = `ConnectionsTo[i]`。多余的文案是脏数据，忽略。
3. 背景 ID：`bgName = xxHash32(UTF-8(bgFriendlyName), seed=0)`（99.89% 实测）。
   `transition`/`bgEffect` 是外部表 ID，表在 `enums.md`；`bgmId` 只有 999=静音确认。
4. `.aap` 里**没有**走位/隐藏/进出场/自动等待/`#nextepisode` 指令——这些是 AA 编译 `.aas`
   时按字段推导的；直接解释 `.aap` 的复刻版要自己实现（`commands.md` §3/§4）。
5. 资源分三层：自定义资源（`manifest.json` + `overrides/`、`projects/<名>/`）→ 我们**完全可读**；
   官方资源包 = Unity Addressables（`catalog.json` + UnityFS bundle）→ 用 UnityPy 本地提取
   （`resources.md` C 节），**不能分发**；中间层格式 `aa_pack` 见 `resources.md` D 节。
6. 先做 P0/P1（自定义资源 + `.aap` 解释 + 过渡/文本/选择），Spine 与官方包提取放 P2，
   UI 特效/particle 不复刻（`resources.md` E 节）。

## 已知缺口

见各文档末尾「未确认 / 推测清单」。最重要的 4 条：

1. `.aas`（FlatBuffers）的精确指令字节格式未逐字节核对——但复刻版不需要写 `.aas`。
2. 官方资源包 bundle 内部结构（Spine 以 TextAsset 还是 MonoBehaviour 引用）无真机样本，
   `resources.md` C.5 给的是基于 Spine-Unity 惯例的 `[推]` 方案 + fallback。
3. `BgEffectOverrides` / `BgSpineOverrides` 自定义格式官方无文档。
4. 真实工程（2024）没有 Spine 自定义立绘样本 → Spine 相关结论主要来自官方文档，
   `manifest.json` 的 Spine 分支实现需实机回归。

## 维护方式

- 新增真实样本：放 `fixtures/aap/`，更新 `SOURCES.md` + `SOURCES.sha256`，并跑
  `aap.md` 附录 A 的统计口径核对键序/枚举是否出现新值。
- 发现与真 AA 不符：优先在对应文档加「未确认/反例」条目并注明样本，再改结论。
- `research/halocue/` 是只读留档（HaloCue 代码 + `tables.py`/`official_catalog.py`），
  不要在其中改实现；我们的实现放 `core/`、`runtime/` 等目录。
