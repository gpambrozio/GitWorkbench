import SwiftUI
import PDFKit

/// Renders a PDF file. Added/deleted → the single document filling the pane; modified → the old and
/// new documents side by side (the issue asks for side-by-side PDFs). PDFKit handles scaling
/// (`autoScales`) and scrolling, so a large document scales down to fit and pages beyond the first
/// stay reachable. Validation re-runs whenever `content`'s bytes change — including an external
/// edit to the same file reloaded by the repository watcher, not just a switch to a different file.
struct PDFDiffView: View {
    let content: BinaryContent
    let file: FileChange
    @State private var validated: Validated?

    /// Sides that PDFKit confirmed parseable (nil side → placeholder logic below).
    private struct Validated {
        var old: Data?
        var new: Data?
    }

    var body: some View {
        ZStack {
            if let validated {
                if let oldData = validated.old, let newData = validated.new {
                    HStack(spacing: 14) {
                        labeled("Before", oldData)
                        labeled("After", newData)
                    }
                    .padding(16)
                } else if let data = validated.new ?? validated.old {
                    PDFDocumentView(data: data).padding(16)
                } else {
                    BinaryPlaceholder(file: file, caption: "Can\u{2019}t display PDF")
                }
            } else {
                ProgressView().controlSize(.small)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: content) {
            // Keyed on `content` (not `file.id`) so a bytes change re-validates even when the file
            // identity is unchanged — e.g. the watcher reloading this same file after an external edit.
            await Task.yield()   // let the spinner paint first (PDFDocument is main-actor here)
            validated = Validated(old: content.old.flatMap(renderablePDF),
                                  new: content.new.flatMap(renderablePDF))
        }
    }

    /// `data` if PDFKit can parse it as a document, else nil (→ placeholder).
    private func renderablePDF(_ data: Data) -> Data? {
        PDFDocument(data: data) != nil ? data : nil
    }

    private func labeled(_ title: String, _ data: Data) -> some View {
        VStack(spacing: 8) {
            CaptionLabel(title)
            PDFDocumentView(data: data)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// A PDFKit `PDFView` wrapper. `autoScales` fits the page to the pane and rescales on resize; the
/// document is rebuilt only when the bytes actually change (guarded through the coordinator) so a
/// SwiftUI re-render doesn't reset the reader's scroll/zoom.
private struct PDFDocumentView: NSViewRepresentable {
    let data: Data

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.backgroundColor = .clear
        apply(to: view, context: context)
        return view
    }

    func updateNSView(_ view: PDFView, context: Context) {
        apply(to: view, context: context)
    }

    private func apply(to view: PDFView, context: Context) {
        guard context.coordinator.data != data else { return }
        context.coordinator.data = data
        view.document = PDFDocument(data: data)
    }

    final class Coordinator { var data: Data? }
}
