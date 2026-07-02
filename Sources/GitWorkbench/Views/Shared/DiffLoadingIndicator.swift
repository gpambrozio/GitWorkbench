import SwiftUI

/// A centered spinner for in-flight diff loads. Invisible for a short grace
/// period so fast loads render directly with no spinner flash; only loads
/// still in flight after the grace period show it. (Behavioral constant, not
/// a design-handoff token.)
struct DiffLoadingIndicator: View {
    @State private var visible = false
    private static let gracePeriod: Duration = .milliseconds(200)

    var body: some View {
        ZStack {   // stable single root across the invisible→spinner flip
            if visible {
                ProgressView().controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            try? await Task.sleep(for: Self.gracePeriod)
            guard !Task.isCancelled else { return }
            visible = true
        }
    }
}
