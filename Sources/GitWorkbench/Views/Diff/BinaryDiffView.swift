import SwiftUI
import AppKit
import CoreGraphics

/// Renders a binary file the viewer understands (image / PDF), dispatching to the right sub-view.
/// The change kind is read off `content` (added / deleted / modified) by each sub-view. Wrapped by
/// `DiffView` in a `.id(file.id)` so switching files resets the comparison controls' local state.
struct BinaryDiffView: View {
    let content: BinaryContent
    let file: FileChange

    var body: some View {
        switch content.kind {
        case .image: ImageDiffView(content: content, file: file)
        case .pdf:   PDFDiffView(content: content, file: file)
        }
    }
}

/// Fallback shown for a binary file with no renderable content (a non-image/PDF binary, or bytes that
/// failed to decode). Mirrors the pre-issue-#12 "Binary file" placeholder.
struct BinaryPlaceholder: View {
    @Environment(\.workbenchTheme) private var theme
    let file: FileChange
    var caption: String? = nil

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: IconLibrary.file).font(.system(size: 22)).foregroundStyle(theme.ink3)
            Text(caption ?? "Binary file").font(.system(size: 13, weight: .semibold)).foregroundStyle(theme.ink2)
            Text("+\(file.additions) \u{2212}\(file.deletions)")
                .font(.system(size: 12, design: .monospaced)).foregroundStyle(theme.ink3)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Shared fit math

/// The size to display `natural`-sized content within `available`, preserving aspect ratio and never
/// upscaling. Issue #12: oversized content scales down to fit the pane; content already smaller than
/// the pane stays at its natural size (centered) rather than being blown up.
func fittedSize(natural: CGSize, available: CGSize) -> CGSize {
    guard natural.width > 0, natural.height > 0, available.width > 0, available.height > 0 else { return natural }
    let scale = min(available.width / natural.width, available.height / natural.height, 1)
    return CGSize(width: natural.width * scale, height: natural.height * scale)
}

extension NSImage {
    /// Pixel dimensions from the largest bitmap representation (DPI-independent), falling back to the
    /// point `size`. A PNG tagged with a non-72 DPI reports a scaled `size`; using the rep's pixel
    /// count keeps aspect-fit honest.
    var pixelDimensions: CGSize {
        let reps = representations
        let w = reps.map(\.pixelsWide).max() ?? 0
        let h = reps.map(\.pixelsHigh).max() ?? 0
        if w > 0, h > 0 { return CGSize(width: w, height: h) }
        return size
    }
}

// MARK: - Transparency checkerboard

/// The classic light/dark checkerboard shown behind images so transparent (alpha) regions are visible
/// instead of blending invisibly into the pane. A tiled bitmap (not a `Canvas`) so it captures reliably
/// in the demo's `cacheDisplay` screenshots. Subtle grays read on both light and dark themes.
struct Checkerboard: View {
    var body: some View {
        Image(nsImage: Self.tile).resizable(resizingMode: .tile)
    }

    private static let tile: NSImage = {
        let side = 20, half = 10
        let space = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8,
                                  bytesPerRow: 0, space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return NSImage(size: NSSize(width: side, height: side))
        }
        ctx.clear(CGRect(x: 0, y: 0, width: side, height: side))
        ctx.setFillColor(CGColor(gray: 0.5, alpha: 0.14))
        ctx.fill(CGRect(x: 0, y: 0, width: half, height: half))
        ctx.fill(CGRect(x: half, y: half, width: half, height: half))
        guard let image = ctx.makeImage() else { return NSImage(size: NSSize(width: side, height: side)) }
        return NSImage(cgImage: image, size: NSSize(width: side, height: side))
    }()
}
