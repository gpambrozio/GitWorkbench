import Foundation

/// Renderable content for a binary file the component can display directly (images, PDFs).
///
/// The component never reads the filesystem or runs `git`, so the host's provider supplies the raw
/// bytes of the pre- and post-change blobs. A nil side means the file didn't exist there, which
/// also encodes the change kind:
/// - `old == nil` → **added** (nothing to compare against; show the new content on its own)
/// - `new == nil` → **deleted**
/// - both present → **modified** (offers the before/after comparison)
///
/// A provider only sets this for kinds the built-in viewers understand (see ``kind(forPath:)``);
/// any other binary leaves it `nil`, so the pane falls back to the plain "Binary file" placeholder.
public struct BinaryContent: Sendable, Hashable {
    /// Which built-in viewer renders this file.
    public enum Kind: Sendable, Hashable {
        case image
        case pdf
    }

    public var kind: Kind
    /// Bytes of the pre-change blob; `nil` when the file was added.
    public var old: Data?
    /// Bytes of the post-change blob; `nil` when the file was deleted.
    public var new: Data?

    public init(kind: Kind, old: Data?, new: Data?) {
        self.kind = kind
        self.old = old
        self.new = new
    }

    /// Infers the renderable kind from a path's file extension, or `nil` for a binary the built-in
    /// viewers can't display (which keeps the plain "Binary file" placeholder). Extension-based —
    /// the same heuristic `git` and most diff tools use to pick a viewer.
    public static func kind(forPath path: String) -> Kind? {
        switch (path as NSString).pathExtension.lowercased() {
        case "png", "jpg", "jpeg", "gif", "bmp", "tiff", "tif", "heic", "heif", "webp", "ico":
            return .image
        case "pdf":
            return .pdf
        default:
            return nil
        }
    }
}
