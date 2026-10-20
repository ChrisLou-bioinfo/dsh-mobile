import SwiftUI

struct GlassSurface: ViewModifier {
    let radius: CGFloat
    let dark: Bool
    let tint: Color?
    let clear: Bool
    let shadowOpacity: Double

    func body(content: Content) -> some View {
        // Terminal surfaces: flat fill + 1px hairline border, tiny radius.
        let r = min(radius, 6)
        let fill = tint?.opacity(clear ? 0.10 : 0.55)
        content
            .background {
                RoundedRectangle(cornerRadius: r, style: .continuous)
                    .fill(fill.map { AnyShapeStyle($0) } ?? AnyShapeStyle(DSHColor.panelFill))
            }
            .overlay {
                RoundedRectangle(cornerRadius: r, style: .continuous)
                    .strokeBorder(
                        tint.map { AnyShapeStyle($0.opacity(0.45)) } ?? AnyShapeStyle(DSHColor.border),
                        lineWidth: 1
                    )
            }
    }
}

extension View {
    func glassSurface(radius: CGFloat = 22, dark: Bool = false, tint: Color? = nil, clear: Bool = false, shadowOpacity: Double = 0.18) -> some View {
        modifier(GlassSurface(radius: radius, dark: dark, tint: tint, clear: clear, shadowOpacity: shadowOpacity))
    }

    /// Flat circular control for the terminal theme.
    func glassCircleButton() -> some View {
        // Terminal theme: flat square-ish control instead of a glass bubble.
        self
            .buttonStyle(.plain)
            .background(DSHColor.panelFill, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .strokeBorder(DSHColor.border, lineWidth: 1)
            )
    }
}

struct ConnectionDot: View {
    let state: ConnectionState

    private var color: Color {
        switch state {
        case .connected:
            DSHColor.success
        case .failed:
            .red
        case .connecting:
            DSHColor.amber
        case .disconnected:
            .gray
        }
    }

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
            .shadow(color: color.opacity(0.65), radius: 5)
    }
}

struct HarnessMark: View {
    var onDarkBackground = true
    var width: CGFloat = 216

    var body: some View {
        HStack(spacing: 8) {
            Image("MydshLaunchMark")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .foregroundStyle(onDarkBackground ? Color.white : Color.black)
                .frame(width: 26, height: 26)
            Text("mydsh")
                .font(.system(size: 22, weight: .semibold, design: .monospaced))
                .tracking(0.5)
                .foregroundStyle(onDarkBackground ? Color.white : Color.black)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: width, alignment: .leading)
        .frame(height: 29)
        .accessibilityLabel("Mydsh")
    }
}

struct WhalenessOrcaIcon: View {
    var size: CGFloat

    var body: some View {
        Image("DshOrcaMark")
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

extension View {
    @ViewBuilder
    func colorInvertIfNeeded(_ inverted: Bool) -> some View {
        if inverted { colorInvert() } else { self }
    }
}
