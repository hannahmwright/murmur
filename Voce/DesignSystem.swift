import AppKit
import SwiftUI

enum VoceDesign {
    // MARK: - Colors

    private static func adaptive(light: Color, dark: Color) -> Color {
        Color(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                ? NSColor(dark) : NSColor(light)
        }))
    }

    // Monet accent palette (from the app icon — used sparingly for color pops)
    static let wheat = Color(red: 0.82, green: 0.74, blue: 0.52)        // golden wheat highlight
    static let sage = Color(red: 0.58, green: 0.68, blue: 0.52)         // soft sage green
    static let skyBlue = Color(red: 0.62, green: 0.78, blue: 0.90)      // light impressionist sky
    static let lavender = Color(red: 0.72, green: 0.70, blue: 0.84)     // soft purple haze
    static let roseLight = Color(red: 0.86, green: 0.74, blue: 0.72)    // soft pinkish warmth

    // Primary accent: bright sky cerulean (Monet's Water Lilies sky)
    static let accent = Color(red: 0.32, green: 0.60, blue: 0.82)       // #5299D1
    static let accentSecondary = skyBlue

    // Clean glass surfaces — light, cool, airy
    static let background = adaptive(
        light: Color(red: 0.965, green: 0.970, blue: 0.980),            // cool near-white
        dark: Color(red: 0.09, green: 0.09, blue: 0.11)                 // deep cool charcoal
    )
    static let surface = adaptive(
        light: Color.white.opacity(0.88),
        dark: Color(red: 0.18, green: 0.19, blue: 0.21).opacity(0.90)
    )
    static let surfaceSecondary = adaptive(
        light: Color.white.opacity(0.80),
        dark: Color(red: 0.21, green: 0.22, blue: 0.24).opacity(0.86)
    )
    static let surfaceSolid = adaptive(
        light: Color(red: 0.972, green: 0.976, blue: 0.985),
        dark: Color(red: 0.16, green: 0.17, blue: 0.19)
    )
    static let windowBackground = adaptive(
        light: Color(red: 0.952, green: 0.960, blue: 0.972),
        dark: Color(red: 0.115, green: 0.12, blue: 0.135)
    )
    static let textPrimary = adaptive(
        light: Color(red: 0.12, green: 0.13, blue: 0.15),               // cool near-black
        dark: Color(red: 0.93, green: 0.94, blue: 0.95)                 // cool off-white
    )
    static let textSecondary = adaptive(
        light: Color(red: 0.44, green: 0.46, blue: 0.50),               // cool mid-grey
        dark: Color(red: 0.58, green: 0.60, blue: 0.64)                 // cool light-grey
    )
    static let border = adaptive(
        light: Color.black.opacity(0.06),                                // very subtle cool border
        dark: Color.white.opacity(0.10)
    )

    // Semantic colors (clean and modern, lightly tinted)
    static let success = Color(red: 0.30, green: 0.70, blue: 0.46)      // #4DB375  fresh green
    static let successBackground = success.opacity(0.10)
    static let successBorder = success.opacity(0.20)
    static let warning = Color(red: 0.90, green: 0.68, blue: 0.25)      // #E6AD40  warm gold
    static let warningBackground = warning.opacity(0.10)
    static let warningBorder = warning.opacity(0.20)
    static let error = Color(red: 0.88, green: 0.35, blue: 0.32)        // #E05952  soft red
    static let errorBackground = error.opacity(0.08)
    static let errorBorder = error.opacity(0.18)

    // MARK: - Gradients (Monet-inspired)

    /// Accent gradient for the mic button and highlights
    static let accentGradient = LinearGradient(
        colors: [accent, skyBlue],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// Warm glow gradient for recording state
    static let recordingGradient = LinearGradient(
        colors: [accent, lavender, skyBlue],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    // MARK: - Typography

    static func heading1() -> Font { .title3.weight(.bold) }
    static func heading2() -> Font { .title3.weight(.semibold) }
    static func heading3() -> Font { .headline }
    static func body() -> Font { .body }
    static func bodyEmphasis() -> Font { .subheadline.weight(.semibold) }
    static func callout() -> Font { .callout }
    static func subheadline() -> Font { .subheadline }
    static func caption() -> Font { .caption }
    static func captionEmphasis() -> Font { .caption.weight(.medium) }
    static func label() -> Font { .caption2.weight(.medium) }
    static func labelEmphasis() -> Font { .caption2.weight(.semibold) }

    // MARK: - Opacity

    static let opacityDisabled: Double = 0.5
    static let opacitySubtle: Double = 0.12
    static let opacityMuted: Double = 0.2
    static let opacityBorder: Double = 0.3
    static let opacityHover: Double = 0.08
    static let opacityGlowMax: Double = 0.8
    static let opacityGlass: Double = 0.70
    static let opacityGlassBorder: Double = 0.18
    static let opacityWindowGlass: Double = 0.52

    // MARK: - Spacing

    static let xxs: CGFloat = 2
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32
    static let xxxl: CGFloat = 48

    // MARK: - Radii

    static let radiusTiny: CGFloat = 2
    static let radiusSmall: CGFloat = 10
    static let radiusMedium: CGFloat = 14
    static let radiusLarge: CGFloat = 20
    static let radiusPill: CGFloat = 999

    // MARK: - Border Widths

    static let borderThin: CGFloat = 0.5
    static let borderNormal: CGFloat = 1.0
    static let borderThick: CGFloat = 2.0
    static let borderHeavy: CGFloat = 3.0

    // MARK: - Icon Sizes

    static let iconSM: CGFloat = 12
    static let iconMD: CGFloat = 16
    static let iconLG: CGFloat = 20
    static let iconXL: CGFloat = 26

    // MARK: - Animation Durations

    static let animationFast: Double = 0.15
    static let animationNormal: Double = 0.3
    static let animationSlow: Double = 0.5
    static let animationGlow: Double = 1.2

    // MARK: - Shadow System

    enum ShadowLevel {
        case none, sm, md, lg, xl, recording, idle

        var style: ShadowStyle {
            switch self {
            case .none:
                return ShadowStyle(color: .clear, radius: 0, x: 0, y: 0)
            case .sm:
                return ShadowStyle(color: .black.opacity(0.04), radius: 3, x: 0, y: 1)
            case .md:
                return ShadowStyle(color: .black.opacity(0.06), radius: 6, x: 0, y: 2)
            case .lg:
                return ShadowStyle(color: .black.opacity(0.08), radius: 10, x: 0, y: 4)
            case .xl:
                return ShadowStyle(color: .black.opacity(0.12), radius: 16, x: 0, y: 6)
            case .recording:
                return ShadowStyle(color: VoceDesign.accent.opacity(0.30), radius: 16, x: 0, y: 2)
            case .idle:
                return ShadowStyle(color: .black.opacity(0.06), radius: 8, x: 0, y: 2)
            }
        }

        var darkStyle: ShadowStyle {
            switch self {
            case .none:
                return ShadowStyle(color: .clear, radius: 0, x: 0, y: 0)
            case .sm:
                return ShadowStyle(color: .black.opacity(0.25), radius: 3, x: 0, y: 1)
            case .md:
                return ShadowStyle(color: .black.opacity(0.30), radius: 6, x: 0, y: 2)
            case .lg:
                return ShadowStyle(color: .black.opacity(0.35), radius: 10, x: 0, y: 4)
            case .xl:
                return ShadowStyle(color: .black.opacity(0.45), radius: 16, x: 0, y: 6)
            case .recording:
                return ShadowStyle(color: VoceDesign.accent.opacity(0.35), radius: 16, x: 0, y: 2)
            case .idle:
                return ShadowStyle(color: .black.opacity(0.30), radius: 8, x: 0, y: 2)
            }
        }
    }

    // MARK: - Component Sizes

    static let micButtonGlowSize: CGFloat = 92
    static let micButtonSize: CGFloat = 74
    static let micButtonGlowScale: CGFloat = 1.2
    static let dividerHeight: CGFloat = 1
    static let windowMinWidth: CGFloat = 600
    static let windowIdealWidth: CGFloat = 620
    static let windowMinHeight: CGFloat = 640
    static let windowIdealHeight: CGFloat = 680
    static let searchBarMaxWidth: CGFloat = 220
    static let insertionListHeight: CGFloat = 120
}

struct ShadowStyle {
    let color: Color
    let radius: CGFloat
    let x: CGFloat
    let y: CGFloat
}

// MARK: - Shadow Modifier

struct ShadowModifier: ViewModifier {
    let level: VoceDesign.ShadowLevel
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        let s = colorScheme == .dark ? level.darkStyle : level.style
        content.shadow(color: s.color, radius: s.radius, x: s.x, y: s.y)
    }
}

// MARK: - Glass Card Style

struct CardStyle: ViewModifier {
    var elevation: VoceDesign.ShadowLevel = .md
    var padding: CGFloat = VoceDesign.md

    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background {
                RoundedRectangle(cornerRadius: VoceDesign.radiusMedium)
                    .fill(VoceDesign.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: VoceDesign.radiusMedium)
                            .fill(
                                colorScheme == .dark
                                    ? AnyShapeStyle(.regularMaterial.opacity(0.20))
                                    : AnyShapeStyle(.regularMaterial.opacity(0.35))
                            )
                    )
            }
            .clipShape(RoundedRectangle(cornerRadius: VoceDesign.radiusMedium))
            .overlay(
                RoundedRectangle(cornerRadius: VoceDesign.radiusMedium)
                    .stroke(
                        colorScheme == .dark
                            ? Color.white.opacity(0.06)
                            : Color.white.opacity(0.50),
                        lineWidth: VoceDesign.borderThin
                    )
            )
            .shadowStyle(elevation)
    }
}

// MARK: - Interactive Glass Card Style

struct InteractiveCardStyle: ViewModifier {
    var elevation: VoceDesign.ShadowLevel = .md
    var padding: CGFloat = VoceDesign.md

    @State private var isHovering = false
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background {
                RoundedRectangle(cornerRadius: VoceDesign.radiusMedium)
                    .fill(isHovering ? VoceDesign.surface : VoceDesign.surfaceSecondary)
                    .overlay(
                        RoundedRectangle(cornerRadius: VoceDesign.radiusMedium)
                            .fill(
                                colorScheme == .dark
                                    ? AnyShapeStyle(.regularMaterial.opacity(isHovering ? 0.24 : 0.18))
                                    : AnyShapeStyle(.regularMaterial.opacity(isHovering ? 0.40 : 0.30))
                            )
                    )
            }
            .clipShape(RoundedRectangle(cornerRadius: VoceDesign.radiusMedium))
            .overlay(
                RoundedRectangle(cornerRadius: VoceDesign.radiusMedium)
                    .stroke(
                        colorScheme == .dark
                            ? Color.white.opacity(isHovering ? 0.10 : 0.06)
                            : Color.white.opacity(isHovering ? 0.60 : 0.50),
                        lineWidth: VoceDesign.borderThin
                    )
            )
            .shadowStyle(isHovering ? .lg : elevation)
            .scaleEffect(isHovering ? 1.005 : 1.0)
            .animation(.easeInOut(duration: VoceDesign.animationFast), value: isHovering)
            .onHover { hovering in
                isHovering = hovering
            }
    }
}

// MARK: - Pressable Button Style

struct PressableButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.95 : 1.0)
            .animation(
                reduceMotion ? nil : .spring(response: 0.1, dampingFraction: 0.7),
                value: configuration.isPressed
            )
    }
}

// MARK: - Copy Button View

struct CopyButtonView: View {
    let action: () -> Void
    var label: String = "Copy transcript"

    @State private var didCopy = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button {
            action()
            didCopy = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                didCopy = false
            }
        } label: {
            Image(systemName: didCopy ? "checkmark" : "doc.on.doc")
                .font(VoceDesign.caption())
                .foregroundStyle(didCopy ? VoceDesign.success : VoceDesign.textSecondary)
                .scaleEffect(didCopy && !reduceMotion ? 1.15 : 1.0)
                .animation(
                    reduceMotion ? nil : .spring(response: 0.2, dampingFraction: 0.6),
                    value: didCopy
                )
        }
        .buttonStyle(.plain)
        .help("Copy")
        .accessibilityLabel(label)
    }
}

// MARK: - View Extensions

extension View {
    func shadowStyle(_ level: VoceDesign.ShadowLevel) -> some View {
        modifier(ShadowModifier(level: level))
    }

    func cardStyle(elevation: VoceDesign.ShadowLevel = .md, padding: CGFloat = VoceDesign.md) -> some View {
        modifier(CardStyle(elevation: elevation, padding: padding))
    }

    func interactiveCardStyle(elevation: VoceDesign.ShadowLevel = .md, padding: CGFloat = VoceDesign.md) -> some View {
        modifier(InteractiveCardStyle(elevation: elevation, padding: padding))
    }

    func glassBackground(cornerRadius: CGFloat = VoceDesign.radiusMedium) -> some View {
        self
            .background {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(VoceDesign.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .fill(VoceDesign.surfaceSolid.opacity(0.18))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .fill(.regularMaterial.opacity(VoceDesign.opacityWindowGlass))
                    )
            }
    }
}
