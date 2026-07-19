#!/usr/bin/env swift
// Generates AppIcon.icns: teal squircle, viewfinder crop brackets, and a
// scissors mark. Usage: swift make-icon.swift  (run from the trim dir)

import AppKit
import Foundation

let here    = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let iconset = here.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

let sizes: [(String, Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]

func makePNG(size px: Int) -> Data? {
    let pf = CGFloat(px)
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 32)
    else { return nil }
    rep.size = NSSize(width: pf, height: pf)

    NSGraphicsContext.saveGraphicsState()
    defer { NSGraphicsContext.restoreGraphicsState() }
    guard let ctx = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
    NSGraphicsContext.current = ctx

    // Squircle background: crisp teal gradient.
    let radius = pf * 0.225
    let squircle = NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: pf, height: pf),
                                xRadius: radius, yRadius: radius)
    squircle.addClip()
    let grad = NSGradient(colors: [
        NSColor(red: 0.16, green: 0.74, blue: 0.65, alpha: 1),
        NSColor(red: 0.02, green: 0.38, blue: 0.46, alpha: 1),
    ])!
    grad.draw(in: NSRect(x: 0, y: 0, width: pf, height: pf), angle: -90)

    let white = NSColor.white
    let lineW = max(1.5, pf * 0.052)

    // Viewfinder crop brackets in all four corners of an inner frame.
    let inset = pf * 0.20
    let arm = pf * 0.13
    let frame = NSRect(x: inset, y: inset, width: pf - 2 * inset, height: pf - 2 * inset)
    let brackets = NSBezierPath()
    // bottom-left
    brackets.move(to: NSPoint(x: frame.minX, y: frame.minY + arm))
    brackets.line(to: NSPoint(x: frame.minX, y: frame.minY))
    brackets.line(to: NSPoint(x: frame.minX + arm, y: frame.minY))
    // bottom-right
    brackets.move(to: NSPoint(x: frame.maxX - arm, y: frame.minY))
    brackets.line(to: NSPoint(x: frame.maxX, y: frame.minY))
    brackets.line(to: NSPoint(x: frame.maxX, y: frame.minY + arm))
    // top-right
    brackets.move(to: NSPoint(x: frame.maxX, y: frame.maxY - arm))
    brackets.line(to: NSPoint(x: frame.maxX, y: frame.maxY))
    brackets.line(to: NSPoint(x: frame.maxX - arm, y: frame.maxY))
    // top-left
    brackets.move(to: NSPoint(x: frame.minX + arm, y: frame.maxY))
    brackets.line(to: NSPoint(x: frame.minX, y: frame.maxY))
    brackets.line(to: NSPoint(x: frame.minX, y: frame.maxY - arm))
    brackets.lineWidth = lineW
    brackets.lineCapStyle = .round
    brackets.lineJoinStyle = .round
    white.withAlphaComponent(0.92).setStroke()
    brackets.stroke()

    // Scissors: two blades crossing at a pivot, two ring handles below.
    let cx = pf * 0.5
    let pivotY = pf * 0.52
    let bladeTipY = pf * 0.70
    let bladeSpread = pf * 0.105
    let handleY = pf * 0.375
    let handleSpread = pf * 0.10
    let handleR = pf * 0.058

    let blades = NSBezierPath()
    blades.move(to: NSPoint(x: cx - handleSpread, y: handleY + handleR))
    blades.line(to: NSPoint(x: cx + bladeSpread, y: bladeTipY))
    blades.move(to: NSPoint(x: cx + handleSpread, y: handleY + handleR))
    blades.line(to: NSPoint(x: cx - bladeSpread, y: bladeTipY))
    blades.lineWidth = lineW
    blades.lineCapStyle = .round
    white.setStroke()
    blades.stroke()

    for dx in [-handleSpread, handleSpread] {
        let ring = NSBezierPath(ovalIn: NSRect(
            x: cx + dx - handleR, y: handleY - handleR,
            width: handleR * 2, height: handleR * 2))
        ring.lineWidth = lineW * 0.8
        ring.stroke()
    }

    let pivotR = max(1, pf * 0.026)
    let pivot = NSBezierPath(ovalIn: NSRect(
        x: cx - pivotR, y: pivotY - pivotR, width: pivotR * 2, height: pivotR * 2))
    white.setFill()
    pivot.fill()

    return rep.representation(using: .png, properties: [:])
}

for (name, px) in sizes {
    guard let data = makePNG(size: px) else { continue }
    try data.write(to: iconset.appendingPathComponent("\(name).png"))
}

let proc = Process()
proc.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
proc.arguments = ["-c", "icns", iconset.path, "-o", here.appendingPathComponent("AppIcon.icns").path]
try proc.run()
proc.waitUntilExit()
print("Wrote AppIcon.icns")
