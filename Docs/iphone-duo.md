# iPhone Duo 适配调研

> 本文记录对本项目在 Apple 折叠屏 iPhone（iPhone Duo）上的适配调研与结论。
> 官方依据：Apple Developer Documentation《Preparing your app for iPhone Duo》与同名 Tech Talk。

## 一、设备形态（官方描述）

- iPhone Duo 是折叠设备，包含**较小的外屏**与**较大的内屏**，两面都有前置摄像头（内屏摄像头不用时隐藏）。
- 设备可**展开 / 闭合 / 半折叠 / 旋转**，内容需要在屏幕间迁移并随姿态调整；半折叠时视图要避开折痕区域。
- 部分姿态下，系统会把**导航栏、工具栏、标签栏竖排显示在屏幕侧边**。
- 必须用**最新 Xcode** 构建才能完整使用屏幕空间（Xcode 26 及更早构建的 App 不会延伸到状态栏与摄像头下方）。

## 二、Apple 给出的适配要点（浓缩）

1. **可缩放（resizing）是核心能力**：布局要按容器尺寸自适应，不能写死 iPhone 尺寸。
2. 优先使用系统容器：split view、tab bar、arrangement view、navigation stack —— 它们会自动处理外屏/内屏、折痕与摄像头遮挡。
3. 用 **size class 与 scene geometry** 做适配；用自动 trait 追踪监听尺寸变化。
4. **不要**用 `UIScreen.main.bounds` 之类做布局判断。
5. 检查导航栏/工具栏/标签栏是否被系统竖排显示；若没有，说明没有使用系统栏容器（自绘 bar 不会获得该行为）。
6. SwiftUI 侧：把 toolbar 项挂到 `NavigationStack` / `.toolbar`；sheet 可用 `presentationAdaptation` 之类控制竖排栏行为。
7. 测试要求：在模拟器或真机的**每种姿态**下检查（闭合/展开/半折叠/各方向旋转），逐页检查 view、sheet、popover，找出落在折痕上的控件。

## 三、本项目现状评估

| 要求 | 现状 | 结论 |
|---|---|---|
| 可缩放布局 | 首页用 `AdaptiveLayout.workspaceUsesColumns`（宽度≥900 且高度≥500 分栏）；对话页用 `readableContentWidth` 限宽居中 | 基本具备，但只在极端宽度验证过 |
| 方向支持 | 原本**锁定竖屏** | ❌ 已改为支持竖屏 + 左右横屏 |
| 设备族 | `TARGETED_DEVICE_FAMILY = 1`（仅 iPhone） | Duo 属 iPhone 族，无需改回 iPad |
| 基于容器的尺寸计算 | 布局使用 `GeometryReader` 的容器尺寸，未使用 `UIScreen.main` | ✅ 符合要求 |
| 系统导航栏/工具栏 | 多为自绘 header（为了终端风格视觉） | ⚠️ 竖排栏行为不会自动生效，可接受（自绘栏随布局自适应） |
| 折痕区域避让 | 未做 | ⚠️ 待真机验证；当前内容居中限宽，折痕落在留白区时问题不大 |
| 外屏紧凑布局 | 未验证 | ⚠️ 外屏宽度接近普通 iPhone，理论可直接运行 |

## 四、本次改动

1. `Info.plist` 解除竖屏锁定：`UISupportedInterfaceOrientations` 增加 `LandscapeLeft` / `LandscapeRight`。
2. 复用既有自适应能力：宽屏（内屏展开/横屏）下首页自动转为分栏；对话保持限宽居中。
3. 本轮未引入 `UIArrangementViewController`（iOS 27 新 API，用于折痕分栏）——先跑通可缩放，再评估是否需要。

## 五、模拟器实测记录（Xcode 27.1 / iOS 27.1 模拟器）

在本机创建 iPhone Duo 模拟器并实际运行本项目，得到以下观察：

- **可以正常运行**：App 启动、渲染、审批/输入区布局均正常，未崩溃。
- 模拟器默认处于**半折叠姿态**：截图中可用显示区在左，右侧是被折走的区域，系统在那里**竖排显示时间与状态图标**——这正是苹果文档描述的
  "部分姿态下导航栏/工具栏/标签栏竖排显示"的同一套机制。
- 需要注意的是：**项目仍以 iPhone 设备族构建**（`TARGETED_DEVICE_FAMILY = 1`）。做过对照实验，改成 `"1,2"`（iPad 族）后再跑，
  渲染结果完全相同，说明当前显示范围取决于"姿态"，而不是设备族声明。
- **工具限制**：`simctl` 没有旋转/fold 命令，姿态切换必须在 DeviceHub 界面里点；
  且模拟器闲置后屏幕会熄灭，截图会得到全黑图，需要先重新 boot 或唤起 DeviceHub 才能截到内容。

## 六、后续待办（需要在真机或 DeviceHub 交互验证）

- [ ] 内屏展开态、半折叠态下逐页检查（尤其是输入框、侧边栏、Canvas 右滑页是否落在折痕上）
- [ ] 外屏闭合态可用性（搜索、新建会话、扫码配对流程）
- [ ] 旋转过程中的布局过渡是否抖动
- [ ] 评估 `UIArrangementViewController`：若半折叠时希望"上/下分区"呈现（如上半对话、下半输入），它是官方推荐路径
- [ ] 若系统竖排工具栏普及，可把部分自绘 header 迁到 `NavigationStack.toolbar`

## 七、验证方法

```bash
# 本机已有 iPhone Duo 模拟器类型
xcrun simctl list devicetypes | grep -i duo
# 创建并启动
xcrun simctl create "iPhone Duo" com.apple.CoreSimulator.SimDeviceType.iPhone-Duo com.apple.CoreSimulator.SimRuntime.iOS-27-1
xcrun simctl boot <UDID> && open -a DeviceHub
```

> 注：`simctl` 没有旋转/fold 命令，姿态切换要在 DeviceHub 界面里操作，因此半折叠等姿态只能人工验证。
