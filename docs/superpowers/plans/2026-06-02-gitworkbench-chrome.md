# GitWorkbench Chrome (Toolbar + Rail) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Build the shared chrome — `WorkbenchToolbar` (pull/push/fetch, branch pill + menu, History/Stash toggles, unified/split control), `WorkspaceRail` (Workspace/Branches/Remotes), the `BranchMenu` popover — and compose them into the real `GitWorkbenchView` (toolbar + rail + active-view body + toast overlay + theme injection). Adds two small store intents (`setBranchMenuOpen`, `dismissToast`).

**Architecture:** Plan 6 (Foundation→DiffRenderer on `main`). The chrome views are `@ObservedObject store`-driven and read `@Environment(\.workbenchTheme)`; `GitWorkbenchView` resolves the theme from `colorScheme`, injects it via `.workbenchTheme(_:)`, lays out toolbar + (rail + body), overlays the toast, and switches the body on `state.activeView`. The three workspace bodies are temporary `EmptyState` placeholders here; Plans 7–8 replace them with the real Changes/History/Stash views.

**Tech Stack:** Swift 6, SwiftPM, macOS 15+, SwiftUI, XCTest. Zero deps.

**Conventions:** Metrics/colors from §03 (Toolbar/Rail/BranchMenu) + §04. Chrome views internal. Minus/ellipsis via `\u{2212}`/`\u{2026}`. Run from repo root; execution on `feat/chrome`.

---

### Task 1: Store intents + WorkbenchToolbar + BranchMenu

**Files:**
- Modify: `Sources/GitWorkbench/Store/GitWorkbenchStore.swift` (append `setBranchMenuOpen`/`dismissToast` to a same-file extension)
- Create: `Sources/GitWorkbench/Views/Toolbar/WorkbenchToolbar.swift`
- Create: `Sources/GitWorkbench/Views/Toolbar/BranchMenu.swift`

- [ ] **Step 1: Add the two store intents**

Append to `Sources/GitWorkbench/Store/GitWorkbenchStore.swift` (same-file extension, so it can set `private(set) state`):

```swift
// MARK: - Chrome intents

extension GitWorkbenchStore {
    public func setBranchMenuOpen(_ open: Bool) { state.branchMenuOpen = open }
    public func dismissToast() { state.toast = nil }
}
```

- [ ] **Step 2: Write `WorkbenchToolbar.swift`**

```swift
import SwiftUI

/// The top bar: repo name · pull/push/fetch · branch pill · History/Stash toggles · diff-mode control.
struct WorkbenchToolbar: View {
    @ObservedObject var store: GitWorkbenchStore
    @Environment(\.workbenchTheme) private var theme

    var body: some View {
        let s = store.state
        HStack(spacing: 0) {
            Text(s.repo.repositoryName)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(theme.ink)
                .padding(.leading, 20)
                .frame(width: Tokens.railWidth, alignment: .leading)
                .frame(maxHeight: .infinity)
                .overlay(alignment: .trailing) { Rectangle().fill(theme.sep).frame(width: 1) }

            HStack(spacing: 3) {
                ToolButton(icon: IconLibrary.pull, label: pullLabel) { Task { await store.pull() } }
                    .disabled(s.isBusy)
                ToolButton(icon: IconLibrary.push, label: pushLabel) { Task { await store.push() } }
                    .disabled(s.isBusy)
                ToolButton(icon: IconLibrary.fetch, label: "Fetch") { Task { await store.fetch() } }
                    .disabled(s.isBusy)
                Rectangle().fill(theme.sep).frame(width: 1, height: 22).padding(.horizontal, 4)
                BranchPill(name: s.repo.currentBranch) { store.setBranchMenuOpen(!s.branchMenuOpen) }
                    .popover(isPresented: branchMenu, arrowEdge: .bottom) { BranchMenu(store: store) }
                ToolButton(icon: IconLibrary.history, active: s.activeView == .history) { store.select(.history) }
                ToolButton(icon: IconLibrary.folder, active: s.activeView == .stashes) { store.select(.stashes) }
            }
            .padding(.leading, 14)

            Spacer(minLength: 0)

            Segmented(value: diffMode, options: [
                .init(value: .unified, icon: IconLibrary.unifiedRows),
                .init(value: .split, icon: IconLibrary.splitColumns),
            ])
            .padding(.trailing, 14)
        }
        .frame(height: Tokens.toolbarHeight)
        .background(theme.titlebar)
        .overlay(alignment: .bottom) { Rectangle().fill(theme.sep).frame(height: 1) }
    }

    private var pullLabel: String { store.state.repo.behind > 0 ? "Pull \(store.state.repo.behind)" : "Pull" }
    private var pushLabel: String { store.state.repo.ahead > 0 ? "Push \(store.state.repo.ahead)" : "Push" }
    private var branchMenu: Binding<Bool> {
        Binding(get: { store.state.branchMenuOpen }, set: { store.setBranchMenuOpen($0) })
    }
    private var diffMode: Binding<DiffMode> {
        Binding(get: { store.state.diffMode }, set: { store.setDiffMode($0) })
    }
}
```

- [ ] **Step 3: Write `BranchMenu.swift`**

```swift
import SwiftUI

/// The "switch branch" popover content.
struct BranchMenu: View {
    @ObservedObject var store: GitWorkbenchStore
    @Environment(\.workbenchTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("SWITCH BRANCH")
                .font(.system(size: 11, weight: .bold)).tracking(0.4)
                .foregroundStyle(theme.ink3)
                .padding(.init(top: 12, leading: 14, bottom: 6, trailing: 14))

            ForEach(store.state.branches) { branch in
                BranchMenuRow(
                    branch: branch,
                    isCurrent: branch.name == store.state.repo.currentBranch,
                    ahead: store.state.repo.ahead,
                    behind: store.state.repo.behind
                ) { Task { await store.switchBranch(to: branch) } }
            }

            Divider().padding(.vertical, 4)

            Button {} label: {
                HStack(spacing: 8) {
                    Image(systemName: IconLibrary.plus)
                    Text("New branch from HEAD\u{2026}")
                }
                .font(.system(size: 12.5))
                .foregroundStyle(theme.ink2)
                .padding(.init(top: 6, leading: 14, bottom: 12, trailing: 14))
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
        }
        .frame(width: 280)
    }
}

private struct BranchMenuRow: View {
    @Environment(\.workbenchTheme) private var theme
    @State private var hover = false
    let branch: Branch
    let isCurrent: Bool
    let ahead: Int
    let behind: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: IconLibrary.branch)
                    .foregroundStyle(isCurrent ? theme.accent : theme.ink3)
                Text(branch.name)
                    .font(.system(size: 12.5, weight: isCurrent ? .semibold : .regular))
                    .foregroundStyle(theme.ink)
                Spacer(minLength: 8)
                if isCurrent {
                    Text("\(ahead)\u{2191} \(behind)\u{2193}")
                        .font(.system(size: 11).monospacedDigit())
                        .foregroundStyle(theme.ink3)
                    Image(systemName: IconLibrary.check).foregroundStyle(theme.accent).font(.system(size: 11))
                }
            }
            .padding(.horizontal, 14).frame(height: 30)
            .frame(maxWidth: .infinity)
            .background(hover ? Color.black.opacity(0.05) : .clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}
```

- [ ] **Step 4: Build & commit**

Run: `swift build && swift test`
Expected: build succeeds; tests still pass (~67).

```bash
git add Sources/GitWorkbench/Store/GitWorkbenchStore.swift Sources/GitWorkbench/Views/Toolbar/WorkbenchToolbar.swift Sources/GitWorkbench/Views/Toolbar/BranchMenu.swift
git commit -m "Chrome: add WorkbenchToolbar, BranchMenu, and chrome store intents"
```

---

### Task 2: WorkspaceRail

**Files:**
- Create: `Sources/GitWorkbench/Views/Rail/WorkspaceRail.swift`

> Width 218, `sidebarDeep` background, three sections (Workspace / Branches / Remotes). `RailItem` height 28; selected = accent fill + white.

- [ ] **Step 1: Write `WorkspaceRail.swift`**

```swift
import SwiftUI

struct WorkspaceRail: View {
    @ObservedObject var store: GitWorkbenchStore
    @Environment(\.workbenchTheme) private var theme

    var body: some View {
        let s = store.state
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                railHeader("WORKSPACE")
                RailItem(icon: IconLibrary.file, title: "Changes", count: s.repo.files.count,
                         selected: s.activeView == .changes) { store.select(.changes) }
                RailItem(icon: IconLibrary.history, title: "History", count: s.commits.count,
                         selected: s.activeView == .history) { store.select(.history) }
                RailItem(icon: IconLibrary.folder, title: "Stashes", count: s.stashes.count,
                         selected: s.activeView == .stashes) { store.select(.stashes) }

                railHeader("BRANCHES")
                ForEach(s.branches) { branch in
                    RailItem(icon: IconLibrary.branch, title: branch.name, count: nil,
                             selected: false, current: branch.name == s.repo.currentBranch) {
                        Task { await store.switchBranch(to: branch) }
                    }
                }

                railHeader("REMOTES")
                RailItem(icon: IconLibrary.folder, title: "origin", count: nil, selected: false) {}
                if let upstream = s.repo.upstream {
                    RailItem(icon: IconLibrary.branch, title: upstream, count: nil, selected: false, indent: 26) {}
                }
                Spacer(minLength: 8)
            }
            .padding(.bottom, 8)
        }
        .frame(width: Tokens.railWidth)
        .background(theme.sidebarDeep)
    }

    private func railHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .bold)).tracking(0.4)
            .foregroundStyle(theme.ink3)
            .padding(.init(top: 14, leading: 16, bottom: 5, trailing: 16))
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct RailItem: View {
    @Environment(\.workbenchTheme) private var theme
    @State private var hover = false
    let icon: String
    let title: String
    var count: Int?
    let selected: Bool
    var current: Bool = false
    var indent: CGFloat = 0
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundStyle(selected ? .white : (current ? theme.accent : theme.ink2))
                Text(title)
                    .font(.system(size: 12.5, weight: current ? .bold : .medium))
                    .foregroundStyle(selected ? .white : theme.ink)
                    .lineLimit(1)
                Spacer(minLength: 6)
                if current && !selected {
                    Text("HEAD")
                        .font(.system(size: 9.5, weight: .bold))
                        .foregroundStyle(theme.accentDeep)
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(theme.accentSoft, in: RoundedRectangle(cornerRadius: 4))
                }
                if let count {
                    Text("\(count)")
                        .font(.system(size: 11, weight: .semibold).monospacedDigit())
                        .foregroundStyle(selected ? Color.white.opacity(0.85) : theme.ink3)
                }
            }
            .padding(.leading, 8 + indent).padding(.trailing, 8)
            .frame(height: Tokens.railRowHeight)
            .frame(maxWidth: .infinity)
            .background(rowBackground, in: RoundedRectangle(cornerRadius: Tokens.rowRadius, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .padding(.horizontal, Tokens.railInsetH)
    }

    private var rowBackground: Color {
        if selected { return theme.accent }
        if hover { return Color.black.opacity(0.05) }
        return .clear
    }
}
```

- [ ] **Step 2: Build & commit**

Run: `swift build`
Expected: succeeds.

```bash
git add Sources/GitWorkbench/Views/Rail/WorkspaceRail.swift
git commit -m "Chrome: add WorkspaceRail (Workspace/Branches/Remotes)"
```

---

### Task 3: GitWorkbenchView composition + toast overlay

**Files:**
- Modify: `Sources/GitWorkbench/GitWorkbenchView.swift` (replace the skeleton body with the real composition)

> Compose toolbar + (rail + active-view body), inject the resolved theme, overlay the toast (auto-dismissing non-progress toasts), and switch the body on `activeView`. The three bodies are temporary `EmptyState` placeholders (Plans 7–8 replace them).

- [ ] **Step 1: Replace `GitWorkbenchView.swift`**

```swift
import SwiftUI

/// The reusable git-workbench component: toolbar + rail + active workspace view, themed and toasted.
public struct GitWorkbenchView: View {
    @ObservedObject private var store: GitWorkbenchStore
    @Environment(\.colorScheme) private var colorScheme

    public init(store: GitWorkbenchStore) {
        self.store = store
    }

    private var configuration: WorkbenchConfiguration { store.configuration }
    private var theme: WorkbenchTheme {
        WorkbenchTheme.resolved(for: colorScheme,
                                adoptsSystemAccent: configuration.theme.adoptsSystemAccent)
    }

    public var body: some View {
        VStack(spacing: 0) {
            if configuration.showsToolbar { WorkbenchToolbar(store: store) }
            HStack(spacing: 0) {
                WorkspaceRail(store: store)
                body(for: store.state.activeView)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(theme.winBg)
        .foregroundStyle(theme.ink)
        .workbenchTheme(theme)
        .overlay(alignment: .bottom) { toastOverlay }
        .task { await store.reload() }
    }

    @ViewBuilder
    private func body(for view: WorkspaceView) -> some View {
        switch view {
        case .changes: placeholder(IconLibrary.file, "Changes")
        case .history: placeholder(IconLibrary.history, "History")
        case .stashes: placeholder(IconLibrary.folder, "Stashes")
        }
    }

    // Temporary — replaced by the real Changes/History/Stash views in Plans 7–8.
    private func placeholder(_ icon: String, _ title: String) -> some View {
        EmptyState(icon: icon, title: title, subtitle: "View coming in the next plan.")
            .background(theme.winBg)
    }

    @ViewBuilder
    private var toastOverlay: some View {
        if let toast = store.state.toast {
            ToastView(toast: toast)
                .padding(.bottom, Tokens.toastBottomInset)
                .transition(.opacity)
                .task(id: toast.id) {
                    guard toast.style != .progress else { return }
                    try? await Task.sleep(for: .seconds(2.2))
                    store.dismissToast()
                }
        }
    }
}

#Preview("Workbench — light") {
    GitWorkbenchView(store: .preview).frame(width: 1100, height: 680)
}

#Preview("Workbench — dark") {
    GitWorkbenchView(store: .preview).frame(width: 1100, height: 680).preferredColorScheme(.dark)
}
```

- [ ] **Step 2: Build & run the full suite**

Run: `swift build && swift test`
Expected: build succeeds (previews compile); all tests pass.

- [ ] **Step 3: Verify the chrome renders**

Open `Package.swift` in Xcode and resume the canvas for `GitWorkbenchView.swift`. Confirm: the toolbar shows "aurora-cli", Pull 1 / Push 2 / Fetch, the branch pill, History/Stash toggles, and the unified/split control; the rail shows Workspace (Changes 7 / History 6 / Stashes 2), Branches (feat/auto-sync bold with HEAD), Remotes; clicking History/Stash highlights them; the branch pill opens the menu. Light + dark both correct.

- [ ] **Step 4: Commit**

```bash
git add Sources/GitWorkbench/GitWorkbenchView.swift
git commit -m "Chrome: compose GitWorkbenchView (toolbar + rail + body switch + toast)"
```

---

## Self-Review

**1. Spec coverage (vs. §03 Toolbar/Rail/BranchMenu):**
- Toolbar: repo cluster, pull/push/fetch (+counts, busy-disabled), divider, branch pill (+popover), History/Stash toggles (active state), unified/split segmented → Task 1 ✓
- BranchMenu: header, per-branch rows (current = semibold/accent/ahead-behind/checkmark, hover), "New branch from HEAD…" → Task 1 ✓
- Rail: Workspace (counts, selection), Branches (current bold + HEAD pill, switch), Remotes (origin + indented upstream) → Task 2 ✓
- GitWorkbenchView composition: toolbar + rail + body switch + theme injection + toast overlay (auto-dismiss) → Task 3 ✓
- Store intents `setBranchMenuOpen`/`dismissToast` → Task 1 ✓
- **Temporary:** the three workspace bodies are `EmptyState` placeholders; Plans 7–8 supply the real Changes/History/Stash views. ⌘-shortcuts and context menus are deferred to the a11y/polish plan.

**2. Placeholder scan:** Complete code in every step; the placeholders in `body(for:)` are explicitly temporary and labeled. Manual canvas check in Task 3.

**3. Type/signature consistency:** `WorkbenchToolbar`/`WorkspaceRail`/`BranchMenu` take `@ObservedObject store`. `store.setBranchMenuOpen`/`dismissToast`/`select`/`setDiffMode`/`pull`/`push`/`fetch`/`switchBranch` (Plans 3 + this) used consistently. `ToolButton`/`BranchPill`/`Segmented`/`SegmentedOption`/`EmptyState`/`ToastView` (Plan 4), `Tokens.*`/`IconLibrary.*`/`\.workbenchTheme`/`WorkbenchTheme.resolved` (Plans 1/4) used correctly. `GitWorkbenchView(store:)` (Plan 3) keeps its public signature.
