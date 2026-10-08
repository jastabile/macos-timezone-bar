// Renders the TimeZoneBar icon: scripts/make-icon.swift <size> <output.png>
import AppKit

let size = CGFloat(Double(CommandLine.arguments[1])!)
let out = CommandLine.arguments[2]
let s = size / 1024 // design on a 1024 grid

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size), bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                           bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext

func color(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(red: CGFloat(hex >> 16 & 0xff) / 255, green: CGFloat(hex >> 8 & 0xff) / 255, blue: CGFloat(hex & 0xff) / 255, alpha: a)
}

// Background: rounded square, deep indigo -> blue gradient.
let bg = CGPath(roundedRect: CGRect(x: 0, y: 0, width: size, height: size), cornerWidth: 230 * s, cornerHeight: 230 * s, transform: nil)
ctx.addPath(bg); ctx.clip()
let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [color(0x2B2F8F), color(0x3A7BFF)] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: 0), end: CGPoint(x: size, y: size), options: [])

// Clock face.
let center = CGPoint(x: 512 * s, y: 580 * s), r = 300 * s
ctx.setFillColor(color(0xFFFFFF))
ctx.fillEllipse(in: CGRect(x: center.x - r, y: center.y - r, width: 2 * r, height: 2 * r))
// Hour ticks.
ctx.setStrokeColor(color(0x2B2F8F, 0.55)); ctx.setLineCap(.round)
for i in 0..<12 {
    let a = CGFloat(i) * .pi / 6, long = i % 3 == 0
    ctx.setLineWidth((long ? 22 : 12) * s)
    let r1 = r - 40 * s, r2 = r - (long ? 95 : 75) * s
    ctx.move(to: CGPoint(x: center.x + r1 * sin(a), y: center.y + r1 * cos(a)))
    ctx.addLine(to: CGPoint(x: center.x + r2 * sin(a), y: center.y + r2 * cos(a)))
    ctx.strokePath()
}
// Hands at 9:00 ... hour hand at 9 (left), minute hand at 12 (up).
ctx.setStrokeColor(color(0x1E2160)); ctx.setLineWidth(40 * s)
ctx.move(to: center); ctx.addLine(to: CGPoint(x: center.x - 150 * s, y: center.y)); ctx.strokePath()
ctx.setLineWidth(28 * s)
ctx.move(to: center); ctx.addLine(to: CGPoint(x: center.x, y: center.y + 215 * s)); ctx.strokePath()
ctx.setFillColor(color(0x3A7BFF))
ctx.fillEllipse(in: CGRect(x: center.x - 34 * s, y: center.y - 34 * s, width: 68 * s, height: 68 * s))

// Day slider: night / working hours / night, with a thumb in the green.
let trackY = 165 * s, trackH = 64 * s, x0 = 150 * s, x1 = 874 * s
let track = CGRect(x: x0, y: trackY, width: x1 - x0, height: trackH)
ctx.saveGState()
ctx.addPath(CGPath(roundedRect: track, cornerWidth: trackH / 2, cornerHeight: trackH / 2, transform: nil)); ctx.clip()
let w = x1 - x0
for (from, to, c) in [(0.0, 9.0, color(0x8C7BFF)), (9.0, 18.0, color(0x34D17A)), (18.0, 24.0, color(0x8C7BFF))] {
    ctx.setFillColor(c)
    ctx.fill(CGRect(x: x0 + w * CGFloat(from / 24), y: trackY, width: w * CGFloat((to - from) / 24), height: trackH))
}
ctx.restoreGState()
let tx = x0 + w * 9.0 / 24 + 30 * s, tr = 58 * s
ctx.setFillColor(color(0xFFFFFF))
ctx.fillEllipse(in: CGRect(x: tx - tr, y: trackY + trackH / 2 - tr, width: 2 * tr, height: 2 * tr))
ctx.setStrokeColor(color(0x3A7BFF)); ctx.setLineWidth(18 * s)
ctx.strokeEllipse(in: CGRect(x: tx - tr + 9 * s, y: trackY + trackH / 2 - tr + 9 * s, width: 2 * tr - 18 * s, height: 2 * tr - 18 * s))

NSGraphicsContext.current = nil
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
