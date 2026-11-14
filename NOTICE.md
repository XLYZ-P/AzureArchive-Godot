# NOTICE · 第三方内容与声明

本项目是**非官方粉丝技术复刻**（AzureArchive · Godot 版），与 Foxxlight（狐光体）、
Yostar、Nexon、Nexon Games 无任何关联。

## 第三方内容

| 内容 | 来源 | 用途/说明 |
|---|---|---|
| `fixtures/aap/*.aap` 等真实工程样本 | GitHub 仓库 `systemannounce/BA_AAedit`（公开） | 仅用于格式兼容性测试；版权归原作者，见 `fixtures/aap/SOURCES.md` |
| `research/aa-docs/*.md` | AzureArchive 官方文档站 <https://aadoc.foxxlight.top/> 的文字整理 | 格式研究参考，非分发目标 |
| `research/halocue/*` | GitHub 仓库 `Suciko/HaloCue`（MIT License） | 逆向格式结论参考 |
| `assets/fonts/wqy-zenhei-extracted.ttf` | 文泉驿正黑（WenQuanYi Zen Hei，GPL v2 + 字体嵌入例外） | 内置中文字体，可自行替换 |
| 脚本 `#额外指令`/内联标记等行为 | AzureArchive 官方文档 | 为兼容性而实现，非官方素材 |

## 未包含

- 不包含《蔚蓝档案》任何官方图片、音频、Spine 骨骼或字体素材；
- 不包含 AzureArchive 本体或其资源包；
- 官方资源包需用户在自己的机器上用 `tools/extract_aa_pack.py` 本地转换，
  转换产物仅供个人使用，请勿再分发。

## 代码许可

本项目代码（`addons/`、`scenes/`、`tools/`、`scripts/`、`tests/`）由项目作者原创，
供学习与二次创作使用。引用的第三方内容按各自的许可/条款处理。
