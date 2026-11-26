// Cleans the matte of the owner's icon artwork (see Resources/icon-master/MATTE.md).
//
//   swift Resources/clean-matte.swift Resources/icon-master/owner-artwork.webp Resources/icon-master/owner-artwork-clean.png
//
// Only the alpha channel and the colour of semi-transparent edge pixels change; opaque artwork
// is never redrawn, recoloured or reshaped:
//   1. alpha is remapped linearly so the haze floor (≤ 12/255) becomes 0 and the solid interior
//      (247–254/255) becomes fully opaque; the antialiased ramp in between keeps its shape;
//   2. nothing is kept more than 3 px from a solid shape (alpha ≥ 50 %): stray glow and speckle;
//   3. semi-transparent edge pixels take the colour of the adjoining opaque artwork (grown
//      outward one pixel at a time), so no glow colour survives in the antialiasing.
// The original shadow data was only haze, so no shadow is kept: the tile adds its own.
import AppKit

guard CommandLine.arguments.count == 3 else {
    FileHandle.standardError.write(Data("usage: swift Resources/clean-matte.swift <input> <output.png>\n".utf8)); exit(64)
}
let input = CommandLine.arguments[1], output = CommandLine.arguments[2]

struct Img { var w: Int; var h: Int; var r: [Float]; var g: [Float]; var b: [Float]; var a: [Float] } // straight colour 0...1
func loadStraight(_ p: String) -> Img {
    let src = CGImageSourceCreateWithURL(URL(filePath: p) as CFURL, nil)!
    let cg = CGImageSourceCreateImageAtIndex(src, 0, nil)!
    let w = cg.width, h = cg.height
    // Read the stored bytes (WebP decodes as straight, non-premultiplied alpha).
    let data = cg.dataProvider!.data! as Data
    let bpr = cg.bytesPerRow
    var img = Img(w: w, h: h, r: .init(repeating: 0, count: w*h), g: .init(repeating: 0, count: w*h), b: .init(repeating: 0, count: w*h), a: .init(repeating: 0, count: w*h))
    if cg.bitsPerPixel != 32 {
        // Wide images: draw into a 16-bit premultiplied buffer, then unpremultiply.
        var buf = [UInt16](repeating: 0, count: w*h*4)
        let c = CGContext(data: &buf, width: w, height: h, bitsPerComponent: 16, bytesPerRow: w*8, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder16Little.rawValue)!
        c.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        for i in 0..<(w*h) { let A = Float(buf[i*4+3]) / 65535; img.a[i] = A
            if A > 0 { img.r[i] = min(1, Float(buf[i*4]) / 65535 / A); img.g[i] = min(1, Float(buf[i*4+1]) / 65535 / A); img.b[i] = min(1, Float(buf[i*4+2]) / 65535 / A) } }
        return img
    }
    let premul = cg.alphaInfo == .premultipliedLast || cg.alphaInfo == .premultipliedFirst
    let first = cg.alphaInfo == .first || cg.alphaInfo == .premultipliedFirst
    data.withUnsafeBytes { (p: UnsafeRawBufferPointer) in
        for y in 0..<h { for x in 0..<w {
            let o = y*bpr + x*4, i = y*w + x
            let A = Float(p[o + (first ? 0 : 3)]) / 255
            let c0 = first ? 1 : 0
            var R = Float(p[o+c0]) / 255, G = Float(p[o+c0+1]) / 255, B = Float(p[o+c0+2]) / 255
            if premul && A > 0 { R = min(1, R/A); G = min(1, G/A); B = min(1, B/A) }
            img.r[i] = R; img.g[i] = G; img.b[i] = B; img.a[i] = A
        }}
    }
    return img
}
let m = loadStraight(input)
let w = m.w, h = m.h, n = w*h
let lo: Float = 12/255, hi: Float = 247/255
// 1. Solid shapes and distance from them (chessboard, capped).
let solid = m.a.map { $0 >= 0.5 }
var dist = [UInt8](repeating: 255, count: n)
for i in 0..<n where solid[i] { dist[i] = 0 }
for d in 1...4 {
    var next = dist
    for y in 0..<h { for x in 0..<w { let i = y*w+x; guard dist[i] == 255 else { continue }
        outer: for dy in -1...1 { for dx in -1...1 { let xx = x+dx, yy = y+dy
            if xx>=0 && yy>=0 && xx<w && yy<h && dist[yy*w+xx] == UInt8(d-1) { next[i] = UInt8(d); break outer } } } } }
    dist = next
}
var c = m
var cleared = 0, remapped = 0
for i in 0..<n {
    // 2. Haze floor out, solid interior to fully opaque: linear remap lo...hi → 0...1.
    var a = min(1, max(0, (m.a[i] - lo) / (hi - lo)))
    // 3. Nothing survives more than 3 px from a solid shape (stray glow, speckle).
    if dist[i] > 3 { a = 0 }
    if a == 0 && m.a[i] > 0 { cleared += 1 } else if a != m.a[i] { remapped += 1 }
    c.a[i] = a
}
// 4. Decontaminate edges: semi-transparent pixels take the colour of the neighbouring opaque
//    art (grown outward one pixel at a time), so no glow colour survives in the antialiasing.
var known = c.a.map { $0 >= 0.98 }
var fixed = 0
for _ in 0..<5 {
    var nk = known; var r = c.r, g = c.g, b = c.b
    for y in 0..<h { for x in 0..<w { let i = y*w+x; guard !known[i], c.a[i] > 0 || dist[i] <= 4 else { continue }
        var sr: Float = 0, sg: Float = 0, sb: Float = 0, k: Float = 0
        for dy in -1...1 { for dx in -1...1 { let xx = x+dx, yy = y+dy
            if xx>=0 && yy>=0 && xx<w && yy<h { let j = yy*w+xx; if known[j] { sr += c.r[j]; sg += c.g[j]; sb += c.b[j]; k += 1 } } } }
        if k > 0 { r[i] = sr/k; g[i] = sg/k; b[i] = sb/k; nk[i] = true; if c.a[i] > 0 { fixed += 1 } } } }
    c.r = r; c.g = g; c.b = b; known = nk
}
for i in 0..<n where c.a[i] == 0 { c.r[i] = 0; c.g[i] = 0; c.b[i] = 0 }
print("clean-matte: haze pixels cleared:", cleared, "alpha remapped:", remapped, "edge colours decontaminated:", fixed)
// Write straight-alpha PNG (16-bit to keep edge precision).
var px16 = [UInt16](repeating: 0, count: n*4)
for i in 0..<n { px16[i*4] = UInt16(c.r[i]*65535); px16[i*4+1] = UInt16(c.g[i]*65535); px16[i*4+2] = UInt16(c.b[i]*65535); px16[i*4+3] = UInt16(c.a[i]*65535) }
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h, bitsPerSample: 16, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bitmapFormat: [.alphaNonpremultiplied], bytesPerRow: w*8, bitsPerPixel: 64)!
px16.withUnsafeBytes { src in _ = memcpy(rep.bitmapData!, src.baseAddress!, n*8) }
let tagged = rep.retagging(with: .sRGB)!
try! tagged.representation(using: .png, properties: [:])!.write(to: URL(filePath: output))
print("clean-matte: wrote \(output)")
