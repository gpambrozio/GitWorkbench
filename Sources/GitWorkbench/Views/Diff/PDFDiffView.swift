import SwiftUI
import PDFKit

/// Renders a PDF file. Added/deleted → the single document filling the pane; modified → the old and
/// new documents side by side (the issue asks for side-by-side PDFs). PDFKit handles scaling
/// (`autoScales`) and scrolling, so a large document scales down to fit and pages beyond the first
/// stay reachable.
struct PDFDiffView: View {
    @Environment(\.workbenchTheme) private var theme
    let content: BinaryContent
    let file: FileChange

    var body: some View {
        if let oldData = content.old, let newData = content.new {
            HStack(spacing: 14) {
                labeled("Before", oldData)
                labeled("After", newData)
            }
            .padding(16)
        } else if let data = content.new ?? content.old {
            PDFDocumentView(data: data).padding(16)
        } else {
            BinaryPlaceholder(file: file, caption: "Can\u{2019}t display PDF")
        }
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
