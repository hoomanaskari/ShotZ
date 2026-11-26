/// Decodes an array, skipping elements that fail to decode (e.g. a shape kind written by a
/// newer Shotz), so one unknown object never makes a whole document unreadable.
struct LossyArray<Element: Decodable>: Decodable {
    var elements: [Element]

    private struct Skip: Decodable {}

    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        var out: [Element] = []
        while !container.isAtEnd {
            if let e = try? container.decode(Element.self) {
                out.append(e)
            } else {
                _ = try? container.decode(Skip.self) // advance past the undecodable element
            }
        }
        elements = out
    }
}
