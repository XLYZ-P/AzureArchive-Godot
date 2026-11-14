# 使用说明（AzureArchive · Godot 复刻）

本文面向**使用者**：从打开软件到播放/编辑 AA 剧情、导入资源与常见问题。
开发/架构请看 [DESIGN.md](DESIGN.md)，格式规范看 [spec/](spec/)。

---

## 1. 启动与数据目录

用 Godot 4.7 打开 `project.godot` 并按 F5；导出后的可执行文件直接双击运行。

首次启动会自动创建数据目录（**默认** `user://aa_data`，即 Godot 的 `app_userdata/AzureArchive Godot/aa_data`）：

```
aa_data/
├── projects/     # 剧情工程 .aap（每个工程可带同名自定义资源文件夹）
├── saves/        # 剧情存档 .aas（可带同名文件夹；本复刻暂不解析 .aas，见 §6）
├── overrides/    # 全局自定义资源（对所有工程生效）
├── assets/       # AA 官方资源（本复刻用 packs/ 替代）
├── packs/        # 已安装的 aa_pack（由 AA 官方资源包转换而来）
└── settings/
```

**最省事的方式**：在「数据目录设置」里把数据目录指向 AA 的真实数据目录，直接复用你已有的工程与自定义资源：

| 平台 | AA 数据目录 |
|---|---|
| Windows | `C:\Users\<用户名>\AppData\LocalLow\foxxlight\AzureArchive\data` |
| Android | `/storage/emulated/0/Android/data/com.foxxlight.AzureArchive/files/data` |
| iOS | 文件 App 内 `AzureArchive/data` |

> AA 0.8.8 以后可以在 AA 内改存储路径；如果你改过，真实位置在 `settings/user_settings.json` 的 `workspacePath` 里。

## 2. 目录界面（主界面）

- **工程列表 / 存档列表**：两个标签页；工程若文件名形如 `分类-名称`，会显示 `[分类] 名称`。
- **双击工程** = 播放；选中后也可以点右侧按钮。
- 右侧按钮：
  - **播放选中工程**：进入剧情播放器
  - **编辑选中工程**：进入节点编辑器
  - **新建工程**：生成一个合法 `.aap`（入口节点 + 一个脚本节点），可直接编辑
  - **导入 .aap/.aas 文件**：从任意位置复制进数据目录
  - **载入内置示例工程**：把自带真实样本（`fixtures/aap/`）复制到 `projects/`，没有自己的工程时先体验
  - **资源包管理**：安装/查看 aa_pack
  - **数据目录设置**：见 §1
  - **操作说明**：键位速查

## 3. 播放器

| 操作 | 按键 / 鼠标 |
|---|---|
| 推进对话 | 鼠标左键 / 空格 / 回车 |
| 选择选项 | 点击 或 数字键 `1`–`9` |
| AUTO 自动播放 | `A`（再按关闭） |
| 历史记录 / 回看 | `H` |
| 快进 | 按住 `Ctrl` |
| 显示调试信息（行号/guid） | `F8` |
| 退出播放 | `Esc` 或右上角「退出」 |

支持（从 `.aap` 直接解释运行，无需先编译 `.aas`）：
- 背景切换与过渡（Fade / Fade White / Crossfade 等，按 AA 的 transition 表；不支持的特殊过渡退化为淡入淡出）
- BGM / 音效 / 语音（`999` = 静音；语音按 `voice` GUID 找 `<本地文件夹>/voices/<guid>.ogg`）
- 5 个立绘位 + 无立绘说话位：表情、走位、进出场、高亮/变暗、气泡、动作、形状效果（sig/black/closeup）
- 对话框打字机、姓名+昵称、`[size]` `[颜色]` `[ruby]` 内联标记
- 选择节点（含重复连线）、出口 Ending / 未完待续 / 下回预告场景衔接
- 额外指令：`#wait` `#bgshake` `#fx` `#zmc` `#st/#stm/#clearST` `#hidemenu/#showmenu` `#N;m/hide/al/ar/a/dl/dr/d/fx/em` 等
- 缺资源时使用程序化占位素材，不会崩溃。

> 说明：本复刻直接解释 `.aap`，因此 AA 在编译期生成的行为（角色走位 `#N;mK`、隐藏 `#N;hide`、进出场动画、自动等待、`#nextepisode`）由播放器自行推导，效果与 AA 一致。

## 4. 编辑器

三栏布局：**左：节点工厂 / 中：节点图 GraphEdit / 右：检查器**。

| 操作 | 方法 |
|---|---|
| 创建节点 | 从左侧节点工厂拖到画布（或单击在视野中心创建） |
| 移动节点 | 左键拖动节点 |
| 连线 | 右键拖动节点（上半=入端、下半=出端）；选择节点每个选项一支出端口 |
| 断开连线 | 右键拖空白划线剪断 / 直接点连线上的断开 |
| 删除节点 | 选中后 `Delete` 或拖到垃圾桶（入口和带连线节点不可删） |
| 编辑属性 | 双击节点 或 单击后看右侧检查器 |
| 平移 / 缩放 | 左键拖空白 / 滚轮 |
| 新建/打开/保存/另存 | `Ctrl+N` / `Ctrl+O` / `Ctrl+S` / 工具栏「另存为」 |
| 撤销 / 重做 | `Ctrl+Z` / `Ctrl+Y` |
| 编译并预览 | `F5`（使用当前编辑内容实时播放） |
| 自动保存 | 工具栏开关（60 秒，默认关） |

检查器覆盖：
- **脚本节点**：脚本列表增删/排序/复制；台词、额外指令、6 个栏位的角色/表情/位置/进出场/动作/气泡/形状/高亮/发言/走位终点；环境（背景、背景效果、过渡、BGM、弹出图、音效、语音、地点名）。
- **选择节点**：选项文字（数量 = 出边数；支持重复连线到同一目标）。
- **出口节点**：Ending / 未完待续 / 下回预告（NeHeader/NeTitle/结局文字）。
- **入口节点 / 工程属性**：标题、序号、封面背景、统计与工程校验。

保存的 `.aap` 保持 AA 的 `$type`、字段顺序与 16 槽选项/6 槽角色结构，**可被真正的 AA 打开**；`.aap` 本身是 UTF-8 无 BOM 的紧凑 JSON。

## 5. 资源：自定义资源与 aa_pack

### 5.1 直接用 AA 的自定义资源（推荐，零转换）

AA 的两种自定义资源目录本复刻原生支持：

- 全局：`<数据目录>/overrides/`（对所有工程生效）
- 本地：`<数据目录>/projects/<工程名>/` 或 `<数据目录>/saves/<存档名>/`（只对同名工程生效）

结构同 AA：`manifest.json` + `bgs/`（背景 png）+ `sounds/`（ogg/mp3/wav）+ `popups/` + `voices/<guid>.ogg` + `characters/<Identifier>/`（Spine 或 PNG 立绘）。字段规范见 [spec/resources.md](spec/resources.md)。
优先级：**aa_pack < overrides（全局） < 本地文件夹**。

### 5.2 安装 AA 官方资源包（aa_pack）

AA 官方资源包是 Unity Addressables 包（`WIN_xxx.zip` / `AND_xxx.zip`）。本复刻用 Python 工具把它转换成开放的 `aa_pack`：

```bash
# 依赖：pip install unitypy（国内可用清华镜像）
python3 tools/extract_aa_pack.py --input AA资源包.zip --output my_pack --zip
# 产物 my_pack.zip / my_pack/ 即为 aa_pack
```

然后在「资源包管理 → 导入资源包」选择 `my_pack.zip`（或文件夹）。

> 合规：转换必须在你自己的机器上进行，转换产物仅供个人使用，不得再分发；官方素材版权归原作者。

### 5.3 没有官方资源包也能用

- 剧情逻辑、背景颜色/占位、立绘占位、BGM/音效缺失时静音，播放器都能正常演出；
- 自定义背景/立绘/语音只要放进 overrides 或工程本地文件夹即可真实显示。

## 6. 与 AA 的兼容性 / 已知限制

| 项 | 说明 |
|---|---|
| `.aap` 读取/写回 | ✅ 完整（含未知字段保留、字段顺序、null、float32 坐标、16 槽选项） |
| `.aas` 读取 | ❌ AA 的编译产物是 FlatBuffers 二进制、无公开 schema；请直接播放 `.aap`（本复刻不需要编译） |
| 自定义资源 manifest | ✅ 角色别名/Spine 立绘/PNG 立绘/背景/音效/弹出图/语音/BGM |
| 官方资源包 | ⚠️ 需 `tools/extract_aa_pack.py` 转换；提取结果取决于资源包版本 |
| Spine 骨骼动画 | ⚠️ 静态帧/atlas 兜底 + PNG 立绘完整支持；骨骼动画接入点已预留（见 `docs/spec/resources.md`） |
| bgEffect 粒子/特殊过渡 | ⚠️ 颜色滤镜类做近似，UI_FX prefab 类不复刻 |
| AUTO 选项（AA 1.0 新字段） | ⚠️ 未纳入规格（未知字段原样保留） |
| 联网下载资源包/账号 | ❌ 不实现（AA 官方在线服务已停止） |

## 7. 常见问题

- **打开工程一片黑/没有背景**：没有安装资源包或自定义背景；播放器会用占位背景，属于正常。
- **角色没有立绘**：没有对应角色资源；会显示占位剪影 + 名字。装 aa_pack 或自定义立绘后正常。
- **BGM 不响**：先确认数据目录下资源存在；`bgmId=999` 在 AA 里就是静音。
- **保存后 AA 打不开？** 请用「另存为」保存到数据目录内；确认没有用文本编辑器改坏 JSON。
- **headless/CI 跑不起来**：本机不能跑 `godot --import`；先 `python3 scripts/gen_class_cache.py`，用 `scripts/godot.sh` / `scripts/test.sh`。
