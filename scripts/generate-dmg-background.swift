#!/usr/bin/env swift
//
// generate-dmg-background.swift
//
// Produces scripts/dmg-background.png — the artwork shown behind the
// drag-to-install icons in the release DMG. Run once after editing this
// file; the PNG is then committed and reused by scripts/release.sh.
//
// Usage:
//   ./scripts/generate-dmg-background.swift [output-path]
//

import AppKit

let outputPath = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "scripts/dmg-background.png"

let canvas = NSSize(width: 600, height: 400)
let image = NSImage(size: canvas)
image.lockFocus()

// Soft cream background.
NSColor(calibratedRed: 0.98, green: 0.96, blue: 0.92, alpha: 1.0).setFill()
NSRect(origin: .zero, size: canvas).fill()

// Title.
let title = "Drag NekoRun into Applications"
let titleAttrs: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 22, weight: .medium),
    .foregroundColor: NSColor(calibratedWhite: 0.18, alpha: 1.0),
]
let titleSize = (title as NSString).size(withAttributes: titleAttrs)
(title as NSString).draw(
    at: NSPoint(x: (canvas.width - titleSize.width) / 2, y: 320),
    withAttributes: titleAttrs
)

// Arrow.
let arrowColor = NSColor(calibratedWhite: 0.35, alpha: 0.85)
arrowColor.setStroke()
arrowColor.setFill()

let arrowY: CGFloat = 200
let arrowStartX: CGFloat = 240
let arrowEndX: CGFloat = 360
let headLength: CGFloat = 18
let headHalfWidth: CGFloat = 12

let shaft = NSBezierPath()
shaft.move(to: NSPoint(x: arrowStartX, y: arrowY))
shaft.line(to: NSPoint(x: arrowEndX, y: arrowY))
shaft.lineWidth = 4
shaft.lineCapStyle = .round
shaft.stroke()

let head = NSBezierPath()
head.move(to: NSPoint(x: arrowEndX + headLength, y: arrowY))
head.line(to: NSPoint(x: arrowEndX, y: arrowY + headHalfWidth))
head.line(to: NSPoint(x: arrowEndX, y: arrowY - headHalfWidth))
head.close()
head.fill()

image.unlockFocus()

// Encode and write PNG.
guard
    let tiff = image.tiffRepresentation,
    let bitmap = NSBitmapImageRep(data: tiff),
    let png = bitmap.representation(using: .png, properties: [:])
else {
    FileHandle.standardError.write(Data("Failed to encode PNG\n".utf8))
    exit(1)
}
try png.write(to: URL(fileURLWithPath: outputPath))
print("Wrote \(outputPath)")
