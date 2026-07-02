import SwiftUI
import AppKit

/// How a modified image's before/after is compared (mirrors the modes GitHub offers for image diffs).
enum ImageCompareMode: String, CaseIterable, Hashable {
    case sideBySide   // old and new laid out next to each other
    case swipe        // both overlaid; a draggable divider reveals old on one side, new on the other
    case fade         // both overlaid; a slider cross-fades old ↔ new
}

/// The divider orientation in ``ImageCompareMode/swipe`` — the issue asks for a "vertical or horizontal
/// divider". Vertical splits left (old) / right (new); horizontal splits top (old) / bottom (new).
enum DividerAxis: Hashable { case vertical, horizontal }

/// Renders an image file. Added/deleted → the single image filling the pane; modified → the
/// before/after comparer. Bytes are decoded once per view instance (the parent re-identifies this view
/// per file via `.id`, so a new file re-decodes).
struct ImageDiffView: View {
    let file: FileChange
    private let oldImage: NSImage?
    private let newImage: NSImage?

    init(content: BinaryContent, file: FileChange) {
        self.file = file
        self.oldImage = content.old.flatMap { NSImage(data: $0) }
        self.newImage = content.new.flatMap { NSImage(data: $0) }
    }

    var body: some View {
        if let oldImage, let newImage {
            ModifiedImageComparer(old: oldImage, new: newImage)
        } else if let single = newImage ?? oldImage {
            ImageCanvas(image: single).padding(16)   // added / deleted: fill the available space
        } else {
            BinaryPlaceholder(file: file, caption: "Can\u{2019}t display image")
        }
    }
}

// MARK: - Single image

/// One image, aspect-fit into the available space over the transparency checkerboard, centered.
struct ImageCanvas: View {
    let image: NSImage
    var body: some View {
        GeometryReader { geo in
            let fit = fittedSize(natural: image.pixelDimensions, available: geo.size)
            FittedImage(image: image, size: fit)
                .background(Checkerboard())
                .frame(maxWidth: .infinity, maxHeight: .infinity)   // center within the pane
        }
    }
}

/// An image scaled to fit exactly `size` (no distortion, no upscale beyond `size`).
struct FittedImage: View {
    let image: NSImage
    let size: CGSize
    var body: some View {
        Image(nsImage: image)
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .frame(width: size.width, height: size.height)
    }
}

/// The rectangle a swipe/fade overlay draws into: fit the *union* of the two images' natural sizes, so
/// both share one frame and line up (each is aspect-fit within it, letterboxed if their ratios differ).
private func overlayFit(_ old: NSImage, _ new: NSImage, available: CGSize) -> CGSize {
    let natural = CGSize(width: max(old.pixelDimensions.width, new.pixelDimensions.width),
                         height: max(old.pixelDimensions.height, new.pixelDimensions.height))
    return fittedSize(natural: natural, available: available)
}

// MARK: - Modified image comparer

/// Control bar (mode picker + mode-specific control) over the chosen comparison. Local `@State` holds
/// the transient view choices; it resets when the file changes because `DiffView` re-identifies the
/// binary view with `.id(file.id)`.
struct ModifiedImageComparer: View {
    @Environment(\.workbenchTheme) private var theme
    let old: NSImage
    let new: NSImage

    @State private var mode: ImageCompareMode = .sideBySide
    @State private var axis: DividerAxis = .vertical
    @State private var fraction: CGFloat = 0.5
    @State private var newOpacity: Double = 1

    var body: some View {
        VStack(spacing: 0) {
            controlBar
            Rectangle().fill(theme.sep).frame(height: 1)
            content.padding(16)
        }
    }

    @ViewBuilder private var content: some View {
        switch mode {
        case .sideBySide: SideBySideImages(old: old, new: new)
        case .swipe:      SwipeCompare(old: old, new: new, axis: axis, fraction: $fraction)
        case .fade:       FadeCompare(old: old, new: new, newOpacity: newOpacity)
        }
    }

    private var controlBar: some View {
        HStack(spacing: 10) {
            Segmented(value: $mode, options: [
                .init(value: .sideBySide, icon: IconLibrary.compareSideBySide, label: "Side by Side"),
                .init(value: .swipe, icon: IconLibrary.compareSwipe, label: "Swipe"),
                .init(value: .fade, icon: IconLibrary.compareFade, label: "Fade"),
            ])
            Spacer(minLength: 8)
            switch mode {
            case .swipe:
                Segmented(value: $axis, options: [
                    .init(value: .vertical, icon: IconLibrary.axisVertical),
                    .init(value: .horizontal, icon: IconLibrary.axisHorizontal),
                ])
            case .fade:
                fadeSlider
            case .sideBySide:
                EmptyView()
            }
        }
        .padding(.horizontal, 16)
        .frame(height: Tokens.diffHeaderHeight)
    }

    private var fadeSlider: some View {
        HStack(spacing: 8) {
            CaptionLabel("Before")
            Slider(value: $newOpacity, in: 0...1).frame(width: 150).tint(theme.accent)
            CaptionLabel("After")
        }
    }
}

/// Old and new side by side, each captioned and aspect-fit into its half.
struct SideBySideImages: View {
    let old: NSImage
    let new: NSImage
    var body: some View {
        HStack(spacing: 14) {
            LabeledImage(title: "Before", image: old)
            LabeledImage(title: "After", image: new)
        }
    }
}

private struct LabeledImage: View {
    let title: String
    let image: NSImage
    var body: some View {
        VStack(spacing: 8) {
            CaptionLabel(title)
            ImageCanvas(image: image)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Both images overlaid in one shared rect; a draggable divider reveals old (leading/top) up to
/// `fraction` and new (trailing/bottom) beyond it.
struct SwipeCompare: View {
    let old: NSImage
    let new: NSImage
    let axis: DividerAxis
    @Binding var fraction: CGFloat

    var body: some View {
        GeometryReader { geo in
            let fit = overlayFit(old, new, available: geo.size)
            ZStack {
                Checkerboard().frame(width: fit.width, height: fit.height)
                FittedImage(image: new, size: fit)                    // base: new (revealed side)
                FittedImage(image: old, size: fit)                    // top: old, clipped to `fraction`
                    .mask(alignment: axis == .vertical ? .leading : .top) {
                        Rectangle().frame(width: axis == .vertical ? fit.width * fraction : fit.width,
                                          height: axis == .horizontal ? fit.height * fraction : fit.height)
                    }
                divider(fit: fit)
            }
            .frame(width: fit.width, height: fit.height)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                let p = axis == .vertical ? value.location.x / fit.width : value.location.y / fit.height
                fraction = min(max(p, 0), 1)
            })
            .frame(maxWidth: .infinity, maxHeight: .infinity)   // center
        }
    }

    private func divider(fit: CGSize) -> some View {
        let vertical = axis == .vertical
        let x = vertical ? fit.width * fraction : fit.width / 2
        let y = vertical ? fit.height / 2 : fit.height * fraction
        return ZStack {
            Rectangle().fill(.white)
                .frame(width: vertical ? 2 : fit.width, height: vertical ? fit.height : 2)
                .position(x: x, y: y)
                .shadow(color: .black.opacity(0.3), radius: 1)
            Circle().fill(.white).frame(width: 20, height: 20)
                .overlay(Image(systemName: vertical ? IconLibrary.axisVertical : IconLibrary.axisHorizontal)
                    .font(.system(size: 9, weight: .bold)).foregroundStyle(.black.opacity(0.65)))
                .shadow(color: .black.opacity(0.3), radius: 2)
                .position(x: x, y: y)
        }
        .frame(width: fit.width, height: fit.height)
        .allowsHitTesting(false)   // the drag lives on the ZStack so the whole area is grabbable
    }
}

/// Both images overlaid; `newOpacity` cross-fades the new image over the old (onion skin).
struct FadeCompare: View {
    let old: NSImage
    let new: NSImage
    let newOpacity: Double
    var body: some View {
        GeometryReader { geo in
            let fit = overlayFit(old, new, available: geo.size)
            ZStack {
                Checkerboard().frame(width: fit.width, height: fit.height)
                FittedImage(image: old, size: fit)
                FittedImage(image: new, size: fit).opacity(newOpacity)
            }
            .frame(width: fit.width, height: fit.height)
            .frame(maxWidth: .infinity, maxHeight: .infinity)   // center
        }
    }
}

/// An uppercase micro-caption ("BEFORE" / "AFTER"), matching the detail-pane section headers.
struct CaptionLabel: View {
    @Environment(\.workbenchTheme) private var theme
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).font(.system(size: 10.5, weight: .bold)).tracking(0.4).textCase(.uppercase)
            .foregroundStyle(theme.ink3)
    }
}
