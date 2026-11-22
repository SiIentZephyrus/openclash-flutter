# OpenClash Mobile

一个基于 Flutter 的 OpenClash / Mihomo 安卓远程控制客户端。借鉴 [MetaCubeXD](https://github.com/MetaCubeX/metacubexd) 的卡片、策略组和延迟标识，使用适合手机操作的底部导航。

## 功能

- 概览：实时上传/下载速率、流量曲线、累计流量、连接数、内存和当前代理。
- 代理：按配置顺序显示策略组和节点延迟、可折叠策略组、节点选择、固定顶部的全部/策略组/节点分范围搜索、延迟/名称排序、规则/全局/直连模式。支持卡片、列表、紧凑三种布局并保存布局偏好。固定工具栏和悬浮菜单支持全部收起、全部展开、返回顶部和刷新。
- 测速：节点按钮只测试本节点，不切换节点；策略组按钮测试该组及其成员；悬浮菜单支持测试所有节点或所有策略组当前路线。批量请求去重，最多 6 个并发，显示进度、超时与失败。策略组未单独测速时沿当前选中路线读取节点延迟，不把未测速当成 0 ms。
- 订阅节点：合并 `/proxies` 与 `/providers/proxies` 数据，显示订阅节点的真实协议类型和延迟，按所属集合进行测速。旧内核缺少集合内单节点测速接口时，批量测速会按集合执行一次健康检查，再读取结果；单节点按钮会明确提示内核限制，不偷偷测试整个集合。
- 连接：搜索活跃连接、查看来源与代理链、关闭单条连接，以及搜索路由规则。
- 日志：WebSocket 实时推送、级别筛选、文本搜索、暂停显示、跟随最新、复制和清空。最多保留 1,500 条。
- 设置：首次启动必须配置控制器，连接验证并保存成功后进入。地址和 API Secret 加密保存在本机，后续启动自动读取并连接。设置页默认只读，只有点击「修改控制器」并重新保存才会更换配置。
- 操作提示：统一为带状态图标的顶部浮层卡片，测速结果分列成功、超时、失败统计；支持手动关闭、滑动收起和自动消失，新提示直接替换旧提示。表单错误和测速进度使用相同视觉风格。

这是远程控制面板，不在手机上运行代理内核，也不会创建 Android VPN。

## 安卓安装和连接

最新安装包从 [GitHub Releases](https://github.com/SiIentZephyrus/openclash-flutter/releases) 下载，本地构建输出到 `dist/`。按 CPU 架构分别提供 `OpenClash-1.0.5-arm64-v8a.apk`（64 位 ARM）、`OpenClash-1.0.5-armeabi-v7a.apk`（32 位 ARM）和 `OpenClash-1.0.5-x86_64.apk`（64 位 x86）。只需安装与设备匹配的一个 APK，无需同时安装。分包减少单个安装包中不需要的原生库。

无本地配置时只显示控制器配置页，不能进入面板；App 不包含演示数据。

1. 将 APK 传到安卓设备并安装，手机与路由器连接同一局域网。
2. 在 OpenClash 中确认外部控制器端口和 Secret，确保控制器允许局域网访问。
3. 首次启动时填写 `http://192.168.1.1:9090`（替换成实际地址和端口）及密钥，点击「保存并进入」。这里不是 LuCI 管理页面的地址。

地址和 Secret 作为一份配置保存在系统安全存储中（Android 使用加密存储），不会把密钥写入普通偏好设置。下次启动自动沿用配置；路由器暂时不可达时保留配置并自动重试。手动修改的地址或密钥验证失败、或保存失败时，仍保留原配置。旧版本只有地址没有密钥，因此升级后会预填旧地址，需要重新连接保存一次。

HTTP 和 WebSocket 访问基于 [Mihomo 官方 API](https://wiki.metacubex.one/api/)，实时通道断开后每 4 秒重连。HTTPS 控制器使用 WSS；不绕过证书验证。

Android 已配置 INTERNET 权限和明文网络访问，以支持局域网常见的 HTTP 控制器。

## 开发和打包

使用 Flutter 3.38.4 / Dart 3.10.3 验证，需要 Android SDK 和 JDK 17 或更高版本。

```sh
flutter pub get
flutter run
flutter analyze
flutter test
flutter build apk --release --split-per-abi
```

Windows 可直接运行打包脚本，默认按 CPU 架构分包，并将文件按版本重命名输出到 `dist/`，同时生成 SHA-256 校验文件：

```powershell
.\scripts\build-android.ps1
```

Flutter 原始分包输出位于 `build/app/outputs/flutter-apk/app-<ABI>-release.apk`。如确实需要包含所有架构的通用包，可运行 `flutter build apk --release`。

本地未配置签名时使用本机 Android debug 证书。可在 `android/key.properties` 配置 `storeFile`（绝对路径）、`storePassword`、`keyAlias`、`keyPassword`，release 构建会优先使用这份配置。签名文件和密钥均被 Git 忽略。默认包名为 `dev.silentz.openclash_client`；后续版本应沿用相同证书，才能覆盖安装并保留本地设置。

## GitHub Actions 构建与发布

[Android APK 工作流](https://github.com/SiIentZephyrus/openclash-flutter/actions/workflows/android.yml) 使用固定 Flutter 3.38.4 和 JDK 17，先运行静态分析及测试，再构建 ARM64、ARMv7、x86_64 三个 APK，附带 SHA-256 校验文件。

- 推送 `main` 或向 `main` 提交 PR：自动检查、构建，安装包在 Actions 的 Artifacts 中保存 14 天，不创建 Release。
- 手动发布：进入 Actions → Android APK → Run workflow，选择 `main`，保留 `publish=true`。需要预发布版本时勾选 `prerelease`。
- 标签发布：将 `pubspec.yaml` 更新为新的 `版本号+构建号` 后，推送对应的 `v版本号` 标签，例如 `version: 1.0.6+7` 对应 `v1.0.6`，自动构建并发布。

发布版本与文件名取自 `pubspec.yaml`，标签必须匹配。已发布的版本不会被覆盖；再次发布需递增版本号和构建号。发布先创建草稿，全部安装包上传成功后才对外显示；若上传中途失败留下草稿，删除失败草稿后重新运行。普通构建无需个人访问令牌，发布使用工作流自带的 `GITHUB_TOKEN` 和仅发布任务拥有的 `contents: write` 权限。

也可安装 [GitHub CLI](https://cli.github.com/) 并运行一次 `gh auth login`，之后用本地工具触发：

```powershell
.\scripts\ci.ps1                # 构建并发布当前版本
.\scripts\ci.ps1 -BuildOnly     # 只构建，不创建 Release
.\scripts\ci.ps1 -Prerelease    # 构建并标记为预发布
```

### CI 签名

在仓库 Settings → Secrets and variables → Actions 中配置以下四个 Repository secrets：

| Secret | 内容 |
| --- | --- |
| `ANDROID_KEYSTORE_BASE64` | 签名 keystore 文件的 Base64 字符串 |
| `ANDROID_KEYSTORE_PASSWORD` | keystore 密码 |
| `ANDROID_KEY_ALIAS` | 密钥别名 |
| `ANDROID_KEY_PASSWORD` | 密钥密码 |

例如在 PowerShell 中将现有签名文件编码并复制到剪贴板，粘贴到 Secret 值中：

```powershell
[Convert]::ToBase64String([IO.File]::ReadAllBytes('C:\path\to\release.jks')) | Set-Clipboard
```

也可使用 GitHub CLI 一次性配置（密码以隐藏输入询问；同名 Secrets 会更新）：

```powershell
.\scripts\configure-ci-signing.ps1 -KeystorePath 'C:\path\to\release.jks' -KeyAlias 'release'
# 若需沿用此前本机打包的预览版证书，保留覆盖安装能力：
.\scripts\configure-ci-signing.ps1 -UseCurrentDebugKey
```

请复用并备份同一份签名文件。CI 密钥仅在构建期间写入 runner 临时目录，任务结束后删除，不会上传到 Artifacts 或 Release。没有签名 Secrets 时，普通 CI 生成仅供测试的 debug 签名包；发布任务会明确报错，避免每次用不同证书发布而无法覆盖安装。来自 PR 的构建不读取签名 Secrets。

工程保留 Flutter 生成的 iOS、Windows、Web 平台目录，但此次交付目标是 Android。其他平台未做发布验证；Web 还受控制器 CORS 与浏览器混合内容限制。

## 验证与截图

42 项测试覆盖 URL 校验、Bearer 认证、中文/特殊字符编码、接口错误、HTTP/WebSocket 通信、订阅节点读取与测速、旧内核批量测速兼容、切换失败时保留原节点，以及首次配置、本地持久化、手机布局、搜索和日志操作。通知测试覆盖连续替换、自动消失、关闭、滑动收起，以及 320 宽屏幕放大字体后的排版。网络回归测试使用本地模拟控制器；另外已在 Android 模拟器上连接实际控制器，完成 104 个节点的批量测速流程验证。

可选截图工具（字体使用机器上的 CJK 字体文件）：

```sh
flutter test test/preview_capture.dart --dart-define=PREVIEW_FONT=C:/Windows/Fonts/msyh.ttc
```

截图输出到 `screenshots/`。`setup.png` 是首次配置界面；其他面板截图使用仅存在于 `test/support/` 的测试数据，测试数据不会打入 App。
