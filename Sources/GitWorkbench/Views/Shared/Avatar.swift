import SwiftUI

/// A monogram disc, colored by an OKLCH hue (handoff §03: `oklch(0.62 0.15 hue)`).
struct Avatar: View {
    let initials: String
    var size: CGFloat = 26
    var hue: Double

    var body: some View {
        Circle()
            .fill(OKLCH.color(l: 0.62, c: 0.15, h: hue))
            .overlay(Circle().strokeBorder(Color.black.opacity(0.10), lineWidth: 0.5))
            .overlay(
                Text(initials)
                    .font(.system(size: size * 0.42, weight: .semibold))
                    .foregroundStyle(.white)
            )
            .frame(width: size, height: size)
    }
}

#Preview("Avatars") {
    HStack(spacing: 12) {
        Avatar(initials: "GA", hue: 295)
        Avatar(initials: "MP", hue: 25)
        Avatar(initials: "GA", size: 40, hue: 295)
    }
    .padding()
}
