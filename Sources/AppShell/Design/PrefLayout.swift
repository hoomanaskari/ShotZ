import SwiftUI

/// Layout grid shared by every Settings pane: a fixed, right-aligned label
/// column, controls on one leading edge, an 8-pt spacing rhythm, section
/// headers with a hairline, help text one size down in secondary colour.
enum PrefMetrics {
    static let paneWidth: CGFloat = 620
    static let labelWidth: CGFloat = 176
    static let columnGap: CGFloat = 12
    static let rowSpacing: CGFloat = 8
    static let sectionSpacing: CGFloat = 24
    static let insets = EdgeInsets(top: 24, leading: 28, bottom: 28, trailing: 28)
    static var controlColumnWidth: CGFloat { paneWidth - insets.leading - insets.trailing - labelWidth - columnGap }
}

/// A whole pane: fixed width, natural height (the window sizes to it, so
/// short panes never scroll).
struct PrefPane<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: PrefMetrics.sectionSpacing) {
            content
        }
        .padding(PrefMetrics.insets)
        .frame(width: PrefMetrics.paneWidth, alignment: .topLeading)
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// A group of rows under an optional header.
struct PrefSection<Content: View>: View {
    var title: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let title {
                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)
                        .accessibilityAddTraits(.isHeader)
                    Divider()
                }
            }
            VStack(alignment: .leading, spacing: PrefMetrics.rowSpacing) {
                content
            }
        }
    }
}

/// One row: right-aligned label, then the control column.
struct PrefRow<Control: View>: View {
    var label: String?
    var alignment: VerticalAlignment = .firstTextBaseline
    @ViewBuilder var control: Control

    var body: some View {
        HStack(alignment: alignment, spacing: PrefMetrics.columnGap) {
            Text(label.map { $0 + ":" } ?? "")
                .multilineTextAlignment(.trailing)
                .frame(width: PrefMetrics.labelWidth, alignment: .trailing)
                .foregroundStyle(.primary)
                .accessibilityHidden(label == nil)
            VStack(alignment: .leading, spacing: 6) {
                control
            }
            .frame(width: PrefMetrics.controlColumnWidth, alignment: .leading)
        }
    }
}

/// Secondary explanation under a control (inside a `PrefRow`'s control column).
struct PrefHelp: View {
    let text: String
    var tone: Tone = .secondary

    enum Tone { case secondary, warning, error }

    init(_ text: String, tone: Tone = .secondary) {
        self.text = text
        self.tone = tone
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            if tone != .secondary {
                ShellIcon.warning.view(size: 11)
                    .foregroundStyle(tone == .error ? Color.red : Color.orange)
                    .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 1 }
            }
            Text(text)
                .font(.system(size: 11))
                .foregroundStyle(tone == .secondary ? Color.secondary : (tone == .error ? Color.red : Color.orange))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Small status pill (e.g. Screen Recording allowed / not allowed).
struct StatusPill: View {
    let text: String
    let positive: Bool

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(positive ? Color.green : Color.orange)
                .frame(width: 7, height: 7)
            Text(text).font(.system(size: 11, weight: .medium))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background((positive ? Color.green : Color.orange).opacity(0.14), in: Capsule())
        .accessibilityElement(children: .combine)
    }
}
