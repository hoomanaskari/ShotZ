import ShotzCore
import SwiftUI

/// Surfaces for the illustrations, chosen for luminance contrast in both
/// appearances: light "paper" objects on a tinted stage (in dark mode the
/// stage is a stronger tint and the paper stays light, never dark on dark).
struct IllustrationPalette {
    let scheme: ColorScheme
    var paper: Color { scheme == .dark ? Color(white: 0.90) : .white }
    var paperInset: Color { Color.accentColor.opacity(scheme == .dark ? 0.22 : 0.10) }
    var shadow: Color { .black.opacity(scheme == .dark ? 0.45 : 0.18) }
    var muted: Color { Color(white: scheme == .dark ? 0.55 : 0.70) }
    func stage(_ tint: Color) -> LinearGradient {
        LinearGradient(colors: scheme == .dark ? [tint.opacity(0.42), tint.opacity(0.20)] : [tint.opacity(0.16), tint.opacity(0.05)],
                       startPoint: .top, endPoint: .bottom)
    }
}

/// Original line-and-shape illustrations for the onboarding steps. Drawn with
/// SwiftUI shapes so they adapt to light and dark and stay crisp.
struct IllustrationStage<Content: View>: View {
    var tint: Color = .accentColor
    @ViewBuilder var content: Content
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(IllustrationPalette(scheme: scheme).stage(tint))
            content
        }
        .frame(height: 150)
        .accessibilityHidden(true)
    }
}

private struct Card: View {
    var width: CGFloat
    var showArrow = false
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let palette = IllustrationPalette(scheme: scheme)
        ZStack {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(palette.paper)
                .shadow(color: palette.shadow, radius: 6, y: 3)
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(palette.paperInset)
                .padding(6)
            if showArrow {
                ArrowScribble()
                    .stroke(Color(red: 1, green: 0.35, blue: 0.21), style: StrokeStyle(lineWidth: 3.5, lineCap: .round, lineJoin: .round))
                    .padding(14)
            }
        }
        .frame(width: width, height: width * 0.62)
    }
}

/// A curved annotation arrow, the Shotz motif.
struct ArrowScribble: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let start = CGPoint(x: r.maxX, y: r.maxY)
        let tip = CGPoint(x: r.minX + r.width * 0.28, y: r.minY + r.height * 0.32)
        p.move(to: start)
        p.addQuadCurve(to: tip, control: CGPoint(x: r.maxX - r.width * 0.05, y: r.minY + r.height * 0.2))
        p.move(to: CGPoint(x: tip.x + r.width * 0.16, y: tip.y - r.height * 0.14))
        p.addLine(to: tip)
        p.addLine(to: CGPoint(x: tip.x + r.width * 0.12, y: tip.y + r.height * 0.22))
        return p
    }
}

struct WelcomeIllustration: View {
    var body: some View {
        IllustrationStage {
            ZStack {
                Card(width: 120).rotationEffect(.degrees(-9)).offset(x: -40, y: 6).opacity(0.75)
                Card(width: 120).rotationEffect(.degrees(6)).offset(x: 40, y: -4).opacity(0.85)
                Card(width: 132, showArrow: true).offset(y: 4)
            }
        }
    }
}

struct ScreenRecordingIllustration: View {
    let granted: Bool
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let palette = IllustrationPalette(scheme: scheme)
        IllustrationStage(tint: granted ? .green : .accentColor) {
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(palette.paper)
                    .shadow(color: palette.shadow, radius: 6, y: 3)
                HStack(spacing: 5) {
                    ForEach([Color.red, .orange, .green], id: \.self) { Circle().fill($0.opacity(0.8)).frame(width: 7, height: 7) }
                }
                .padding(9)
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                    .foregroundStyle(granted ? Color.green : Color.accentColor)
                    .frame(width: 104, height: 54)
                    .offset(x: 46, y: 34)
                ZStack {
                    Circle().fill(granted ? Color.green : Color.accentColor)
                    (granted ? ShellIcon.checkmark : ShellIcon.screenRecording).view(size: 16)
                        .foregroundStyle(.white)
                }
                .frame(width: 30, height: 30)
                .offset(x: 138, y: 72)
            }
            .frame(width: 200, height: 110)
        }
    }
}

struct ShortcutsIllustration: View {
    let combos: [KeyCombo]
    let allClear: Bool

    var body: some View {
        IllustrationStage(tint: allClear ? .accentColor : .orange) {
            VStack(spacing: 12) {
                ForEach(Array(combos.prefix(3).enumerated()), id: \.offset) { _, combo in
                    KeyCapsRow(combo: combo, size: 16)
                        .environment(\.colorScheme, .light)   // light caps on the tinted stage in both appearances
                }
            }
        }
    }
}

struct LaunchAtLoginIllustration: View {
    let on: Bool
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let palette = IllustrationPalette(scheme: scheme)
        IllustrationStage(tint: on ? .accentColor : .gray) {
            VStack(spacing: 14) {
                HStack(spacing: 12) {
                    Spacer()
                    ForEach(0..<2, id: \.self) { _ in
                        Capsule().fill(palette.muted).frame(width: 16, height: 7)
                    }
                    // Template glyph on light paper: dark ink in both appearances.
                    Image(nsImage: StatusItemIcon.make(variant: AppVariant.current))
                        .renderingMode(AppVariant.current == .production ? .template : .original)
                        .foregroundStyle(Color(white: 0.2))
                        .padding(4)
                        .background(RoundedRectangle(cornerRadius: 5).fill(Color.accentColor.opacity(on ? 0.25 : 0.08)))
                    Text("9:41").font(.system(size: 12, weight: .medium)).foregroundStyle(Color(white: 0.35))
                }
                .padding(.horizontal, 14)
                .frame(width: 230, height: 28)
                .background(RoundedRectangle(cornerRadius: 8).fill(palette.paper).shadow(color: palette.shadow, radius: 4, y: 2))
                ZStack {
                    Circle().fill(on ? Color.accentColor : Color.secondary.opacity(0.5))
                    ShellIcon.launchAtLogin.view(size: 20).foregroundStyle(.white)
                }
                .frame(width: 40, height: 40)
            }
        }
    }
}
