import ShotzCore
import SwiftUI

/// Original line-and-shape illustrations for the onboarding steps. Drawn with
/// SwiftUI shapes so they adapt to light and dark and stay crisp.
struct IllustrationStage<Content: View>: View {
    var tint: Color = .accentColor
    @ViewBuilder var content: Content

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(LinearGradient(colors: [tint.opacity(0.16), tint.opacity(0.05)], startPoint: .top, endPoint: .bottom))
            content
        }
        .frame(height: 150)
        .accessibilityHidden(true)
    }
}

private struct Card: View {
    var width: CGFloat
    var showArrow = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color(nsColor: .textBackgroundColor))
                .shadow(color: .black.opacity(0.18), radius: 6, y: 3)
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.accentColor.opacity(0.10))
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

    var body: some View {
        IllustrationStage(tint: granted ? .green : .accentColor) {
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(nsColor: .textBackgroundColor))
                    .shadow(color: .black.opacity(0.15), radius: 6, y: 3)
                HStack(spacing: 5) {
                    ForEach([Color.red, .orange, .green], id: \.self) { Circle().fill($0.opacity(0.8)).frame(width: 7, height: 7) }
                }
                .padding(9)
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                    .foregroundStyle(granted ? Color.green : Color.accentColor)
                    .frame(width: 104, height: 54)
                    .offset(x: 46, y: 34)
                Image(systemName: granted ? "checkmark.circle.fill" : "record.circle")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(granted ? Color.green : Color.red)
                    .background(Circle().fill(Color(nsColor: .textBackgroundColor)).padding(2))
                    .offset(x: 140, y: 74)
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
                }
            }
        }
    }
}

struct LaunchAtLoginIllustration: View {
    let on: Bool

    var body: some View {
        IllustrationStage(tint: on ? .accentColor : .gray) {
            VStack(spacing: 14) {
                HStack(spacing: 12) {
                    Spacer()
                    ForEach(["wifi", "battery.75percent"], id: \.self) { Image(systemName: $0).foregroundStyle(.secondary) }
                    Image(nsImage: StatusItemIcon.make(variant: AppVariant.current))
                        .padding(4)
                        .background(RoundedRectangle(cornerRadius: 5).fill(Color.accentColor.opacity(on ? 0.25 : 0.08)))
                    Text("9:41").font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 14)
                .frame(width: 230, height: 28)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .textBackgroundColor)).shadow(color: .black.opacity(0.12), radius: 4, y: 2))
                Image(systemName: "power.circle.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(on ? Color.accentColor : Color.secondary)
            }
        }
    }
}
