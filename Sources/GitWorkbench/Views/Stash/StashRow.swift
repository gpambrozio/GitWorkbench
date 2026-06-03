import SwiftUI

/// A stash list row: ref pill + message, then branch · relative · file count.
struct StashRow: View {
    @ObservedObject var store: GitWorkbenchStore
    @Environment(\.workbenchTheme) private var theme
    @State private var hover = false
    let stash: Stash

    var body: some View {
        let selected = store.state.selectedStashID == stash.id
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                Text(stash.ref)
                    .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(selected ? .white : theme.accentDeep)
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background(selected ? Color.white.opacity(0.22) : theme.accentSoft,
                                in: RoundedRectangle(cornerRadius: Tokens.pillRadius))
                Text(stash.message).font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(selected ? .white : theme.ink).lineLimit(1)
            }
            HStack(spacing: 5) {
                Image(systemName: IconLibrary.branch).font(.system(size: 10))
                    .foregroundStyle(selected ? Color.white.opacity(0.8) : theme.ink3)
                Text(stash.branch).font(.system(size: 11))
                    .foregroundStyle(selected ? Color.white.opacity(0.9) : theme.ink2)
                Text("\u{00B7} \(stash.relativeDate)").font(.system(size: 11))
                    .foregroundStyle(selected ? Color.white.opacity(0.7) : theme.ink3)
                Spacer(minLength: 6)
                Text("\(stash.files.count) file\(stash.files.count == 1 ? "" : "s")")
                    .font(.system(size: 11)).foregroundStyle(selected ? Color.white.opacity(0.7) : theme.ink3)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(selected ? theme.accent : (hover ? Color.black.opacity(0.04) : .clear))
        .overlay(alignment: .bottom) { Rectangle().fill(theme.sep).frame(height: 1) }
        .contentShape(Rectangle())
        .onTapGesture { Task { await store.selectStash(stash.id) } }
        .onHover { hover = $0 }
    }
}
