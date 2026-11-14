# 构建说明（Windows / Android）

> 本机是 Android proot aarch64 环境，**Godot 自带的导出器跑不起来**：
> `--import` / `--editor` / `--export` 在初始化时都会 `double free or corruption` 崩溃（glibc，非项目问题）。
> 因此本仓库的构建走"**引擎内置 PCKPacker + 官方模板手工装配**"的路线，全部可复现：

```
python3 scripts/gen_class_cache.py        # 1. 生成 class_name 全局缓存（必须）
scripts/godot.sh --headless --path . --script scripts/pack_project.gd -- --out=build/game.pck
python3 scripts/build_windows.py          # 2. Windows：模板 exe + PCK 页脚 → 单文件 exe
python3 scripts/build_android.py          # 3. Android：模板 APK + 品牌补丁 + PCK + 自签
bash scripts/build_all.sh                 # 一键全部 + 拷贝到 /sdcard/Download/DSH-Go/AA-Godot-builds/
```

## Windows

- 模板：`~/.local/share/godot/export_templates/4.7.2.stable/windows_release_x86_64.exe`
- PCK：`build/game.pck`（`scripts/pack_project.gd` 用引擎 `PCKPacker` 生成，内容为 project.godot +
  `.godot/global_script_class_cache.cfg` + addons/scenes/assets/fixtures/aap）
- 装配：exe + pck + `[u64 pck_size][u32 "GDPC"]` 页脚（Godot 自包含 PCK 格式，
  见 `core/io/file_access_pack.cpp`），得到单文件 `AzureArchiveGodot.exe`。
- 产物：`build/windows/AzureArchiveGodot.exe`（约 118MB）

## Android

- 模板：`android_release.apk`（Godot 4.7.2 官方 release 模板，arm64-v8a lib 71MB）
- 品牌补丁（纯二进制原地改，不重编译资源）：
  - 重建 `AndroidManifest.xml` 的字符串池：`package=com.godot.game` → **`com.nextarchive.alll`**
    （activity class 名保持不变，dex 不需要动）；
  - 重建 `resources.arsc` 全局字符串池：`godot-project-name*` → `AzureArchive Godot`（全部语言）；
  - 替换 mipmap/drawable 图标为脚本生成的品牌 webp（Pillow 无损 webp）。
- 游戏数据：`build/game.pck` 以 **STORED（不压缩）** 写入 `assets/assets.sparsepck`——
  Android 端引擎的固定查找路径（`core/config/project_settings.cpp`：
  `_load_resource_pack("res://assets.sparsepck")`）。
- **对齐 ZIP**：Android 11+ 对 `targetSdk>=30` 的 APK 强制要求 `resources.arsc` 以 STORED 存放
  且数据偏移 4 字节对齐，否则安装报
  `-124: Failed parse during installPackageLI: Targeting R+ ... requires the resources.arsc ... stored uncompressed and aligned on a 4-byte boundary`。
  Python `zipfile` 不会对齐，`zipalign` 又不可用，所以脚本里自写了对齐 ZIP 写入器
  （往 local header 的 extra field 塞填充，校验 `data_off % 4 == 0`）。
- **对齐 ZIP**：Android 11+ 对 `targetSdk>=30` 的 APK 强制要求 `resources.arsc` 以 STORED 存放
  且数据偏移 4 字节对齐，否则安装报
  `-124: Failed parse during installPackageLI: Targeting R+ (version 30 and above) requires the resources.arsc of installed APKs to be stored uncompressed and aligned on a 4-byte boundary`。
  Python `zipfile` 不会对齐，`zipalign` 又不可用，所以脚本里自写了对齐 ZIP 写入器
  （local header 的 extra field 填充，断言 `data_off % 4 == 0`）。
- 只保留 `arm64-v8a`（省 ~75MB）；签名：`apksigner` v1+v2（自签 keystore 自动生成于
  `build/android/aa-release.keystore`，口令 `azurearchive`，仅测试/自用）。
- 产物：`build/android/AzureArchive-Godot.apk`（约 46MB）

## 已验证

- Linux arm64 验证版（同一份 PCK + linux 模板）实际渲染跑通（Xvfb 截图见
  `docs/screenshots/05-exported-linux.png`），证明 PCK 打包/加载链路正确；
- APK：`aapt dump badging` 校验包名 **`com.nextarchive.alll`**、应用名
  `AzureArchive Godot`、minSdk 24 / targetSdk 36；`apksigner verify` v2/v3 通过；
  `resources.arsc` 数据偏移 4 字节对齐校验通过；
- **真机（Redmi Note 9 Pro / HyperOS）实测**：APK 安装成功 → 启动进入目录界面 →
  「载入内置示例工程」从 PCK 解出 3 个示例工程 → 播放「示例-Ending」进入播放器
  （背景 / 角色 Kei / 台词 / 气泡 / 菜单均正常渲染）。截图：`docs/screenshots/06-android.png`。
- Windows exe 页脚回读校验通过（PE 模板 104MB + PCK 14MB）。

## 安装 / 运行

- Windows：双击 `AzureArchiveGodot.exe` 即可（单文件自包含，会把数据写
  `%APPDATA%\Godot\app_userdata\AzureArchive Godot\aa_data`）。
- Android：安装 `AzureArchive-Godot.apk`（需允许未知来源），首次启动数据目录为
  应用私有目录；在「数据目录设置」里可改到 AA 的 data 目录（需要存储权限/文件选择器）。
- Linux（验证用）：`AzureArchiveGodot-linux-arm64` + 同目录 `.pck` 一起运行。
