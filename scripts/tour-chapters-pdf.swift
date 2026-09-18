#!/usr/bin/env swift
//
// The contents sheet that goes out with the Fishers video tour: every chapter and every caption, against
// the second it lands on, so a customer can open the film at the part they care about.
//
//   swift -suppress-warnings scripts/tour-chapters-pdf.swift <index.json> <out.pdf>
//
// The index is written by scripts/tour-video.swift (`indexFile` in the spec, or `--index-only` to
// work out the timings without exporting the video again), so the timestamps here are the video's
// own arithmetic rather than a second copy of it.
//
import AppKit
import CoreGraphics
import Foundation

// MARK: - Index

struct Index: Decodable {
    var title: String
    var subtitle: String
    var footer: String
    var video: String
    /// When the tour was filmed, so a sheet regenerated later still dates the recording.
    var recordedAt: Double?
    var duration: Double
    var width: Int
    var height: Int
    var brandMark: String
    var chapters: [Chapter]
}

struct Chapter: Decodable {
    var number: Int
    var title: String
    var subtitle: String
    var cardAt: Double
    var startsAt: Double
    var endsAt: Double
    var beats: [BeatRow]
}

struct BeatRow: Decodable {
    var at: Double
    var text: String
}

let arguments = CommandLine.arguments
guard arguments.count > 2 else {
    FileHandle.standardError.write("usage: tour-chapters-pdf.swift <index.json> <out.pdf>\n"
        .data(using: .utf8)!)
    exit(2)
}
let index = try JSONDecoder().decode(Index.self, from: Data(contentsOf: URL(fileURLWithPath: arguments[1])))
let outURL = URL(fileURLWithPath: arguments[2])

// MARK: - Page

enum Page {
    static let size = CGSize(width: 595, height: 842)      // A4 portrait, in points
    static let margin: CGFloat = 52
    static let top: CGFloat = 64
    static let bottom: CGFloat = 58
    static var contentWidth: CGFloat { size.width - margin * 2 }
    static let stampColumn: CGFloat = 52                   // width of the timestamp column
    static let stampGap: CGFloat = 14
}

/// Ink on paper, in the club's colours: a deep sage for headings and the sage the app uses for
/// the timestamps, dark enough to read on white.
enum Ink {
    static let navy = NSColor(srgbRed: 0.106, green: 0.153, blue: 0.110, alpha: 1)   // #1B271C
    static let teal = NSColor(srgbRed: 0.318, green: 0.404, blue: 0.310, alpha: 1)   // sage, darkened
    static let body = NSColor(srgbRed: 0.161, green: 0.208, blue: 0.259, alpha: 1)
    static let muted = NSColor(srgbRed: 0.427, green: 0.475, blue: 0.529, alpha: 1)
    static let rule = NSColor(srgbRed: 0.851, green: 0.882, blue: 0.906, alpha: 1)
}

func text(_ string: String, size: CGFloat, weight: NSFont.Weight = .regular, color: NSColor = Ink.body,
          lineHeight: CGFloat = 1.3, tracking: CGFloat = 0, monospaced: Bool = false) -> NSAttributedString {
    let paragraph = NSMutableParagraphStyle()
    paragraph.lineSpacing = size * (lineHeight - 1)
    paragraph.lineBreakMode = .byWordWrapping
    let font = monospaced ? NSFont.monospacedDigitSystemFont(ofSize: size, weight: weight)
                          : NSFont.systemFont(ofSize: size, weight: weight)
    return NSAttributedString(string: string, attributes: [
        .font: font, .foregroundColor: color, .kern: tracking, .paragraphStyle: paragraph,
    ])
}

extension NSAttributedString {
    func height(fittingWidth width: CGFloat) -> CGFloat {
        boundingRect(with: CGSize(width: width, height: .greatestFiniteMagnitude),
                     options: [.usesLineFragmentOrigin, .usesFontLeading]).height.rounded(.up)
    }

    /// Draws with the first line's top at `top`, measured from the top of the page.
    @discardableResult
    func draw(x: CGFloat, top: CGFloat, width: CGFloat) -> CGFloat {
        let used = height(fittingWidth: width)
        draw(with: CGRect(x: x, y: Page.size.height - top - used, width: width, height: used),
             options: [.usesLineFragmentOrigin, .usesFontLeading])
        return used
    }
}

/// Round once, then split. Rounding the seconds but truncating the minutes turns 15:59.5 into
/// 15:00, which reads as a chapter running backwards.
func stamp(_ seconds: Double) -> String {
    let whole = Int(seconds.rounded())
    return String(format: "%d:%02d", whole / 60, whole % 60)
}

func mark() -> NSImage? {
    guard !index.brandMark.isEmpty, FileManager.default.fileExists(atPath: index.brandMark) else { return nil }
    return NSImage(contentsOfFile: index.brandMark)
}

// MARK: - Drawing

var mediaBox = CGRect(origin: .zero, size: Page.size)
guard let pdf = CGContext(outURL as CFURL, mediaBox: &mediaBox, nil) else {
    fatalError("could not write \(outURL.path)")
}

var page = 0
var cursor: CGFloat = 0          // how far down the page we are
/// The chapter being listed, repeated at the top of the page when one spills over.
var continuing: String?

func beginPage() {
    pdf.beginPDFPage(nil)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: pdf, flipped: false)
    page += 1
    cursor = Page.top
    if let continuing {
        cursor += text("\(continuing) (continued)", size: 10, weight: .semibold, color: Ink.muted)
            .draw(x: Page.margin, top: cursor, width: Page.contentWidth) + 14
    }
}

func footer() {
    let line = text("\(index.title) · video tour contents · page \(page)", size: 8.5, color: Ink.muted)
    line.draw(x: Page.margin, top: Page.size.height - Page.bottom + 18, width: Page.contentWidth)
    Ink.rule.setFill()
    NSRect(x: Page.margin, y: Page.bottom, width: Page.contentWidth, height: 0.5).fill()
}

func endPage() {
    footer()
    NSGraphicsContext.restoreGraphicsState()
    pdf.endPDFPage()
}

/// Starts a new page when what comes next will not fit on this one.
func room(for height: CGFloat) {
    if cursor + height > Page.size.height - Page.bottom - 24 {
        endPage()
        beginPage()
    }
}

beginPage()

// Masthead
if let mark = mark() {
    let box = NSRect(x: Page.margin, y: Page.size.height - Page.top - 54, width: 54, height: 54)
    NSGraphicsContext.saveGraphicsState()
    let clip = box.insetBy(dx: box.width * 0.022, dy: box.height * 0.022)
    NSBezierPath(roundedRect: clip, xRadius: clip.width * 0.2237, yRadius: clip.width * 0.2237).setClip()
    mark.draw(in: box)
    NSGraphicsContext.restoreGraphicsState()
}
let mastheadX = Page.margin + (mark() == nil ? 0 : 70)
let mastheadWidth = Page.size.width - Page.margin - mastheadX
text(index.title, size: 21, weight: .bold, color: Ink.navy).draw(x: mastheadX, top: Page.top + 2, width: mastheadWidth)
text(index.subtitle, size: 11, color: Ink.teal).draw(x: mastheadX, top: Page.top + 30, width: mastheadWidth)
cursor = Page.top + 74

Ink.navy.setFill()
NSRect(x: Page.margin, y: Page.size.height - cursor, width: Page.contentWidth, height: 1.5).fill()
cursor += 22

cursor += text("Video tour — contents", size: 26, weight: .bold, color: Ink.navy)
    .draw(x: Page.margin, top: cursor, width: Page.contentWidth) + 10

let minutes = Int(index.duration) / 60, seconds = Int(index.duration) % 60
let formatter = DateFormatter()
formatter.dateFormat = "d MMMM yyyy"
let recorded = index.recordedAt.map { Date(timeIntervalSince1970: $0) } ?? Date()
let facts = "\(index.chapters.count) chapters · \(minutes) min \(seconds) sec · "
    + "\(index.width)×\(index.height) H.264 · \(index.video) · recorded \(formatter.string(from: recorded))"
cursor += text(facts, size: 9.5, color: Ink.muted).draw(x: Page.margin, top: cursor, width: Page.contentWidth) + 16

cursor += text("Each line is a screen in the film, at the time it appears. The timestamps are the "
               + "video's own, so they can be typed straight into the player.",
               size: 10.5, color: Ink.body).draw(x: Page.margin, top: cursor, width: Page.contentWidth) + 26

// Chapters
for chapter in index.chapters {
    let heading = text("\(chapter.number).  \(chapter.title)", size: 14, weight: .semibold, color: Ink.navy)
    let subtitle = chapter.subtitle.isEmpty ? nil : text(chapter.subtitle, size: 10, color: Ink.muted)
    let headingHeight = heading.height(fittingWidth: Page.contentWidth - Page.stampColumn - Page.stampGap)
        + (subtitle?.height(fittingWidth: Page.contentWidth - Page.stampColumn - Page.stampGap) ?? 0)
    // Keep a chapter's heading with at least its first caption.
    room(for: headingHeight + 46)

    continuing = "\(chapter.number).  \(chapter.title)"
    let bodyX = Page.margin + Page.stampColumn + Page.stampGap
    let bodyWidth = Page.contentWidth - Page.stampColumn - Page.stampGap
    text(stamp(chapter.cardAt), size: 11, weight: .bold, color: Ink.teal, monospaced: true)
        .draw(x: Page.margin, top: cursor + 2, width: Page.stampColumn)
    var used = heading.draw(x: bodyX, top: cursor, width: bodyWidth)
    if let subtitle { used += subtitle.draw(x: bodyX, top: cursor + used + 2, width: bodyWidth) + 2 }
    cursor += used + 10

    for beat in chapter.beats {
        let line = text(beat.text, size: 9.5, color: Ink.body, lineHeight: 1.28)
        let height = line.height(fittingWidth: bodyWidth)
        room(for: height + 8)
        text(stamp(beat.at), size: 9, color: Ink.teal, monospaced: true)
            .draw(x: Page.margin, top: cursor + 1, width: Page.stampColumn)
        line.draw(x: bodyX, top: cursor, width: bodyWidth)
        cursor += height + 7
    }
    continuing = nil
    cursor += 14
    // A rule between chapters, but not under the last one or at the foot of a page.
    if chapter.number < index.chapters.count, cursor + 20 < Page.size.height - Page.bottom - 24 {
        Ink.rule.setFill()
        NSRect(x: Page.margin, y: Page.size.height - cursor + 6, width: Page.contentWidth, height: 0.5).fill()
        cursor += 16
    }
}

// Closing note, on this page if it fits.
let note = text(index.footer, size: 9, color: Ink.muted)
room(for: note.height(fittingWidth: Page.contentWidth) + 12)
cursor += note.draw(x: Page.margin, top: cursor + 8, width: Page.contentWidth)

endPage()
pdf.closePDF()

print("\(outURL.path) — \(index.chapters.count) chapters, "
      + "\(index.chapters.reduce(0) { $0 + $1.beats.count }) entries, \(page) pages")
