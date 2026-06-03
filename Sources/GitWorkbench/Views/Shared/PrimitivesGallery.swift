import SwiftUI

/// A gallery of every design-system primitive, for visual review.
struct PrimitivesGallery: View {
    @State private var mode: DiffMode = .split

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                row("Status glyphs") {
                    ForEach(FileStatus.allCases, id: \.self) { StatusGlyph(status: $0) }
                    ForEach(FileStatus.allCases, id: \.self) { StatusGlyph(status: $0, selected: true) }
                }
                row("Stage boxes") {
                    StageBox(checked: false); StageBox(checked: true); StageBox(checked: false, partial: true)
                }
                row("Stats") {
                    StatChips(additions: 24, deletions: 6); StatChips(additions: 31, deletions: 0)
                }
                row("Avatars") {
                    Avatar(initials: "GA", hue: 295); Avatar(initials: "MP", hue: 25)
                }
                row("Tool buttons") {
                    ToolButton(icon: IconLibrary.pull, label: "Pull") {}
                    ToolButton(icon: IconLibrary.history, active: true) {}
                    ToolButton(icon: IconLibrary.check, label: "Commit", role: .primary) {}
                    ToolButton(icon: IconLibrary.trash, label: "Drop", role: .danger) {}
                }
                row("Segmented") {
                    Segmented(value: $mode, options: [
                        .init(value: .unified, icon: IconLibrary.unifiedRows),
                        .init(value: .split, icon: IconLibrary.splitColumns),
                    ])
                }
                row("Branch pills") {
                    BranchPill(name: "feat/auto-sync") {}
                    BranchPill(name: "main", dim: true, showsChevron: false, height: 24)
                }
                SectionHeader(title: "Staged", count: 3, actionTitle: "Unstage all") {}
                row("Toasts") {
                    ToastView(toast: .success("Committed 3 files"))
                    ToastView(toast: .progress("Pushing\u{2026}"))
                }
                EmptyState(icon: IconLibrary.file, title: "Select a file to view changes")
                    .frame(height: 160)
            }
            .padding(24)
        }
    }

    @ViewBuilder private func row(_ title: String, @ViewBuilder _ content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: 11, weight: .bold)).tracking(0.4).foregroundStyle(.secondary)
            HStack(spacing: 12) { content() }
        }
    }
}

#Preview("Gallery \u{2014} light") {
    PrimitivesGallery()
        .workbenchTheme(.standard)
        .frame(width: 720, height: 760)
        .background(Color(hex: 0xF3F3F5))
}

#Preview("Gallery \u{2014} dark") {
    PrimitivesGallery()
        .workbenchTheme(.darkStandard)
        .frame(width: 720, height: 760)
        .background(Color(hex: 0x1E1E20))
        .preferredColorScheme(.dark)
}
