#!/usr/bin/env swift
//
// Turns a Simulator screen recording of the Fishers tour into a presentable video: the phone
// screen framed on a branded canvas, a chapter card per part, and a caption per beat.
//
//   swift -suppress-warnings scripts/tour-video.swift <spec.json>
//
// The spec is written by scripts/cut-tour-video.sh from the markers the UI test prints, so the
// captions line up with what the recording was doing at that moment. Everything is drawn with
// AVFoundation and Core Graphics — no ffmpeg, nothing to install.
//
// Ported from the WSLCRM tour builder; the shape of the spec is the same, the colours are the
// club's: sage, cream and the gold of a trophy.
//
// Spec shape (times are epoch seconds, as printed by the test):
//   { "video": …, "out": …, "recordStart": …, "title": …, "subtitle": …, "brandMark": …,
//     "footer": …, "sections": [ { "title": …, "subtitle": …, "start": …, "end": …,
//                                  "beats": [ { "at": …, "text": … } ] } ] }
//
import AVFoundation
import AppKit
import CoreMedia

// MARK: - Spec

struct Spec: Decodable {
    var video: String
    var out: String
    var recordStart: Double
    var title: String
    var subtitle: String
    var brandMark: String?
    var footer: String?
    var chaptersFile: String?
    /// Where to write the timestamped contents — every chapter and every caption, at the second
    /// each one lands on in the finished video. scripts/tour-chapters-pdf.swift reads it.
    var indexFile: String?
    var align: [AlignSample]?
    var sections: [Section]
}

struct Section: Decodable {
    var title: String
    var subtitle: String?
    var start: Double
    var end: Double
    var beats: [Beat]
    /// Stretches of the recording to drop — a wait the tour sat through, such as a faked outage.
    var cuts: [Cut]?
}

struct Cut: Decodable {
    var from: Double
    var to: Double
}

/// A screenshot the tour took, and the moment it says it took it. Comparing the two against the
/// recording measures how long the recorder took to start, so the captions land on the frames
/// they describe rather than a second either side.
struct AlignSample: Decodable {
    var at: Double
    var image: String
}

struct Beat: Decodable {
    var at: Double
    var text: String
    var id: String?
}

// MARK: - Canvas

enum Layout {
    static let canvas = CGSize(width: 1920, height: 1080)
    static let phoneInset: CGFloat = 64      // top and bottom margin around the phone
    static let phoneLeft: CGFloat = 96
    static let panelGap: CGFloat = 80
    static let panelRight: CGFloat = 88
    static let cardSeconds = 3.0             // chapter card before each section
    static let leadSeconds = 1.0             // footage kept before a section's first beat
    static let tailSeconds = 1.6             // …and after its last
    static let introSeconds = 5.0
    static let outroSeconds = 4.0
}

/// The club's four colours, as the app uses them: sage #8FA28A on the deep sage #2C3A2D the
/// dark theme is built from, with the gold used for an award kept for the kickers.
enum Palette {
    static let navy = NSColor(srgbRed: 0.106, green: 0.153, blue: 0.110, alpha: 1)      // #1B271C
    static let navyLight = NSColor(srgbRed: 0.173, green: 0.227, blue: 0.176, alpha: 1) // #2C3A2D
    static let teal = NSColor(srgbRed: 0.561, green: 0.635, blue: 0.541, alpha: 1)      // #8FA28A sage
    static let white = NSColor.white
    static let muted = NSColor(srgbRed: 0.780, green: 0.827, blue: 0.753, alpha: 1)     // #C7D3C0
    static let faint = NSColor(srgbRed: 0.545, green: 0.608, blue: 0.529, alpha: 1)
}

// MARK: - Drawing helpers

/// Draws into a bitmap and hands back a CGImage, so every overlay is a plain image layer:
/// no CATextLayer, whose vertical alignment differs between AppKit and the video renderer.
func image(size: CGSize, _ draw: (CGContext) -> Void) -> CGImage {
    let width = Int(size.width.rounded()), height = Int(size.height.rounded())
    let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                            bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue)!
    // AppKit draws with the origin at the bottom left, like the layer tree this ends up in.
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
    draw(context)
    NSGraphicsContext.restoreGraphicsState()
    return context.makeImage()!
}

func attributed(_ text: String, size: CGFloat, weight: NSFont.Weight = .regular,
                color: NSColor = Palette.white, lineHeight: CGFloat = 1.25,
                tracking: CGFloat = 0, alignment: NSTextAlignment = .left) -> NSAttributedString {
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = alignment
    paragraph.lineSpacing = size * (lineHeight - 1)
    paragraph.lineBreakMode = .byWordWrapping
    return NSAttributedString(string: text, attributes: [
        .font: NSFont.systemFont(ofSize: size, weight: weight),
        .foregroundColor: color,
        .kern: tracking,
        .paragraphStyle: paragraph,
    ])
}

extension NSAttributedString {
    func height(fittingWidth width: CGFloat) -> CGFloat {
        boundingRect(with: CGSize(width: width, height: .greatestFiniteMagnitude),
                     options: [.usesLineFragmentOrigin, .usesFontLeading]).height.rounded(.up)
    }

    /// Draws with the text's first line at `top`, measuring from the top of the box.
    func drawFromTop(in rect: CGRect) {
        let used = height(fittingWidth: rect.width)
        draw(with: CGRect(x: rect.minX, y: rect.maxY - used, width: rect.width, height: used),
             options: [.usesLineFragmentOrigin, .usesFontLeading])
    }
}

func backgroundGradient(in context: CGContext, size: CGSize) {
    let gradient = NSGradient(colors: [Palette.navyLight, Palette.navy],
                             atLocations: [0, 1], colorSpace: .sRGB)!
    gradient.draw(in: NSRect(origin: .zero, size: size), angle: -78)
    // A soft teal wash behind the phone, the way the brand mark's curve sits under the wordmark.
    // The rect covers the whole canvas — a smaller one leaves a visible edge where it stops.
    let glow = NSGradient(starting: Palette.teal.withAlphaComponent(0.16),
                          ending: Palette.teal.withAlphaComponent(0))!
    glow.draw(in: NSRect(origin: .zero, size: size), relativeCenterPosition: NSPoint(x: -0.55, y: -0.1))
}

func loadMark(_ path: String?) -> NSImage? {
    guard let path, FileManager.default.fileExists(atPath: path) else { return nil }
    return NSImage(contentsOfFile: path)
}

/// The brand mark is a square app icon with opaque corners, so it is drawn through the same
/// rounded mask iOS uses rather than as a white tile on the dark canvas.
func draw(mark: NSImage, in rect: NSRect) {
    NSGraphicsContext.saveGraphicsState()
    let radius = rect.width * 0.2237
    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).setClip()
    mark.draw(in: rect)
    NSGraphicsContext.restoreGraphicsState()
}

// MARK: - Spec in, layout out

let arguments = CommandLine.arguments
// --index-only works out the timeline and writes the contents without exporting, which takes
// seconds rather than minutes: the same arithmetic, so the timestamps are the video's own.
let indexOnly = arguments.contains("--index-only")
guard let specPath = arguments.dropFirst().first(where: { !$0.hasPrefix("--") }) else {
    FileHandle.standardError.write("usage: tour-video.swift <spec.json> [--index-only]\n".data(using: .utf8)!)
    exit(2)
}
let spec = try JSONDecoder().decode(Spec.self, from: Data(contentsOf: URL(fileURLWithPath: specPath)))
let mark = loadMark(spec.brandMark)

let sourceURL = URL(fileURLWithPath: spec.video)
let asset = AVURLAsset(url: sourceURL)

struct SourceInfo {
    var duration: Double
    var track: AVAssetTrack
    var size: CGSize
    var transform: CGAffineTransform
    var frameRate: Float
}

func loadSource() async throws -> SourceInfo {
    let duration = try await asset.load(.duration)
    guard let track = try await asset.loadTracks(withMediaType: .video).first else {
        throw NSError(domain: "tour-video", code: 1,
                      userInfo: [NSLocalizedDescriptionKey: "no video track in \(spec.video)"])
    }
    let (size, transform, rate) = try await track.load(.naturalSize, .preferredTransform, .nominalFrameRate)
    return SourceInfo(duration: CMTimeGetSeconds(duration), track: track, size: size,
                      transform: transform, frameRate: rate)
}

let source = try runBlocking { try await loadSource() }

// MARK: - Lining the captions up with the footage

/// A small grey thumbnail, for comparing a frame with a screenshot cheaply.
func thumbnail(_ cgImage: CGImage, width: Int = 24, height: Int = 52) -> [Double] {
    let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                            bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(),
                            bitmapInfo: CGImageAlphaInfo.none.rawValue)!
    context.interpolationQuality = .low
    context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
    let pixels = context.data!.bindMemory(to: UInt8.self, capacity: width * height)
    return (0..<(width * height)).map { Double(pixels[$0]) }
}

func difference(_ a: [Double], _ b: [Double]) -> Double {
    guard a.count == b.count, !a.isEmpty else { return .infinity }
    return zip(a, b).reduce(0) { $0 + abs($1.0 - $1.1) } / Double(a.count)
}

/// How far each screenshot sits from where the estimated start put it in the recording — negative
/// when the recorder took a moment to begin capturing, which is the usual case. Searched per
/// sample and taken as the median, so one mistimed screen cannot drag the whole video off.
func measuredLag(_ samples: [AlignSample], recordStart: Double) async throws -> Double? {
    let generator = AVAssetImageGenerator(asset: asset)
    generator.requestedTimeToleranceBefore = .zero
    generator.requestedTimeToleranceAfter = .zero
    generator.appliesPreferredTrackTransform = true
    var lags: [Double] = []
    for sample in samples {
        guard let shot = NSImage(contentsOfFile: sample.image)?
            .cgImage(forProposedRect: nil, context: nil, hints: nil) else { continue }
        let wanted = thumbnail(shot)
        let nominal = sample.at - recordStart
        func search(_ steps: StrideThrough<Double>) async -> (lag: Double, difference: Double)? {
            var best: (lag: Double, difference: Double)?
            for step in steps {
                let moment = nominal + step
                guard moment >= 0, moment <= source.duration else { continue }
                guard let frame = try? await generator.image(at: CMTime(seconds: moment,
                                                                        preferredTimescale: 600)).image
                else { continue }
                let score = difference(thumbnail(frame), wanted)
                if best == nil || score < best!.difference { best = (step, score) }
            }
            return best
        }
        // Coarse first, so a recorder that took its time to start is still found, then fine around
        // it — a frame-accurate seek is expensive on a twenty-minute file.
        guard let coarse = await search(stride(from: -8.0, through: 8.0, by: 1.0)) else { continue }
        let best = await search(stride(from: coarse.lag - 0.9, through: coarse.lag + 0.9, by: 0.1))
        // A screen the recording never showed (a sheet that had already gone, say) matches
        // nothing; leave those out rather than let them pull the median around.
        if let best, best.difference < 12 { lags.append(best.lag) }
    }
    guard lags.count >= 3 else { return nil }
    return lags.sorted()[lags.count / 2]
}

var recordStart = spec.recordStart
if let samples = spec.align, !samples.isEmpty {
    if let lag = try runBlocking({ try await measuredLag(samples, recordStart: spec.recordStart) }) {
        // A screenshot taken at S was found `lag` seconds from where the estimate put it, so the
        // recording really began `lag` seconds the other side of that estimate.
        recordStart -= lag
        print(String(format: "lined up against %d screenshots: the recording began %.1fs later than the estimate",
                     samples.count, -lag))
    } else {
        FileHandle.standardError.write(
            "could not line the captions up against the screenshots; using the recorder's own start\n"
                .data(using: .utf8)!)
    }
}

/// A run of footage taken straight from the recording.
struct Piece {
    var sourceStart: Double      // seconds into the recording
    var duration: Double
    var compStart: Double        // seconds into the finished video
}

/// One section's footage, placed on the finished timeline.
struct Placed {
    var section: Section
    var pieces: [Piece]
    var cardStart: Double
    var footageStart: Double
    var footageEnd: Double

    /// Where a moment in the recording ended up in the finished video. A moment inside a cut
    /// lands at the start of the next piece, which is where the tour picks up again.
    func finishedTime(forSource moment: Double) -> Double {
        for piece in pieces {
            if moment < piece.sourceStart { return piece.compStart }
            if moment <= piece.sourceStart + piece.duration {
                return piece.compStart + (moment - piece.sourceStart)
            }
        }
        return footageEnd
    }
}

let timeScale: CMTimeScale = 600
func time(_ seconds: Double) -> CMTime { CMTime(seconds: max(0, seconds), preferredTimescale: timeScale) }

var placed: [Placed] = []
var cursor = Layout.introSeconds
for section in spec.sections {
    let firstBeat = section.beats.first?.at ?? section.start
    let lastBeat = section.beats.last?.at ?? section.end
    let rawStart = (min(section.start, firstBeat) - recordStart) - Layout.leadSeconds
    let rawEnd = (max(section.end, lastBeat) - recordStart) + Layout.tailSeconds
    let start = max(0, rawStart)
    let end = min(source.duration, rawEnd)
    guard end - start > 0.5 else {
        FileHandle.standardError.write("skipping \"\(section.title)\": no footage in range\n".data(using: .utf8)!)
        continue
    }
    // Take the cuts out of the section, leaving the pieces either side of each one.
    var spans: [(Double, Double)] = [(start, end)]
    for cut in (section.cuts ?? []).sorted(by: { $0.from < $1.from }) {
        let from = cut.from - recordStart, to = cut.to - recordStart
        spans = spans.flatMap { span -> [(Double, Double)] in
            guard to > span.0, from < span.1 else { return [span] }
            return [(span.0, min(span.1, from)), (max(span.0, to), span.1)].filter { $0.1 - $0.0 > 0.4 }
        }
    }
    let footageStart = cursor + Layout.cardSeconds
    var at = footageStart
    var pieces: [Piece] = []
    for span in spans {
        pieces.append(Piece(sourceStart: span.0, duration: span.1 - span.0, compStart: at))
        at += span.1 - span.0
    }
    guard !pieces.isEmpty else { continue }
    placed.append(Placed(section: section, pieces: pieces, cardStart: cursor,
                         footageStart: footageStart, footageEnd: at))
    cursor = at
}
guard !placed.isEmpty else { fatalError("no sections with footage — nothing to build") }
let total = cursor + Layout.outroSeconds

// MARK: - Composition

let composition = AVMutableComposition()
let videoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)!

// The intro and the chapter cards are gaps in the track: the background shows through and the card
// is drawn over it, so no still frames have to be generated and muxed in. Inserting footage past
// the end of the track leaves the gap implicitly; the outro is an empty range on the end.
var footageRanges: [CMTimeRange] = []
for piece in placed.flatMap(\.pieces) {
    let at = time(piece.compStart)
    try videoTrack.insertTimeRange(
        CMTimeRange(start: time(piece.sourceStart), duration: time(piece.duration)),
        of: source.track, at: at)
    footageRanges.append(CMTimeRange(start: at, duration: time(piece.duration)))
}
composition.insertEmptyTimeRange(CMTimeRange(start: time(cursor), duration: time(Layout.outroSeconds)))

// Where the phone screen sits on the canvas.
let phoneHeight = Layout.canvas.height - Layout.phoneInset * 2
let phoneScale = phoneHeight / source.size.height
let phoneWidth = (source.size.width * phoneScale).rounded()
let phoneFrame = CGRect(x: Layout.phoneLeft, y: Layout.phoneInset, width: phoneWidth, height: phoneHeight)
let panelX = phoneFrame.maxX + Layout.panelGap
let panelWidth = Layout.canvas.width - panelX - Layout.panelRight

let videoComposition = AVMutableVideoComposition()
videoComposition.renderSize = Layout.canvas
videoComposition.frameDuration = CMTime(value: 1, timescale: 30)
videoComposition.renderScale = 1

var instructions: [AVMutableVideoCompositionInstruction] = []
func gap(_ range: CMTimeRange) {
    guard range.duration.seconds > 0.001 else { return }
    let instruction = AVMutableVideoCompositionInstruction()
    instruction.timeRange = range
    instruction.backgroundColor = Palette.navy.cgColor
    instruction.layerInstructions = []
    instructions.append(instruction)
}
var previousEnd = CMTime.zero
for range in footageRanges {
    gap(CMTimeRange(start: previousEnd, duration: range.start - previousEnd))
    let instruction = AVMutableVideoCompositionInstruction()
    instruction.timeRange = range
    instruction.backgroundColor = Palette.navy.cgColor
    let layer = AVMutableVideoCompositionLayerInstruction(assetTrack: videoTrack)
    // Video composition space has its origin at the top left, so the phone's y is measured down.
    let topY = Layout.canvas.height - phoneFrame.maxY
    layer.setTransform(source.transform
        .concatenating(CGAffineTransform(scaleX: phoneScale, y: phoneScale))
        .concatenating(CGAffineTransform(translationX: phoneFrame.minX, y: topY)), at: range.start)
    instruction.layerInstructions = [layer]
    instructions.append(instruction)
    previousEnd = range.end
}
gap(CMTimeRange(start: previousEnd, duration: time(total) - previousEnd))
videoComposition.instructions = instructions

// MARK: - Overlays

let parent = CALayer()
parent.frame = CGRect(origin: .zero, size: Layout.canvas)
parent.backgroundColor = Palette.navy.cgColor

let videoLayer = CALayer()
videoLayer.frame = parent.bounds
parent.addSublayer(videoLayer)

func add(_ cgImage: CGImage, frame: CGRect, opacity: Float = 1) -> CALayer {
    let layer = CALayer()
    layer.frame = frame
    layer.contents = cgImage
    layer.contentsGravity = .resize
    layer.opacity = opacity
    parent.addSublayer(layer)
    return layer
}

/// Shows the layer between `from` and `to` seconds of the finished video, fading at each end.
func show(_ layer: CALayer, from: Double, to: Double, fade: Double = 0.4) {
    let span = max(0.01, total)
    let start = max(0, min(from, span)), end = max(start + 0.05, min(to, span))
    var keyTimes: [Double] = [0, start, min(start + fade, end), max(start + fade, end - fade), end, span]
    keyTimes = keyTimes.map { $0 / span }
    for index in 1..<keyTimes.count where keyTimes[index] <= keyTimes[index - 1] {
        keyTimes[index] = min(1, keyTimes[index - 1] + 0.00001)
    }
    let animation = CAKeyframeAnimation(keyPath: "opacity")
    animation.values = [0, 0, 1, 1, 0, 0]
    animation.keyTimes = keyTimes.map { NSNumber(value: $0) }
    animation.beginTime = AVCoreAnimationBeginTimeAtZero
    animation.duration = span
    animation.fillMode = .both
    animation.isRemovedOnCompletion = false
    layer.opacity = 0
    layer.add(animation, forKey: "show")
}

// The canvas behind everything: gradient, then the phone's rounded frame punched out of it so the
// recording's square corners never show.
let backdrop = image(size: Layout.canvas) { context in
    backgroundGradient(in: context, size: Layout.canvas)
}
let backdropLayer = CALayer()
backdropLayer.frame = parent.bounds
backdropLayer.contents = backdrop
parent.insertSublayer(backdropLayer, below: videoLayer)

let phoneRadius: CGFloat = 46
let phoneTrim = image(size: Layout.canvas) { _ in
    // Everything outside the phone's rounded rect is repainted, hiding the video's corners and
    // the band where the canvas is wider than the frame.
    let outside = NSBezierPath(rect: NSRect(origin: .zero, size: Layout.canvas))
    outside.append(NSBezierPath(roundedRect: phoneFrame, xRadius: phoneRadius, yRadius: phoneRadius).reversed)
    let gradientImage = image(size: Layout.canvas) { inner in backgroundGradient(in: inner, size: Layout.canvas) }
    NSGraphicsContext.current!.cgContext.saveGState()
    outside.setClip()
    NSGraphicsContext.current!.cgContext.draw(gradientImage, in: CGRect(origin: .zero, size: Layout.canvas))
    NSGraphicsContext.current!.cgContext.restoreGState()
    Palette.teal.withAlphaComponent(0.55).setStroke()
    let bezel = NSBezierPath(roundedRect: phoneFrame.insetBy(dx: -1.5, dy: -1.5),
                             xRadius: phoneRadius + 2, yRadius: phoneRadius + 2)
    bezel.lineWidth = 3
    bezel.stroke()
}
_ = add(phoneTrim, frame: parent.bounds)

// MARK: Panel

let markSize: CGFloat = 76
let panelTop = Layout.canvas.height - 96

let header = image(size: CGSize(width: panelWidth, height: markSize + 24)) { _ in
    var textX: CGFloat = 0
    if let mark {
        draw(mark: mark, in: NSRect(x: 0, y: 12, width: markSize, height: markSize))
        textX = markSize + 22
    }
    let width = panelWidth - textX
    attributed(spec.title, size: 34, weight: .semibold)
        .drawFromTop(in: CGRect(x: textX, y: 0, width: width, height: markSize + 24 - 8))
    attributed(spec.subtitle, size: 23, weight: .regular, color: Palette.teal)
        .drawFromTop(in: CGRect(x: textX, y: 0, width: width, height: markSize + 24 - 50))
}
_ = add(header, frame: CGRect(x: panelX, y: panelTop - markSize - 24, width: panelWidth, height: markSize + 24))

let ruleTop = panelTop - markSize - 60
let rule = image(size: CGSize(width: panelWidth, height: 2)) { _ in
    Palette.teal.withAlphaComponent(0.4).setFill()
    NSRect(x: 0, y: 0, width: panelWidth, height: 2).fill()
}
_ = add(rule, frame: CGRect(x: panelX, y: ruleTop, width: panelWidth, height: 2))

// A chapter's heading and its caption, which changes beat by beat underneath it.
let headingHeight: CGFloat = 210
let headingTop = ruleTop - 56

for (index, item) in placed.enumerated() {
    let section = item.section
    let heading = image(size: CGSize(width: panelWidth, height: headingHeight)) { _ in
        attributed("CHAPTER \(index + 1) OF \(placed.count)", size: 21, weight: .semibold,
                   color: Palette.teal, tracking: 3)
            .drawFromTop(in: CGRect(x: 0, y: 0, width: panelWidth, height: headingHeight))
        attributed(section.title, size: 56, weight: .bold, lineHeight: 1.1)
            .drawFromTop(in: CGRect(x: 0, y: 0, width: panelWidth, height: headingHeight - 44))
        if let subtitle = section.subtitle {
            attributed(subtitle, size: 28, weight: .regular, color: Palette.muted)
                .drawFromTop(in: CGRect(x: 0, y: 0, width: panelWidth, height: headingHeight - 128))
        }
    }
    let layer = add(heading, frame: CGRect(x: panelX, y: headingTop - headingHeight,
                                           width: panelWidth, height: headingHeight))
    show(layer, from: item.footageStart - 0.6, to: item.footageEnd + 0.2)
}

// Captions: one layer per beat, shown until the next beat starts.
let captionTop = headingTop - headingHeight - 34
let captionHeight: CGFloat = 360
let captionBarWidth: CGFloat = 5

for item in placed {
    let beats = item.section.beats
    for (index, beat) in beats.enumerated() {
        let at = item.finishedTime(forSource: beat.at - recordStart)
        let until = index + 1 < beats.count
            ? item.finishedTime(forSource: beats[index + 1].at - recordStart)
            : item.footageEnd
        guard until > at else { continue }
        let caption = image(size: CGSize(width: panelWidth, height: captionHeight)) { _ in
            let text = attributed(beat.text, size: 37, weight: .medium, lineHeight: 1.3)
            let width = panelWidth - captionBarWidth - 26
            let used = min(captionHeight, text.height(fittingWidth: width))
            Palette.teal.setFill()
            NSBezierPath(roundedRect: NSRect(x: 0, y: captionHeight - used, width: captionBarWidth, height: used),
                         xRadius: 2.5, yRadius: 2.5).fill()
            text.drawFromTop(in: CGRect(x: captionBarWidth + 26, y: 0, width: width, height: captionHeight))
        }
        let layer = add(caption, frame: CGRect(x: panelX, y: captionTop - captionHeight,
                                               width: panelWidth, height: captionHeight))
        show(layer, from: at, to: until, fade: 0.25)
    }
}

// Footer and a progress bar, both there for the whole run.
if let footer = spec.footer {
    let height: CGFloat = 60
    let footerImage = image(size: CGSize(width: panelWidth, height: height)) { _ in
        attributed(footer, size: 21, weight: .regular, color: Palette.faint)
            .drawFromTop(in: CGRect(x: 0, y: 0, width: panelWidth, height: height))
    }
    let layer = add(footerImage, frame: CGRect(x: panelX, y: 64, width: panelWidth, height: height))
    show(layer, from: Layout.introSeconds - 0.5, to: cursor + 0.5)
}

let progressTrack = image(size: CGSize(width: Layout.canvas.width, height: 6)) { _ in
    Palette.white.withAlphaComponent(0.09).setFill()
    NSRect(x: 0, y: 0, width: Layout.canvas.width, height: 6).fill()
}
_ = add(progressTrack, frame: CGRect(x: 0, y: 0, width: Layout.canvas.width, height: 6))

let progressFill = image(size: CGSize(width: Layout.canvas.width, height: 6)) { _ in
    Palette.teal.setFill()
    NSRect(x: 0, y: 0, width: Layout.canvas.width, height: 6).fill()
}
let progressLayer = CALayer()
progressLayer.contents = progressFill
progressLayer.anchorPoint = CGPoint(x: 0, y: 0.5)
progressLayer.frame = CGRect(x: 0, y: 0, width: Layout.canvas.width, height: 6)
parent.addSublayer(progressLayer)
let sweep = CABasicAnimation(keyPath: "transform.scale.x")
sweep.fromValue = 0
sweep.toValue = 1
sweep.beginTime = AVCoreAnimationBeginTimeAtZero
sweep.duration = total
sweep.fillMode = .both
sweep.isRemovedOnCompletion = false
progressLayer.add(sweep, forKey: "sweep")

// MARK: Cards

func card(title: String, subtitle: String?, kicker: String?, lines: [String] = []) -> CGImage {
    image(size: Layout.canvas) { context in
        backgroundGradient(in: context, size: Layout.canvas)
        let width: CGFloat = 1240
        let x = (Layout.canvas.width - width) / 2
        var y = Layout.canvas.height - 300
        if let mark {
            draw(mark: mark, in: NSRect(x: (Layout.canvas.width - 132) / 2, y: y + 40, width: 132, height: 132))
        }
        if let kicker {
            attributed(kicker, size: 24, weight: .semibold, color: Palette.teal, tracking: 4,
                       alignment: .center).drawFromTop(in: CGRect(x: x, y: 0, width: width, height: y))
            y -= 52
        }
        let heading = attributed(title, size: 84, weight: .bold, lineHeight: 1.1, alignment: .center)
        heading.drawFromTop(in: CGRect(x: x, y: 0, width: width, height: y))
        y -= heading.height(fittingWidth: width) + 26
        if let subtitle {
            let text = attributed(subtitle, size: 34, weight: .regular, color: Palette.muted,
                                  lineHeight: 1.35, alignment: .center)
            text.drawFromTop(in: CGRect(x: x, y: 0, width: width, height: y))
            y -= text.height(fittingWidth: width) + 44
        }
        if !lines.isEmpty {
            Palette.teal.withAlphaComponent(0.5).setFill()
            NSRect(x: (Layout.canvas.width - 120) / 2, y: y, width: 120, height: 2).fill()
            y -= 40
            for line in lines {
                let text = attributed(line, size: 27, weight: .regular, color: Palette.muted, alignment: .center)
                text.drawFromTop(in: CGRect(x: x, y: 0, width: width, height: y))
                y -= text.height(fittingWidth: width) + 14
            }
        }
    }
}

let intro = card(title: spec.title, subtitle: spec.subtitle, kicker: nil,
                 lines: placed.enumerated().map { "\($0.offset + 1).  \($0.element.section.title)" })
show(add(intro, frame: parent.bounds), from: 0, to: Layout.introSeconds, fade: 0.6)

for (index, item) in placed.enumerated() {
    let chapter = card(title: item.section.title, subtitle: item.section.subtitle,
                       kicker: "CHAPTER \(index + 1)")
    show(add(chapter, frame: parent.bounds), from: item.cardStart,
         to: item.cardStart + Layout.cardSeconds, fade: 0.5)
}

let outro = card(title: spec.title, subtitle: spec.footer, kicker: "END OF TOUR",
                 lines: placed.map { $0.section.title })
show(add(outro, frame: parent.bounds), from: cursor, to: total, fade: 0.7)

videoComposition.animationTool = AVVideoCompositionCoreAnimationTool(
    postProcessingAsVideoLayer: videoLayer, in: parent)

// MARK: - Contents

func stamp(_ seconds: Double) -> String {
    String(format: "%d:%02d", Int(seconds) / 60, Int(seconds) % 60)
}

// A chapter list, so the video can be published with timestamps.
if let path = spec.chaptersFile {
    var lines = ["\(stamp(0))  \(spec.title)"]
    for item in placed { lines.append("\(stamp(item.cardStart))  \(item.section.title)") }
    lines.append("\(stamp(cursor))  End")
    try (lines.joined(separator: "\n") + "\n").write(toFile: path, atomically: true, encoding: .utf8)
}

// The same thing in full, caption by caption, for the contents sheet that goes out with the video.
if let path = spec.indexFile {
    var chapters: [[String: Any]] = []
    for (index, item) in placed.enumerated() {
        let beats = item.section.beats.map { beat -> [String: Any] in
            var row: [String: Any] = ["at": item.finishedTime(forSource: beat.at - recordStart),
                                      "text": beat.text]
            if let id = beat.id { row["id"] = id }
            return row
        }
        chapters.append([
            "number": index + 1,
            "title": item.section.title,
            "subtitle": item.section.subtitle ?? "",
            "cardAt": item.cardStart,
            "startsAt": item.footageStart,
            "endsAt": item.footageEnd,
            "beats": beats,
        ])
    }
    let index: [String: Any] = [
        "title": spec.title, "subtitle": spec.subtitle, "footer": spec.footer ?? "",
        "video": URL(fileURLWithPath: spec.out).lastPathComponent, "recordedAt": recordStart,
        "duration": total, "width": Int(Layout.canvas.width), "height": Int(Layout.canvas.height),
        "brandMark": spec.brandMark ?? "", "chapters": chapters,
    ]
    try JSONSerialization.data(withJSONObject: index, options: [.prettyPrinted, .sortedKeys])
        .write(to: URL(fileURLWithPath: path))
}

if indexOnly {
    print(String(format: "contents only — %d chapters, %.0f seconds", placed.count, total))
    exit(0)
}

// MARK: - Export

let outURL = URL(fileURLWithPath: spec.out)
try? FileManager.default.removeItem(at: outURL)
try FileManager.default.createDirectory(at: outURL.deletingLastPathComponent(),
                                        withIntermediateDirectories: true)

guard let export = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) else {
    fatalError("could not create an export session")
}
export.videoComposition = videoComposition
export.timeRange = CMTimeRange(start: .zero, duration: time(total))
try runBlocking { try await export.export(to: outURL, as: .mp4) }

print(String(format: "%@ — %d chapters, %.0f seconds, %dx%d",
             outURL.path, placed.count, total, Int(Layout.canvas.width), Int(Layout.canvas.height)))

// MARK: - Running async work from a script

func runBlocking<T>(_ work: @escaping @Sendable () async throws -> T) throws -> T {
    let semaphore = DispatchSemaphore(value: 0)
    let box = Box<Result<T, Error>>()
    Task {
        do { box.value = .success(try await work()) } catch { box.value = .failure(error) }
        semaphore.signal()
    }
    semaphore.wait()
    return try box.value!.get()
}

final class Box<T>: @unchecked Sendable {
    var value: T?
}
