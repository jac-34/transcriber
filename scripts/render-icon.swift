// Usage: swift scripts/render-icon.swift out.png
// Draws a 1024x1024 rounded square with a gradient and white waveform bars.
import AppKit

let size = 1024.0
let out = CommandLine.arguments[1]
let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()
let ctx = NSGraphicsContext.current!.cgContext

let rect = CGRect(x: 0, y: 0, width: size, height: size).insetBy(dx: size * 0.06, dy: size * 0.06)
let path = CGPath(roundedRect: rect, cornerWidth: size * 0.22, cornerHeight: size * 0.22, transform: nil)
ctx.addPath(path)
ctx.clip()
let colors = [CGColor(red: 0.07, green: 0.42, blue: 0.55, alpha: 1), CGColor(red: 0.10, green: 0.66, blue: 0.62, alpha: 1)] as CFArray
let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])!
ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: size), end: CGPoint(x: size, y: 0), options: [])

// Waveform bars
let heights: [CGFloat] = [0.18, 0.32, 0.52, 0.72, 0.46, 0.60, 0.30, 0.20]
let barWidth = size * 0.055
let gap = size * 0.035
let totalWidth = CGFloat(heights.count) * barWidth + CGFloat(heights.count - 1) * gap
var x = (size - totalWidth) / 2
ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.95))
for h in heights {
    let barHeight = size * h
    let bar = CGRect(x: x, y: (size - barHeight) / 2, width: barWidth, height: barHeight)
    ctx.addPath(CGPath(roundedRect: bar, cornerWidth: barWidth / 2, cornerHeight: barWidth / 2, transform: nil))
    ctx.fillPath()
    x += barWidth + gap
}
image.unlockFocus()

let tiff = image.tiffRepresentation!
let png = NSBitmapImageRep(data: tiff)!.representation(using: .png, properties: [:])!
try! png.write(to: URL(fileURLWithPath: out))
