import Foundation
import Testing
@testable import ShotzCore

struct KeyComboTests {
    @Test func codableRoundTrip() throws {
        let combo = KeyCombo(keyCode: KeyCombo.keyCode4, modifiers: [.command, .shift])
        let data = try JSONEncoder().encode(combo)
        #expect(try JSONDecoder().decode(KeyCombo.self, from: data) == combo)
    }

    @Test func stableEncoding() throws {
        let data = try JSONEncoder().encode(KeyCombo.defaultArea)
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Int]
        #expect(object == ["keyCode": 0x15, "modifiers": 3])
    }

    @Test func descriptions() {
        #expect(KeyCombo.defaultFullscreen.description == "⇧⌘3")
        #expect(KeyCombo.devArea.description == "⌃⌥⌘4")
        #expect(KeyCombo(keyCode: 0x00, modifiers: []).description == "A")
        #expect(KeyCombo(keyCode: 0x6F, modifiers: [.control, .option, .shift, .command]).description == "⌃⌥⇧⌘F12")
        #expect(KeyCombo(keyCode: 0x7A, modifiers: []).description == "F1")
        #expect(KeyCombo(keyCode: 0x50, modifiers: [.shift]).description == "⇧F19")
        #expect(KeyCombo(keyCode: 0x31, modifiers: [.option]).description == "⌥Space")
        #expect(KeyCombo(keyCode: 0x7E, modifiers: [.command]).description == "⌘↑")
        #expect(KeyCombo(keyCode: 0x24, modifiers: [.command]).description == "⌘↩")
        #expect(KeyCombo(keyCode: 0x2A, modifiers: [.command]).description == "⌘\\")
        #expect(KeyCombo(keyCode: 0xEE, modifiers: [.command]).description == "⌘Key 238")
    }

    @Test func defaultsAreCmdShift345() {
        #expect(KeyCombo.defaultFullscreen == KeyCombo(keyCode: 0x14, modifiers: [.command, .shift]))
        #expect(KeyCombo.defaultArea.keyCode == 0x15)
        #expect(KeyCombo.defaultAllInOne.keyCode == 0x17)
    }
}
