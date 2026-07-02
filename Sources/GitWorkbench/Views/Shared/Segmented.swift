import SwiftUI

/// One option in a `Segmented` control.
struct SegmentedOption<Value: Hashable>: Identifiable {
    var value: Value
    var icon: String? = nil
    var label: String? = nil
    var id: Value { value }
}

/// Track + white selected segment (handoff §04 §4.3). Generic over a `Hashable` value.
struct Segmented<Value: Hashable>: View {
    @Environment(\.workbenchTheme) private var theme
    @Binding var value: Value
    let options: [SegmentedOption<Value>]

    /// The selected segment sits on an always-white pill (below), so its ink must stay dark in both
    /// schemes — `theme.ink` flips to near-white in dark mode and would vanish on the white fill.
    private var selectedInk: Color { WorkbenchTheme.standard.ink }

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options) { option in
                let isSelected = option.value == value
                Button { value = option.value } label: {
                    HStack(spacing: 5) {
                        if let icon = option.icon { Image(systemName: icon) }
                        if let label = option.label { Text(label) }
                    }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(isSelected ? selectedInk : theme.ink2)
                    .padding(.horizontal, 10)
                    .frame(height: 22)
                    .background {
                        if isSelected {
                            RoundedRectangle(cornerRadius: Tokens.segmentInnerRadius, style: .continuous)
                                .fill(.white)
                                .shadow(color: Color.black.opacity(0.14), radius: 1, y: 1)
                        }
                    }
                    .contentShape(Rectangle())   // whole segment is tappable, not just the icon
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(Color.black.opacity(0.06),
                    in: RoundedRectangle(cornerRadius: Tokens.segmentOuterRadius, style: .continuous))
    }
}

#Preview("Segmented") {
    struct Wrap: View {
        @State var mode: DiffMode = .split
        var body: some View {
            Segmented(value: $mode, options: [
                .init(value: .unified, icon: IconLibrary.unifiedRows),
                .init(value: .split, icon: IconLibrary.splitColumns),
            ])
            .padding()
        }
    }
    return Wrap()
}
