# Mydsh — 自用 iOS 客户端（基于 Whaleness / dsh-mobile）

本仓库是 [Clarklevis1995/dsh-mobile](https://github.com/Clarklevis1995/dsh-mobile) 的本地定制分支，
用于把 DeepSeek Harness 的移动端接到自己的 iPhone 上。品牌落地为 **Mydsh**。

- Bundle ID：`com.jiachenglou.dshmobile`
- 签名团队：`239B5T5LP3`（Apple Development，自动签名）
- 设备：iPhone 15 Pro Max（iOS 27.0.1）
- 网关插件：[dsh-plugin-mobile-gateway](https://github.com/Clarklevis1995/dsh-plugin-mobile-gateway) ≥ 0.10.3

## 本分支相对上游的改动

### 1. 品牌

| 项 | 文件 |
|---|---|
| 显示名 / Bundle 名 → `Mydsh` | `DeepSeekHarnessMobile/Resources/Info.plist`、`InfoPlist.xcstrings` |
| App 图标（深海渐变 + M 标 + 青色光标） | `Assets.xcassets/AppIcon.appiconset/AppIcon-{light,dark}.png` |
| 启动页（深海底色 + M 标） | `Resources/LaunchScreen.storyboard`、`Assets.xcassets/MydshLaunchMark.imageset` |
| 首页品牌头图改为 `Mydsh` 文本 | `Components/Glass.swift`（`HarnessMark`） |
| 文案 Whaleness → Mydsh | `Localizable.xcstrings`、`RootView.swift`、`AppStore.swift`、`WorkspaceView.swift`、`AgentLiveActivityWidget.swift` |

图标源文件在 `../lab/assets/icons/`（生成脚本 `final.py`）。

### 2. 修复：iOS 27 / Xcode 27 打开会话必崩

**现象**：在 iOS 27 设备上打开任意会话，App 立即 `EXC_BAD_ACCESS / SIGSEGV`
（`KERN_PROTECTION_FAILURE at <stack guard>`），崩溃日志顶部是
`swift::SubstGenericParametersFromMetadata::getMetadata` /
`swift::_checkGenericRequirements` / `checkInvertibleRequirements` 的递归。

**根因**：`ConversationView` 的输入区（composer）编译后是一个极深的嵌套泛型类型
（符号名可见 3000+ 字符的 `some View` 类型，约 40 层泛型嵌套）。
Swift 6.4（Xcode 27）生成的类型元数据在 iOS 27 运行时上做
`__swift_instantiateConcreteTypeFromMangledNameV2` 时，`checkInvertibleRequirements`
逐层解析泛型要求并递归，最终耗尽栈保护页。
Xcode 26 / Swift 6.3 编译同样源码不会崩溃，属于编译器/运行时回归。

**修复**（`DeepSeekHarnessMobile/Views/ConversationView.swift`）：

1. 输入区底部按钮行拆为独立子视图（`composerPhotoButton`、`composerContextButton`、
   `composerActionButton`），并在 `composerButtonsRow` 中用 `AnyView(...)` 装箱，
   使父类型退化为 `HStack<TupleView<(AnyView, AnyView, Spacer, AnyView, ...)>>`。
2. 模型选择不再用 `Menu`（`Menu` + `Section` + 嵌套 `ForEach` 会进一步加深类型），
   改为 `Button` + `.sheet`，选择器独立为 `ModelPickerSheet`。

> 注意：`ENABLE_DEBUG_DYLIB` 与此崩溃无关（已实测：开/关都能正常打开会话），
> 不需要为此改构建设置。

### 3. 已知限制（来自网关，不是 App 缺陷）

- 对话里的文件卡片 / 正文文件链接只能预览**会话工作目录内**的文件；
  指向 `cwd` 之外的路径会返回 `file-not-allowed: path must stay inside the
  session working directory`。这是 `dsh-plugin-mobile-gateway` 的安全边界。
- 签名证书有效期：免费个人团队 7 天、付费开发账号 1 年；到期需重新构建安装。

验证方式：用 `dshmobile://session?gateway=<gatewayLocalID>&id=<sessionId>` 深链直接打开会话，
抓 `systemCrashLogs` 确认无新增 `.ips`。本机 `lab/gateway/verify.mjs` 可验证网关侧协议。

## 构建

前置：

```bash
export JAVA_HOME="$HOME/Library/Java/JavaVirtualMachines/jdk-21.jdk/Contents/Home"
export ANDROID_HOME="$HOME/Library/Android/sdk"   # KMP 的 android target 配置期需要
```

`config/Local.xcconfig`（本地、gitignore）提供签名变量：

```
LOCAL_BUNDLE_IDENTIFIER = com.jiachenglou.dshmobile
LOCAL_DEVELOPMENT_TEAM = 239B5T5LP3
```

真机 Debug 构建：

```bash
xcodebuild -project DeepSeekHarnessMobile.xcodeproj \
  -scheme DeepSeekHarnessMobile -configuration Debug \
  -destination 'platform=iOS,id=00008130-000C6D0A3083401C' \
  -allowProvisioningUpdates build
```

安装与启动：

```bash
APP=~/Library/Developer/Xcode/DerivedData/DeepSeekHarnessMobile-*/Build/Products/Debug-iphoneos/DshMobile.app
xcrun devicectl device install app --device 00008130-000C6D0A3083401C "$APP"
xcrun devicectl device process launch --device 00008130-000C6D0A3083401C com.jiachenglou.dshmobile
```

运行时依赖（首次构建自动处理）：Gradle 9.1.0、Kotlin/Native 2.3.20 工具链、
Android SDK Platform 36、Metal Toolchain（`xcodebuild -downloadComponent MetalToolchain`）。
Xcode 若升级大版本，Metal Toolchain 需要重新下载。

## 连接 DSH

1. 在运行 DSH 的机器上安装并启用 `dsh-plugin-mobile-gateway@0.10.3+`。
2. WebUI「移动设备」→ 运行模式「常驻开启」→ 生成配对二维码。
3. App 首页右上角人形图标 → 扫码完成配对。

局域网直连地址形如 `ws://<电脑局域网 IP>:3081/ws/mobile`（3080 仅监听回环，真机不可用）。