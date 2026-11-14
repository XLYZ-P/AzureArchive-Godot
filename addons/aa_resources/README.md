# aa_resources —— AA 资源层（数据目录 / manifest / overrides / aa_pack / 资源解析）

> AzureArchive Godot 复刻 · pack-dev · 契约见 `docs/DESIGN.md` §5.2，格式细节见
> `docs/spec/resources.md`。本目录**不依赖导入器**：所有贴图/字体/音频都用
> `AaRawLoader` 运行时加载（本机 headless `--import` 会崩，见 DESIGN §10）。

## 1. 文件清单

| 文件 | 角色 | class_name |
|---|---|---|
| `aa_resources.gd` | autoload `AAResources`：数据根/目录布局/工程列表/资源包安装卸载/make_context | （autoload，无） |
| `res_context.gd` | 资源上下文：按覆盖优先级解析角色/背景/BGM/音效/弹出图/语音/背景效果 | `AaResContext` |
| `aa_manifest.gd` | `manifest.json` 全字段读写 + `overlay()` 合并 | `AaManifest` |
| `character_asset.gd` | 单角色解析结果（原生/别名/Spine/PNG 立绘/占位） | `AaCharacterAsset` |
| `aa_pack.gd` | aa_pack 目录/zip 读取（扁平格式 + docs/spec D 节现代格式兼容） | `AaPack` |
| `raw_loader.gd` | 绕过导入器的原始资源加载（文本/JSON/贴图/音频/字体/目录工具） | `AaRawLoader` |
| `res_hash.gd` | xxHash32（`bgName = xxh32(utf8(bgFriendlyName), 0)`），资源层内部用 | （无） |
| `placeholders.gd` | 占位素材工厂：渐变背景/角色剪影/静音流/缩略图 | （无） |

## 2. 数据根目录布局

默认 `user://aa_data`，可用 `AAResources.set_data_root(path)` 指向 **AA 真实 data 目录**
（如 `/storage/emulated/0/Android/data/com.foxxlight.AzureArchive/files/data`）：

```
<data_root>/
├── projects/                 # *.aap 工程 + <工程名>/ 本地自定义资源文件夹
├── saves/                    # *.aas 存档 + <工程名>/ 本地自定义资源文件夹
├── overrides/                # 全局自定义资源（结构同本地文件夹）
├── assets/                   # 预留
├── packs/<pack_id>/          # 安装的 aa_pack（我们转换/开放格式）
└── settings/                 # 预留
```

`ensure_layout()` 会创建上述 6 个目录；`join_root(rel)`（目录界面在用，勿删）拼接根路径。
`get_local_dir_for(file_path)` 按 AA 规则返回同名文件夹路径（不存在也返回，不创建）。

## 3. `AAResources`（autoload）API

```gdscript
signal packs_changed                 # 安装/卸载/启用集变化
signal data_root_changed

var data_root: String                # 默认 "user://aa_data"
var last_error: String               # 最近一次操作失败原因（空串 = 成功）
var enabled_pack_ids: PackedStringArray  # 空 = 启用全部已安装 pack

func set_data_root(path: String) -> void
func ensure_layout() -> void
func join_root(rel: String) -> String

func get_projects() -> Array[Dictionary]
func get_saves() -> Array[Dictionary]
#   条目字段：name, path, category, modified, preview_title, preview_header,
#             preview_bg_name:int, project_name, file_name, error
#   「分类-名称」规则：文件名 `<分类>-<名称>.aap`；读 .aap 顶部 ProjectName/
#   PreviewHeader/PreviewTitle/PreviewBgName；分类分组优先、未分类排最后，
#   组内按名称排序。.aas（FlatBuffers 二进制）只按文件名解析。

func get_packs() -> Array[Dictionary]
#   条目字段：id, name, version, author, description, game, format, format_version,
#             path, is_zip, valid, errors, manifest(AaManifest), manifest_dict,
#             counts:{bgs,bgm,sounds,popups,characters,voices}
func get_pack_summaries() -> Array[Dictionary]   # 精简：id/name/version/path/valid
func get_pack(pack_id: String) -> AaPack
func get_installed_pack_objects() -> Array       # AaPack 实例，按 id 升序（低→高优先级）
func set_enabled_packs(ids: PackedStringArray) -> void

func install_pack(source_path: String) -> Error  # 支持 目录 / .zip / .aapack
func uninstall_pack(pack_id: String) -> Error

func make_context(project_path := "", save_path := "") -> AaResContext
func ensure_local_dir(file_path: String) -> String   # 创建并返回 <文件stem>/ 本地资源目录
func clear_caches() -> void
func detect_aa_data_root() -> String                 # 只读探测常见 AA data 目录
static func parse_category_name(stem: String) -> Dictionary  # {category, name}
```

`install_pack` 行为：
- id 取 `catalog.json.id` → 缺省取 `pack.json.id` → 再缺省取文件夹名/文件名 stem；
- 非法的 id（含 `/`、`\`、`:`、控制字符、`.`、`..`）返回 `ERR_INVALID_PARAMETER`；
- 目录：递归复制；zip/.aapack：逐项解压并拒绝路径穿越后写到临时目录；
- 先复制/解压到 `packs/.installing_*` 暂存，再原子改名到 `packs/<id>/`；同 id 已存在先删后装；
- 缺 `catalog.json` 时返回 OK 但 `last_error` 记录警告（兼容手工包）。

## 4. `AaResContext` —— 资源解析

由 `AAResources.make_context(project_path, save_path)` 创建；`project_path/save_path`
可以是 `.aap/.aas` 文件，也可以直接是同名资源文件夹。

### 覆盖优先级（低 → 高，索引时后注册覆盖先注册）

```
aa_pack（按 id 升序，后装覆盖先装）
  < <data_root>/overrides/（全局自定义）
  < <data_root>/projects/<工程名>/（工程本地）
  < <data_root>/saves/<存档名>/（存档本地，最高）
```

每一层都会注册：目录内 `bgs/ bgm/ sounds/ popups/ voices/ fonts/ bg_effects/ characters/`
的**自动扫描** + 该层 `manifest.json` 登记（同层 manifest 优先）。manifest 登记了但文件
缺失时**跳过该条目**，不会遮蔽低优先级层（qa Q-005）。

### 公共 API

```gdscript
func setup(data_root, packs: Array, project_path := "", save_path := "") -> void
func refresh() -> void
func get_layers() -> Array           # [{kind:"pack"|"global"|"project"|"save", label, root, manifest, pack}]
func get_packs() -> Array            # AaPack 实例（低→高）
func get_manifest() -> AaManifest    # 所有层 overlay 合并后的 manifest
func get_data_root() -> String
func get_project_name() -> String

func get_bg(friendly_name: String) -> Texture2D        # 空名 → null（"没有背景"）
func get_bg_by_id(bg_id: int) -> Texture2D             # bg_id = xxHash32(friendly,0)
func get_bg_entries(with_textures := true) -> Array[Dictionary]
#   [{id:int, name, category, path, source, texture?}]（texture 是 <=320x180 缩略图）

func get_bgm(key: Variant) -> AudioStream    # key: int/name；999 = 静音（返回静音流）
func get_bgm_entries() -> Array[Dictionary]  # [{key,name,title,id,path,source}]
func get_sound(name: String) -> AudioStream
func get_sound_entries() -> Array[Dictionary]
func get_popup(name: String) -> Texture2D
func get_popup_entries(with_textures := true) -> Array[Dictionary]
func get_voice(guid: String) -> AudioStream  # voices/<guid>.ogg|wav|mp3
func has_voice(guid: String) -> bool
func get_voice_entries() -> Array[Dictionary]  # [{guid,path,text,source}]
func get_bg_effect(name: Variant) -> Variant   # 返回描述 Dictionary：{name,id,type,path,params,placeholder}
func get_bg_effect_entries() -> Array[Dictionary]
func get_bg_spine_layers(name: String) -> Array[Dictionary]

func get_character(id: String) -> AaCharacterAsset
func get_characters() -> Array[AaCharacterAsset]   # 自定义 + 原生 + 别名引用到的目标
func get_font(name: String) -> Font
func get_ui_texture(name: String) -> Texture2D

func get_missing() -> PackedStringArray   # 已记录的缺失资源 "kind:key"，上限 256
func clear_missing() -> void
static func is_placeholder(res: Variant) -> bool
func get_placeholder_texture(key := "missing") -> Texture2D
func report() -> Dictionary                # 层列表 + 各类索引数量 + missing
```

### 缺失资源策略（重要）

**除"请求本身为空串"外，任何缺失资源都返回可用占位，绝不返回 null**：

| 资源 | 缺失时 |
|---|---|
| 背景 / 弹出图 / UI | 按 key 生成渐变占位 `Texture2D`，`meta: aa_placeholder=true` |
| BGM / 音效 / 语音 | 100ms 静音 `AudioStreamWAV`，`meta: aa_placeholder=true`（999 静音流带 `aa_mute=true`，不算占位） |
| 角色 | `AaCharacterAsset`（`mode="placeholder"`/`is_placeholder=true`），`get_face_texture()` 返回剪影 |
| 背景效果 | `{"type":"placeholder", ..., "placeholder":true}` 字典 |
| 字体 | 回退 `assets/fonts/wqy-zenhei-extracted.ttf`，再失败返回 null |

`get_bg("")` / `get_sound("")` / `get_popup("")` / `get_voice("")` 返回 null（表示"没有"）。

### 角色 `AaCharacterAsset` 字段/API

```gdscript
var identifier, display_name, nickname: String
var character_reference: String    # manifest CharacterReference（别名目标/原生角色名）
var original_identifier: String
var spine_base_path: String        # Spine 基础路径（不带后缀）
var small_portrait_path: String
var mode: String                   # "none"|"native"|"alias"|"spine"|"png"|"placeholder"
var face_paths: Dictionary         # face_id -> PNG 绝对路径（PNG 模式）
var face_ids: PackedStringArray
var source: String                 # "pack:<id>" / "overrides" / "project:xxx" / "native" / "missing"
var is_placeholder: bool
var meta: Dictionary
# 供播放器/编辑器直接 Object.get() 的懒填充属性：
var portrait, small_portrait: Texture2D   # 小头像
var faces: Dictionary                      # face_id -> Texture2D

func get_face_texture(face_id := "") -> Texture2D   # 缺失回退 00 → 01 → 占位剪影
func get_small_portrait() -> Texture2D
func get_placeholder() -> Texture2D
func prepare_textures(load_faces := true) -> void   # 由 context 自动调用
func has_portrait_data() -> bool
func is_native() -> bool
func get_display_label() -> String
func to_dict() -> Dictionary
static func face_id_from_filename(fname) -> String  # 00~12/99/halo_01/halo_02 命名规则
static func is_avatar_filename(fname) -> bool       # *-avatar.png / *_avatar.png
static func scan_character_dir(dir) -> Dictionary   # {faces, avatar, spine_base, files}
```

角色来源识别：
1. **原生**：`characters[].name` 是官方角色 ID（韩文等），`mode="native"`；没有官方资源包时
   纹理为占位剪影（`meta.official_portrait_available=false`），显示名可用
   `aa_pack.catalog.native_characters` 提供的映射。
2. **别名**（`CharacterReference` 指向另一个角色/原生角色）：保留自己的 `Name/Nickname`，
   继承目标的立绘数据；`"???"` = 无立绘角色（`mode="none"`）。
3. **自定义 Spine**：`SpinePortraitPath` 不带后缀；Spine 运行时不在资源层实现
   （DESIGN §9），`get_face_texture()` 返回同名静态图或占位剪影，由后续 `AaSpineProvider` 接管。
4. **自定义 PNG 立绘**：`characters/<Identifier>/` 下按 AA 规则命名的图
   （名字包含 `00`~`12`、`99`、`halo_01`、`halo_02`；`*-avatar.png` 为小头像）。
5. 未知 id → 占位角色（`mode="placeholder"`，显示名 = id）。

## 5. `AaManifest`

```gdscript
var character_overrides, voice_overrides, popup_overrides, sound_overrides,
    bg_overrides, bg_effect_overrides, bg_spine_overrides, bgm_overrides
var source_path: String   # manifest 所在路径（相对路径基于其目录解析）
var extra: Dictionary     # 未识别顶层字段（round-trip 保留）
var format_version: int   # 6 = 只写旧版 6 字段；8 = 含 BgEffect/BgSpine
var load_error: String

static func make_empty(version := 8) -> AaManifest
static func load_from_file(path) -> AaManifest
static func from_dict(data: Dictionary, path := "") -> AaManifest
func to_dict() -> Dictionary
func to_json_text(pretty := true) -> String
func save_to_file(path) -> Error
func overlay(local: AaManifest) -> void   # local 为高优先级并进 self
func find_character(identifier) -> Dictionary   # 不区分大小写兜底
func get_character_identifiers() -> PackedStringArray
func is_empty() -> bool
func clone() -> AaManifest
func summary() -> Dictionary
static func normalize_relative(rel) -> String    # \\→/、拒绝绝对路径/..；不安全返回 ""
func resolve_relative(rel) -> String
func source_dir() -> String
```

兼容性：
- 旧版 6 字段 / 新版 8+ 字段都接受；缺失 key 按空数组；**保存时保留 8 字段**（AA 1.0 模板）；
  从未出现过新字段的旧文件写回 6 字段（`format_version=6`）。
- 键名同时接受 PascalCase（AA 原生）和 snake_case（手写 aa_pack 更友好）；
- 角色条目归一化为 7 个标准字段（缺失填空），未知角色字段保留；
- overlay：角色按 `Identifier` 替换/追加；路径列表追加去重（voice 按 guid、其余按文件 stem），
  索引时"后写覆盖先写"；`extra` 字段 high 覆盖 low。

## 6. aa_pack 读取

`AaPack` 支持两种 catalog 形态（详见 `tools/README.md`）：
1. **扁平格式（本实现/fixtures 默认）**：`catalog.json` 直接有
   `bgs/bgm/sounds/popups/characters/voices/fonts/ui/bg_effects/native_characters` 数组；
2. **`docs/spec/resources.md` D 节格式**：`pack.json` + `catalog.json {format:"aa_pack/1",
   entries:[{kind,id,key,path,...}]}`，读取时自动转换（`is_modern_format()` 可判断）。

目录与 zip（`.zip`/`.aapack`）都能读；安装后的包统一解压到 `packs/<id>/` 目录。

## 7. 与 core / player / editor 的对接

- **autoload**：`AAResources` 已注册在 `project.godot`，`_ready()` 只 `ensure_layout()`，不阻塞。
  注意 `--script` 测试模式下 autoload 在 **第一帧后**才可用（QA 测试在 deferred 里取，
  或用 `AAResources` 全局名）；不要在 SceneTree `_init` 里直接取。
- **播放器**（runtime-dev）：`AAResources.make_context(project_path)` → `AaResContext`，
  传给 `AaResProvider`。`AaResProvider` 会用 `Object.get(...)` 读取 `AaCharacterAsset` 的
  `display_name/nickname/small_portrait/faces` 属性（本层已提供懒填充属性，兼容）。
  角色 id 直接使用 `.aap` 的 `characters[i].name`。
- **编辑器**（editor-dev）：选择器用 `get_bg_entries/get_bgm_entries/get_sound_entries/
  get_popup_entries/get_voice_entries/get_characters`。条目都是 Dictionary，可能含
  `texture`（缩略图）与 `path/source`；`get_characters()` 返回 `AaCharacterAsset`。
- **core-dev**：`AaHash.bg_id()` 与本目录 `res_hash.gd` 算法一致（已用样本 6/7 个
  bgName 交叉验证；`BG_CS_Millenium_01_c` 是研究文档记录的大小写漂移例外）。
  `.aap` 顶部字段由 `AAResources` 直接用 `AaRawLoader.read_json` 读取，不反向依赖 AaProject。

## 8. 与 AA 官方资源包的对应关系

AA 官方资源以 **Unity Addressables** 形式分发（`catalog.json` + 大量 UnityFS `*.bundle`，
缓存布局 `<cache>/<bundle_name>/<content_hash>/__data`）。资源层**不直接读 bundle**，
而是用 `tools/extract_aa_pack.py`（UnityPy）先转成 aa_pack，再经 `install_pack()` 安装、
`make_context()` 解析。字段对应关系：

| AA / bundle 里的东西 | aa_pack 落点 | aa_pack catalog 字段（扁平格式） | 对应 `.aap` 字段 |
|---|---|---|---|
| `Texture2D` 名称 `BG_*` / `Background*` | `bgs/<name>.png` | `bgs:[{name,file,category?,id?}]`；`id` 缺省 = `xxHash32(name,0)` | `bgName` / `bgFriendlyName` |
| `Texture2D` 名称 `popup*` | `popups/<name>.png` | `popups:[{name,file}]` | `popup` |
| `Texture2D` 名称 `UI_*` / 其它 | `ui/<name>.png` | `ui:[{name,file}]` | 选择器图标等 |
| `AudioClip` 名称 `Theme_*/BGM_*` | `bgm/<key>.(ogg/wav)` | `bgm:[{key,file,title?,id?}]`；`id` 可选 = `bgmId` | `bgmId`（999 = 静音，不建条目） |
| `AudioClip` 名称 `SE_*/SFX_*` | `sounds/<name>.(ogg/wav)` | `sounds:[{name,file}]` | `sound`（stem） |
| `AudioClip` 名称是 GUID | `voices/<guid>.ogg` | `voices:[{guid,file,text?}]` | `voice` |
| `TextAsset`/`MonoBehaviour` 角色表 | `tables/<name>.json|.bin` | `tables:[{name,file,format}]` + `native_characters:[{key,display_name,nickname?}]` | `characters[].name`（原生角色 ID） |
| Spine `.skel/.atlas/图集 png` | `characters/<stem>/`（三件套原样） | `characters:[{identifier,display_name,nickname?,dir,portrait_mode:"spine",spine_base,small_portrait?}]` | manifest `CharacterOverrides` 的 `SpinePortraitPath`/`SmallPortraitPath` |
| PNG 立绘（AA 0.8.5+） | `characters/<id>/00.png…` | `characters:[{identifier,…,portrait_mode:"png",face_files:{…},small_portrait}]` | 同上 |
| 字体 | `fonts/` | `fonts:[{name,file}]` | 对话框字体（可选） |
| `UI_FX_*` prefab / 贴图 | `ui/` 或 `bg_effects/`（贴图）；prefab 不复刻 | `bg_effects:[{name,type,file?,params?,id?}]` | `bgEffect`（近似/占位） |

**会被提取的 Unity Asset 类型**（详见 `tools/README.md` §4.2）：

- `Texture2D` → PNG（UnityPy 解码 DXT/ETC 等压缩；有损）；
- `Sprite` → 图集纹理裁切 PNG（依赖图集缺失时告警跳过）；
- `AudioClip` → WAV/OGG（`.samples`，支持 bundle 内 `.resS` 外部资源流；FSB/Vorbis 解码失败告警）；
- `TextAsset` → Spine `.skel/.atlas` 原样、JSON 表、其它原始字节（二进制不经过字符串解码）；
- `MonoBehaviour` → 有 typetree 时 JSON、无 typetree 时原始字节 + 告警（release 包常见）；
- `Prefab/Material/Shader/AnimationClip` 等 → **跳过**（UI 特效 prefab 无法在 Godot 复现）。

**Spine 在 bundle 里的不确定性**：

- Spine-Unity 序列化形式通常是 `SkeletonDataAsset`（MonoBehaviour）+ `.skel/.json`/`.atlas`
  TextAsset + 图集页 Texture2D；**release 包可能剥离 MonoBehaviour typetree**，此时只能靠
  TextAsset/Texture2D 名字拼三件套；
- 官方立绘是 Spine 3.8~4.2 + AA 私有扩展（halo、混合模式、S2 第二季），转换后可能缺效果；
- AA 不支持 3.8.75 的 `.skel`（官方 FAQ），3.8↔4.2 需要额外转换工具；
- 资源层只保证"原样导出 + 识别 + 占位兜底"，**不在本层解析/渲染骨骼**（预留
  `AaSpineProvider`，见 §9 TODO）。

**合规声明**：官方素材版权属 Blue Archive / Nexon / AzureArchive 作者。转换工具只做
**本机转换**（只读用户已安装 AA 目录，不下载、不改 AA、不嵌入素材），产物 `source:"official"`、
`license:"local-extraction-only"`，**不得二次分发/发布**。仓库内 `fixtures/pack/synth_pack/`
全部是程序化合成素材，不含任何官方内容。

## 9. headless / 环境注意

- 不跑 `--import`；素材一律 `AaRawLoader`（`Image.load`/`AudioStream*.load_from_*`/
  `FontFile.load_dynamic_font`），zip 包用 `ZIPReader` + 内存解码。
- 新增/修改 `class_name` 后跑 `python3 scripts/gen_class_cache.py`（或统一用 `scripts/godot.sh`）。
- 自测：`scripts/godot.sh --script /tmp/test_resources_selftest.gd`（pack-dev 自测脚本在
  /tmp，不提交）；qa 的正式用例是 `bash scripts/test.sh -- --only=resources`。

## 10. TODO / 已知限制

- [ ] `AaSpineProvider`：Spine 运行时（静态帧/动画）不在资源层；目前只暴露
      `spine_base_path` + 占位剪影，等 runtime-dev 接入 spine-godot。
- [ ] 官方 Addressables 资源包不能直接加载；先用 `tools/extract_aa_pack.py` 转 aa_pack。
- [ ] `bgmId` 官方 ID→名称对照表未取得（只有 `999`=静音）；数字 key 目前返回静音占位。
      aa_pack 可通过 `catalog.bgm[].id` 显式映射。
- [ ] `bgEffect` 官方表（`ScenarioBGEffectExcel`）未内置；`get_bg_effect(int)` 返回占位描述。
- [ ] `bg_effect`/`BgSpineOverrides` 官方自定义格式未知（研究文档标 `[推]`），当前按
      "路径/JSON 描述"容错处理。
- [ ] `get_projects` 每次调用都会解析 `.aap` JSON 顶部（大工程列表可加 mtime 缓存）。
- [ ] 编辑器把新资源写回 `manifest.json` 的 API（add/remove/register）尚未提供，
      目前只读 + 整体 `save_to_file`。
- [ ] 字体：`get_font` 找包内 fonts/，找不到回退内置中文字体；UI 全局主题仍由各场景构建。
