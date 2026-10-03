# 构建发布文件

使用 Godot **4.7.2** 和对应的导出模板。两个预设已保存在 `export_presets.cfg`：Windows x64 单文件 EXE（内嵌 PCK）与正式签名的 Android APK。

## 工具配置

1. 在 Godot 的「编辑器 → 管理导出模板」安装 4.7.2 模板。
2. 按 [Godot 官方 Android 导出指南](https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_android.html) 安装 JDK、Android SDK Command-line Tools、Platform Tools、Build Tools 35.0.1 与 Android 平台工具，并接受 SDK 许可。本项目使用预编译 APK 模板，不使用 Gradle / NDK / CMake。
3. 在「编辑器设置 → 导出 → Android」设置 `Java SDK Path` 为 JDK 根目录（包含 `bin/java.exe`），设置 `Android SDK Path` 为 SDK 根目录。
4. `project.godot` 的版本号、Android 预设的 `version/name` / `version/code` 和 Windows 文件版本必须同步更新。

此 APK 模板的最低 API 为 24（Android 7.0）、目标 API 为 36。ARM64、ARMv7、x86_64 均包含在 APK 中。应用只请求联网和网络状态权限，供 ENet 局域网房间使用。

## 首次生成私有发布密钥

在项目根目录运行（替换本机 JDK 路径）：

```powershell
./tools/Build-Release.ps1 -JavaHome 'C:/Program Files/Java/jdk-25.0.2' -CreateAndroidKey
```

默认输出在 `build/`。可用 `-OutputDirectory` 指定输出目录，`-GodotExecutable` 指定 Godot 控制台程序。

仅首次构建时，`-CreateAndroidKey` 创建 RSA 3072 位发布密钥与随机密码，保存到被 Git 和 Godot 忽略的 `.private/`。**私下备份这个目录**，以便后续版本使用同一签名覆盖安装。不要提交、上传或放进 Release。已有密钥不会被替换。

之后不加 `-CreateAndroidKey` 即可重新构建。也可以通过以下环境变量提供外部密钥（脚本执行完会恢复原有环境）：

- `GODOT_ANDROID_KEYSTORE_RELEASE_PATH`
- `GODOT_ANDROID_KEYSTORE_RELEASE_USER`
- `GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD`

`export_presets.cfg` 不保存密码；测试、文档、工具和私有密钥不会打入游戏。

## 文件验证与发布

输出包括 EXE、APK、`SHA256SUMS.txt` 和构建日志。APK 的 `.idsig` 附加文件无需单独下载。使用 Android SDK 的 `apksigner verify --verbose` 检查正式签名，`aapt dump badging` 检查包名、版本、架构和权限。Windows EXE 需单独启动验证。

按照 README 运行规则、界面与真实 ENet 房间测试。发布时将代码提交并推送，再用 GitHub CLI 建立版本 Release，上传 EXE、APK 和校验文件。使用 `--notes-file` 提供版本说明。
