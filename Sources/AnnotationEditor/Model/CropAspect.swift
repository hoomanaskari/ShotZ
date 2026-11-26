import CoreGraphics

/// Crop aspect presets (SPEC §5.3).
enum CropAspect: String, CaseIterable, Sendable {
    case free, original, square, fourThree, sixteenNine, threeTwo

    var title: String {
        switch self {
        case .free: String(localized: "Free")
        case .original: String(localized: "Original")
        case .square: "1:1"
        case .fourThree: "4:3"
        case .sixteenNine: "16:9"
        case .threeTwo: "3:2"
        }
    }

    /// width / height; nil = free.
    func ratio(imageSize: CGSize) -> CGFloat? {
        switch self {
        case .free: nil
        case .original: imageSize.height > 0 ? imageSize.width / imageSize.height : nil
        case .square: 1
        case .fourThree: 4.0 / 3.0
        case .sixteenNine: 16.0 / 9.0
        case .threeTwo: 3.0 / 2.0
        }
    }

    /// The largest rect of `ratio` centred on `rect`'s centre that fits inside `rect` ∩ `bounds`.
    static func fit(_ rect: CGRect, ratio: CGFloat, within bounds: CGRect) -> CGRect {
        var w = rect.width, h = rect.height
        if w / max(h, 1) > ratio { w = h * ratio } else { h = w / ratio }
        var r = CGRect(x: rect.midX - w / 2, y: rect.midY - h / 2, width: w, height: h)
        // Shift back inside the image.
        r.origin.x = min(max(r.minX, bounds.minX), bounds.maxX - r.width)
        r.origin.y = min(max(r.minY, bounds.minY), bounds.maxY - r.height)
        return r
    }
}
