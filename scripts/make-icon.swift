import AppKit
import Foundation
let destination = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
for size in [16, 32, 64, 128, 256, 512, 1024] {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    let scale = Double(size) / 1024
    let transform = NSAffineTransform(); transform.scale(by: scale); transform.concat()
    NSColor(calibratedRed: 0.13, green: 0.34, blue: 0.29, alpha: 1).setFill()
    NSBezierPath(roundedRect: NSRect(x: 55, y: 55, width: 914, height: 914), xRadius: 205, yRadius: 205).fill()
    NSColor(calibratedRed: 0.89, green: 0.97, blue: 0.91, alpha: 1).setStroke()
    let wave = NSBezierPath(); wave.lineWidth = 43; wave.lineCapStyle = .round; wave.lineJoinStyle = .round
    wave.move(to: NSPoint(x: 225, y: 510))
    for point in [(310,510),(365,680),(445,340),(535,740),(620,400),(680,510),(800,510)] { wave.line(to: NSPoint(x: point.0, y: point.1)) }
    wave.stroke()
    image.unlockFocus()
    let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
    let data = bitmap.representation(using: .png, properties: [:])!
    if size <= 512 { try data.write(to: destination.appendingPathComponent("icon_\(size)x\(size).png")) }
    if size >= 32 { let base = size / 2; try data.write(to: destination.appendingPathComponent("icon_\(base)x\(base)@2x.png")) }
}
