import AppKit
import ShotzCore
import SwiftUI
import Testing
@testable import ShotzUI

/// Renders the SwiftUI counterparts (Settings/onboarding) beside nothing else: rest and disabled.
@MainActor
@Suite(.serialized)
struct SwiftUIGalleryTests {
    struct Sample: View {
        @State var on = true
        @State var off = false
        var body: some View {
            VStack(alignment: .leading, spacing: ShotzUI.Space.m) {
                Text("SwiftUI counterparts").font(ShotzUI.Typography.title.swiftUIFont).foregroundStyle(Color(nsColor: ShotzUI.Palette.textPrimary))
                HStack(spacing: ShotzUI.Space.s) {
                    Button {} label: { ShotzLabel("Save", icon: .save) }.buttonStyle(.shotz(.primary))
                    Button {} label: { ShotzLabel("Copy", icon: .copy) }.buttonStyle(.shotz(.secondary))
                    Button("Choose…") {}.buttonStyle(.shotz(.secondary))
                    Button("Reset") {}.buttonStyle(.shotz(.quiet))
                    Button {} label: { ShotzLabel("Delete", icon: .trash) }.buttonStyle(.shotz(.destructive))
                    Button {} label: { ShotzLabel(icon: .more) }.buttonStyle(.shotz(.quiet))
                }
                HStack(spacing: ShotzUI.Space.s) {
                    Button {} label: { ShotzLabel("Save", icon: .save) }.buttonStyle(.shotz(.primary)).disabled(true)
                    Button("Choose…") {}.buttonStyle(.shotz(.secondary)).disabled(true)
                    Toggle("Outline", isOn: $on).toggleStyle(.shotzChip)
                    Toggle("Outline", isOn: $off).toggleStyle(.shotzChip)
                    Toggle("Shadow", isOn: $on).toggleStyle(.shotzChip(icon: .shadow))
                }
            }
            .padding(ShotzUI.Space.xl)
            .background(Color(nsColor: ShotzUI.Palette.windowBackground))
        }
    }

    @Test func renderSwiftUIGallery() throws {
        guard !GalleryOutput.directories.isEmpty else { return }
        _ = NSApplication.shared
        ShotzUI.Palette.accentOverride = GalleryOutput.blue
        defer { ShotzUI.Palette.accentOverride = nil }
        for (name, scheme) in [("light", ColorScheme.light), ("dark", ColorScheme.dark)] {
            let renderer = ImageRenderer(content: Sample().environment(\.colorScheme, scheme))
            renderer.scale = 2
            // Dynamic NSColors resolve against the drawing appearance.
            var image: CGImage?
            NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)!.performAsCurrentDrawingAppearance { image = renderer.cgImage }
            if let image { try GalleryOutput.write(image, name: "swiftui-\(name)@2x.png") }
        }
    }
}
