import CoreGraphics
import CoreText
import Foundation

/// Core Text layout of a `TextBox`, in base-image pixels. The editor uses it to size the
/// in-place text field and its handles so they line up exactly with rendered text.
public struct TextLayout {
    /// The whole text object (insets included); `TextBox.origin` is its top-left.
    public let frame: CGRect
    /// Where the glyphs are laid out.
    public let textRect: CGRect
    public let fontSize: CGFloat
    let ctFrame: CTFrame

    /// Horizontal and vertical inset between the box edge and the glyphs. Identical for every
    /// decoration so switching style never moves the text.
    public static func insets(fontSize: CGFloat) -> CGSize {
        CGSize(width: (fontSize * 0.42).rounded(), height: (fontSize * 0.2).rounded())
    }

    /// Corner radius of the pill decorations.
    public static func pillRadius(for frame: CGRect, fontSize: CGFloat) -> CGFloat {
        min(frame.height / 2, fontSize * 0.62)
    }

    /// Width of the outline drawn around outlined text (beyond the glyph edge).
    static func outlineWidth(fontSize: CGFloat) -> CGFloat { max(fontSize * 0.075, 1) }

    public init(box: TextBox, fontSize: CGFloat) {
        self.init(box: box, fontSize: fontSize, color: CGColor(gray: 0, alpha: 1), stroke: nil)
    }

    init(box: TextBox, fontSize rawSize: CGFloat, color: CGColor, stroke: (color: CGColor, width: CGFloat)?) {
        let size = max(rawSize, 1)
        fontSize = size
        let inset = Self.insets(fontSize: size)
        let string = box.string.isEmpty ? " " : box.string
        let attributed = Self.attributedString(string, style: box.style, fontSize: size, color: color, stroke: stroke)
        let setter = CTFramesetterCreateWithAttributedString(attributed)
        let constraint: CGFloat
        if let wrap = box.wrapWidth {
            constraint = max(wrap - 2 * inset.width, size)
        } else {
            constraint = .greatestFiniteMagnitude
        }
        let suggested = CTFramesetterSuggestFrameSizeWithConstraints(
            setter, CFRange(location: 0, length: 0), nil, CGSize(width: constraint, height: .greatestFiniteMagnitude), nil)
        let textWidth = box.wrapWidth == nil ? ceil(suggested.width) + 1 : constraint
        // Trailing newline: Core Text does not count the empty last line; add it so the caret fits.
        var textHeight = ceil(suggested.height)
        if string.hasSuffix("\n") { textHeight += ceil(Self.lineHeight(fontSize: size, bold: box.style.isBold)) }
        textHeight = max(textHeight, ceil(Self.lineHeight(fontSize: size, bold: box.style.isBold)))
        let path = CGPath(rect: CGRect(x: 0, y: 0, width: textWidth, height: textHeight), transform: nil)
        ctFrame = CTFramesetterCreateFrame(setter, CFRange(location: 0, length: 0), path, nil)
        let width = box.wrapWidth ?? (textWidth + 2 * inset.width)
        frame = CGRect(x: box.origin.x, y: box.origin.y, width: width, height: textHeight + 2 * inset.height)
        textRect = CGRect(x: box.origin.x + inset.width, y: box.origin.y + inset.height, width: textWidth, height: textHeight)
    }

    static func font(size: CGFloat, bold: Bool) -> CTFont {
        CTFontCreateUIFontForLanguage(bold ? .emphasizedSystem : .system, size, nil)
            ?? CTFontCreateWithName("Helvetica" as CFString, size, nil)
    }

    static func lineHeight(fontSize: CGFloat, bold: Bool) -> CGFloat {
        let f = font(size: fontSize, bold: bold)
        return CTFontGetAscent(f) + CTFontGetDescent(f) + CTFontGetLeading(f)
    }

    static func attributedString(_ string: String, style: TextStyle, fontSize: CGFloat, color: CGColor,
                                 stroke: (color: CGColor, width: CGFloat)?) -> CFAttributedString {
        var alignment: CTTextAlignment
        switch style.alignment {
        case .left: alignment = .left
        case .center: alignment = .center
        case .right: alignment = .right
        }
        let paragraph = withUnsafeBytes(of: &alignment) { raw -> CTParagraphStyle in
            var setting = CTParagraphStyleSetting(spec: .alignment, valueSize: MemoryLayout<CTTextAlignment>.size, value: raw.baseAddress!)
            return CTParagraphStyleCreate(&setting, 1)
        }
        var attributes: [CFString: Any] = [
            kCTFontAttributeName: font(size: fontSize, bold: style.isBold),
            kCTParagraphStyleAttributeName: paragraph,
            kCTForegroundColorAttributeName: color,
        ]
        if style.decoration == .outlined {
            // The halo sits outside each glyph; open the tracking by the same amount so
            // neighbouring halos don't fuse letters together. Measured and drawn alike.
            attributes[kCTKernAttributeName] = outlineWidth(fontSize: fontSize) * 1.1
        }
        if let stroke {
            // Positive stroke width = stroke only, as a percentage of the font size; the stroke
            // is centred on the glyph edge, so double it to get `width` outside the glyph.
            attributes[kCTStrokeWidthAttributeName] = stroke.width * 2 / fontSize * 100
            attributes[kCTStrokeColorAttributeName] = stroke.color
        }
        return CFAttributedStringCreate(nil, string as CFString, attributes as CFDictionary)
    }

    /// Draws the laid-out glyphs into a top-left (flipped) user space.
    func drawGlyphs(in ctx: CGContext) {
        ctx.saveGState()
        ctx.translateBy(x: textRect.minX, y: textRect.maxY)
        ctx.scaleBy(x: 1, y: -1)
        ctx.textMatrix = .identity
        CTFrameDraw(ctFrame, ctx)
        ctx.restoreGState()
    }
}
