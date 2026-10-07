// The app's icon, drawn rather than exported: the mark is Brauz's
// glyph, a б drawn as one stroke of a pen, 72 units wide.
// The icon puts it on a plate, because a Dock icon has to be an opaque
// square whether the logo itself wants a background or not.

import AppKit

let out = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "AppIcon.iconset")
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

/// The colours, sRGB, as in the drawings the icon was made from: a cream
/// plate with the mark in ink, and in Dark the other way round, on a plate
/// a shade lighter than the ink.
let cream = (r: 0xE9 / 255.0, g: 0xE1 / 255.0, b: 0xD3 / 255.0)
let ink = (r: 0x11 / 255.0, g: 0x11 / 255.0, b: 0x11 / 255.0)
let night = (r: 0x16 / 255.0, g: 0x16 / 255.0, b: 0x16 / 255.0)

/// Brauz's mark, constructed in 1024x1024 y-down coordinates and stroked 72 units wide.
let outline: CGPath = {
    let centreline = CGMutablePath()
    centreline.move(to: CGPoint(x: 644, y: 292))
    centreline.addLine(to: CGPoint(x: 515, y: 292))
    centreline.addCurve(to: CGPoint(x: 372, y: 410), control1: CGPoint(x: 429.2, y: 292), control2: CGPoint(x: 372, y: 339.2))
    centreline.addLine(to: CGPoint(x: 372, y: 620))
    centreline.addEllipse(in: CGRect(x: 372, y: 480, width: 280, height: 280))
    return centreline.copy(strokingWithWidth: 72, lineCap: .round, lineJoin: .round, miterLimit: 10)
}()

func draw(_ size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    defer { image.unlockFocus() }

    // Apple's grid: the shape takes 824 of 1024, and its corners are 22.37%.
    let s = size / 1024
    let plate = NSRect(x: 100 * s, y: 100 * s, width: 824 * s, height: 824 * s)
    let radius = 824 * 0.2237 * s
    let shape = NSBezierPath(roundedRect: plate, xRadius: radius, yRadius: radius)

    // A soft shadow under the plate, the way every icon on the Dock has one.
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.18)
    shadow.shadowBlurRadius = 24 * s
    shadow.shadowOffset = NSSize(width: 0, height: -10 * s)
    shadow.set()
    NSColor(srgbRed: cream.r, green: cream.g, blue: cream.b, alpha: 1).setFill()
    shape.fill()
    NSGraphicsContext.restoreGraphicsState()

    // Brauz's mark, ink on the plate: a б stroked 72 units wide,
    // sitting slightly below centre.
    if let ctx = NSGraphicsContext.current?.cgContext {
        var t = CGAffineTransform(a: s, b: 0, c: 0, d: -s, tx: 0, ty: 1024 * s)
        if let path = outline.copy(using: &t) {
            ctx.addPath(path)
            ctx.setFillColor(CGColor(srgbRed: ink.r, green: ink.g, blue: ink.b, alpha: 1))
            ctx.fillPath(using: .winding)
        }
    }
    return image
}

func write(_ image: NSImage, to url: URL, pixels: Int) {
    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff)
    else { return }
    // The bitmap is asked for at the pixel size, whatever the screen thinks,
    // and in sRGB, the colours' own: in the screen's, the cream came out paler.
    let sized = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!.retagging(with: .sRGB)!
    sized.size = NSSize(width: pixels, height: pixels)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: sized)
    NSGraphicsContext.current?.imageInterpolation = .high
    rep.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
    NSGraphicsContext.restoreGraphicsState()
    guard let png = sized.representation(using: .png, properties: [:]) else { return }
    try? png.write(to: url)
}

for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = points * scale
        let image = draw(CGFloat(pixels))
        let name = scale == 1 ? "icon_\(points)x\(points).png" : "icon_\(points)x\(points)@2x.png"
        write(image, to: out.appendingPathComponent(name), pixels: pixels)
    }
}
print("drew: \(out.path)")

// The same icon as an Icon Composer document, when a second path is given.
// macOS 26 lets the Dock show icons Dark, Clear or Tinted, and it can only
// do that well with an icon that says what each style should be: from the
// flat image above it made a darkened plate with the black mark still on
// it, black on black (#337). Here the plate and the mark are separate, so
// Dark turns them round, a light mark on the dark plate, the loop showing
// the plate through it, and Tinted gets a white mark whose brightness the
// system tints. The light look uses the beige plate and dark mark, with
// no glass, gloss or shadow of its own.
// build.sh compiles it with actool; the images above stay the .icns.
if CommandLine.arguments.count > 2 {
    let doc = URL(fileURLWithPath: CommandLine.arguments[2])
    let assets = doc.appendingPathComponent("Assets")
    try? FileManager.default.removeItem(at: doc)
    try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)

    func svgPath(from path: CGPath) -> String {
        func fmt(_ v: CGFloat) -> String {
            let s = String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), v)
            if s.hasSuffix(".00") { return String(s.dropLast(3)) }
            if s.hasSuffix("0") { return String(s.dropLast()) }
            return s
        }
        var d: [String] = []
        path.applyWithBlock { elem in
            let p = elem.pointee.points
            switch elem.pointee.type {
            case .moveToPoint:
                d.append("M\(fmt(p[0].x)) \(fmt(p[0].y))")
            case .addLineToPoint:
                d.append("L\(fmt(p[0].x)) \(fmt(p[0].y))")
            case .addQuadCurveToPoint:
                d.append("Q\(fmt(p[0].x)) \(fmt(p[0].y)) \(fmt(p[1].x)) \(fmt(p[1].y))")
            case .addCurveToPoint:
                d.append("C\(fmt(p[0].x)) \(fmt(p[0].y)) \(fmt(p[1].x)) \(fmt(p[1].y)) \(fmt(p[2].x)) \(fmt(p[2].y))")
            case .closeSubpath:
                d.append("Z")
            @unknown default:
                break
            }
        }
        return d.joined(separator: " ")
    }

    let svg = """
    <svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="100 100 824 824">\
    <path fill-rule="nonzero" fill="#111111" d="\(svgPath(from: outline))"/></svg>
    """
    try svg.write(to: assets.appendingPathComponent("mark.svg"), atomically: true, encoding: .utf8)

    func solid(_ c: (r: Double, g: Double, b: Double)) -> String {
        String(format: #"{ "solid" : "srgb:%.5f,%.5f,%.5f,1.00000" }"#, locale: Locale(identifier: "en_US_POSIX"), c.r, c.g, c.b)
    }
    let light = solid(cream)
    let dark = solid(ink)
    let white = solid((1, 1, 1))
    let json = """
    {
      "fill" : \(light),
      "fill-specializations" : [
        { "value" : \(light) },
        { "appearance" : "dark", "value" : \(solid(night)) }
      ],
      "groups" : [
        {
          "layers" : [
            {
              "name" : "mark",
              "image-name" : "mark.svg",
              "glass" : false,
              "fill-specializations" : [
                { "value" : \(dark) },
                { "appearance" : "dark", "value" : \(light) },
                { "appearance" : "tinted", "value" : \(white) }
              ]
            }
          ],
          "shadow" : { "kind" : "none", "opacity" : 0.5 },
          "specular" : false,
          "translucency" : { "enabled" : false, "value" : 0.5 }
        }
      ],
      "supported-platforms" : { "squares" : [ "macOS" ] }
    }
    """
    try json.write(to: doc.appendingPathComponent("icon.json"), atomically: true, encoding: .utf8)
    print("wrote: \(doc.path)")
}
