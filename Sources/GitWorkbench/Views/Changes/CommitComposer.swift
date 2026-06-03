import SwiftUI

struct CommitComposer: View {
    @ObservedObject var store: GitWorkbenchStore
    @Environment(\.workbenchTheme) private var theme
    @FocusState private var focused: Bool

    var body: some View {
        let canCommit = store.state.canCommit
        VStack(spacing: 8) {
            ZStack(alignment: .topLeading) {
                if store.state.commitMessage.isEmpty {
                    Text("Message (\u{2318}\u{21A9} to commit)")
                        .font(.system(size: 13)).foregroundStyle(theme.ink3)
                        .padding(.horizontal, 12).padding(.vertical, 10).allowsHitTesting(false)
                }
                TextEditor(text: messageBinding)
                    .font(.system(size: 13))
                    .foregroundStyle(theme.ink)
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, 8).padding(.vertical, 6)
                    .focused($focused)
            }
            .frame(height: 58)
            .background(theme.field, in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(focused ? theme.accentRing : theme.sep, lineWidth: focused ? 1.5 : 1)
            )

            Button { Task { await store.commit() } } label: {
                HStack(spacing: 7) {
                    Image(systemName: IconLibrary.check)
                    Text(commitTitle)
                }
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(canCommit ? .white : theme.ink3)
                .frame(maxWidth: .infinity).frame(height: 30)
                .background(canCommit ? theme.accent : Color.black.opacity(0.07),
                            in: RoundedRectangle(cornerRadius: 7))
            }
            .buttonStyle(.plain)
            .disabled(!canCommit)
            .keyboardShortcut(.return, modifiers: .command)
        }
        .padding(12)
        .background(theme.sidebar)
        .overlay(alignment: .top) { Rectangle().fill(theme.sep).frame(height: 1) }
    }

    private var commitTitle: String {
        let n = store.state.staged.count
        let files = n == 1 ? "file" : "files"
        return n > 0 ? "Commit \(n) \(files) to \(store.state.repo.currentBranch)" : "Commit"
    }
    private var messageBinding: Binding<String> {
        Binding(get: { store.state.commitMessage }, set: { store.setCommitMessage($0) })
    }
}
