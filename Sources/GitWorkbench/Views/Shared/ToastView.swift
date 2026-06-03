import SwiftUI

/// The toast capsule. A spinner for `.progress`; a colored glyph for success/error/info.
struct ToastView: View {
    let toast: Toast

    var body: some View {
        HStack(spacing: 8) {
            leading
            Text(toast.message)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .background(Color.black.opacity(0.92), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .shadow(color: Color.black.opacity(0.34), radius: 15, y: 8)
    }

    @ViewBuilder private var leading: some View {
        switch toast.style {
        case .progress:
            ProgressView().controlSize(.small).tint(.white)
        case .success:
            Image(systemName: IconLibrary.check).foregroundStyle(Color(hex: 0x4FBE7C))
        case .error:
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Color(hex: 0xE36258))
        case .info:
            Image(systemName: "info.circle.fill").foregroundStyle(.white.opacity(0.9))
        }
    }
}

#Preview("ToastView") {
    VStack(spacing: 12) {
        ToastView(toast: .success("Committed 3 files"))
        ToastView(toast: .error("Push rejected \u{2014} pull first"))
        ToastView(toast: .progress("Pushing to origin\u{2026}"))
    }
    .padding(40)
    .background(Color.gray)
}
