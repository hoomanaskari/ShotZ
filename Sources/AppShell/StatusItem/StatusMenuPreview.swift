import AppKit
import SwiftUI

/// Off-screen picture of the status menu built from its real items (titles,
/// icons, shortcuts, enabled state), for design review only. The real menu is
/// the system's NSMenu; this mirrors its layout so changes can be reviewed
/// without opening it over the user's work.
struct StatusMenuPreview: View {
    struct Row: Identifiable {
        let id = UUID()
        var separator = false
        var title = ""
        var image: NSImage?
        var shortcut = ""
        var enabled = true
        var hasSubmenu = false
    }

    let rows: [Row]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(rows) { row in
                if row.separator {
                    Divider().padding(.vertical, 5).padding(.horizontal, 10)
                } else {
                    HStack(spacing: 8) {
                        Group {
                            if let image = row.image {
                                Image(nsImage: image).renderingMode(.template)
                            } else {
                                Color.clear
                            }
                        }
                        .frame(width: 18)
                        Text(row.title)
                        Spacer(minLength: 24)
                        if row.hasSubmenu {
                            Text("›").font(.system(size: 15, weight: .medium))
                        } else {
                            Text(row.shortcut).foregroundStyle(.secondary)
                        }
                    }
                    .font(.system(size: 13))
                    .foregroundStyle(row.enabled ? Color.primary : Color.secondary.opacity(0.6))
                    .padding(.horizontal, 12)
                    .frame(height: 22)
                }
            }
        }
        .padding(.vertical, 5)
        .frame(width: 300)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color(nsColor: .windowBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5))
        .padding(16)
    }

    @MainActor static func render(rows: [Row], appearance: NSAppearance.Name) async -> Data? {
        let hosting = NSHostingView(rootView: StatusMenuPreview(rows: rows))
        let size = hosting.fittingSize
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: appearance)
        window.backgroundColor = appearance == .darkAqua ? NSColor(white: 0.12, alpha: 1) : NSColor(white: 0.86, alpha: 1)
        window.contentView = hosting
        hosting.frame = NSRect(origin: .zero, size: size)
        return await OffscreenRenderer.capture(window)
    }
}
