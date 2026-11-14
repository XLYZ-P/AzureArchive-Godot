# 枚举与 ID 表（`AaEnums` 数据源）

本文件是 Godot 复刻版 `AaEnums`（或等价 Resource/JSON）的**数据源**：
字段含义见 `docs/spec/aap.md`，指令语义见 `docs/spec/commands.md`。

证据等级：

- `[实]` 本次对 36 个真实 `.aap`（8268 条 ScriptData / 49608 条角色记录）的统计复算。
- `[三]` HaloCue 逆向来源，已留档 `research/halocue/tables.py` 与
  `research/halocue/build_index.py`；HaloCue 侧验证规模：139 工程 / 18932 台词。
- `[官]` 官方文档 `research/aa-docs/`。
- `[译]` 中文译名（我们起的，用于 UI 显示，非 AA 官方本地化）。
- `[推]` 推测，未确认。

> **给 core 的一句话**：`AaEnums` 里真正需要**数据驱动**的是
> `transition`（60 个具名 ID + 0）和 `bgEffect`（26 个具名 ID + 0）两张表，
> 数据在 `research/halocue/tables.py` 的 `TRANSITION` / `BGEFFECT` dict，
> 可原样转成 Godot `Dictionary`/JSON。其余枚举是**小整数**（emoticon/action/appear/shape），
> 直接硬编码即可。`bgmId` 没有完整表，只有 999=静音 能确认。

---

## 1. 总表：哪个字段用哪张枚举

| `.aap` 字段 | 枚举 | 类型/范围 | 证据 |
|---|---|---|---|
| `ScriptData.transition` | [过渡](#4-过渡-transition61-条) | uint32 ID，60 具名 + 0 | `[三]`+`[实]` |
| `ScriptData.bgEffect` | [背景效果](#5-背景效果-bgeffect27-条) | uint32 ID，26 具名 + 0 | `[三]`+`[实]` |
| `ScriptData.bgmId` | [BGM](#6-背景音乐-bgmid) | int；999=静音 | `[实]`+`[三]` |
| `CharacterRecordData.emoticon` | [表情符号](#2-表情符号-emoticon) | int，−1 无，0–19 | `[三]`+`[实]` |
| `CharacterRecordData.action` | [动作](#3-动作-action) | int，0 无，1–7 | `[三]`+`[实]` |
| `CharacterRecordData.appear` | [进出场](#7-进出场-appear) | int，0 无，1–6 | `[三]`+`[实]` |
| `CharacterRecordData.shapeOverride` | [立绘效果](#8-立绘效果-shapeoverride位掩码) | int 位掩码 0–7 | `[实]`+`[三]` |
| `CharacterRecordData.faceId` | [表情](#9-表情-faceid) | 字符串，非枚举 | `[实]`+`[官]` |
| `CharacterRecordData.effect` | 无（恒 0） | — | `[实]` 49608/49608=0 |
| `ScriptData.selectionGroup` | 无（恒 0，保留） | — | `[实]` 8268/8268=0 |
| `speakerSlotNum` / `highlightedSlotNums` / `startingPos` / `endingPos` | 槽下标 0–5 | int | `[实]`+`[官]` |

---

## 2. 表情符号 `emoticon`

字段：`CharacterRecordData.emoticon`（int）。**`-1` = 无表情符号；`0` 是真实值（怒筋）**。

| 值 | 原生符号 | 中文 `[译]` | 样本用量 `[实]` |
|---:|---|---|---:|
| −1 | （无） | 无 | 47210 |
| 0 | `[빠직]` | 怒筋 | 64 |
| 1 | `[재잘]` | 叽喳（Chat） | 14 |
| 2 | `…` | 沉默 | 302 |
| 3 | `[!]` | 惊叹 | 293 |
| 4 | `[하트]` | 爱心 | 14 |
| 5 | `[음표]` | 音符 | 131 |
| 6 | `[?]` | 疑问 | 173 |
| 7 | `[반응]` | 反应 | 599 |
| 8 | `[///]` | 脸红 | 22 |
| 9 | `[?!]` | 惊疑 | 77 |
| 10 | `[땀]` | 冷汗 | 31 |
| 11 | `[반짝]` | 闪亮 | 226 |
| 12 | `[속상함]` | 难过 | 293 |
| 13 | `[딴생각]` | 走神 | 12 |
| 14 | `{Bulb}` | 灵光一闪 | 6 |
| 15 | `{Sad}` | 悲伤 | 34 |
| 16 | `{Sigh}` | 叹气 | 59 |
| 17 | `{Steam}` | 冒烟 | 22 |
| 18 | `{Tear}` | 落泪 | 25 |
| 19 | `{Zzz}` | 瞌睡 | 1 |

- 来源：`[三]` HaloCue `build_index.py` 的 `EMOTICON`（由 `.aap`↔`.aas` 配对反推）；
  `[实]` 20 个值全部在真实工程中出现过（含 0 与 19），覆盖面 100%。
- 实现：每个值对应一套 UI 图标/动画资源；原生素材在官方资源包里（见 resources.md）。
  复刻版可以先做**占位图标**（用符号文字），后续再换资源。
- `[三]` 有 emoticon 的行会被编译器自动插入 `#wait;2500`（见 commands.md 自动等待）。
- 陷阱：`[叽喳]` 是 `emoticon=1`，不是动作；`{jump}` 是 `action=6`，不是表情符号。

---

## 3. 动作 `action`

字段：`CharacterRecordData.action`（int）。**0 = 无**。

| 值 | 名称 | 中文 `[译]` | 样本用量 `[实]` |
|---:|---|---|---:|
| 0 | （无） | 无 | 48473 |
| 1 | `greeting` | 向下确认/鞠躬 | 260 |
| 2 | `falldownl` | 向左倒 | 23 |
| 3 | `falldownr` | 向右倒 | 31 |
| 4 | `stiff` | 小颤抖 | 429 |
| 5 | `shake` | 大颤抖 | 83 |
| 6 | `jump` | 跳 | 42 |
| 7 | `hophop` | 蹦跳 | 267 |

- 来源：`[三]` `build_index.py` `ACTION`；`[实]` 1–7 全部出现。
- 实现：这是 Spine 骨骼的**动画名**（官方模型里对应同名动画）；没有骨骼时用整体
  位移/旋转补间近似（见下"可数据驱动"）。
- `[三]` 有动作的行编译时自动插 `#wait;1500`（若同时有 emoticon 则用 2500）。

---

## 4. 进出场 `appear`

字段：`CharacterRecordData.appear`（int）。**0 = 不变**。

| 值 | 名称 | 中文 `[译]` | 样本用量 `[实]` | 对应编译期指令 `[三]` |
|---:|---|---|---:|---|
| 0 | （无） | 不变/已在场 | 48291 | 不生成 |
| 1 | `al` | 从左入场（从右侧滑入 ← 注意方向） | 23 | `#N;al` |
| 2 | `ar` | 从右入场（从左侧滑入） | 72 | `#N;ar` |
| 3 | `a` | 登场（渐显） | 963 | `#N;a` |
| 4 | `dl` | 向左退场 | 29 | `#N;dl` |
| 5 | `dr` | 向右退场 | 29 | `#N;dr` |
| 6 | `d` | 退场（渐隐） | 201 | `#N;d` |

> 方向命名以 AA 面板按钮为准 `[三]`：面板从左到右是
> `≪(dl) ▷(ar) ＋(a) [1][2][3][4][5] －(d) ◁(al) ≫(dr)`。
> `al`/`ar` 的字面是 "appear left/right"，但**入场动画的移动方向与名字相反**
> （`al` 从屏幕右侧滑入到左侧槽位）。实现时以"终点槽位"为准，入场动画从屏幕外
> 对应侧滑入即可，名字只作为动画键。

---

## 5. 立绘效果 `shapeOverride`（位掩码）

字段：`CharacterRecordData.shapeOverride`（int）。**位掩码**，可以组合：

| 位 | 值 | 名称 `[译]` | 含义 `[三]` | 样本用量 `[实]` |
|---|---:|---|---|---:|
| — | 0 | 无 | 正常立绘 | 48708 |
| bit0 | 1 | 通讯 | 立绘上叠一层通讯/电子屏滤镜（"sig"） | 659 |
| bit1 | 2 | 黑屏剪影 | 立绘变暗/剪影（"black"） | 124 |
| bit2 | 4 | 特写 | 立绘放大（"closeup"） | 75 |
| 0+1 | 3 | 通讯+剪影 | 组合 | 35 |
| 0+2 | 5 | 通讯+特写 | 组合 | 1 |
| 1+2 | 6 | 剪影+特写 | 组合 | 2 |
| 3 位全开 | 7 | 通讯+剪影+特写 | 组合 | 4 |

- `[实]` 关键修正：HaloCue 早期文档只写了 1/2/4；本次 36 工程实测出现
  **3/5/6/7 四种组合值**（共 42 条），因此确认是**位掩码**而非枚举。
- 字段 `effect`（恒 0）不是这个枚举，已废弃 `[实]`/`[三]`。
- 编辑器面板"效果"那一行三个图标就写这个字段 `[三]`。
- 实现：1=屏幕/通讯 overlay shader；2=立绘亮度/剪影 shader；4=立绘放大。

---

## 6. 表情 `faceId`

字段：`CharacterRecordData.faceId`（**字符串，不是整数**）。它不是一个封闭枚举，
而是"Spine 立绘的动画名前缀"。

### 6.1 命名规则 `[官]`（p20）

- 立绘表情**使用两位数字名称**：`"00"`、`"01"`、…、`"99"`。
- 待机动画名 `Idle_01`；眨眼动画名 `Eye_Close_01`（可以没有）。
- **眨眼动画仅在无表情和 `"01"` 时播放。**
- 所以 `faceId` 就是 Spine 里"表情动画名"去掉后缀/前缀后的两位数字前缀。

### 6.2 标准 BA 模型的表情语义 `[三]`（`.atlas` region 名自带语义）

标准 atlas 里 region 形如 `00_default`、`01_normal`、`02_respond`、`03_smile`、
`04_embarrassed`、`05_serious`、`06_depressed`、`00_eyeclose`：

| faceId | 语义 `[译]` | 说明 |
|---|---|---|
| `"00"` | default 默认/无表情 | 样本最多（空槽也写 `"00"`） |
| `"01"` | normal 平常 | 眨眼动画在此值下仍会播 |
| `"02"` | respond 回应 | |
| `"03"` | smile 微笑 | |
| `"04"` | embarrassed 害羞 | |
| `"05"` | serious 认真 | |
| `"06"` | depressed 低落 | |
| `"07"`+ | 各角色/各套模型自定义 | 不保证跨角色语义一致 |

### 6.3 实测取值 `[实]`（51 种，按用量）

```
"00" 8402, "04" 1772, "02" 1645, "03" 1392, "01" 1325, "06" 1118,
"05" 954, "07" 712, "10" 407, "08" 396, "12" 329, "09" 215,
"99" 211, "14" 177, "15" 127, "11" 124, "13" 89, "18" 73,
"17" 55, "16" 51, "19" 47, "20" 25, "21" 16, "27" 8, "28" 7,
"22" 5, "25" 5, "38" 4, "29" 4, "23" 3, "46" 2, "43" 2,
"39" 1, "24" 1, "32" 1, "26" 1
S2_00 37, S2_04 45, S2_02 18, S2_01 17, S2_03 8, S2_06 7,
S2_15 7, S2_05 6, S2_07 6, S2_21 2, S2_27 2, S2_08 2,
S2_14 1, S2_26 1
```

- `"99"`：实测 211 次 `[实]`，语义未确认 `[推]`（可能是特殊/闭眼/无脸占位）。
- `"S2_xx"`：第二季（Season 2）模型的表情变体，前缀 `S2_` `[推]`。
  读取时不要假设长度=2；写入时原样保留。
- `"10"`–`"46"`：各角色专属表情，语义不通用 → **UI 不要显示语义名，只显示编号**，
  表情名从该角色的 `.atlas`/模型元数据动态读（见 resources.md）。
- 官方美术拼写错误很多，做 atlas 语义归一化时用下表 `[三]`（`FACE_ALIAS`）：

| 拼写错误 | 归一化 |
|---|---|
| `embarassed` / `embrassed` / `embarrased` / `emvarassed` / `embarrass` | `embarrassed` |
| `nomal` | `normal` |
| `defualt` / `deuflat` | `default` |
| `depressde` / `deparaeesd` | `depressed` |
| `repond` | `respond` |
| `sarcatic` | `sarcastic` |
| `yarn` | `yawn` |
| `serioous` | `serious` |
| `inocent` | `innocent` |
| `eyeclosed` / `eye_close` | `eyeclose` |
| `thingking` | `thinking` |

---

## 7. 槽位与说话者（不是枚举，但属于 "AaEnums" 常被混进来）

| 概念 | 取值 | 说明 `[实]`/`[官]` |
|---|---|---|
| `characters` 数组下标 | 0–5 | 0=无立绘发言槽，1–5=立绘位（左→右） |
| `speakerSlotNum` | 0–5 | 说话者所在槽下标；实测 0:3361、1:649、2:967、3:2000、4:789、5:502 |
| `highlightedSlotNums` | int 列表，元素 1–5（实测无 0） | 高亮槽；**顺序不保证**（`[3,1,5]` 合法），比较时当集合 |
| `startingPos`/`endingPos` | 0–5 | `endingPos != startingPos` = 本行走位 |

`[官]` p15：#1–#5 初始位置分别为 左、中偏左、中、中偏右、右；
已上场角色可通过 Position 移动，但"栏位"不变。

---

## 8. 过渡 `transition`（61 条）

字段：`ScriptData.transition`（uint32 ID）。**0 = 无过渡（None）**。
来源 `[三]`：`GameAssembly.dll` 中 `Studio.Scripts.EnvProp.TransitionProp::Init()`
的 61 次 `Dictionary.Add(name, id)`（60 具名 + None=0）。
HaloCue 在 139 个工程里遇到 29 个值，**100% 命中**；本次 36 个工程实测 **22 个不同值，全部命中** `[实]`。

完整表（数值即 `.aap` 里直接写的十进制）：

### 8.1 Fade 淡入淡出（23 条）

| 名称 | ID |
|---|---:|
| `None` | 0 |
| `Fade 250 >> 250` | 1408872282 |
| `Fade 500 >> 500` | 2130373248 |
| `Fade 1000 >> 1000` | 1122508889 |
| `Fade 1500 >> 1500` | 509674679 |
| `Fade 2000 >> 2000` | 2482233134 |
| `Fade 2500 >> 2500` | 1606908815 |
| `Fade 3000 >> 3000` | 2752031158 |
| `Fade 4000 >> 4000` | 1238175709 |
| `Fade 5000 >> 5000` | 3411222921 |
| `Fade >> 250` | 326824049 |
| `Fade >> 500` | 1974926776 |
| `Fade >> 1000` | 2136104277 |
| `Fade >> 1500` | 2127590351 |
| `Fade >> 2000` | 2457385855 |
| `Fade >> 3000` | 3222392982 |
| `Fade >> 4000` | 259497043 |
| `Fade 250 >>` | 2089682509 |
| `Fade 500 >>` | 2046503352 |
| `Fade 1000 >>` | 348351892 |
| `Fade 1500 >>` | 4203358158 |
| `Fade 2000 >>` | 2243764445 |
| `Fade 3000 >>` | 3174465279 |
| `Fade 4000 >>` | 1272583944 |

### 8.2 Fade White 淡入淡出（白）（21 条）

| 名称 | ID |
|---|---:|
| `Fade White 250 >> 250` | 3868567233 |
| `Fade White 500 >> 500` | 2246884625 |
| `Fade White 1000 >> 1000` | 3182852162 |
| `Fade White 1500 >> 1500` | 1289388507 |
| `Fade White 2000 >> 2000` | 3785883235 |
| `Fade White 2500 >> 2500` | 3181383424 |
| `Fade White 3000 >> 3000` | 1346493585 |
| `Fade White 4000 >> 4000` | 4075662009 |
| `Fade White 5000 >> 5000` | 3539052749 |
| `Fade White >> 500` | 3977094957 |
| `Fade White >> 1000` | 1626584722 |
| `Fade White >> 1500` | 457377075 |
| `Fade White >> 2000` | 2527144513 |
| `Fade White >> 3000` | 2259711251 |
| `Fade White >> 4000` | 3765959531 |
| `Fade White 500 >>` | 42187309 |
| `Fade White 1000 >>` | 2878370298 |
| `Fade White 1500 >>` | 2160391595 |
| `Fade White 2000 >>` | 704731093 |
| `Fade White 3000 >>` | 3657480713 |
| `Fade White 4000 >>` | 429693191 |

### 8.3 Crossfade 交叉渐变（10 条，只有单向）

| 名称 | ID |
|---|---:|
| `Crossfade 200 >>` | 375948222 |
| `Crossfade 300 >>` | 4187997050 |
| `Crossfade 500 >>` | 3854440696 |
| `Crossfade 1000 >>` | 4004024664 |
| `Crossfade 1500 >>` | 1173843909 |
| `Crossfade 2000 >>` | 1369285246 |
| `Crossfade 2500 >>` | 3054018111 |
| `Crossfade 3000 >>` | 1027503790 |
| `Crossfade 3500 >>` | 3196842123 |
| `Crossfade 4000 >>` | 2091508330 |

### 8.4 Special 特殊（6 条）

| 名称 | ID | 中文 `[译]` |
|---|---:|---|
| `Swipe R` | 1127535352 | 右扫 |
| `Swipe L` | 3957412172 | 左扫 |
| `Swipe D` | 3029168926 | 下扫 |
| `Swipe U` | 4152299906 | 上扫 |
| `Noise` | 3344317924 | 噪点 |
| `Circle` | 1914875660 | 圆形 |

### 8.5 `>>` 的语义 `[三]`

- `Fade 1000 >> 1000` = 淡出 1000ms → 切场 → 淡入 1000ms（共 2000ms）。
- `Fade 1000 >>` = 只淡出，不淡入（下一个脚本自带淡入或黑屏）。
- `Fade >> 1000` = 只淡入。
- Crossfade 只有单向（`>>` 结尾），语义是"交叉渐变到新画面"。

### 8.6 中文别名 `[三]`（`TRANS_CN`，可供编辑器输入）

| 中文 | 展开 | 默认时长 |
|---|---|---:|
| 无 | `None` | — |
| 淡入淡出 | `Fade {d} >> {d}` | 1000 |
| 淡出 | `Fade {d} >>` | 1000 |
| 淡入 | `Fade >> {d}` | 1000 |
| 白淡入淡出 / 淡入淡出白 | `Fade White {d} >> {d}` | 1000 |
| 白淡出 | `Fade White {d} >>` | 1000 |
| 白淡入 | `Fade White >> {d}` | 1000 |
| 交叉渐变 / 叠化 | `Crossfade {d} >>` | 1000 |
| 右扫 / 左扫 / 下扫 / 上扫 | `Swipe R/L/D/U` | — |
| 噪点 / 圆形 | `Noise` / `Circle` | — |

> **注意**：`Fade 5000 >> 5000`（3411222921）在 HaloCue 表里存在，但 HaloCue 文档
> 写"Fade 23 条"时没有单列它；本表以 `tables.py` 为准（60 具名 + None = 61）。
> 若某个 ID 在真 AA 里无效，以 AA UI 实际列出的档位为准——UI 上 4 个按钮是分组，
> 组内再选时长 `[三]`。

### 8.7 实现建议（能数据驱动 vs 只能近似）

| 组 | 能否纯数据驱动 | 建议 |
|---|---|---|
| Fade / Fade White 全部 | **可以**：一个全屏 ColorRect 的 alpha 补间，时长 = 名称里的毫秒数 | 直接按 ID 表解析时长，颜色黑/白 |
| Crossfade | 可以：两张背景 TextureRect 交叉淡化 | 需要双背景层 |
| Swipe R/L/D/U | 近似：背景整体平移出/入 | 用 shader 或 Control 位移 |
| Noise | 近似：叠一层噪点 shader 淡入 | 需要噪声贴图（官方资源包含 prefab，见 resources.md） |
| Circle | 近似：圆形遮罩扩展 | shader |

---

## 9. 背景效果 `bgEffect`（27 条）

字段：`ScriptData.bgEffect`（uint32 ID）。**0 = 无**。
来源 `[三]`：`flatdata_assets_all.bundle` 里的 `ScenarioBGEffectExcel` 解密，
全部对应 catalog 中真实存在的 `UI_FX_<name>.prefab`。
HaloCue 文档说"46 行、35 个具名效果"，但 `tables.py` 收口为 26 个具名 + None=0
（其余名字没有进工具表）。本次 36 工程实测 13 个不同值 `[实]`：
**12 个命中表，1 个未命中：`2245459904`（1 次）** → 说明官方效果多于 26 条，
表不完整 `[推]`。

| 名称 | ID | 中文别名 `[译]`（`BGFX_CN`） |
|---|---:|---|
| `None` | 0 | 无 |
| `BG_Dust_L` | 1377724294 | 烟尘 / 扬尘 |
| `BG_FocusLine` | 3550865647 | 集中线 / 速度线 |
| `BG_Mist_L` | 2728481130 | 烟雾 / 雾 / 朦胧 |
| `BG_UnderFire` | 3134544579 | 枪战 / 被射击 |
| `BG_UnderFire_R` | 2313116516 | 枪战（右）`[推]` |
| `BG_Filter_Red` | 4006301275 | 红滤镜 / 危机 |
| `BG_Filter_Red_BG` | 2174743540 | 红滤镜（无背景）`[推]` |
| `BG_Ash_Black` | 3934311147 | 黑灰 / 灰烬 |
| `BG_Ash_Red` | 736631543 | 红灰 |
| `BG_Shining_L` | 1061522909 | 闪光 |
| `BG_Shining_L_BGOff` | 1870781268 | 闪光无背景 |
| `BG_Love_L` | 1679852157 | 爱心 |
| `BG_Love_L_BGOff` | 3023046476 | 爱心无背景 |
| `BG_Flash` | 786952175 | 闪白 |
| `BG_Flash_Sound` | 1566732214 | 闪电（含音效） |
| `BG_Teleport` | 880081110 | 传送 |
| `BG_Rain_L` | 3676184657 | 雨 |
| `BG_Snow_L` | 2675527592 | 雪 |
| `BG_SandStorm_L` | 575794762 | 沙尘暴 |
| `BG_Wave_F` | 866423043 | 水波 |
| `BG_WaveShort_F` | 3610115052 | 短水波 |
| `BG_ScrollL_1.0` | 176581582 | 向左滚动 1.0 `[推]` |
| `BG_ScrollR_1.0` | 442565896 | 向右滚动 1.0 `[推]` |
| `BG_ScrollB_0.5` | 1488006201 | 向下滚动 0.5 `[推]` |
| `BG_Fireworks_L_BGOff_01` | 2551519896 | 烟花 01（无背景） |
| `BG_Fireworks_L_BGOff_02` | 2499688462 | 烟花 02（无背景） |

未确认 ID（不在 HaloCue 表里，出现 1 次 `[实]`）：

| ID | 状态 |
|---:|---|
| 2245459904 | `[推]` 官方效果表中未收录的一条 `UI_FX_*`；实现时按"无效果"并告警 |

### 实现建议

| 效果 | 建议 |
|---|---|
| `BG_Flash` / `BG_Shining_L` / `BG_Love_L` / `BG_Ash_*` / `BG_Filter_Red` | 用 ColorRect/CanvasModulate + shader **近似**（颜色叠加/闪烁/调色） |
| `BG_Rain_L` / `BG_Snow_L` / `BG_Dust_L` / `BG_Mist_L` / `BG_FocusLine` | 需要粒子/贴图；官方是 prefab，**只能用资源包提取的素材**（resources.md）或自绘近似的 GPUParticles2D |
| `BG_Wave_F` / `BG_Teleport` / `Swipe/Noise/Circle` 过渡 | shader 近似 |
| 优先级 | 先支持 0 + 红滤镜/闪光类（纯 shader，成本低），粒子类后做 |

> **AA 行为**：`bgEffect` 是"这一行开始时施加的背景效果"，持续到下一次改变/换背景；
> 实现为状态机而不是一次性动画更接近真机 `[推]`（HaloCue 文档未写持续时间）。

---

## 10. 背景音乐 `bgmId`

字段：`ScriptData.bgmId`（int）。**没有完整对照表** `[推]`。

- `[三]`/`[实]` `999` = **静音**（样本 1042 次）。
- `[实]` 其余实测取值 3–155（如 5、93、73、64、22、21、32…），是官方 BGM 表的
  整数主键；本次样本覆盖 60+ 个值，但**无名称对照**。
- `[推]` 与 `bgName` 不同，`bgmId` **不是哈希**（值域太小且连续），是 Excel 主键。
  官方资源包里有 `ScenarioBGMExcel`（见 resources.md）可导出完整表。
- Godot 实现：`bgmId` 当不透明 ID 用；`999` → 停止 BGM；资源目录用
  `bgm_<id>.<ext>`；等 pack 生成器从官方资源包补全 ID→文件名映射。

---

## 11. 其它需要 AaEnums 收口的常量

| 常量 | 值 | 说明 |
|---|---|---|
| 节点类型 | `EntryNodeData` / `ScriptNodeData` / `SelectionNodeData` / `ExitNodeData` | `$type` 前缀（见 aap.md） |
| `ExitNodeData.IsEnding` | `false` = 未完待续 / `true` = 完 | `[实]` 7 true / 29 false |
| `characters` 槽数 | 6 | 固定 |
| `selectionTexts` 槽数 | 16 | 固定 |
| 屏幕空间 | 宽 **2960** 单位，原点在屏幕中心，高度可变 | `[官]` p17/p18；`#zmc` 的缩放系数 3160 与 2960 差 200 是官方数值 `[三]`，按官方 3160 实现 |
| 对话框文字原大小 | `[size=60]` = 原大小 | `[三]`（p17 只说可放大缩小） |
| 屏幕文字原大小 | `#st/#stm` 字号 50 = 原大小 | `[三]` |
| 立绘图 / 头像 | `characters/<Identifier>/<stem>.skel/.atlas/.png` + `<stem>-avatar.png` | `[三]`+`[官]` |
| Spine 动画名 | `Idle_01`、`Eye_Close_01`、表情两位数字 `00`–`99` | `[官]` p20 |
| Spine 版本 | AA 支持 **3.8 ~ 4.2**；**不支持 3.8.75**，推荐 3.8.96 | `[官]` p21/p24（任务书里的"3.8.96 限制"即此） |

---

## 12. 数据驱动 vs 只能近似（给 runtime 的优先级）

| 数据 | 可完全数据驱动？ | 备注 |
|---|---|---|
| `transition` 时长/颜色 | ✅ Fade/FadeWhite/Crossfade | 名称解析出毫秒数即可 |
| `transition` Special | ⚠️ 近似 | Swipe/Noise/Circle 需 shader；官方是 prefab |
| `bgEffect` | ❌ 资源依赖 | 26 个都是 `UI_FX_*.prefab`，Godot 需自绘或从资源包提取贴图/材质后近似 |
| `emoticon` | ⚠️ 资源依赖 | 需要图标资源；先占位 |
| `action` / `appear` | ⚠️ 骨骼依赖 | Spine 动画名；无骨骼时用补间近似 |
| `faceId` | ⚠️ 骨骼依赖 | Spine 表情动画名前缀 |
| `shapeOverride` | ✅ shader | 3 个位 = 3 个 shader 开关 |
| `bgmId` | ❌ 缺 ID→文件表 | 先支持 999=静音 + 直读 `bgm_<id>.ogg` |
| `bgName` | ✅ 哈希可算 | 素材仍需资源包 |

---

## 13. 来源与留档

- HaloCue `tables.py`：`research/halocue/tables.py`（含 `TRANSITION`、`BGEFFECT`、
  `TRANS_CN`、`BGFX_CN`、`resolve_transition`、`resolve_bgeffect`、`xxh32`、`implicit_wait`）。
- HaloCue `build_index.py` 的 `EMOTICON`/`EMOTICON_CN`/`ACTION`/`ACTION_CN`/
  `APPEAR`/`APPEAR_CN`/`SHAPE`/`SHAPE_CN`/`FACE_ALIAS`：
  源仓库 `Suciko/HaloCue`（raw: `https://raw.githubusercontent.com/Suciko/HaloCue/main/build_index.py`）。
- 官方文档：`research/aa-docs/p15`（栏位）、`p17/p18`（指令/坐标/字号）、
  `p20`（自定义骨骼命名）、`p21`（Spine 版本）、`p24`（更新公告：支持 3.8~4.2）。
- 实测统计：36 个真实工程，见 `fixtures/aap/SOURCES.md`。
