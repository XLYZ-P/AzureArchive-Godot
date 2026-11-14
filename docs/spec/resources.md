# 资源包与自定义资源格式

覆盖三块，服务三类读者：

| 读者 | 该看 |
|---|---|
| 编辑器/运行时（读写自定义资源） | A 节（数据目录）、B 节（`manifest.json`、Spine/PNG 立绘、配音） |
| 资源包提取器（UnityPy / 官方资源包） | C 节（Addressables、FlatData、提取方案） |
| `aa_pack` 开放格式开发者 | D 节（我们定义的目标格式 + catalog schema） |

证据等级：`[实]`=本次 36 个真实工程（`fixtures/aap/`）；`[官]`=官方文档 `research/aa-docs/`；
`[三]`=HaloCue 逆向（已留档 `research/halocue/*.py`）；`[推]`=推测。

---

## A. AA 数据目录布局

### A.1 目录位置

| 平台 | `data` 目录 | 证据 |
|---|---|---|
| Windows | `C:\Users\<用户名>\AppData\LocalLow\foxxlight\AzureArchive\data` | `[官]` p19 |
| Android | `/storage/emulated/0/Android/data/com.foxxlight.AzureArchive/files/data` | `[官]` p19 |
| iOS | `我的iPhone/iPad/AzureArchive/data` | `[官]` p19 |

- 0.8.8+ 可在 AA 设置里改「存储目录」（aap/aas/override 等）与「缓存目录」（资源包模型数据），
  改完后旧位置只剩 `settings/user_settings.json` `[官]` p24/p36。
- `settings/user_settings.json` 里的关键字段（`[三]` `aa_install_discovery.py` 实际读取）：
  - `workspacePath`：真正的 `data` 目录（改过存储路径时用）
  - `cachePath`：资源缓存根（见 C.2）
  - `visitedFiles`：最近打开的 `.aap`/`.aas` 路径列表（字符串数组）
- 探测优先级 `[三]`：显式路径 > `user_settings.workspacePath` > `LocalLow/foxxlight/AzureArchive/data` >
  `aa_config.json.aa_data` / 环境变量 `AA_DATA`。判定 `data` 的依据是**存在 `projects/` 子目录**。
- Unity 身份：`<install>/AzureArchive_Data/app.info` 前两行 = vendor/product
  （默认 `foxxlight` / `AzureArchive`）`[三]`。
- 安装根：`AzureArchive.exe` 所在目录；如果是 `.../App/AzureArchive.exe` 布局则取 `App` 的父目录 `[三]`。

### A.2 目录成员

```
<data>/
├── assets/          # 资源文件（资源包装好后放这里；一般不需要手动改） [官]p19
├── overrides/       # 全局自定义资源目录（作用于所有工程与存档） [官]p19/p20
├── projects/        # 工程：<工程名>.aap + 同名文件夹（本地自定义资源） [官]p19
├── saves/           # 存档：<工程名>.aas + 可能存在的同名自定义资源文件夹 [官]p19
├── settings/        # 设置（user_settings.json 等） [官]p19
└── manual_install/  # 手动安装资源包用（放入 zip 内容后启动 AA 自动安装，之后目录消失） [官]p02
```

- `[官]` p19 把最后一项写作 `manualInstall/`，p02（更新更晚、描述更具体）写作
  `manual_install`（"这个文件夹是要自己创建的！放入后此文件夹会自行消失"）。
  **实现建议：两个名字都探测，优先 `manual_install`**（`[推]` 后者是实际拼写）。
- **移植工程必须连带**：`.aap` + 同名 `projects/<名>/` 文件夹 + `saves/<名>/`（若有）`[官]` p19。
- `assets/`、`saves/` 的精确内部结构官方未公开；提取器应面向 C 节的
  Addressables catalog + 缓存目录，而不是硬编码 `assets/` 结构 `[推]`。

### A.3 全局 overrides vs 本地工程文件夹

`[官]` p20：

- **两者结构完全一致**；区别是作用域：
  - `data/overrides/` = **全局自定义资源**，对所有工程/存档生效；
  - `data/projects/<工程名>/` = **本地自定义资源**，只对该工程生效，且便于随工程移植。
- 存档侧同理可能有 `data/saves/<工程名>/`（0.6.0+ 的"项目文件分类"）`[官]` p19/p22。
- 自动自定义（选择器左上角背包按钮 / 角色名片按钮）**导入到本地自定义文件夹** `[官]` p20。
- 同名资源冲突时谁优先：官方未写明；`[推]` **本地（projects/<名>/）优先于全局 overrides**，
  因为本地是"为该工程定制的覆盖"；实现建议：查表顺序 `projects/<名>/` → `data/overrides/`。
- 二者共用的子目录约定（`[实]` 真实工程 + `[三]` HaloCue 注册器）：

| 子目录 | 内容 | 对应 manifest 列表 | 证据 |
|---|---|---|---|
| `characters/<Identifier>/` | Spine 立绘（`.skel` `.atlas` `.png/.webp`）+ `<stem>-avatar.png` | `CharacterOverrides` | `[实]`/`[三]`/`[官]` |
| `bgs/` | 背景图片（`.png`，实测也有 `.jpg`） | `BgOverrides` | `[实]` 4 工程 |
| `sounds/` | 音效（`.ogg` `.wav` `.mp3`） | `SoundOverrides` | `[实]` 8 工程 |
| `voices/` | 配音 `<guid>.ogg` + `voices.txt` | `VoiceOverrides` | `[实]` 36 工程 |
| `popups/` | 弹出图片（约定名，非强制） | `PopupOverrides` | `[推]` 无真实样本 |
| `bgms/` | 自定义 BGM | `BgmOverrides` | `[推]` 无真实样本 |
| `bgEffects/` | 自定义背景效果 | `BgEffectOverrides` | `[推]` 无真实样本 |
| `bgSpines/` | 自定义 Spine 背景 | `BgSpineOverrides` | `[推]` 无真实样本 |

> 关键：`BgOverrides`/`SoundOverrides`/`PopupOverrides` 等列表存的是**相对 overrides
> 根目录的路径（带扩展名）**，所以文件**不必**放在上表约定目录里——
> 官方 p20 的例子就是 `"koharu.webp"`、`"yuzu/0721.webp"`。
> 子目录名只是各分类的默认约定。

---

## B. `manifest.json` —— 自定义资源清单

每个全局 `overrides/`、每个本地 `projects/<名>/`、`saves/<名>/` 各有一份 `manifest.json`，
UTF-8（可带 BOM，读取用 `utf-8-sig`）`[实]`。

### B.1 顶层结构

官方模板 8 个数组 `[官]` p20：

```json
{
  "CharacterOverrides": [],
  "VoiceOverrides": [],
  "PopupOverrides": [],
  "SoundOverrides": [],
  "BgOverrides": [],
  "BgEffectOverrides": [],
  "BgSpineOverrides": [],
  "BgmOverrides": []
}
```

- **重要实测差异** `[实]`：本次 36 个真实工程的 manifest 全部**只有 6 个 key**
  （`CharacterOverrides, VoiceOverrides, PopupOverrides, SoundOverrides, BgOverrides, BgmOverrides`），
  没有 `BgEffectOverrides` / `BgSpineOverrides`。
  这说明它们由旧版 AA 写出、AA 读取时**缺失的 key 按空数组处理**。
  - 读取器：必须容忍缺失 key（按 `[]`）。
  - 写入器：**保留 8 个 key**（新版本 AA 可能要；官方模板如此）。
    如果做"HaloCue 风格"的最小写回，注意 HaloCue 的 `MANIFEST_LISTS` 只有 6 个 key，
    会把后两个 key 丢掉——复刻版不要重复这个 bug。
- 每个值必须是数组；所有路径用 **Windows 反斜杠**（JSON 里写作 `"voices\\xxx.ogg"`），
  读取器同时接受 `/` `[实]`。

### B.2 `CharacterOverrides` 条目（7 字段，顺序固定）

`[实]` 36 工程 219 个条目，**键序零例外**：

```json
{"Identifier": "01", "Name": "绿", "Nickname": "游戏开发部",
 "CharacterReference": "미도리", "OriginalIdentifier": null,
 "SpinePortraitPath": null, "SmallPortraitPath": null}
```

| # | 字段 | 类型 | 说明 | 证据 |
|---|---|---|---|---|
| 1 | `Identifier` | string | 角色标识，**不透明字符串**，由用户填写，不能与已有重复。实测取值有 `"0"`、`"00"`、`"01"`、`"999"`、`"mom"`、`"21+"`、`"-1"`、`"0000"` 等 → **没有任何数字语义**，不要当 int | `[实]` 219 条 / `[官]` |
| 2 | `Name` | string | 剧情中显示的名字；实测有 68 条 Name 或 Nickname 为空（官方说"所有字段不要留空"，实际 AA 容忍） | `[实]` / `[官]` |
| 3 | `Nickname` | string | 名字右侧小字（社团/昵称） | `[实]` / `[官]` |
| 4 | `CharacterReference` | string \| null | **别名模式**：指向一个官方角色的 ID（韩文名，如 `"미도리"`、`"케이"`）。**`"???"` = 无立绘角色**（见 B.3）。与 Spine 模式互斥 | `[实]` 219 条全为 string / `[官]` |
| 5 | `OriginalIdentifier` | string \| null | 实测 **219/219 全 null**，语义未公开。`[推]`：记录"被覆盖的原角色 Identifier"或老师/特殊占位用；读写时原样保留 null | `[实]` / `[三]` |
| 6 | `SpinePortraitPath` | string \| null | **Spine 模式**：`characters\<Identifier>\<stem>`，**不带扩展名**（AA 自动找同名 `.skel`/`.atlas`/`.png`）。别名模式为 null | `[实]` null（无 Spine 样本）/ `[官]`/`[三]` |
| 7 | `SmallPortraitPath` | string \| null | 小头像 PNG 路径，**带扩展名**，如 `characters\<Identifier>\<stem>-avatar.png` | `[实]` null / `[官]`/`[三]` |

**写入规则（照抄即可）**：

- 别名（改官方角色名字/昵称）：`{"Identifier","Name","Nickname","CharacterReference":"<官方ID>","OriginalIdentifier":null,"SpinePortraitPath":null,"SmallPortraitPath":null}`
- 新角色带 Spine 立绘：
  `CharacterReference: null, OriginalIdentifier: null, SpinePortraitPath: "characters\\<Id>\\<stem>", SmallPortraitPath: "characters\\<Id>\\<stem>-avatar.png"`
- 无立绘角色：`CharacterReference: "???"`（见 B.3）

### B.3 三种 CharacterOverride 形态

| 形态 | 关键字段 | 用途 | 证据 |
|---|---|---|---|
| ① Spine 立绘 | `SpinePortraitPath` + `SmallPortraitPath` 非空，`CharacterReference=null` | 全新自定义角色，有立绘 | `[官]` p20 / `[三]` |
| ② CharacterReference 别名 | `CharacterReference`=官方角色 ID，两个 path = null | 改名字/昵称、给官方角色换名、把某官方立绘换个显示名 | `[实]` 219/219 / `[官]` |
| ③ 无立绘 "???" | `CharacterReference` **字面量 `"???"`**，两个 path = null | 只需一个"说话人名 + 无立绘"的角色（旁白式发言者） | `[官]` p20（原文："没错就是'???'，无需修改"）；`[实]` 无此形态样本 |

> 注意区分：真实工程里 `Name` 有不少写作全角 `"？？？"`（显示名），
> 那是**显示文字**；`CharacterReference: "???"`（半角三个问号）才是"无立绘"语义标记。
> 两者不要混。`[推]` AA 读取时对 `"???"` 做特判。

### B.4 其它 7 个列表

| 列表 | 元素 | 扩展名/格式 | 证据 |
|---|---|---|---|
| `VoiceOverrides` | `"voices\\<guid>.ogg"`（每个 `.aap` 用到的 voice GUID 都要登记） | `.ogg`（实测；支持 wav/mp3 未确认） | `[实]` 36/36 有值 |
| `SoundOverrides` | `"sounds\\<文件名>.<ext>"`，`.aap` 的 `sound` 字段写**不带扩展名的 stem** | `.ogg` `.mp3` `.wav`（实测三种都有） | `[实]` 8 工程 |
| `BgOverrides` | `"bgs\\<文件名>.<ext>"`，`.aap` 的 `bgFriendlyName` 写**不带扩展名的 stem**；`bgName=xxHash32(stem)`（含空格/中文/大小写） | 官方 p20 写 PNG；**实测有 `.jpg`**（AA 接受 jpg 作背景） | `[实]` 4 工程 / `[官]` |
| `PopupOverrides` | 弹出图片路径（`.aap.popup` 写 stem） | PNG（官方） | `[官]`；`[实]` 无样本 |
| `BgmOverrides` | 自定义 BGM 路径 | `.ogg`/`.mp3`/`.wav` `[推]` | `[官]` 模板有 key；`[实]` 0 工程 |
| `BgEffectOverrides` | 自定义背景效果 | **格式未知** `[推]`：1.0 新增"加载自定义背景效果"（p24），可能是一组帧图或 prefab 描述 | `[官]` p24/p20 模板；`[实]` 无 |
| `BgSpineOverrides` | 自定义 Spine 背景 | **格式未知** `[推]`：可能与 CharacterOverrides 的 Spine 三件套同类，路径不带扩展名 | `[官]` p20 模板；无其它文档 |

> 所有 Overrides 路径 = **相对 overrides/工程根目录**，带扩展名（`SpinePortraitPath` 例外，不带）。
> `.aap` 与 manifest 的对应：`sound`/`popup`/`bgFriendlyName` 用 **stem**，
> 清单里用 **带扩展名的相对路径**。

### B.5 Spine 立绘文件命名与动画规范

`[官]` p20 + `[三]` + 本次实测：

**文件**（放在 `characters/<Identifier>/` 下，文件名 stem 必须完全一致）：

```
characters/<Identifier>/<stem>.skel     # Spine 骨骼二进制
characters/<Identifier>/<stem>.atlas    # 图集描述（纯文本）
characters/<Identifier>/<stem>.png      # 图集贴图（官方文档也接受 .webp）
characters/<Identifier>/<stem>-avatar.png  # 小头像（PNG，单独裁切）
```

- `SpinePortraitPath` = `characters\<Identifier>\<stem>`（**不含扩展名**）；
  `SmallPortraitPath` = `characters\<Identifier>\<stem>-avatar.png`（含扩展名）。
- 官方文档写 `.webp`，HaloCue 注册器按 `.png` 校验 `all_files`；**实现建议：`.png` 为主，
  读时也接受 `.webp`**，写时用 `.png`。
- 头像需要特定分辨率与裁切才能正常显示（"详情参考示例"，具体尺寸官方未给 `[推]`）。

**动画名** `[官]` p20：

| 动画 | 名称 | 必需 | 说明 |
|---|---|---|---|
| 待机 | `Idle_01` | 是 | 待机循环 |
| 眨眼 | `Eye_Close_01` | 否 | **仅在无表情和 `"01"` 时播放** |
| 表情 | **两位数字**：`"00"`、`"01"`、…、`"99"` | 至少 `00` | `faceId` 直接就是这两个字符；实际是动画名前缀（标准 BA atlas 里 `00_default`、`03_smile` 等，见 enums.md §6） |

- 表情动画的命名不要求语义；`faceId` 存储的就是 `"00"`–`"99"`（含 `S2_xx` 变体，见 enums.md）。
- 材质混合：0.8.4+ 支持相加/相乘/滤色混合 `[官]` p24。
- Spine 版本：0.8.0+ 支持 **3.8 ~ 4.2**；**不支持 3.8.75**，推荐 3.8.96 `[官]` p20/p21/p24。
  写 pack 提取器/导入校验时要检查 `.skel` 头里的版本号并提示。

**PNG 立绘（图片转骨骼）模式** `[官]` p24 0.8.5 / p35：

- 在"导入骨骼"界面选择一个**文件夹**导入（0.8.5+）。
- AA 扫描文件夹中**文件名包含** `00`~`12`、`99`、`halo_01`、`halo_02` 的 `.png`
  （"名字包含"= 子串匹配，例如 `00.png`、`03_smile.png`、`halo_01.png` 都行），
  作为模型资源中对应表情下显示的内容。
- **所有图片必须同一尺寸**；图片**中间 80%**（上下各留 10%）是界面上的正常头身位置。
- 0.8.6+ 支持调整光环位置/大小/人物位置；1.0 修复了混入不符合命名规则文件导致崩溃
  （→ 复刻版提取器要过滤非法文件名而不是崩溃）。
- 该模式产出的角色仍登记为 `CharacterOverrides` 条目（`[推]`：走 Spine 字段指向转换后的模型）。

### B.6 配音与 `voices.txt`

- 每行 `ScriptData.voice` 是 36 字符 GUID，对应 `<工程>/voices/<guid>.ogg` `[实]`/`[三]`。
- 用到的配音要登记进 `manifest.json.VoiceOverrides`（路径 `voices\<guid>.ogg`）`[实]`。
- AA 会导出 `<工程>/voices/voices.txt`，格式 `[实]`（8270 行统计，8267 行标准）：

```
<guid> => [<角色名>] <台词>
c2bfde38-2cfd-4773-8d9c-65719e8cc91b => [-] 
c2932da4-282b-442c-ace8-54f98ca8c974 => [Kei] Yahoo！看起来爱丽丝你们进展相当顺利呢……
```

- 角色名 `[-]` 表示**无立绘说话者/旁白**（对应 0 号槽 / `speakerSlotNum=0`）。
- 台词后面可能带尾随空格；GUID 后固定 ` => `（空格-等号-大于-空格）。
- 真实文件里可能有**非标准行**（作者手写备注/漏格式，实测 3/8270）——
  读取器逐行 `try`，跳过非标准行并告警。
- 用途：给配音/TTS 参考（`guid → 台词 + 角色`）。
  HaloCue 生成 GUID 是确定性的（工程名+行号 uuid5），重生成不会让音频错位 `[三]`；
  复刻版建议同样用确定性 GUID。

---

## C. AA 官方资源包 = Unity Addressables

### C.1 结论与安装形态

`[三]`（`aa_install_discovery.py`、`aa_resource_cache.py`、`official_catalog.py`）
+ `[官]` p02/p19/p24/p36：

- AA 是 Unity 游戏（`AzureArchive_Data/`），资源走 **Unity Addressables**：
  - 内置 catalog：`<install>/AzureArchive_Data/StreamingAssets/aa/catalog.json`；
  - 资源内容 = **UnityFS bundle**（`__data` 文件，前 7 字节 magic `UnityFS`）；
  - bundle 缓存根：默认 `C:\Users\<用户>\AppData\LocalLow\Unity\foxxlight_AzureArchive`
    （Unity 的 Caching），0.8.8+ 可由 AA 设置改，存进 `settings/user_settings.json.cachePath`；
    HaloCue 还会探测 `<data 的祖父目录>/资源文件` 作为备选 `[三]`。
- 官方资源包 zip（`WIN_xxxxxxxxxxxx.zip` / `AND_...` / `IOS_...`，约 **4GB**）：
  在 AA 加载界面点"手动安装"选 zip，或解压到 `data/manual_install/` 后启动 AA `[官]` p02。
  **资源包版本必须与 AA 本体版本匹配**（官方给了对应表）`[官]` p02/p21。
- 手动安装后内容进入 `data/assets/`（p19 说 assets 存资源文件，Step 2C 离线安装会动它）`[推]`；
  实际加载仍通过 Addressables catalog + Unity 缓存。
- 不能分发：资源包是 BA 版权素材 + AA 加密封装，**pack 工具必须本地运行、只服务已安装 AA 的用户**。

### C.2 缓存目录布局

`[三]`（`aa_resource_cache.py` / `official_catalog.py`）：

```
<cache_root>/
└── <bundle_name>/            # 例：flatdata_assets_all.bundle（也可能以 hash 命名）
    └── <content_hash>/       # Unity Addressables 内容哈希
        └── __data            # UnityFS bundle 实体
```

- 探测逻辑：`<cache_root>/<任意目录>/<任意目录>/__data`，检查前 7 字节 == `UnityFS`。
- 同一 catalog 里 bundle 名 + hash 唯一确定文件；
  版本更新会改变 hash → **必须读 catalog 动态解析，不能硬编码路径** `[三]`。

### C.3 `catalog.json` 结构（Addressables 序列化格式）

`[三]` `official_catalog.py` 实测可读的字段：

| 字段 | 类型 | 含义 |
|---|---|---|
| `m_InternalIds` | string[] | 每个资源/ bundle 的内部 ID 字符串。表资源的 ID 形如 `<表名>.bytes`（小写，如 `scenariocharacternameexceltable.bytes`） |
| `m_EntryDataString` | base64 string | 紧凑二进制记录：前 4 字节头，之后每 **28 字节**一条 = **7 个 int32**。`row[0]`=内部 ID 索引、`row[2]`=所属 bundle 的 entry 索引（-1 表示自身就是 bundle）、`row[4]`=extra data 偏移 |
| `m_ExtraDataString` | base64 string | bundle 选项区。在偏移处找 `{\x00`，前 4 字节是 JSON 字节长度，内容是 **UTF-16LE JSON**：`m_BundleName`（bundle 文件名）、`m_Hash`（内容哈希） |

解析伪码（可直接移植）：

```python
entries = {row0: row for row0,row in enumerate(7-int records from m_EntryDataString)}
for internal_index, internal_id in enumerate(m_InternalIds):
    entry = entries[internal_index]
    bundle_index = entry[2]
    bundle_entry = entries[bundle_index] if bundle_index >= 0 else entry
    options = utf16_json_at(extra_data, bundle_entry[4])   # 搜 '{\x00'
    bundle_name, content_hash = options["m_BundleName"], options["m_Hash"]
    data_path = cache_root / bundle_name / content_hash / "__data"
```

> 复刻版只需支持"读"，不需要写 catalog。

### C.4 FlatData 表（角色/BGM/背景/音效 ID 的权威来源）

`[三]` `official_catalog.py` + `tables.py`：

- 表都在 **`flatdata_assets_all.bundle`** 里的 **`TextAsset`**；
  文本资源名小写，已确认：
  - `scenariocharacternameexceltable`（角色名表，HaloCue 实际读取）
  - `scenariobgeffectexceltable` 所在的背景效果表（tables.py 注释：`flatdata_assets_all.bundle` 的 `ScenarioBGEffectExcel`，46 行/35 具名）
  - `[推]` 同族命名：`scenariobgmexceltable`、`scenariobgexceltable`、`scenariosoundexceltable`
    （任务书提到的 `ScenarioBGMExcel`/`ScenarioBGExcel` 即此；名字按驼峰，TextAsset 名全小写）
- **表内容是加密的 FlatBuffers**（不是明文 JSON/CSV）：
  - 字符串：`base64` → 与 key `26 8b d5 0b 5c ce 86 33` 循环 XOR → **UTF-16LE** 解码；
  - uint 字段：与 key **前 4 字节按小端**解释的 int 做 XOR
    （`CHARACTER_NAME_UINT_KEY = int.from_bytes(key[:4],"little")`）；
  - 表布局：FlatBuffers vtable（`vtable = table_offset - i32(blob, table_offset)`，
    `count = (u16(blob,vtable)-4)//2`，字段偏移数组）。
- 角色表字段（0-based slot，`official_catalog.py` 实测）：
  `slot0`=native_key(u32, =`xxHash32(角色 identifier)`)、`slot1`=shape(u32)、
  `slot2`=identifier（NameKR 韩文名，就是 `.aap` 里 `name` 用的字符串）、
  `slot8`=name（NameTW 显示名）、`slot9`=club（社团）、
  `slot13`=spine 资源路径、`slot14`=avatar 头像路径。
  → **角色 ID 的产生方式**：`.aap` 存**字符串**（韩文 NameKR）；
  表里同时存它的 `xxHash32` 版本作为 native_key，供反查（`select_native_characters` 就是这么匹配的）。
- **各资源的 ID 产生方式汇总**：

| 资源 | `.aap` 字段 | ID 生成 | 证据 |
|---|---|---|---|
| 背景 | `bgName` (uint32) | **`xxHash32(UTF-8(bgFriendlyName), seed=0)`**；`bgFriendlyName` = 文件名 stem | `[实]` 8259/8268 命中；见 aap.md §8 |
| 背景 | `bgFriendlyName` | 官方背景表的名字/文件名 stem（`BG_*`） | `[实]` |
| 角色 | `characters[].name` | **字符串** = 官方角色 identifier（韩文 NameKR）；表内 native_key = `xxHash32(identifier)` | `[三]` official_catalog |
| 背景效果 | `bgEffect` (uint32) | Excel 主键（`ScenarioBGEffectExcel` 名字→ID），非哈希 | `[三]` tables.py；enums.md §9 |
| 过渡 | `transition` (uint32) | DLL 里 `TransitionProp::Init()` 的 `Dictionary.Add(name,id)` 硬编码，非哈希 | `[三]` tables.py；enums.md §8 |
| BGM | `bgmId` (int) | Excel 整数主键；`999`=静音；无完整表 | `[实]`/`[推]`；enums.md §10 |
| 音效 | `sound` (string) | 名字字符串（`SE_*`/`SFX_*`）；自定义音效直接用文件 stem | `[实]` |
| 配音 | `voice` (guid) | AA/工具生成的 GUID → `voices/<guid>.ogg` | `[实]` |
| 立绘 | `characters[].name` 指向 CharacterOverrides 的 `Identifier` | 用户自定义不透明字符串 | `[实]`/`[官]` |

### C.5 UnityPy 提取方案（写 `aa_pack` 生成器）

**前置**：用户本机已安装 AA + 资源包；工具只读，不修改 AA 目录；不打包分发原始素材。

```bash
pip install UnityPy      # 需要能读到 __data bundle
```

步骤：

1. **定位目录**
   - 从 `<install>/AzureArchive_Data/app.info` 得到 vendor/product → `LocalLow/<vendor>/<product>/data`；
   - 或读 `settings/user_settings.json` 的 `workspacePath`（存储路径被改过时）；
   - catalog：`<install>/AzureArchive_Data/StreamingAssets/aa/catalog.json`；
   - cache：`user_settings.cachePath` → 否则 `LocalLow/Unity/<vendor>_<product>` →
     否则 `<data 祖父目录>/资源文件`。
2. **解析 catalog**（C.3），得到所有 `(internal_id, bundle_name, content_hash, data_path)`。
   按 `internal_id` 关键字过滤要抽的资源（表、spine、贴图、音频）。
3. **逐 bundle `UnityPy.load(data_path)`**，遍历 `env.objects`，按类型处理：

| Unity 类型 | 提取 | 用途 / 注意事项 |
|---|---|---|
| `TextAsset` | `obj.read().m_Script`（bytes） | FlatData 表（需 XOR 解密）、Spine `.atlas`/`.skel` 文本、AA 文本配置。**最可靠**，优先用它 |
| `Texture2D` | `obj.read().image` → `save(png)` | 背景、Spine 图集页、UI 图标。Unity 里可能是 **DXT5/ETC 压缩**（第三方 4K 修复 mod 就是改这个 `[三]`），UnityPy 会解码，接受有损画质 |
| `Sprite` | `obj.read()` → 取 `m_RD.texture` + `m_Rect` 裁切；或 `image` | UI/头像类。AA 是 NGUI 风格，很多 UI 是 Texture2D + prefab，Sprite 可能较少 |
| `AudioClip` | `obj.read()` → `.samples`（dict）导出 WAV；失败时导出原始 FSB 用 vgmstream | BGM/SE/语音。注意压缩格式（Vorbis/FSB）与循环点 |
| `MonoBehaviour` | 有 typetree 时 `read_typetree()`；无 typetree 时只拿 raw bytes | Spine 的 `SkeletonDataAsset`、UI prefab 组件、配置对象。**release 包可能剥离 typetree**，是最大不确定性 |
| `AnimationClip` / `Prefab` / `Material` / `Shader` | 一般**不提取** | UI 特效 prefab 无法在 Godot 复现；只取贴图/材质颜色做近似 |
| `Font` | 可按需导 TMP 字体图集 | 对话框字体 |

4. **Spine 在 bundle 里的存在形式**（`[推]`，基于 Spine-Unity 惯例 + 已知 AA 行为）：
   - Spine-Unity 资源不是裸文件，而是：
     - `SkeletonDataAsset`（MonoBehaviour/ScriptableObject）引用
     - `.skel`（二进制）或 `.json`（文本）→ 通常序列化为 **TextAsset**；
     - `.atlas` → **TextAsset**；
     - 图集页 → **Texture2D**；
   - 所以提取顺序：找 `TextAsset` 里以 `.atlas` 文本格式（`xxx.png` + `size:` 行）或
     Spine 二进制 magic 开头的内容；再按 atlas 里的页名找 `Texture2D`。
   - **官方立绘的扩展行为**（halo 光环、`S2_` 第二季、3.8→4.2 转换、混合模式）可能由
     AA 自身运行时插件处理，不在标准 Spine 数据里 → 提取后可能缺效果 `[推]`。
   - `[推]` 若 typetree 被剥离，靠 TextAsset + Texture2D 名字（含角色 identifier 路径）也能配齐三件套。
5. **FlatData 表的解密**（C.4）：TextAsset bytes → 按 vtable 遍历 → 字符串 base64+XOR+UTF-16LE。
   角色表可得到 `identifier/name/club/spine/avatar/native_key`；
   同方法读 BGM/BG/Sound 表补全 `bgmId→名字`、背景名列表、音效名列表。
6. **产出 `aa_pack`**（D 节）：按类型落盘 + 生成 `catalog.json` + 记 `source`/`license`/`aa_version`。

### C.6 必须面对的限制（写进工具 UI，不要假装没有）

1. **Atlas/Spine 动画很难直接移植**：官方立绘是 Spine 3.8~4.2 + AA 私有的转换/扩展，
   Godot 的 spine-godot runtime 版本必须匹配；3.8 的 `.skel` 需要转换工具；
   atlas 页贴图分离、`halo` 部件/混合模式可能丢失。
2. **UI 特效（`bgEffect` 的 26 个 `UI_FX_*.prefab`）不可移植**：prefab 层级、材质、shader、
   particle 参数都在 Unity 序列化里，UnityPy 只能导出贴图/材质；Godot 需**自绘近似**，
   或干脆先只支持颜色滤镜类效果。
3. **MonoBehaviour typetree 可能被剥离**：AA 是 release 构建，`read_typetree` 可能失败，
   只能读 TextAsset/Texture2D/AudioClip 这些"自带结构"的类型。
4. **音频压缩**：Unity 的 Vorbis/FSB 需要解码；循环点、音量归一化需额外处理。
5. **图片有损**：DXT5 等压缩导致画质损失（社区为此做了高清修复 mod 就是重导贴图）。
6. **版本强绑定**：资源包与 AA 版本必须匹配；`m_Hash`/bundle 名随版本变化，
   提取器必须每次重新解析 catalog，不能缓存硬编码路径。
7. **合规**：素材版权属 BA/Nexon/AA 作者；**不得二次分发**。`aa_pack` 生成器必须是
   "用户本地转换"工具，产物仅本人使用；`catalog.json` 里记 `source:"official"`、
   `license:"local-extraction-only"`。
8. **体量**：官方包约 4GB；提取要按需（用户只装需要的章节/角色），不要一次性全转。
9. **不透明格式**：`BgEffectOverrides`/`BgSpineOverrides` 官方无文档，自定义资源包格式未知 `[推]`。

---

## D. `aa_pack` —— 我们定义的开放资源包格式

目标：把"自定义资源（B 节）+ 从官方包提取的素材（C 节）"统一成 Godot 可直接加载、
可增量分发、可校验的格式。**不是 AA 官方格式**，是我们自用的中间层。

### D.1 目录结构

```
<name>.aapack/                    # 或 zip 包；目录名 = pack id
├── pack.json                     # 包元信息（必需）
├── catalog.json                  # 资源索引（必需）
├── backgrounds/
│   ├── BG_GameDevRoom.png
│   └── bg_<bgName>.webp          # 官方提取的也可用 ID 命名
├── characters/
│   └── <identifier>/
│       ├── <stem>.skel
│       ├── <stem>.atlas
│       ├── <stem>.png
│       └── <stem>-avatar.png
├── portraits_png/                # PNG 立绘模式（0.8.5+）
│   └── <identifier>/
│       ├── 00.png 03.png 99.png
│       └── halo_01.png halo_02.png
├── audio/
│   ├── bgm/<id>.ogg
│   ├── se/<name>.ogg
│   └── voice/<guid>.ogg
├── effects/
│   ├── emoticon/<0..19>.png
│   └── bgfx/<name>/frame_000.png …
├── ui/
│   ├── popup/<name>.png
│   └── avatar/<identifier>.png
└── voices.txt                    # 可选：原样带上（见 B.6）
```

### D.2 `pack.json`（包元信息）

```json
{
  "format": "aa_pack/1",
  "id": "kei-ch1",
  "name": "Kei 第一章素材",
  "version": "1.0.0",
  "source": "official+custom",
  "aa_version": "0.8.8 / 资源包 202408202213",
  "created_at": "2026-11-14T12:00:00+08:00",
  "license": "local-extraction-only",
  "notes": "官方素材仅本机使用，勿分发",
  "requirements": {"spine": "3.8~4.2", "aa_pack": "1"}
}
```

### D.3 `catalog.json` schema（核心）

```jsonc
{
  "format": "aa_pack/1",
  "entries": [
    {
      "kind": "background",          // 见 D.4 枚举
      "id": 1194944144,              // bgName（uint32）；或字符串 ID（见 kind）
      "key": "BG_GameDevRoom",       // 友好名/stem/identifier（kind 相关）
      "path": "backgrounds/BG_GameDevRoom.png",
      "hash": "sha256:…",            // 文件 sha256（可校验）
      "source": "custom",            // custom | official | converted
      "meta": {"width": 1920, "height": 1080}
    },
    {
      "kind": "character",
      "id": "01",                    // CharacterOverrides.Identifier
      "key": "绿",
      "nickname": "游戏开发部",
      "path": "characters/01/CH0335_noweapon_spr",
      "avatar": "characters/01/CH0335_noweapon_spr-avatar.png",
      "hash": "sha256:…",
      "source": "custom",
      "meta": {
        "mode": "spine",             // spine | png
        "idle": "Idle_01",
        "blink": "Eye_Close_01",
        "faces": ["00", "01", "02", "03", "04", "05", "06", "99"],
        "spine_version": "3.8",
        "reference": null            // 别名模式时 = 官方角色 ID
      }
    },
    {
      "kind": "bgm",
      "id": 93, "key": "BGM_Theme_12",
      "path": "audio/bgm/93.ogg", "hash": "sha256:…",
      "source": "official", "meta": {"loop": [0, 0]}
    },
    {
      "kind": "sound",
      "id": "SE_DoorOpen_01",
      "path": "audio/se/SE_DoorOpen_01.ogg", "hash": "sha256:…", "source": "official"
    },
    {
      "kind": "voice",
      "id": "c2bfde38-2cfd-4773-8d9c-65719e8cc91b",
      "path": "audio/voice/c2bfde38-2cfd-4773-8d9c-65719e8cc91b.ogg",
      "source": "custom", "meta": {"character": "Kei", "text": "台词"}
    },
    {
      "kind": "emoticon",
      "id": 7, "path": "effects/emoticon/07.png", "source": "official"
    },
    {
      "kind": "bg_effect",
      "id": 3550865647, "key": "BG_FocusLine",
      "path": "effects/bgfx/BG_FocusLine/",        // 帧动画可给目录
      "source": "converted", "meta": {"fps": 30, "loop": true, "approximation": true}
    },
    {
      "kind": "popup",
      "id": "popup14", "path": "ui/popup/popup14.png", "source": "custom"
    },
    {
      "kind": "font",
      "id": "default", "path": "ui/font/aa_sans.ttf", "source": "official"
    }
  ],
  "id_map": {
    "background": {"1194944144": "BG_GameDevRoom"},
    "bgm": {"999": null},
    "transition": "static",          // 过渡用内置表（不随包发放）
    "character": {"01": "characters/01/CH0335_noweapon_spr"}
  }
}
```

### D.4 `kind` 枚举与 ID 规则

| `kind` | `id` 类型 | 来源 | 对应 `.aap` 字段 |
|---|---|---|---|
| `background` | int（uint32） | `bgName`；`key`=stem | `bgName`/`bgFriendlyName` |
| `character` | string | `Identifier`；`key`=显示名 | `characters[].name` |
| `portrait_png` | string | `Identifier`（PNG 模式角色） | 同 character |
| `avatar` | string | `Identifier` | `SmallPortraitPath` |
| `bgm` | int | `bgmId`；999=静音（不建条目） | `bgmId` |
| `sound` | string | `.aap.sound` 的 stem | `sound` |
| `voice` | string（guid） | `ScriptData.voice` | `voice` |
| `popup` | string | `ScriptData.popup` 的 stem | `popup` |
| `emoticon` | int 0–19 | 内置枚举 | `characters[].emoticon` |
| `bg_effect` | int（uint32） | `bgEffect` | `bgEffect` |
| `transition` | int（uint32） | 内置表（`research/halocue/tables.py`），**不进 pack** | `transition` |
| `font` | string | 内置/官方 | 对话框 |

### D.5 设计约束

1. **只读兼容**：`aa_pack` 是导出的素材层，不回写 AA；编辑 `.aap` 仍以 AA 原生结构为准。
2. **ID 必须与 `.aap` 字段一致**：`id` 直接是 `.aap` 里写的值（`bgName`/`bgmId`/`sound` stem/
   `voice` guid/`Identifier`），这样 runtime 拿到 `.aap` 就能 O(1) 查表。
3. **`source`/`license` 必填**：官方素材一律 `local-extraction-only`，工具拒绝把
   `official` 素材导出到共享目录/发布包（合规硬约束）。
4. **`hash` 用 sha256** 便于增量更新与完整性校验；可选 `xxh32` 快捷键。
5. **近似资源要标记**：`bg_effect`/`transition` 的 Godot 实现是近似的，`meta.approximation=true`，
   运行时/编辑器 UI 应提示"效果为近似还原"。
6. **版本字段**：`format` 做向前兼容；未知 `kind` 忽略并告警。
7. **打包**：目录形式便于开发；发布用 zip（扩展名 `.aapack`），解压后结构一致。

### D.6 建议的转换流水线

```
官方 AA 安装 + 资源包
   │ ① catalog 解析（C.3）
   ▼
bundle 列表 ──② UnityPy 提取（C.5）──► 中间目录（raw/）
   │ ③ FlatData 解密（C.4）→ 表：角色/BGM/背景/音效名
   │ ④ 自定义资源（B 节）→ manifest.json + 文件
   ▼
aa_pack 生成器：按 D.1 落盘 + 算 hash + 写 pack.json/catalog.json
   ▼
Godot 加载器：读 pack.json → catalog → 建 ID 索引 → ResourceLoader 按 path 加载
```

---

## E. 给 Godot 端的建议（先做什么、后做什么）

| 阶段 | 内容 | 依赖 | 理由 |
|---|---|---|---|
| **P0** | `manifest.json` 读取 + 本地/全局 overrides 目录扫描；背景/头像/弹出图片 PNG 直接用 Godot `Texture2D`；自定义音效 OGG/WAV/MP3 | 无（不需要官方包） | 让"自定义资源工程"先跑起来；真实样本 36/36 都是这类 |
| **P0** | `.aap` 解析 + 文本/选择/背景切换 + Fade/FadeWhite/Crossfade 过渡 | `docs/spec/aap.md`、`enums.md` | 占真实工程 90% 以上内容 |
| **P1** | `bgName=xxHash32(stem)` 计算、`voices.txt` 导出/导入、配音播放 | aap.md §8 | 编辑器核心功能 |
| **P1** | emoticon 占位图标 + action/appear 的基础补间（无 Spine 时） | enums.md | 演出骨架 |
| **P2** | 官方资源包提取器（catalog + UnityPy）→ 背景/音频/头像/字体 `aa_pack` | C 节 | 官方素材量最大，但可增量 |
| **P2** | Spine 立绘（先用 spine-godot runtime，3.8 需转换；PNG 立绘模式优先） | C.5 | 视觉核心，但版本/授权复杂 |
| **P3** | `bgEffect` 颜色滤镜类（红滤镜/闪光/灰烬）→ shader 近似；粒子类后续 | enums.md、aa_pack | 低成本还原一部分 |
| **P3** | Special 过渡（Swipe/Noise/Circle）shader；UI_FX prefab 不复刻 | — | 收益低 |
| **不做** | UI prefab / particle / shader 的完整还原；`.aas` 生成 | — | 成本 >> 收益；官方 AA 可自行编译 |

**结论**：先做 P0（纯自定义资源 + `.aap` 解释器）就能覆盖真实工程的主体；
官方资源包提取（P2）是"素材量"问题而不是"格式"问题——catalog + UnityPy 方案已在 C 节给出，
最大风险是 Spine 版本/typetree 剥离/授权，而不是找不到文件。

---

## F. 未确认 / 推测清单

| 项 | 状态 |
|---|---|
| `manualInstall/` vs `manual_install/` 实际拼写 | `[官]` 两处矛盾；建议都探测 |
| `assets/` 内部结构 | 官方未公开；`[推]` 资源包装好后放这里，加载走 Addressables |
| 全局 overrides 与本地同名资源优先级 | `[推]` 本地优先 |
| `OriginalIdentifier` 语义 | `[实]` 219/219 null；`[三]` HaloCue 也未使用；`[推]` 原角色标识 |
| `CharacterReference:"???"` 无立绘 | `[官]` p20 有明确写法；`[实]` 无样本 |
| `BgmOverrides`/`PopupOverrides` 实机格式 | `[官]` 模板有 key，`[实]` 0 工程使用；按"相对路径+扩展名"实现 |
| `BgEffectOverrides`/`BgSpineOverrides` | 官方只有模板 key + 1.0 "自定义背景效果" 一句；**格式未知** |
| Spine 立绘的官方 4 文件命名（`.png` vs `.webp`） | `[官]` 两种都提过；`[实]` 无样本；建议 `.png` 为主、读时兼容 `.webp` |
| 官方 spine 在 bundle 里的具体表示（TextAsset vs MonoBehaviour 引用） | `[推]` Spine-Unity 惯例；无真机包样本 |
| `SkeletonDataAsset` typetree 是否可用 | 未知，可能被剥离 → 提取器需 fallback |
| `avatar` PNG 的具体尺寸/裁切 | `[官]` 说"特殊分辨率与裁切"，未给数值 |
| 官方 BGM/BG/音效表名 | `[推]` 按角色表命名规律；需真机 catalog 验证 |
| AA 1.0 新增的"选择节点 Auto 选项"字段 | `[官]` p24 提到功能；`[实]` 样本（2024）无对应字段 → 新版本 `.aap` 可能多字段，读取器需容忍未知字段 |

---

## G. 本地参考文件

- 目录探测/缓存/版本：`research/halocue/aa_install_discovery.py`、`aa_resource_cache.py`
- `manifest.json` 读写与注册：`research/halocue/aa_registry.py`、`aa_project_assets.py`
- catalog/FlatData 解析：`research/halocue/official_catalog.py`（本次留档）
- ID 表（transition/bgEffect/xxhash/自动等待）：`research/halocue/tables.py`（本次留档）
- 自定义资源官方文档：`research/aa-docs/p19`（数据目录）、`p20`（自定义资源）、
  `p02`（安装/手动安装）、`p21`（FAQ/Spine 版本）、`p24`/`p35`（PNG 立绘、更新日志）、
  `p36`（改路径）
- 真实样本：`fixtures/aap/`（36 工程中的 5 个 + manifest + voices.txt）
