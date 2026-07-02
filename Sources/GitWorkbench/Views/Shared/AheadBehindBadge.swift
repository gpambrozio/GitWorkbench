import SwiftUI

/// A branch's divergence from its upstream, as "{ahead}↑ {behind}↓" in tabular tertiary text — e.g.
/// "2↑ 1↓", "2↑", or "1↓". Renders nothing when the branch is in sync (both zero) or has no
/// upstream, so callers can drop it in unconditionally. Ordering and the ↑ahead / ↓behind arrows
/// follow the design handoff [03 §Branch menu] and the convention used elsewhere (toolbar Pull/Push,
/// the LiveDemo window subtitle): ↑ = commits to push, ↓ = commits to pull.
struct AheadBehindBadge: View {
    @Environment(\.workbenchTheme) private var theme
    var ahead: Int
    var behind: Int
    /// Selected rows paint an accent background, so the text switches to white to stay legible.
    var onAccent: Bool = false

    var body: some View {
        if ahead > 0 || behind > 0 {
            HStack(spacing: 5) {
                if ahead > 0 { Text("\(ahead)\u{2191}") }   // ↑ commits ahead of upstream (to push)
                if behind > 0 { Text("\(behind)\u{2193}") } // ↓ commits behind upstream (to pull)
            }
            .font(.system(size: 11, weight: .semibold).monospacedDigit())
            .foregroundStyle(onAccent ? Color.white.opacity(0.85) : theme.ink3)
            .fixedSize()   // keep the counts intact; the branch name (lineLimit 1) truncates instead
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(voiceOverLabel)
        }
    }

    /// Spell the arrows out for VoiceOver ("2 ahead, 1 behind") rather than reading the glyphs.
    private var voiceOverLabel: String {
        var parts: [String] = []
        if ahead > 0 { parts.append("\(ahead) ahead") }
        if behind > 0 { parts.append("\(behind) behind") }
        return parts.joined(separator: ", ")
    }
}

#Preview("AheadBehindBadge") {
    VStack(alignment: .leading, spacing: 8) {
        AheadBehindBadge(ahead: 2, behind: 1)
        AheadBehindBadge(ahead: 3, behind: 0)
        AheadBehindBadge(ahead: 0, behind: 4)
        AheadBehindBadge(ahead: 0, behind: 0)   // renders nothing
    }
    .padding()
}
