import SwiftUI
import UIKit

enum AppFontScale {
    static let key = "appearance.fontScale"
    static let followsSystemKey = "appearance.fontFollowsSystem"
    static func effective(_ value: Double, followsSystem: Bool) -> Double {
        followsSystem ? 1 : normalized(value)
    }
    static func normalized(_ value: Double) -> Double {
        value.isFinite ? min(1.5, max(0.8, value)) : 1
    }
    static var current: CGFloat {
        let value = UserDefaults.standard.object(forKey: key) as? Double ?? 1
        return CGFloat(effective(value, followsSystem: UserDefaults.standard.bool(forKey: followsSystemKey)))
    }
}

// 统一描述字体，避免固定字号、语义字体和独立 UIKit 宿主使用不同的缩放规则。
struct AppFont {
    private var style: UIFont.TextStyle = .body
    private var size: CGFloat?
    private var fontWeight: Font.Weight?
    private var design: Font.Design = .default
    private var usesMonospacedDigits = false

    static let largeTitle = system(.largeTitle)
    static let title = system(.title)
    static let title2 = system(.title2)
    static let title3 = system(.title3)
    static let headline = system(.headline)
    static let subheadline = system(.subheadline)
    static let body = system(.body)
    static let callout = system(.callout)
    static let footnote = system(.footnote)
    static let caption = system(.caption)
    static let caption2 = system(.caption2)

    static func system(size: CGFloat, weight: Font.Weight = .regular, design: Font.Design = .default) -> AppFont {
        AppFont(size: size, fontWeight: weight, design: design)
    }

    static func system(_ style: Font.TextStyle, design: Font.Design = .default) -> AppFont {
        let uiStyle: UIFont.TextStyle
        switch style {
        case .largeTitle: uiStyle = .largeTitle
        case .title: uiStyle = .title1
        case .title2: uiStyle = .title2
        case .title3: uiStyle = .title3
        case .headline: uiStyle = .headline
        case .subheadline: uiStyle = .subheadline
        case .callout: uiStyle = .callout
        case .footnote: uiStyle = .footnote
        case .caption: uiStyle = .caption1
        case .caption2: uiStyle = .caption2
        default: uiStyle = .body
        }
        return AppFont(style: uiStyle, design: design)
    }

    func weight(_ value: Font.Weight) -> AppFont {
        var copy = self; copy.fontWeight = value; return copy
    }
    func bold() -> AppFont { weight(.bold) }
    func monospaced() -> AppFont {
        var copy = self; copy.design = .monospaced; return copy
    }
    func monospacedDigit() -> AppFont {
        var copy = self; copy.usesMonospacedDigits = true; return copy
    }
    func resolved(scale: CGFloat) -> Font {
        let base = size.map { UIFontMetrics.default.scaledValue(for: $0) }
            ?? UIFont.preferredFont(forTextStyle: style).pointSize
        // Terminal theme: every text style renders monospaced.
        var font = Font.system(size: base * scale, weight: fontWeight ?? (style == .headline ? .semibold : .regular), design: .monospaced)
        if usesMonospacedDigits { font = font.monospacedDigit() }
        return font
    }
}

private struct AppFontModifier: ViewModifier {
    @AppStorage(AppFontScale.key) private var scale = 1.0
    @AppStorage(AppFontScale.followsSystemKey) private var followsSystem = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let value: AppFont
    func body(content: Content) -> some View {
        content.font(value.resolved(scale: CGFloat(AppFontScale.effective(scale, followsSystem: followsSystem))))
    }
}

struct AppFontScope: ViewModifier {
    @AppStorage(AppFontScale.key) private var scale = 1.0
    @AppStorage(AppFontScale.followsSystemKey) private var followsSystem = false
    @Environment(\.dynamicTypeSize) private var systemSize

    func body(content: Content) -> some View {
        // 系统控件也需要显式更新 Dynamic Type；应用自己的字体保留精确倍率。
        let sizes = DynamicTypeSize.allCases
        let target = UIFont.preferredFont(forTextStyle: .body).pointSize * AppFontScale.effective(scale, followsSystem: followsSystem)
        let closest = sizes.min { lhs, rhs in
            abs(bodySize(lhs) - target) < abs(bodySize(rhs) - target)
        } ?? systemSize
        content
            .font(AppFont.body.resolved(scale: CGFloat(AppFontScale.effective(scale, followsSystem: followsSystem))))
            .dynamicTypeSize(closest)
    }

    private func bodySize(_ size: DynamicTypeSize) -> CGFloat {
        let categories: [UIContentSizeCategory] = [.extraSmall, .small, .medium, .large, .extraLarge,
            .extraExtraLarge, .extraExtraExtraLarge, .accessibilityMedium, .accessibilityLarge,
            .accessibilityExtraLarge, .accessibilityExtraExtraLarge, .accessibilityExtraExtraExtraLarge]
        let index = DynamicTypeSize.allCases.firstIndex(of: size) ?? 3
        return UIFont.preferredFont(forTextStyle: .body,
            compatibleWith: UITraitCollection(preferredContentSizeCategory: categories[index])).pointSize
    }
}

extension View {
    func appFont(_ value: AppFont) -> some View { modifier(AppFontModifier(value: value)) }
}

extension UIFont {
    static func appPreferredFont(forTextStyle style: UIFont.TextStyle) -> UIFont {
        let font = preferredFont(forTextStyle: style)
        return font.withSize(font.pointSize * AppFontScale.current)
    }
    static func appMonospacedFont(ofSize size: CGFloat, weight: UIFont.Weight) -> UIFont {
        monospacedSystemFont(ofSize: UIFontMetrics.default.scaledValue(for: size) * AppFontScale.current, weight: weight)
    }
}

/// Terminal / console palette.
///
/// The visual language is deliberately flat and monochrome-plus-accent:
/// near-black surfaces, 1px hairline borders, amber as the single primary
/// accent, cyan for secondary emphasis. No blur, no gradients, no shadows.
enum DSHColor {
    static let navy = Color(red: 0.016, green: 0.016, blue: 0.020)          // 主背景（近黑）
    static let navyRaised = Color(red: 0.063, green: 0.063, blue: 0.071)    // 面板 / 卡片
    static let ocean = Color(red: 1.000, green: 0.690, blue: 0.000)         // 主强调（琥珀 #FFB000）
    static let mist = Color(red: 0.600, green: 0.600, blue: 0.620)          // 次级文字
    static let ink = Color(red: 0.043, green: 0.043, blue: 0.051)           // 浅色模式前景 / 反向
    static let paper = Color(red: 0.965, green: 0.965, blue: 0.973)         // 浅色纸面
    static let purple = Color(red: 0.208, green: 0.839, blue: 0.910)        // 次强调（青）
    static let orange = Color(red: 1.000, green: 0.478, blue: 0.157)        // 警告
    static let amber = Color(red: 1.000, green: 0.820, blue: 0.400)         // 提示
    static let success = Color(red: 0.235, green: 0.855, blue: 0.518)       // 成功

    // Terminal-specific tokens.
    static let border = Color(red: 0.180, green: 0.180, blue: 0.196)        // 面板描边
    static let panelFill = Color(red: 0.055, green: 0.055, blue: 0.063)     // 面板填充
    static let prompt = Color(red: 1.000, green: 0.690, blue: 0.000)        // 提示符
}

/// Kept under the upstream name so screens stay untouched; the terminal theme
/// no longer uses the Metal "deep ocean" shader.
struct DeepOceanBackground: View {
    var body: some View {
        TerminalBackground()
    }
}


/// 根据当前容器伸缩；不读取设备型号或 UIScreen，分屏和台前调度同样生效。
enum AdaptiveLayout {
    static let pageWidth: CGFloat = 1_040
    static let workspaceWidth: CGFloat = 1_440

    static func workspaceUsesColumns(size: CGSize, accessibilityText: Bool = false) -> Bool {
        // 820pt 起分栏：覆盖 iPad 竖屏与 iPhone Duo 展开态（实测内屏容器约 867pt），
        // 让折叠设备直接用上双栏，而不是把手机布局拉宽。
        size.width >= 820 && size.height >= 500 && !accessibilityText
    }

    static func horizontalInset(width: CGFloat, maximumWidth: CGFloat) -> CGFloat {
        max(0, (width - maximumWidth) / 2)
    }
}

extension View {
    /// 背景和滚动区域铺满窗口，正文保持合适的阅读宽度。
    func readableContentWidth(_ maximumWidth: CGFloat = AdaptiveLayout.pageWidth) -> some View {
        frame(maxWidth: maximumWidth)
            .frame(maxWidth: .infinity)
    }

    func adaptiveListWidth(_ maximumWidth: CGFloat = AdaptiveLayout.pageWidth) -> some View {
        modifier(AdaptiveListWidth(maximumWidth: maximumWidth))
    }
}

private struct AdaptiveListWidth: ViewModifier {
    let maximumWidth: CGFloat

    func body(content: Content) -> some View {
        GeometryReader { geometry in
            content.contentMargins(
                .horizontal,
                AdaptiveLayout.horizontalInset(width: geometry.size.width, maximumWidth: maximumWidth),
                for: .scrollContent
            )
        }
    }
}

// MARK: - Terminal background

/// Terminal-themed app background.
///
/// Replaces the upstream animated "deep ocean" whale shader with a static,
/// cheap-to-render console backdrop: near-black field, faint 1px grid,
/// subtle top accent glow and a vignette. Deliberately no Metal, no blur and
/// no animation so it costs nothing on battery and works on any simulator.
struct TerminalBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    /// Grid cell size in points.
    var cell: CGFloat = 28
    var showsGrid: Bool = true

    private var isDark: Bool { colorScheme == .dark }

    private var baseColor: Color {
        isDark ? Color(red: 0.016, green: 0.016, blue: 0.020)
               : Color(red: 0.965, green: 0.965, blue: 0.973)
    }

    private var gridColor: Color {
        isDark ? Color.white.opacity(0.045) : Color.black.opacity(0.055)
    }

    private var glowColor: Color {
        isDark ? DSHColor.ocean.opacity(0.045) : DSHColor.ocean.opacity(0.05)
    }

    var body: some View {
        ZStack {
            baseColor
            if showsGrid { grid }
            // Faint accent bloom behind the header area.
            RadialGradient(
                colors: [glowColor, .clear],
                center: UnitPoint(x: 0.5, y: -0.05),
                startRadius: 0,
                endRadius: 340
            )
            // Vignette keeps the edges quiet.
            RadialGradient(
                colors: [.clear, (isDark ? Color.black : Color.black).opacity(isDark ? 0.55 : 0.06)],
                center: .center,
                startRadius: 220,
                endRadius: 700
            )
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }

    private var grid: some View {
        Canvas { context, size in
            var path = Path()
            var x: CGFloat = 0
            while x <= size.width {
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
                x += cell
            }
            var y: CGFloat = 0
            while y <= size.height {
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
                y += cell
            }
            context.stroke(path, with: .color(gridColor), lineWidth: 0.5)
        }
    }
}
