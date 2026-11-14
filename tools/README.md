# tools —— aa_pack 合成/转换工具（Python 3）

> pack-dev · 与 `addons/aa_resources/` 配套。所有工具**只读** AA 安装目录，产物仅本机使用。
> 真资源包拿不到时用 `--selftest` 生成最小 Unity AssetBundle 做端到端验证（不需要 4GB 官方包）。

## 1. 工具清单

| 工具 | 作用 | 依赖 |
|---|---|---|
| `aa_pack_build.py` | 生成合成 aa_pack fixture（`fixtures/pack/synth_pack/` + `.zip`），供 headless 测试/演示 | **仅 Python 标准库**（zlib+struct 手写 PNG、wave 写 WAV；有 ffmpeg 时语音转 OGG） |
| `extract_aa_pack.py` | **AA 官方资源包（Unity Addressables）→ aa_pack** 转换器 | `UnityPy`（唯一第三方依赖；本机无官方包时用 `--selftest` 验证） |

常用命令：

```bash
cd /root/workspace/aa-godot

# 合成 fixture（可重复运行；有 ffmpeg 时语音输出 .ogg，否则 .wav）
python3 tools/aa_pack_build.py
python3 tools/aa_pack_build.py --no-zip          # 只出目录
python3 tools/aa_pack_build.py --out /tmp/pack

# UnityPy 提取器自测（用 UnityPy 现造一个最小 AssetBundle，端到端 32 项断言）
python3 tools/extract_aa_pack.py --selftest
python3 tools/extract_aa_pack.py --selftest --verbose --workdir /tmp/aa_selftest

# 真实/缓存资源包提取（用户本机已安装 AA + 资源包时）
python3 tools/extract_aa_pack.py -i <资源包目录或zip或单个bundle> -o fixtures/pack/aa_official
python3 tools/extract_aa_pack.py -i <cache目录> -o out --zip --verbose

# 只查看 bundle 内容（不导出）
python3 tools/extract_aa_pack.py --inspect <目录或bundle>

# 只生成测试用最小 bundle
python3 tools/extract_aa_pack.py --make-test-bundle /tmp/selftest.bundle
```

UnityPy 安装（本机 Android proot aarch64 实测）：

```bash
pip install -i https://pypi.tuna.tsinghua.edu.cn/simple unitypy
# 若 pip 报 “No such file or directory: 'clang'”：本机需 apt-get install -y clang 后再装
# （unitypy 1.25.x 的 C 扩展要编译；清华镜像下 lz4/brotli/texture2ddecoder 等有 aarch64 wheel）
```

## 2. aa_pack 开放格式定义

aa_pack 是**我们定义的中间格式**（不是 AA 官方格式）：把"自定义资源 + 从官方资源包提取的
素材"统一成 Godot 可直接运行时加载的目录/zip。一个 pack 一个 id，安装后位于
`<data_root>/packs/<id>/`。可目录可 zip（扩展名 `.zip` 或 `.aapack`，`AAResources.install_pack`
两种都收）。

### 2.1 目录结构（扁平格式 v1，当前实现/夹具默认）

```
<aa_pack>/
├── catalog.json             # 必需：资源索引（见 2.2）
├── manifest.json            # 可选：AA 兼容覆盖表（CharacterOverrides/...，可被 AaManifest 读）
├── bgs/<name>.png           # 背景：name 即 bgFriendlyName（= 文件名 stem）
│                            #   bgName = xxHash32(UTF-8(name), seed=0)
├── bgm/<key>.ogg|wav|mp3    # BGM：key = 文件名 stem（数字 id 用 catalog.id 映射）
├── sounds/<name>.wav|ogg    # 音效：name = stem
├── popups/<name>.png        # 弹出图：name = stem
├── characters/<id>/         # 角色目录：
│   ├── 00.png 01.png … 12.png 99.png   # PNG 立绘模式的表情
│   ├── halo_01.png halo_02.png         # PNG 立绘的光环（AA 0.8.5+ 规则）
│   ├── <anything>-avatar.png           # 小头像
│   └── <stem>.skel <stem>.atlas <stem>.png   # Spine 立绘（原样放，渲染归 runtime）
├── voices/<guid>.ogg|wav    # 语音：guid = AA `.aap` 的 ScriptData.voice
├── fonts/                   # 可选字体
├── ui/                      # 可选 UI 图（选择器/图标）
├── bg_effects/              # 可选：背景效果 JSON 描述
└── tables/                  # 可选：官方提取的文本/二进制表（FlatData 原样）
```

> 目录内文件即使没写进 `catalog.json`，资源层也会按命名规则扫描兜底；
> 但 catalog 条目优先、也便于增量/校验，建议都登记。

### 2.2 `catalog.json` 字段（扁平格式）

```jsonc
{
  "format": "aa_pack",
  "format_version": 1,
  "id": "synth_pack",              // pack 安装目录名；[A-Za-z0-9._-]，install_pack 校验
  "name": "合成资源包",             // 显示名
  "version": "1.0.0",
  "author": "…",
  "description": "…",
  "game": "AzureArchive",

  // 以下数组都可选；条目里字符串等价于 {file: 字符串}
  "bgs":        [{"name": "BG_SynthSunset", "file": "bgs/BG_SynthSunset.png",
                  "category": "城市", "id": 123456789}],   // id 可选，缺省 xxHash32(name)
  "bgm":        [{"key": "Theme_Synth_01", "file": "bgm/Theme_Synth_01.wav",
                  "title": "标题", "id": 93}],             // id 可选（.aap 的 bgmId）
  "sounds":     [{"name": "SE_Synth_Click", "file": "sounds/SE_Synth_Click.wav"}],
  "popups":     [{"name": "popup_synth_01", "file": "popups/popup_synth_01.png"}],
  "characters": [{
      "identifier": "kai",                     // CharacterOverrides.Identifier（不透明字符串）
      "display_name": "凯", "nickname": "特殊现象调查部",
      "dir": "characters/kai",                 // 角色目录
      "portrait_mode": "png",                  // png | spine | native | none
      "face_files": {"00": "00.png"},          // 相对"角色目录"或包根都可以
      "small_portrait": "kai-avatar.png",      // 同上
      "spine_base": "characters/kai/kai",      // spine 模式：不带后缀的基础路径
      "native_reference": "케이"                // 别名模式：指向官方角色 ID
  }],
  "voices":     [{"guid": "421e3665-…", "file": "voices/421e3665-….ogg", "text": "台词(可选)"}],
  "fonts":      [{"name": "aa_sans", "file": "fonts/aa_sans.ttf"}],
  "ui":         [{"name": "icon_synth", "file": "ui/icon_synth.png"}],
  "bg_effects": [{"name": "SynthSparkle", "type": "placeholder",
                  "file": "bg_effects/SynthSparkle.json",   // 可选；有 JSON 则 params 从文件读
                  "params": {"color": "#ffd166", "duration": 1.2}, "id": 42}],
  "native_characters": [{"key": "모모이", "display_name": "桃井", "nickname": "游戏开发部"}]
}
```

资源层把条目转成统一结构（`AaResContext` 的 `get_*_entries()`）：背景
`{id,name,category,path,source,texture?}`，音频 `{name/key,title,id,path,source}`，
语音 `{guid,path,text,source}`，角色 `AaCharacterAsset`。

### 2.3 兼容 `docs/spec/resources.md` D 节格式

研究文档提议的另一种布局（`pack.json` + `catalog.json {format:"aa_pack/1", entries:[…]}`，
目录 `backgrounds/ audio/bgm/ audio/se/ audio/voice/ portraits_png/ characters/ ui/popup/ …`）
也可被 `AaPack` 直接读取（只读兼容，`AaPack.is_modern_format()` 判断）：

- `pack.json`：`{format:"aa_pack/1", id, name, version, source, license, notes, requirements}`
- `catalog.json`：`{format:"aa_pack/1", entries:[{kind,id,key,path,avatar,hash,source,meta}]}`
- `kind` 映射：`background`→bg、`bgm`→bgm、`sound`→音效、`voice`→语音、`popup`→弹出图、
  `character`/`portrait_png`→角色、`bg_effect`→背景效果、`font`→字体、`ui`/`avatar`→UI。
- `id` 直接取 `.aap` 字段（bgName/bgmId/sound stem/guid/Identifier），实现 O(1) 查表。

两种格式的差异：扁平格式一个 catalog 内按类型分数组、文件按类型分目录，手写夹具最方便；
D 节格式 entries 统一列表、id 语义更严格、带 hash/license。转换器输出**扁平格式**。

### 2.4 覆盖优先级（与 AA 一致）

安装的 aa_pack 是最低层；`<data_root>/overrides/`（全局自定义）和
`projects|saves/<同名文件夹>/`（本地自定义）按同结构覆盖 pack 中同名资源。
详细规则见 `addons/aa_resources/README.md` §4。

## 3. `aa_pack_build.py` —— 合成 fixture

- 产物：`fixtures/pack/synth_pack/`（+ 同名 `.zip`），可重复运行（固定参数、固定 zip 时间戳）。
- 内容：3 张渐变/图案背景 PNG、3 段正弦波 BGM、3 个音效、2 张弹出图、4 个角色
  （2 个 PNG 多表情、1 个 Spine 占位目录、1 个无立绘）、3 条语音
  （GUID 与 `fixtures/aap/sample_kei_01.aap` 实际使用的对齐）、1 张 UI 图、
  `native_characters` 映射、AA 兼容 `manifest.json` 示例。
- **不依赖 PIL**：PNG 用 `zlib + struct` 手写（IHDR/IDAT/IEND），WAV 用 `wave` 模块；
  语音在系统有 `ffmpeg` 时转 OGG Vorbis（贴 AA 原生格式），没有就保留 WAV
  （资源层两种都支持）。
- 生成耗时约 10s（纯 Python 逐像素画渐变/剪影）。

## 4. `extract_aa_pack.py` —— 官方资源包 → aa_pack

### 4.1 输入与 bundle 发现

- 输入：AA 资源包目录 / zip / 单个 `.bundle`。zip 会先安全解压到临时目录。
- bundle 发现：递归扫描文件头 `UnityFS`（7 字节 magic），**兼容 Addressables 缓存布局**
  `<cache_root>/<bundle_name>/<content_hash>/__data`；忽略 `catalog.json`/`.hash`。
  不解析 Addressables catalog 的二进制记录也能找齐 bundle（按 magic 扫描是等价且更鲁棒的做法）。
- 输出目录（默认扁平格式）：`bgs/ bgm/ sounds/ popups/ voices/ ui/ characters/<stem>/ tables/`
  + `catalog.json` + AA 兼容 `manifest.json`；`--zip` 额外打包。

### 4.2 资产处理规则

| Unity 类型 | 处理 | 分类启发式 |
|---|---|---|
| `Texture2D` | 解码为 PNG | 名称前缀 `BG_/Background`→`bgs/`；`popup*`→`popups/`；`UI_FX_/fx_`→背景效果纹理；`UI_`→`ui/`；其余未识别→`ui/` + warning |
| `Sprite` | 走图集纹理+裁切解码为 PNG | 同上（解码失败：依赖图集缺失时 warning 跳过） |
| `AudioClip` | `.samples` 导出 wav/ogg（支持 bundle 内 `.resS` 外部资源流；FSB/Vorbis 由 UnityPy 处理） | 名称为 GUID→`voices/`；`Theme_/BGM_`→`bgm/`；`SE_/SFX_`→`sounds/`；其余→`sounds/` |
| `TextAsset` | 原始字节（**手工按序列化格式取**，二进制 `.skel` 不经过字符串解码，避免损坏） | `*.skel`/skeleton→Spine 骨骼；`*.atlas`/atlas 文本→Spine 图集；JSON→`tables/`；其余→`tables/*.bin` |
| `MonoBehaviour` | 有 typetree → `tables/*.json`；无 typetree（release 包常见）→ 原始字节 + warning | FlatData/表 |
| 其它（Prefab/Material/Shader…） | 跳过 | UI 特效 prefab 不复刻（见限制） |

Spine 组装：先收集 `.skel/.atlas` TextAsset，按文件 stem 建 `characters/<stem>/`；随后把
图集页 `Texture2D`（名称等于或前缀匹配 stem）归入同目录，其余贴图按名称分类。
角色 `identifier` 暂用骨骼文件名（官方 identifier↔spine 的映射在 FlatData 表里，
当前版本未解密，见 §5），`catalog.native_characters` 从能读到的角色表 JSON 尽力推导并 warning。

### 4.3 `--selftest`（没有真资源包时验证端到端）

自测**用 UnityPy 现场构造最小 Unity AssetBundle**（手写最小 SerializedFile v21 元数据 +
UnityPy 写入 typetree 对象 + `BundleFile.save("none")` 打包），内容覆盖：

- `Texture2D`×5：`BG_Selftest`(32×18)、`popup_selftest`、`UI_Selftest`、`Mystery_Texture`(兜底)、
  Spine 图集页；
- `AudioClip`×3：`Theme_Selftest`、`SE_Selftest`、GUID 语音（经同一 bundle 的 `.resS` 资源流）；
- `TextAsset`×3：`character_table`(JSON 表)、`spine_selftest.skel/.atlas`。

然后按 Addressables 缓存布局（`<cache>/<outer>/<content>/__data`）放两个 bundle，走完整提取流程并断言：
catalog 存在、PNG 合法且尺寸正确、WAV/OGG magic、Spine 三件套归位、表 JSON、语音 GUID、
`native_characters` 推导、manifest、幂等重跑、zip 输入、`--zip` 输出、单 bundle 输入、
损坏 bundle 明确报错。**当前 32 项断言全过**。UnityPy 不可用时 `--selftest` 打印 SKIP 并
返回 0（降级），提取命令则退出码 2 并给出 pip 安装命令。

### 4.4 `--inspect`

打印每个 bundle 的对象类型计数 + 前 12 个资产名，用于真机资源包排错（不导出任何文件）。

## 5. 已知限制（不要假装没有）

1. **Spine 动画**：只把 `.skel/.atlas/图集 png` 原样导出；不解析骨骼、不渲染、不转 3.8→4.2。
   官方立绘的 Spine 3.8~4.2 + AA 私有转换/扩展（halo、混合模式）可能丢失，Godot 侧需要
   匹配版本的 spine 运行时（DESIGN §9 列为非目标/后续可选项）。
2. **UI 特效 prefab**（`bgEffect` 对应的 `UI_FX_*.prefab`）：UnityPy 只能导出贴图/材质，
   层级/粒子/shader 参数不可移植 → 运行时用占位/近似效果（`meta.approximation=true` 思路）。
3. **FlatData 表未解密**：官方角色/BGM/BG/音效表是 `TextAsset` 里的 FlatBuffers 二进制 +
   base64+循环 XOR(key `26 8b d5 0b 5c ce 86 33`)+UTF-16LE 字符串编码，vtable 布局见
   `docs/spec/resources.md` C.4。当前版本把原始字节导出到 `tables/*.bin` 并 warning；
   解密器是后续 TODO（拿到真包后实现，字段名做容错）。
4. **MonoBehaviour typetree 可能被剥离**（release 构建常见）：`read_typetree()` 失败时
   只导出原始字节，Spine 的 `SkeletonDataAsset`/UI prefab 数据可能拿不到。
5. **音频压缩**：Vorbis/FSB 依赖 UnityPy 解码；解不出时 warning 跳过（可外部 vgmstream 兜底）。
6. **图片有损**：DXT/ETC 解码有画质损失（社区高清 mod 就是重导贴图）；循环点/音量归一化未处理。
7. **版本强绑定**：资源包必须与 AA 版本匹配；bundle 名/hash 随版本变化，工具每次扫描输入，
   不缓存硬编码路径；bundle 加密/自定义压缩不支持（warning 跳过并报告数量）。
8. **体量**：官方包约 4GB，建议按章节/角色增量提取；本工具不下载任何资源包。
9. **`BgEffectOverrides`/`BgSpineOverrides` 官方格式未知**（研究文档 `[推]`），只做
   路径/JSON 描述级容错，不猜二进制结构。

## 6. 合规声明

- AA 官方资源包素材版权属 Blue Archive / Nexon / AzureArchive 作者；本工具**只做本机转换**，
  产出的 aa_pack（`source:"official"`、`license:"local-extraction-only"`）**不得二次分发/发布**。
- 工具只读用户已安装的 AA 目录/资源包，不修改、不联网下载、不嵌入任何官方素材。
- 提交到仓库的 `fixtures/pack/synth_pack/` 全部由 `aa_pack_build.py` 程序化生成（纯色/渐变/
  正弦波/占位剪影），不含任何官方素材。

## 7. 与 Godot 侧集成

```bash
# 生成/转换后，用目录界面「资源包管理 → 导入资源包」安装，或：
#   AAResources.install_pack("res://fixtures/pack/synth_pack")   # 目录
#   AAResources.install_pack("res://fixtures/pack/synth_pack.zip")  # zip
# 安装到 <data_root>/packs/<id>/，随后 AAResources.make_context() 即可解析。
```
