# `.aap` 工程格式规范

AzureArchive（AA）剧情工程文件 `.aap` 的完整 JSON 结构，供 **Godot 复刻版** 的
读写器（core）、编辑器（editor）与运行时（runtime）直接照做。

**证据等级标注**（每条结论后都有）：

- `[实]` 实测：来自 `fixtures/aap/` 的 5 个真实工程 + 同仓库另外 31 个工程
  （共 36 个真实 `.aap`、8268 条 ScriptData、49608 条 CharacterRecordData）。
  统计脚本可复算，样本全部要进 fixtures。
- `[官]` 官方文档：`research/aa-docs/`（aadoc.foxxlight.top 全文转储）。
- `[三]` 第三方逆向：HaloCue（`research/halocue/`）——139 工程 / 18932 台词验证。
- `[推]` 推测：没有直接证据，明确写出推测依据与风险。

> 想要「能被真正的 AA 打开」，最需要守的不是 JSON 排版，而是
> **`$type` 字符串、字段名与顺序、6 个角色槽、16 个选项槽、Guid 全 0 的入口、
> float32 坐标** 这几条。见第 11 节。

- 工程文件：`.aap`，**UTF-8 无 BOM 的单行（minified）JSON**
- 编译产物：`.aas`，FlatBuffers 二进制（不是本文范围，AA 自带 `autoCompile` 生成）

---

## 1. 文件层事实

| 项目 | 结论 | 证据 |
|---|---|---|
| 编码 | UTF-8，**无 BOM**；中文/韩文原样写入，不做 `\uXXXX` 转义 | `[实]` 36/36 文件首字节均为 `7b`（`{`），无 `EF BB BF`；文件内无 `\u` 序列 |
| 排版 | **单行、无空格**：`{"$type":"ProjectData, Assembly-CSharp",...}`；`":"`、`","` 后都没有空格 | `[实]` 36/36；Newtonsoft `JsonConvert.SerializeObject(..., Formatting.None)` 的默认输出 |
| 结尾 | 无换行符 | `[实]` 36/36 以 `}]}}` 直接结束 |
| 键序 | 严格按 C# 类字段声明序（Newtonsoft 默认行为）。**所有 36 个文件的键序完全一致** | `[实]` 每个节点类型只有 1 种键序，见第 3、6、7 节 |
| 大小 | 一个 760 KB 的工程有 130+ 节点、2000+ 剧本行 | `[实]` `sample_kei_05_large.aap` |
| 并行文件 | 每个工程有同名文件夹 `<工程名>/`（`manifest.json`、`voices/`、`characters/`、`bgs/`、`sounds/` …） | `[实]` 36/36 同名文件夹 |

> **写入建议**：复刻版保存 `.aap` 时也用 `Formatting.None` 单行输出。
> 真正的 AA 用 Newtonsoft 解析，理论上排版无关紧要，但单行 + 无 BOM
> 能保证 git diff 行为与官方一致，也避免 BOM 导致部分旧版解析失败。

> **读取要求**：解析器必须容忍任意空白（包括格式化过的手改文件）与 BOM。
> HaloCue 的 `load_manifest`/`document.py` 都用 `encoding="utf-8-sig"` 读，即容忍 BOM。

### `.aap` 与 `.aas` 的关系

- `.aap` 是**编辑期工程**（本文）；`.aas` 是 AA 编译后给播放器执行的 FlatBuffers
  二进制，内含蔚蓝档案原生脚本文本 + 演出指令。
- AA 有 `autoCompile`：打开/保存工程时自动把 `.aap` 编译成 `.aas`。
  **复刻版不需要写 `.aas`**；只要 `.aap` 合法，官方 AA 会自己编译。
- `[三]` HaloCue 正是走这条路线：只生成 `.aap` + `manifest.json`，由 AA 编译。

---

## 2. 顶层：`ProjectData`

```jsonc
{
  "$type": "ProjectData, Assembly-CSharp",
  "ProjectName": "Kei-初遇",
  "PreviewBgName": 3558049603,
  "PreviewHeader": "Kei",
  "PreviewTitle": "初遇",
  "nodes": {
    "$type": "System.Collections.Generic.List`1[[NodeData, Assembly-CSharp]], mscorlib",
    "$values": [ /* 节点数组，见第 3 节 */ ]
  }
}
```

| # | 字段 | C# 类型 | 可空 | 含义 | 证据 |
|---|---|---|---|---|---|
| 1 | `$type` | — | 否 | 恒 `"ProjectData, Assembly-CSharp"` | `[实]` 36/36 |
| 2 | `ProjectName` | `string` | 否（实测 36/36 非空） | 工程名，通常等于文件名 stem | `[实]` 36/36 |
| 3 | `PreviewBgName` | `int`（bg ID，可能 >2³¹，用有符号 64 位存即可） | 否 | 封面背景 ID；0 = 未设置 | `[实]` 36/36 有值；`[三]` 同 |
| 4 | `PreviewHeader` | `string?` | **是** | 封面序号（对应入口节点 `Header`） | `[实]` 36/36 非 null，但 HaloCue 生成器写 `null`，AA 能打开 → 可空 |
| 5 | `PreviewTitle` | `string?` | **是** | 封面标题（对应入口节点 `Title`） | `[实]` 同上 |
| 6 | `nodes` | `List<NodeData>` | 否 | 节点列表（Newtonsoft 数组包装，见下） | `[实]` 36/36 |

`PreviewBgName` 是**背景 ID**（`xxHash32(BG友好名, seed=0)`，见第 8 节），
不是索引。0 表示不使用封面背景（`[推]`：AA 播放器对 0 的处理未实测，按"无封面"实现即可）。

### 数组的 Newtonsoft 包装（全文通用）

Newtonsoft 在带 `$type` 的多态序列化里，对泛型 List 会写成对象 + `$values`：

```jsonc
{"$type": "System.Collections.Generic.List`1[[<元素类型>, 程序集>]], mscorlib",
 "$values": [ ... ]}
```

| 元素类型 | `$type` 字符串 |
|---|---|
| `NodeData` | `System.Collections.Generic.List`1[[NodeData, Assembly-CSharp]], mscorlib` |
| `ScriptData` | `System.Collections.Generic.List`1[[ScriptData, Assembly-CSharp]], mscorlib` |
| `ScriptData+CharacterRecordData` | `System.Collections.Generic.List`1[[ScriptData+CharacterRecordData, Assembly-CSharp]], mscorlib` |
| `System.Guid` | `System.Collections.Generic.List`1[[System.Guid, mscorlib]], mscorlib` |
| `System.Int32` | `System.Collections.Generic.List`1[[System.Int32, mscorlib]], mscorlib` |
| `System.String` | `System.Collections.Generic.List`1[[System.String, mscorlib]], mscorlib` |

> 注意：**`$type` 里没有版本号、Culture、PublicKeyToken**（不是 `..., mscorlib, Version=4.0.0.0`）。
> 这是 `TypeNameHandling.Objects` + 默认 `TypeNameAssemblyFormatHandling.Simple` 的输出。

**读取要点**：遇到 `{ "$type": ..., "$values": [...] }` 就取 `$values`；
遇到裸数组（手改文件）也应接受。写作者必须写完整包装 `[实]` 36/36。

---

## 3. 节点：四种类型 + 字段顺序

`nodes` 数组里是四种 `NodeData` 子类之一，靠 `$type` 区分，**且 `$type` 必须是第一个键**。

### 3.1 公共字段（后三个）

| 字段 | 类型 | 说明 | 证据 |
|---|---|---|---|
| `Guid` | `string`（小写 36 字符 UUID，如 `b292a9b5-dd77-435e-b675-29b1b8ad0e92`） | 节点唯一 ID；被同工程其它节点用 `ConnectionsTo` 引用 | `[实]` 36 文件无重复 Guid |
| `ConnectionsTo` | `List<Guid>` 包装 | 出边，按顺序连向本节点之后的节点 | `[实]` 见 3.6 |
| `X` `Y` | `float`（C# `System.Single`） | **仅编辑器用**的节点画布坐标；运行时无关 | `[实]` 与 float32 精度吻合，见 3.5 |

### 3.2 `EntryNodeData` —— 入口（每个工程恰 1 个）

```jsonc
{"$type": "EntryNodeData, Assembly-CSharp",
 "Title": "初遇", "Header": "Kei",
 "Guid": "00000000-0000-0000-0000-000000000000",
 "ConnectionsTo": {"$type": "…List`1[[System.Guid, mscorlib]], mscorlib", "$values": ["b292a9b5-…"]},
 "X": 0.0, "Y": 0.0}
```

| # | 字段 | 类型 | 说明 | 证据 |
|---|---|---|---|---|
| 1 | `$type` | string | `"EntryNodeData, Assembly-CSharp"` | `[实]` 36/36 |
| 2 | `Title` | `string?` | 剧情标题（封面/标题卡）；可为 null | `[实]` 36/36 非 null；`[三]` 生成器写 null 可被 AA 打开 |
| 3 | `Header` | `string?` | 剧情序号（如 `"Kei"`、`"01"`）；可为 null | `[实]` 同上 |
| 4 | `Guid` | guid | **必须全 0** `00000000-0000-0000-0000-000000000000` | `[实]` 36/36；`[三]` |
| 5 | `ConnectionsTo` | List\<Guid\> | 恰好 1 条，指向第一个剧情节点 | `[实]` 36/36 长度 1 |
| 6-7 | `X` `Y` | float | 实测恒 `0.0, 0.0` | `[实]` 36/36 |

官方文档 `[官]`：入口节点有且仅有一个，无法创建/删除；不填 Title/Header
则生成剧情不含标题部分，只填 Header 则隐藏序号。

### 3.3 `ScriptNodeData` —— 脚本节点（正文）

```jsonc
{"$type": "ScriptNodeData, Assembly-CSharp",
 "Scripts": {"$type": "…List`1[[ScriptData, Assembly-CSharp]], mscorlib",
             "$values": [ /* ScriptData，见第 6 节 */ ]},
 "NodeName": "01",
 "Guid": "b292a9b5-…",
 "ConnectionsTo": {"$type": "…Guid…", "$values": ["056c5faa-…"]},
 "X": 0.0, "Y": -200.7629}
```

| # | 字段 | 类型 | 说明 | 证据 |
|---|---|---|---|---|
| 1 | `$type` | string | `"ScriptNodeData, Assembly-CSharp"` | `[实]` |
| 2 | `Scripts` | `List<ScriptData>` 包装 | 该节点的剧本行；**可为空数组**（见下） | `[实]` 590 个节点中 1 个是 `[]` |
| 3 | `NodeName` | `string?` | 节点名（画布上显示）；**多数为 null** | `[实]` 590 个中 583 个 null，7 个有名字 |
| 4 | `Guid` | guid | 唯一 | `[实]` |
| 5 | `ConnectionsTo` | List\<Guid\> | 通常 1 条；**允许 0 条**（死路/工程末尾） | `[实]` 589/590 长度 1，1 个长度 0 |
| 6-7 | `X` `Y` | float | 画布坐标 | `[实]` |

- **空 `Scripts` 的 ScriptNode 是合法且常见的**：它是选择分支的"分流/汇合占位节点"，
  自身没有台词，只有一出边。官方文档说"空白脚本节点无法通过编译"但已标注「(已过时)」`[官]`，
  实测 36 个真实工程里有大量空节点 → 编译器已接受。
- `NodeName` 可以为 `null`、`""`、中文（如 `"结算"`）、数字串（`"01"`）。

### 3.4 `SelectionNodeData` —— 选择节点

```jsonc
{"$type": "SelectionNodeData, Assembly-CSharp",
 "selectionTexts": {"$type": "…List`1[[System.String, mscorlib]], mscorlib",
   "$values": ["选项一", "选项二", "", "", "", "", "", "", "", "", "", "", "", "", "", ""]},
 "Guid": "056c5faa-4000-4404-af22-2ee74a0e43e6",
 "ConnectionsTo": {"$type": "…Guid…", "$values": ["9b553db7-…", "cce373f4-…"]},
 "X": 0.0, "Y": -466.897644}
```

| # | 字段 | 类型 | 说明 | 证据 |
|---|---|---|---|---|
| 1 | `$type` | string | `"SelectionNodeData, Assembly-CSharp"`（注意 **S 小写开头、无空格**） | `[实]` 588/588 |
| 2 | `selectionTexts` | `List<string>` 包装 | **固定 16 个槽位**，选项文字；未用槽为 `""`（不是 null） | `[实]` 588/588 长度恰 16 |
| 3 | `Guid` | guid | 唯一 | `[实]` |
| 4 | `ConnectionsTo` | List\<Guid\> | **选项数 = 本列表长度**；可重复（同一目标多个选项） | `[实]` 长度分布 1:455、2:122、3:11；`[官]` p13「选项数量取决于连接到其出端的连线条数…连线可以重复」 |
| 5-6 | `X` `Y` | float | 画布坐标 | `[实]` |

#### 选项 ↔ 连线 ↔ 文案 的对应规则（关键）

```
选项 i 的显示文字 = selectionTexts.$values[i]
选项 i 的跳转目标 = ConnectionsTo.$values[i]
选项数量 N = len(ConnectionsTo.$values)
```

证据：

1. `[实]` 588 个选择节点里 584 个满足「非空 selectionTexts 数 == 连线数」，
   且非空文案**总是从下标 0 连续排列**（作者自上而下填）。
2. `[实]` 分支节点的画布 X 坐标：`ConnectionsTo[0]` 的目标 X 为负（左，如 −292.149261），
   `ConnectionsTo[1]` 为正（右，+290.845917）。编辑器从左到右排布 = 选项顺序。
3. `[官]` p13 明确「选项数量取决于连线条数」，因此**多余的非空文案不产生选项**。

**4 个异常样本**（`[实]`，必须容错）：「2 条非空文案 + 1 条连线」出现在
`KeiEnd-WarNeverChanges`、`KeiNew-没有你的未来`（2 处）、`KeiSRT-因为我是RABBIT`。
没有对应孤儿节点，判定为**作者删除过连线后遗留的脏文案**：AA 按 1 个选项渲染，
第 2 条文案被忽略。

> **读**：选项数取 `len(ConnectionsTo)`，文字取 `selectionTexts[i]`（越界或空则显示空串）。
> **写**：输出 16 槽数组，前 N 槽写文字，其余 `""`；连线按选项顺序写。

#### 重复连线（同一目标多个选项）

`[实]` 109 个节点的 `ConnectionsTo` 含重复 Guid，例如
`KeiEnd-WarNeverChanges` 的 `0b86d0ca-…` 出现 2 次。
`[官]` p13 也确认这是受支持的行为。**读取器不能去重**（去重会改变选项数量）。

### 3.5 `ExitNodeData` —— 出口节点（每个工程恰 1 个）

```jsonc
{"$type": "ExitNodeData, Assembly-CSharp",
 "IsEnding": false,
 "EndText": "",
 "NeHeader": "Kei",
 "NeTitle": "我，有名字了？",
 "NeScriptDirty": { /* 完整 ScriptData，17 字段，见第 6 节 */ },
 "Guid": "0d94fcdb-…", "ConnectionsTo": {"$type": "…Guid…", "$values": []},
 "X": 0.0, "Y": -4000.311}
```

| # | 字段 | 类型 | 说明 | 证据 |
|---|---|---|---|---|
| 1 | `$type` | string | `"ExitNodeData, Assembly-CSharp"` | `[实]` 36/36 |
| 2 | `IsEnding` | `bool` | `true`=「完」(Ending)，`false`=「未完待续」 | `[实]` true 7 / false 29 |
| 3 | `EndText` | `string` | 结束语（IsEnding=true 时用） | `[实]` 8 个非空 |
| 4 | `NeHeader` | `string` | 下回预告序号 | `[实]` 31 个非空 |
| 5 | `NeTitle` | `string` | 下回预告标题 | `[实]` 29 个非空 |
| 6 | `NeScriptDirty` | `ScriptData` 对象 | 出口节点的"脏"剧本对象：`isDialogScript` 恒 `false`；用于携带结局画面背景、结局文字 | `[实]` 36/36 是完整 17 字段 ScriptData；`isDialogScript` 全部 false |
| 7 | `Guid` | guid | 唯一 | `[实]` |
| 8 | `ConnectionsTo` | List\<Guid\> | **恒为空数组** | `[实]` 36/36 `[]` |
| 9-10 | `X` `Y` | float | 画布坐标，Y 在全工程最底部（如 −4000.311、−13428.9189） | `[实]` |

**`NeScriptDirty` 实测取值**（对 Godot 实现很重要）：

- `text` 有三种：`""`；`"<Header>;<Title>"`（如 `"Kei;都是我的错……"`）；
  `"<工程名>;<标题>"`。它是结局画面要显示的文字，**不是普通台词**。
- `bgName`/`bgFriendlyName`：结局画面背景，可能为 0/`""`。
- `voice`：36 字符 Guid（可能未被使用），`characters` 是 6 个空记录，`highlightedSlotNums` 为 `[]`。
- `additionalPrompt` 恒 `""` —— 注意 `#nextepisode;…` **不在 `.aap` 里**，
  是 AA 编译成 `.aas` 时按 `NeHeader`/`NeTitle` 自动生成的 `[三]`。复刻版的编译器
  要自己实现这条推导（见 `docs/spec/commands.md`）。

### 3.6 `ConnectionsTo` 与图遍历规则

- 每个节点（除 Exit）通过 `ConnectionsTo` 按顺序连出；`Entry` 只有 1 条，`ScriptNode`
  通常 1 条，`SelectionNode` 为 N 条（N = 选项数）。
- 遍历：从 Guid 全 0 的入口开始，沿 `ConnectionsTo[0]` 前进；到 `SelectionNode`
  时等玩家选择，沿 `ConnectionsTo[选中下标]` 前进；到 `ExitNode` 结束。
- 图**允许**汇合（多个分支连到同一节点）与重复连线；`[实]` 无悬空连线、无重复 Guid，
  但读取器仍应防御悬空 Guid（跳过并警告），否则一个手改文件名就会崩。
- 节点在数组里的顺序 = 编辑器画布顺序，**与执行顺序无关**，执行只看连线。

### 3.7 画布坐标 `X` / `Y`

- 类型是 C# **`float`（System.Single）**，不是 double。`[实]` 证据：JSON 里的十进制
  字面量与 float32 的最短往返表示一致（如 `-200.7629`、`-466.897644`、
  `-1037.65674`）；且出现 `0.0001`/`-0.0001` 这类 float 拖动残留。
- **没有固定布局算法**：Y 间距因文件而异（相邻脚本节点差值实测有
  −238.92 / −270.84 / −597.97 / −669.18 …），X 多为 0，分支节点 ±290~±292。
- 入口恒 `(0,0)`；出口一般 X=0，Y 为最底部最后一个节点再往下约 200~300。
- 结论：`X`/`Y` 纯粹给编辑器画布用，**AA 播放/编译不依赖它**。
  复刻版可以照抄（保持视觉一致）或自己重新布局后写回；写回必须写 float32 精度范围内的数
  （`0.0` 这种整数值 Newtonsoft 会写成 `0.0` 而不是 `0`，见第 11 节）。

---

## 4. Guid 规则

- 格式：**小写** `xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx`（Newtonsoft `Guid` 默认格式 `D`，小写）。
- 入口节点：**全 0**。这是 AA 找入口的唯一依据。
- 其它节点：随机 UUID v4 即可；只要工程内唯一、且被 `ConnectionsTo` 正确引用。
- AA 新建节点时自己生成；复刻版可以沿用 v4，也可以学 HaloCue 用
  `uuid5(NAMESPACE, "<工程名>/scene/<i>")` 做**确定性 Guid**（重生成不漂移）`[三]`。
- 实测：`[实]` 36 个工程无重复 Guid、无悬空引用。
- 空 Guid 字符串（`""`）是非法的；`"00000000-0000-0000-0000-000000000000"` 只允许入口用。

---

## 5. 节点类型与字段顺序速查（写作者照抄）

```
EntryNodeData     : $type, Title, Header, Guid, ConnectionsTo, X, Y
ScriptNodeData    : $type, Scripts, NodeName, Guid, ConnectionsTo, X, Y
SelectionNodeData : $type, selectionTexts, Guid, ConnectionsTo, X, Y
ExitNodeData      : $type, IsEnding, EndText, NeHeader, NeTitle, NeScriptDirty, Guid, ConnectionsTo, X, Y
ScriptData        : 见第 6 节（17 字段）
CharacterRecordData: 见第 7 节（9 字段）
```

`[实]` 全部 36 个文件、1250 个节点（2500 个 X/Y 坐标字段）、8268 条 ScriptData、
49608 条角色记录，键序零例外。

---

## 6. `ScriptData` —— 一行剧本（17 字段，顺序固定）

```jsonc
{
  "$type": "ScriptData, Assembly-CSharp",
  "text": "还差十五分钟。",
  "popup": "",
  "bgEffect": 0,
  "bgName": 1194944144,
  "bgFriendlyName": "BG_GameDevRoom",
  "sound": "",
  "voice": "8ef7c7b1-0000-0000-0000-00000000fe9c",
  "transition": 0,
  "bgmId": 999,
  "selectionGroup": 0,
  "additionalPrompt": "",
  "characters": {"$type": "…ScriptData+CharacterRecordData…", "$values": [ /* 恒 6 项 */ ]},
  "speakerSlotNum": 3,
  "highlightedSlotNums": {"$type": "…System.Int32…", "$values": [1, 2]},
  "isDialogScript": true,
  "placeText": ""
}
```

| # | 字段 | C# 类型 | 空值惯例 | 含义 / 取值 | 证据 |
|---|---|---|---|---|---|
| 1 | `$type` | — | — | 恒 `"ScriptData, Assembly-CSharp"` | `[实]` 8268/8268 |
| 2 | `text` | `string` | `""`（2242 条空串，用于纯演出/等待行） | 对话框台词；可含内联标记 `[size=]` `[RRGGBBAA]` `[ruby=]` | `[实]`；`[官]` p17/p18 |
| 3 | `popup` | `string?` | **null 1803 / `""` 6354** 都出现 | 弹出图片名（对应 `PopupOverrides` 的 stem，不带扩展名）；null 与 `""` 等价 | `[实]` |
| 4 | `bgEffect` | `int` | `0` = 无 | 背景效果 ID（`ScenarioBGEffectExcel` 主键，如 3134544579=BG_UnderFire）；见 enums.md | `[实]`；`[三]` |
| 5 | `bgName` | `int` | `0` 表示"不变/无" | 背景 ID = `xxHash32(UTF-8(bgFriendlyName), seed=0)`；见第 8 节 | `[实]` 8259/8268 精确命中 |
| 6 | `bgFriendlyName` | `string` | `""` | 背景友好名（如 `BG_GameDevRoom`），用于编辑器显示/资源查找 | `[实]` 8268/8268 非空 |
| 7 | `sound` | `string?` | **null 35 / `""` 7402** | 音效名（对应 `SoundOverrides` / 官方 SE 表）；null 与 `""` 等价 | `[实]` |
| 8 | `voice` | `string` | 36 字符 guid 字符串 | 配音槽 GUID → `<工程>/voices/<guid>.ogg`；登记进 `manifest.json.VoiceOverrides` | `[实]` 8268/8268 恰好 36 字符 |
| 9 | `transition` | `int`（可 >2³¹） | `0` = 无 | 过渡 ID（61 条硬编码表，见 enums.md） | `[实]` 0:7571，其余 21 种；`[三]` 61 条表 |
| 10 | `bgmId` | `int` | `999` = 静音 | BGM ID（整数主键；实测 3~155、999） | `[实]` 999 出现 1042 次；`[三]` 999=静音 |
| 11 | `selectionGroup` | `int` | `0` | 实测 **8268/8268 全 0**；分支实际由 `SelectionNodeData` 实现。保留字段，写 0 | `[实]` |
| 12 | `additionalPrompt` | `string` | `""` | 额外指令文本，多条用 `\n` 分隔，如 `"#wait;2000"`、`"#bgshake\n#wait;2000"`；见 commands.md | `[实]` 386 条非空 |
| 13 | `characters` | `List<CharacterRecordData>` 包装 | 恒 **6** 个元素 | 6 个角色槽，见第 7 节 | `[实]` 8268×6=49608 条，无例外 |
| 14 | `speakerSlotNum` | `int` | `0` | 当前说话者所在槽**下标**（0=无立绘发言槽，1–5=立绘位） | `[实]` 0:3361、3:2000、2:967、4:789、1:649、5:502 |
| 15 | `highlightedSlotNums` | `List<int>` 包装 | `[]` | 被高亮的槽下标；顺序**不保证升序**（实测有 `[3,1,5]`、`[1,5,3]`） | `[实]` 6784 条空、1484 条非空 |
| 16 | `isDialogScript` | `bool` | 实测普通行 `true`、出口 `false` | 是否为对话行 | `[实]` 8268/8268 true |
| 17 | `placeText` | `string` | `""` | 地点名称卡文字（`@place`） | `[实]` |

**重要**：`characters` 恒 6 项、`selectionTexts` 恒 16 项，这两个"魔法长度"是
AA 反序列化时数组大小与面板槽位一致的硬约定（`[实]` 全量验证）。少写会下标越界/面板错位。

### 6.1 与 AA 面板的对应（方便 editor 实现）

| AA 面板 | 字段 | 备注 |
|---|---|---|
| 对话输入框 | `text` | 可含内联标记 |
| 环境·背景 | `bgName` + `bgFriendlyName` | 二者要一起写 |
| 环境·过渡 | `transition` | 枚举见 enums.md |
| 环境·背景效果 | `bgEffect` | 枚举见 enums.md |
| 环境·弹出图片 | `popup` | 名字 = manifest `PopupOverrides` 的 stem |
| 环境·BGM | `bgmId` | 999=静音 |
| 环境·音效 | `sound` | |
| 环境·地点 | `placeText` | |
| 角色栏位 | `characters[]` | 6 槽 |
| 说话者 | `speakerSlotNum` | #0 槽 / 立绘槽 |
| 高亮 | `highlightedSlotNums` | |
| 额外指令 | `additionalPrompt` | |

---

## 7. `CharacterRecordData` —— 一个角色槽（9 字段）

```jsonc
{"$type": "ScriptData+CharacterRecordData, Assembly-CSharp",
 "name": "모모이",
 "faceId": "03",
 "startingPos": 3,
 "endingPos": 4,
 "emoticon": -1,
 "action": 0,
 "effect": 0,
 "appear": 0,
 "shapeOverride": 0}
```

| # | 字段 | C# 类型 | 取值 | 证据 |
|---|---|---|---|---|
| 1 | `$type` | — | 恒 `"ScriptData+CharacterRecordData, Assembly-CSharp"`（注意 `+`） | `[实]` 49608/49608 |
| 2 | `name` | `string` | 角色 Identifier / 官方角色 ID；`""` = 该槽无人（29742/49608 空） | `[实]` |
| 3 | `faceId` | `string` | 表情 ID，**字符串不是数字**（`"00"`、`"03"`、`"99"`，第二季 `"S2_04"` 等） | `[实]` 40+ 种取值，见 enums.md |
| 4 | `startingPos` | `int` | 本行开始时角色所处**槽下标**；下标 0 恒 0 | `[实]` 0 出现 35073 次且 `pos_range (0,0)` 35064 |
| 5 | `endingPos` | `int` | 本行结束时槽下标；≠ startingPos 即"走位" | `[实]` 49204/49608 相等，404 条走位 |
| 6 | `emoticon` | `int` | 表情符号 ID；**−1 = 无**（0 是真实值"怒筋"） | `[实]` −1:47210，0:64；见 enums.md |
| 7 | `action` | `int` | 动作 ID；0 = 无 | `[实]` 0:48473；见 enums.md |
| 8 | `effect` | `int` | **未使用**，实测 49608/49608 = 0 | `[实]` |
| 9 | `appear` | `int` | 进出场 ID；0 = 不变 | `[实]` 0:48291；见 enums.md |
| 10 | `shapeOverride` | `int` | 立绘效果**位掩码**：1=通讯/sig，2=黑屏剪影，4=特写；可组合（实测 3、5、6、7） | `[实]` 1:659、2:124、3:35、4:75、5:1、6:2、7:4 |

> 注意字段数：实际是 **9 个业务字段**（`name`…`shapeOverride`）+ `$type` = 10 个键。
> 早期资料写"9 字段"时指业务字段。

### 7.1 六个槽的语义（AA 模型核心）

- `characters` 恒 6 项：**下标 0 = 无立绘说话槽**（旁白/只出声），**下标 1–5 = 五个立绘位**。
- 槽位号越大越靠右：1 左、2 中偏左、3 中、4 中偏右、5 右 `[官]` p15。
- `startingPos` / `endingPos` / `speakerSlotNum` / `highlightedSlotNums` **全部是数组下标**，
  不是"第几个角色"，也不是屏幕位置序号。
- 同一角色留在同一槽：`上一行.endingPos == 本行.startingPos` `[实]`/`[三]` 100%。
- `[三]` 编译器生成的额外指令（不在 `.aap` 里，编译 `.aas` 时加）：
  `startingPos != endingPos` → `#N;m<endingPos>`；
  槽位由有人变无人 → `#N;hide`；
  `appear != 0` → `#N;<al|ar|a|dl|dr|d>`；
  `appear`/`action`/走位/气泡会触发默认自动 `#wait`（见 commands.md）。
- 硬约束（违反则立绘互相覆盖/消失）`[三]`：
  1) 同一行各角色 `startingPos` 两两不同；
  2) 入场角色的落点必须是当前**空着**的槽。

---

## 8. `bgName = xxHash32(UTF-8(bgFriendlyName), seed=0)`

**规则**：`bgName` 是背景友好名的 **xxHash32**（32 位无符号，小写 16 进制转十进制），种子 0。
新背景不需要查表，直接算。

```python
# 参考实现（HaloCue tables.bg_id / xxh32）
M = 0xFFFFFFFF
P1, P2, P3, P4, P5 = 2654435761, 2246822519, 3266489917, 668265263, 374761393

def rotl(x, r): return ((x << r) | (x >> (32 - r))) & M

def xxh32(data: bytes, seed: int = 0) -> int:
    n, i = len(data), 0
    if n >= 16:
        v = [(seed+P1+P2)&M, (seed+P2)&M, seed&M, (seed-P1)&M]
        while i <= n - 16:
            for j in range(4):
                k = int.from_bytes(data[i:i+4], "little"); i += 4
                v[j] = (rotl((v[j] + k*P2) & M, 13) * P1) & M
        h = (rotl(v[0],1)+rotl(v[1],7)+rotl(v[2],12)+rotl(v[3],18)) & M
    else:
        h = (seed + P5) & M
    h = (h + n) & M
    while i <= n - 4:
        h = (h + int.from_bytes(data[i:i+4], "little") * P3) & M
        h = (rotl(h, 17) * P4) & M; i += 4
    while i < n:
        h = (h + data[i] * P5) & M
        h = (rotl(h, 11) * P1) & M; i += 1
    h ^= h >> 15; h = (h * P2) & M
    h ^= h >> 13; h = (h * P3) & M
    h ^= h >> 16
    return h

def bg_id(friendly_name: str) -> int:
    return xxh32(friendly_name.encode("utf-8"), 0)
```

**验证**（`[实]`，本次复算 8268 条 ScriptData）：

- 命中 **8259/8268 = 99.89%**。全部 36 个工程、416 个不同背景名。
- 自检向量：`xxh32(b"") == 0x02CC5D05`，`xxh32(b"a") == 0x550D7456`。
- 唯一 9 条未命中：全部是 `bgFriendlyName = "BG_CS_Millenium_01_c"` 但
  `bgName = 2434566677`（按名计算应为 2177189307）。同一背景名出现在
  `Kei-初遇`、`KeiNew-没有你的未来` 两个工程。`[推]` 原因：官方背景表里该条目的
  真实名字与此处手写名不一致（拼写/大小写漂移），或来自旧版本资源表。
  HaloCue 在 139 个工程上也只遇到 2 处大小写漂移（`SunSet`/`Sunset`），结论一致：
  **不要为了算 ID 而丢弃 bgFriendlyName；两者都存，以 bgName 为运行时的权威 ID。**

**编辑器必须做的**：新建/改名背景时同时写 `bgFriendlyName` 与
`bgName = bg_id(bgFriendlyName)`；文件名中的空格、中文、大小写都参与计算。

---

## 9. 空值 / 默认值速查（跨实现兼容的关键）

| 位置 | 空值表示 | 备注 |
|---|---|---|
| `popup` | **null 或 `""`** 均可 | 读时都当"无"；写时从实测看两种都被 AA 写过（1803 null / 6354 空串） |
| `sound` | **null 或 `""`** | 同上 |
| `bgName` / `bgEffect` / `transition` / `bgmId` | 数字 | 无背景是否写 0 未单独实测；出口 `NeScriptDirty` 有 `bgName:0` + `bgFriendlyName:""` 的实例 |
| `additionalPrompt` / `placeText` / `NodeName` / `Title` / `Header` / `PreviewHeader` / `PreviewTitle` | `""` 或 `null` | 写作者建议：文本字段用 `""`，`Title`/`Header`/`NodeName`/`Preview*` 允许 `null` |
| 列表 | 永远写成 `{...}` 包装，空列表 `"$values": []` | 不要写成 `null` |
| `characters` | 恒 6 个"空记录" | 空记录见下 |

空角色记录（编辑器"清空槽位"用）：

```jsonc
{"$type": "ScriptData+CharacterRecordData, Assembly-CSharp",
 "name": "", "faceId": "00", "startingPos": 0, "endingPos": 0,
 "emoticon": -1, "action": 0, "effect": 0, "appear": 0, "shapeOverride": 0}
```

`[实]` 空槽的 `faceId` 实测全是 `"00"`（38144 条 `"00"` 中绝大多数对应空 name），
`startingPos`/`endingPos` 为 0，`emoticon` 为 −1。

---

## 10. 最小可打开工程（可直接当模板）

```jsonc
{"$type":"ProjectData, Assembly-CSharp","ProjectName":"demo","PreviewBgName":0,
 "PreviewHeader":null,"PreviewTitle":null,
 "nodes":{"$type":"System.Collections.Generic.List`1[[NodeData, Assembly-CSharp]], mscorlib","$values":[
  {"$type":"EntryNodeData, Assembly-CSharp","Title":"序","Header":"01",
   "Guid":"00000000-0000-0000-0000-000000000000",
   "ConnectionsTo":{"$type":"System.Collections.Generic.List`1[[System.Guid, mscorlib]], mscorlib","$values":["11111111-1111-4111-8111-111111111111"]},
   "X":0.0,"Y":0.0},
  {"$type":"ScriptNodeData, Assembly-CSharp",
   "Scripts":{"$type":"System.Collections.Generic.List`1[[ScriptData, Assembly-CSharp]], mscorlib","$values":[
     {"$type":"ScriptData, Assembly-CSharp","text":"你好。","popup":"","bgEffect":0,"bgName":0,
      "bgFriendlyName":"","sound":"","voice":"22222222-2222-4222-8222-222222222222","transition":0,
      "bgmId":999,"selectionGroup":0,"additionalPrompt":"",
      "characters":{"$type":"System.Collections.Generic.List`1[[ScriptData+CharacterRecordData, Assembly-CSharp]], mscorlib","$values":[
        {"$type":"ScriptData+CharacterRecordData, Assembly-CSharp","name":"","faceId":"00","startingPos":0,"endingPos":0,"emoticon":-1,"action":0,"effect":0,"appear":0,"shapeOverride":0},
        {"$type":"ScriptData+CharacterRecordData, Assembly-CSharp","name":"","faceId":"00","startingPos":0,"endingPos":0,"emoticon":-1,"action":0,"effect":0,"appear":0,"shapeOverride":0},
        {"$type":"ScriptData+CharacterRecordData, Assembly-CSharp","name":"","faceId":"00","startingPos":0,"endingPos":0,"emoticon":-1,"action":0,"effect":0,"appear":0,"shapeOverride":0},
        {"$type":"ScriptData+CharacterRecordData, Assembly-CSharp","name":"","faceId":"00","startingPos":0,"endingPos":0,"emoticon":-1,"action":0,"effect":0,"appear":0,"shapeOverride":0},
        {"$type":"ScriptData+CharacterRecordData, Assembly-CSharp","name":"","faceId":"00","startingPos":0,"endingPos":0,"emoticon":-1,"action":0,"effect":0,"appear":0,"shapeOverride":0},
        {"$type":"ScriptData+CharacterRecordData, Assembly-CSharp","name":"","faceId":"00","startingPos":0,"endingPos":0,"emoticon":-1,"action":0,"effect":0,"appear":0,"shapeOverride":0}
      ]},
      "speakerSlotNum":0,"highlightedSlotNums":{"$type":"System.Collections.Generic.List`1[[System.Int32, mscorlib]], mscorlib","$values":[]},
      "isDialogScript":true,"placeText":""}
   ]},
   "NodeName":null,"Guid":"11111111-1111-4111-8111-111111111111",
   "ConnectionsTo":{"$type":"System.Collections.Generic.List`1[[System.Guid, mscorlib]], mscorlib","$values":["33333333-3333-4333-8333-333333333333"]},
   "X":0.0,"Y":-200.0},
  {"$type":"ExitNodeData, Assembly-CSharp","IsEnding":true,"EndText":"Fin","NeHeader":"","NeTitle":"",
   "NeScriptDirty":{"$type":"ScriptData, Assembly-CSharp","text":"","popup":"","bgEffect":0,"bgName":0,
     "bgFriendlyName":"","sound":"","voice":"44444444-4444-4444-8444-444444444444","transition":0,
     "bgmId":0,"selectionGroup":0,"additionalPrompt":"",
     "characters":{"$type":"System.Collections.Generic.List`1[[ScriptData+CharacterRecordData, Assembly-CSharp]], mscorlib","$values":[
       {"$type":"ScriptData+CharacterRecordData, Assembly-CSharp","name":"","faceId":"00","startingPos":0,"endingPos":0,"emoticon":-1,"action":0,"effect":0,"appear":0,"shapeOverride":0},
       {"$type":"ScriptData+CharacterRecordData, Assembly-CSharp","name":"","faceId":"00","startingPos":0,"endingPos":0,"emoticon":-1,"action":0,"effect":0,"appear":0,"shapeOverride":0},
       {"$type":"ScriptData+CharacterRecordData, Assembly-CSharp","name":"","faceId":"00","startingPos":0,"endingPos":0,"emoticon":-1,"action":0,"effect":0,"appear":0,"shapeOverride":0},
       {"$type":"ScriptData+CharacterRecordData, Assembly-CSharp","name":"","faceId":"00","startingPos":0,"endingPos":0,"emoticon":-1,"action":0,"effect":0,"appear":0,"shapeOverride":0},
       {"$type":"ScriptData+CharacterRecordData, Assembly-CSharp","name":"","faceId":"00","startingPos":0,"endingPos":0,"emoticon":-1,"action":0,"effect":0,"appear":0,"shapeOverride":0},
       {"$type":"ScriptData+CharacterRecordData, Assembly-CSharp","name":"","faceId":"00","startingPos":0,"endingPos":0,"emoticon":-1,"action":0,"effect":0,"appear":0,"shapeOverride":0}
     ]},
     "speakerSlotNum":0,"highlightedSlotNums":{"$type":"System.Collections.Generic.List`1[[System.Int32, mscorlib]], mscorlib","$values":[]},
     "isDialogScript":false,"placeText":""},
   "Guid":"33333333-3333-4333-8333-333333333333",
   "ConnectionsTo":{"$type":"System.Collections.Generic.List`1[[System.Guid, mscorlib]], mscorlib","$values":[]},
   "X":0.0,"Y":-400.0}
 ]}}
```

（这是根据实测结构手写的最小样例，未在真 AA 上验证 `[推]`；但每个字段/类型/顺序都有样本依据。）

---

## 11. 写作者规则（要让真 AA 能打开）

按重要性排序：

1. **`$type` 字符串逐字正确**，且必须是该对象的**第一个键**：
   `ProjectData, Assembly-CSharp`、`EntryNodeData, Assembly-CSharp`、
   `ScriptNodeData, Assembly-CSharp`、`SelectionNodeData, Assembly-CSharp`、
   `ExitNodeData, Assembly-CSharp`、`ScriptData, Assembly-CSharp`、
   `ScriptData+CharacterRecordData, Assembly-CSharp`，以及 5 种 `List` 包装串（第 2 节表）。
2. **字段名与顺序**照抄第 3/6/7 节。顺序是 C# 字段声明序，Newtonsoft 反序列化理论上
   不依赖顺序，但实测 36/36 一致，照抄零风险。
3. **入口 Guid 全 0**，且每工程恰一个入口、一个出口。
4. **`characters` 恒 6 项**、**`selectionTexts` 恒 16 项**。
5. **float 坐标**：写 JSON 数字；整数值也要带小数（Newtonsoft 对 `float` 会输出 `0.0`）。
   读取时用 double 接收再转 float32 即可，不要做字符串级比较。
6. **数字类型**：`bgName`/`transition`/`bgEffect` 是 32 位无符号语义，值可达 4 294 967 295
   （超过 int32 上限）。用 C# `int` 存会溢出，用 `uint`/`long`；JSON 层面是普通整数。
   Godot 用 `int`（64 位）即可。
7. **UTF-8 无 BOM、不转义非 ASCII**（`ensure_ascii=False`）；单行 minified 输出。
   **不要加结尾换行**（实测 36/36 没有；加了理论上也能读，但没必要冒险）。
8. 列表永远写 `{"$type": "...List`1[[...]], mscorlib", "$values": [...]}`；空数组写 `[]`。
9. Guid 小写；不要写中文全角括号、不要写 `"$id"`/`"$ref"`（Newtonsoft 引用处理不会出现在 AA 文件里，
   实测 36/36 无 `$id`/`$ref`）。
10. 顶层 `ProjectName` 与文件名 stem 一致（AA 打开时按 `projects/<name>/<name>.aap` 的布局管理同名资源文件夹）。

### 读取器容错清单

- 接受 BOM、任意空白、格式化 JSON。
- `popup`/`sound` 的 `null` 与 `""` 等价。
- `ConnectionsTo` 指向不存在的 Guid：跳过该选项/该出边并告警（不要崩）。
- `selectionTexts` 比连线少：缺的选项显示空串；多：忽略多余（见 3.4 异常样本）。
- `characters` 不足 6 项（手改文件）：补齐空记录；多于 6 项：截断。
- `bgName` 与 `xxHash32(bgFriendlyName)` 不一致：以 `bgName` 为准，`bgFriendlyName` 只做显示/查表。
- 未知字段：忽略（前向兼容）。
- `selectionGroup` 非 0：当前样本无实例，按 0 处理并告警（`[推]` 老版本 AA 可能用它表达分支）。

---

## 12. 与 Godot 实现的对接建议

| 层 | 建议 |
|---|---|
| 数据模型 | GDScript/Resource：`AAPProject`、`AAPNode`（4 子类或 `type` 枚举 + 字段）、`AAScript`、`AACharacter`。字段名与 JSON 全一致，直接用 `Dictionary` 存取也能跑。 |
| 读取 | `JSON.parse_string` → 逐层拆 `$values`；用 `str_to_var` 不行（无 `$type` 语义），必须手写映射。 |
| 写入 | `JSON.stringify` 默认会输出空格且键序不保证 → **手写序列化器**（按第 3/6/7 节顺序手拼字符串或有序 Dictionary）。浮点用 `%.7g` 之类的 float32 精度格式化，整数值补 `.0`。 |
| 校验 | 写一个 `validate_aap()`：入口/出口唯一、Guid 全 0、无重复 Guid、无悬空边、6 槽/16 槽、字段齐全。真实样本旁挂 `SOURCES.sha256`，可做回归。 |
| 编辑 | `X`/`Y` 画布坐标直接复用；双击连线/选项的编辑器交互参考 p13。 |
| 运行时 | 见 `docs/spec/commands.md`、`docs/spec/enums.md`。 |

---

## 13. 尚未确认 / 推测清单

| 项 | 状态 |
|---|---|
| `PreviewHeader`/`PreviewTitle`/`Title`/`Header` 为 `null` 时 AA 的行为 | `[推]` 按"无标题"处理，HaloCue 生成器写 null 且声称 AA 可打开（`[三]`，未亲自验证） |
| `bgName=0` 的语义（保持上一背景？黑屏？） | `[推]` 普通 ScriptData 里实测为 0 的样本不存在（8268/8268 非 0），无法确认；出口 `NeScriptDirty` 有 0 |
| `selectionGroup` 非 0 的含义 | `[三]` 提到老 AA 用单回答 Sel 的独立 SelectionNodeData；样本全 0。保留字段 |
| 未知字段是否会被 AA 保留 | 未测；读取器忽略即可，复刻版保存时应原样保留未知字段以避免破坏（可选） |
| `.aap` 由 AA 保存时是否总会重排 Guid | 未测 |
| 手写的"最小工程"能否被真 AA 打开 | `[推]` 结构正确，未实机验证（无 Windows AA 环境） |

---

## 附录 A：本次统计口径

- 样本：`systemannounce/BA_AAedit` 仓库全部 36 个 `.aap`（2026-11-14 抓取），
  其中 5 个落地到 `fixtures/aap/`（见 `fixtures/aap/SOURCES.md`）。
- 节点：Entry 36、ScriptNode 590、SelectionNode 588、Exit 36，合计 1250 节点。
- ScriptData：8268 条；CharacterRecordData：49608 条 = 8268 × 6。
- 键序统计：每种类型哈希后的键元组在 36 个文件里只有 **1 种**取值，零例外。
- `bgName` xxHash32：`xxh32(friendly.encode('utf-8'), 0)`，命中 8259/8268。
