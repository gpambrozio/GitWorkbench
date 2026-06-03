import Foundation

/// The change kind for one file, mirroring git's status glyphs.
public enum FileStatus: String, Sendable, CaseIterable, Hashable {
    case modified   = "M"
    case added      = "A"
    case deleted    = "D"
    case renamed    = "R"
    case untracked  = "U"
    case conflicted = "!"   // merge conflict; sorts to top in the file list

    /// Long label shown in the diff header.
    public var label: String {
        switch self {
        case .modified:   return "Modified"
        case .added:      return "Added"
        case .deleted:    return "Deleted"
        case .renamed:    return "Renamed"
        case .untracked:  return "Untracked"
        case .conflicted: return "Conflicted"
        }
    }
}
