import AppKit
import ShotzCore

/// Visual review set: every card size in light and dark, resting, hovered
/// (tall and square cards) and with a confirmation showing (wide card).
extension StackSelfTest {
    func gallery(qa: QuickAccessController) async {
        guard let panel = qa.panels.values.first else { return note("gallery skipped: no panel") }
        let original = qa.applied
        func card(where test: (CGSize) -> Bool) -> CardView? {
            qa.cards.values.first { test($0.source.pixelSize) }
        }
        for size in [CardSize.small, .medium, .large] {
            var s = qa.applied
            s.size = size
            qa.apply(s)
            await wait(700) // new card views + thumbnails
            for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
                panel.appearance = NSAppearance(named: appearance)
                await wait(150)
                snapshot("g-\(size.rawValue)-\(name)-1-rest")
                let tall = card { $0.height > $0.width * 2 }
                let wide = card { $0.width > $0.height * 3 }
                let square = card { $0.width == $0.height }
                tall?.setHovered(true)
                tall?.overlay.button(for: .copy)?.stateOverride = .hover
                tall?.overlay.button(for: .save)?.stateOverride = .pressed
                wide?.flash(String(localized: "Copied"), success: true)
                await wait(300)
                snapshot("g-\(size.rawValue)-\(name)-2-hover-tall-flash-wide")
                tall?.overlay.button(for: .copy)?.stateOverride = nil
                tall?.overlay.button(for: .save)?.stateOverride = nil
                tall?.setHovered(false)
                square?.setHovered(true)
                await wait(1300) // flash gone
                snapshot("g-\(size.rawValue)-\(name)-3-hover-square")
                square?.setHovered(false)
                await wait(150)
            }
        }
        panel.appearance = nil
        qa.apply(original)
        await wait(600)
    }
}
