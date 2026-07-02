import Foundation
import AppKit
import CoreGraphics

/// Generates the small image/PDF byte payloads behind the mock provider's binary-file fixtures
/// (issue #12), so SwiftUI previews and the mock-backed `GitWorkbenchDemo` exercise the image/PDF
/// viewers without shipping binary asset files. Drawn with CoreGraphics (thread-safe; no `lockFocus`)
/// and encoded once at load.
enum FixtureImages {

    // MARK: Modified image — old vs new differ, so the pane offers the compare modes.

    /// "Before": a dark banner with a blue mark, one accent stripe.
    static let bannerOld: Data = png(width: 1280, height: 720) { ctx in
        fill(ctx, CGRect(x: 0, y: 0, width: 1280, height: 720), gray: 0.11)
        ctx.setFillColor(CGColor(red: 0.30, green: 0.55, blue: 0.98, alpha: 1))
        ctx.fillEllipse(in: CGRect(x: 200, y: 230, width: 260, height: 260))
        ctx.setFillColor(CGColor(red: 0.30, green: 0.55, blue: 0.98, alpha: 0.85))
        ctx.fill(CGRect(x: 560, y: 330, width: 520, height: 60))
    }

    /// "After": lighter, the mark recolored + moved, and a second stripe added — clearly changed.
    static let bannerNew: Data = png(width: 1280, height: 720) { ctx in
        fill(ctx, CGRect(x: 0, y: 0, width: 1280, height: 720), gray: 0.16)
        ctx.setFillColor(CGColor(red: 0.98, green: 0.55, blue: 0.25, alpha: 1))
        ctx.fillEllipse(in: CGRect(x: 260, y: 210, width: 300, height: 300))
        ctx.setFillColor(CGColor(red: 0.98, green: 0.55, blue: 0.25, alpha: 0.9))
        ctx.fill(CGRect(x: 640, y: 360, width: 460, height: 56))
        ctx.setFillColor(CGColor(red: 0.4, green: 0.85, blue: 0.6, alpha: 0.9))
        ctx.fill(CGRect(x: 640, y: 270, width: 320, height: 46))
    }

    // MARK: Added image (untracked) — a transparent-corner PNG shown on its own, filling the pane.

    static let screenshotNew: Data = png(width: 900, height: 1400) { ctx in
        // transparent background (checkerboard shows through), a rounded "card" with mock content
        ctx.setFillColor(CGColor(red: 0.13, green: 0.14, blue: 0.2, alpha: 1))
        addRoundedRect(ctx, CGRect(x: 60, y: 60, width: 780, height: 1280), radius: 36)
        ctx.fillPath()
        ctx.setFillColor(CGColor(red: 0.45, green: 0.4, blue: 0.95, alpha: 1))
        ctx.fill(CGRect(x: 60, y: 1180, width: 780, height: 160))       // header band
        for row in 0..<8 {
            let y = CGFloat(980 - row * 120)
            ctx.setFillColor(CGColor(gray: 0.85, alpha: 0.9))
            addRoundedRect(ctx, CGRect(x: 120, y: y, width: 660, height: 26), radius: 13); ctx.fillPath()
            ctx.setFillColor(CGColor(gray: 0.6, alpha: 0.6))
            addRoundedRect(ctx, CGRect(x: 120, y: y - 42, width: 420, height: 20), radius: 10); ctx.fillPath()
        }
    }

    // MARK: Modified PDF — old vs new differ, shown side by side.

    static let specOld: Data = pdf(width: 612, height: 792) { ctx in
        drawDocument(ctx, width: 612, height: 792,
                     header: CGColor(red: 0.30, green: 0.55, blue: 0.98, alpha: 1),
                     textLines: 9, chart: [0.4, 0.7, 0.5, 0.9])
    }

    static let specNew: Data = pdf(width: 612, height: 792) { ctx in
        drawDocument(ctx, width: 612, height: 792,
                     header: CGColor(red: 0.98, green: 0.55, blue: 0.25, alpha: 1),
                     textLines: 12, chart: [0.5, 0.6, 0.85, 0.7, 0.95])
    }

    // MARK: Drawing helpers

    private static func fill(_ ctx: CGContext, _ rect: CGRect, gray: CGFloat) {
        ctx.setFillColor(CGColor(gray: gray, alpha: 1))
        ctx.fill(rect)
    }

    private static func addRoundedRect(_ ctx: CGContext, _ rect: CGRect, radius: CGFloat) {
        ctx.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
    }

    /// A simple "document" page: white sheet, a colored header band, text-line bars, and a small bar
    /// chart — enough to read as a changed document when two versions sit side by side.
    private static func drawDocument(_ ctx: CGContext, width w: CGFloat, height h: CGFloat,
                                     header: CGColor, textLines: Int, chart: [CGFloat]) {
        fill(ctx, CGRect(x: 0, y: 0, width: w, height: h), gray: 1)
        ctx.setFillColor(header)
        ctx.fill(CGRect(x: 0, y: h - 96, width: w, height: 96))          // header band (top)
        ctx.setFillColor(CGColor(gray: 1, alpha: 0.9))
        addRoundedRect(ctx, CGRect(x: 48, y: h - 70, width: 300, height: 26), radius: 8); ctx.fillPath()

        for i in 0..<textLines {                                        // body text lines
            let y = h - 150 - CGFloat(i) * 34
            let lineWidth = (i % 3 == 2) ? 0.5 : 0.82
            ctx.setFillColor(CGColor(gray: 0.8, alpha: 1))
            addRoundedRect(ctx, CGRect(x: 48, y: y, width: (w - 96) * lineWidth, height: 14), radius: 7)
            ctx.fillPath()
        }

        let base: CGFloat = 90, chartH: CGFloat = 200, barW = (w - 140) / CGFloat(chart.count) - 16
        for (i, value) in chart.enumerated() {                          // bar chart at the bottom
            ctx.setFillColor(header.copy(alpha: 0.85) ?? header)
            let x = 70 + CGFloat(i) * (barW + 16)
            ctx.fill(CGRect(x: x, y: base, width: barW, height: chartH * value))
        }
    }

    /// Renders a bitmap via a CoreGraphics context and encodes it as PNG (preserving alpha).
    private static func png(width: Int, height: Int, _ draw: (CGContext) -> Void) -> Data {
        let space = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                  bytesPerRow: 0, space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return Data() }
        ctx.clear(CGRect(x: 0, y: 0, width: width, height: height))
        draw(ctx)
        guard let image = ctx.makeImage() else { return Data() }
        return NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) ?? Data()
    }

    /// Renders a single-page PDF via a CoreGraphics PDF context.
    private static func pdf(width: CGFloat, height: CGFloat, _ draw: (CGContext) -> Void) -> Data {
        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data as CFMutableData) else { return Data() }
        var mediaBox = CGRect(x: 0, y: 0, width: width, height: height)
        guard let ctx = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else { return Data() }
        ctx.beginPDFPage(nil)
        draw(ctx)
        ctx.endPDFPage()
        ctx.closePDF()
        return data as Data
    }
}
