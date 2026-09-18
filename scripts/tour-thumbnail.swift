#!/usr/bin/env swift
//
// The YouTube thumbnail for the video tour: the club's colours, the five chapters, and two
// screens from the film itself.
//
//   swift -suppress-warnings scripts/tour-thumbnail.swift [out.jpg|out.png] [stills-dir]
//
// Laid out at 1280x720 and written at the screen's scale, so a Retina Mac gives 2560x1440 —
// YouTube's own recommendation, under its 2MB ceiling as a JPEG. Everything is drawn with
// AppKit, the same approach as scripts/tour-video.swift, so there is nothing to install.
//
import AppKit

let arguments = CommandLine.arguments
let out = URL(fileURLWithPath: arguments.count > 1 ? arguments[1] : ".dev/tour/tour-thumbnail.jpg")
let stills = URL(fileURLWithPath: arguments.count > 2 ? arguments[2] : ".dev/tour/screenshots")

let size = CGSize(width: 1280, height: 720)

enum Palette {
    static let dark = NSColor(srgbRed: 0.086, green: 0.125, blue: 0.090, alpha: 1)   // #16200E-ish
    static let mid = NSColor(srgbRed: 0.173, green: 0.227, blue: 0.176, alpha: 1)    // #2C3A2D
    static let sage = NSColor(srgbRed: 0.561, green: 0.635, blue: 0.541, alpha: 1)   // #8FA28A
    static let pale = NSColor(srgbRed: 0.780, green: 0.827, blue: 0.753, alpha: 1)   // #C7D3C0
    static let gold = NSColor(srgbRed: 0.784, green: 0.663, blue: 0.420, alpha: 1)   // #C8A96B
}

/// The five chapters, as short as they will go and still mean something at thumbnail size.
let chapters = [
    "Join a club",
    "Who can play",
    "Pick the side",
    "Score a T20",
    "The whole card",
]

func attributed(_ text: String, size: CGFloat, weight: NSFont.Weight = .regular,
                color: NSColor = .white, tracking: CGFloat = 0) -> NSAttributedString {
    NSAttributedString(string: text, attributes: [
        .font: NSFont.systemFont(ofSize: size, weight: weight),
        .foregroundColor: color,
        .kern: tracking,
    ])
}

func phone(_ name: String, in rect: NSRect, rotation: CGFloat) {
    guard let image = NSImage(contentsOf: stills.appendingPathComponent(name)) else { return }
    NSGraphicsContext.saveGraphicsState()
    let transform = NSAffineTransform()
    transform.translateX(by: rect.midX, yBy: rect.midY)
    transform.rotate(byDegrees: rotation)
    transform.translateX(by: -rect.midX, yBy: -rect.midY)
    transform.concat()

    let body = NSBezierPath(roundedRect: rect, xRadius: 30, yRadius: 30)
    NSColor.black.withAlphaComponent(0.45).setFill()
    body.fill()
    body.addClip()
    image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()

    // A rim, so the phone reads as a phone against the dark background.
    NSGraphicsContext.saveGraphicsState()
    let rim = NSAffineTransform()
    rim.translateX(by: rect.midX, yBy: rect.midY)
    rim.rotate(byDegrees: rotation)
    rim.translateX(by: -rect.midX, yBy: -rect.midY)
    rim.concat()
    Palette.pale.withAlphaComponent(0.5).setStroke()
    let edge = NSBezierPath(roundedRect: rect, xRadius: 30, yRadius: 30)
    edge.lineWidth = 3
    edge.stroke()
    NSGraphicsContext.restoreGraphicsState()
}

let image = NSImage(size: size)
image.lockFocus()

// Background: the film's canvas, with a sage glow behind the phones.
NSGradient(colors: [Palette.mid, Palette.dark])?
    .draw(in: NSRect(origin: .zero, size: size), angle: 290)
NSGradient(starting: Palette.sage.withAlphaComponent(0.30), ending: Palette.sage.withAlphaComponent(0))?
    .draw(in: NSRect(x: 700, y: -120, width: 760, height: 900), relativeCenterPosition: .zero)

// The two screens the film is mostly about: scoring, and the side that was picked.
phone("sel-01-board.png", in: NSRect(x: 790, y: 78, width: 250, height: 542), rotation: -7)
phone("t20-07-first-over.png", in: NSRect(x: 985, y: 40, width: 268, height: 580), rotation: 5)

// Brand
attributed("FISHERS", size: 34, weight: .heavy, color: .white, tracking: 6)
    .draw(at: NSPoint(x: 72, y: 612))
attributed("Club cricket, on a phone", size: 23, weight: .medium, color: Palette.pale)
    .draw(at: NSPoint(x: 74, y: 576))

// The headline, two lines, as large as fits.
attributed("A SEASON", size: 96, weight: .black, color: .white, tracking: -1)
    .draw(at: NSPoint(x: 68, y: 440))
attributed("ON A PHONE", size: 96, weight: .black, color: Palette.gold, tracking: -1)
    .draw(at: NSPoint(x: 68, y: 348))

// A rule, then the five chapters as the reason to click.
Palette.sage.withAlphaComponent(0.55).setFill()
NSRect(x: 72, y: 318, width: 560, height: 3).fill()

for (index, chapter) in chapters.enumerated() {
    let y = 252.0 - Double(index) * 46
    let badge = NSRect(x: 72, y: y - 6, width: 38, height: 38)
    Palette.sage.withAlphaComponent(0.22).setFill()
    NSBezierPath(roundedRect: badge, xRadius: 10, yRadius: 10).fill()
    attributed("\(index + 1)", size: 22, weight: .bold, color: Palette.gold)
        .draw(at: NSPoint(x: badge.midX - 6, y: y + 2))
    attributed(chapter, size: 30, weight: .semibold, color: .white)
        .draw(at: NSPoint(x: 128, y: y))
}

attributed("20 minutes · every screen, in order", size: 22, weight: .medium,
           color: Palette.pale.withAlphaComponent(0.85))
    .draw(at: NSPoint(x: 72, y: 24))

image.unlockFocus()

// YouTube takes a thumbnail of up to 2MB, and a PNG of this at Retina scale is nearly twice
// that; a JPEG of the same picture is a few hundred kilobytes. The extension decides.
let wantsJPEG = ["jpg", "jpeg"].contains(out.pathExtension.lowercased())
guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: wantsJPEG ? .jpeg : .png,
                                   properties: wantsJPEG ? [.compressionFactor: 0.92] : [:]) else {
    FileHandle.standardError.write("could not render the thumbnail\n".data(using: .utf8)!)
    exit(1)
}
try FileManager.default.createDirectory(at: out.deletingLastPathComponent(),
                                        withIntermediateDirectories: true)
try png.write(to: out)
let bytes = Double(png.count) / 1024
print(String(format: "%@ — %dx%d, %.0fKB", out.path, rep.pixelsWide, rep.pixelsHigh, bytes))
