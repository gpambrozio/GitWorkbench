import Foundation

/// Maps author initials to an OKLCH hue. Fixture authors are pinned to the prototype's hues;
/// others derive a stable hue from their initials.
func authorHue(_ initials: String) -> Double {
    switch initials {
    case "GA": return 295
    case "MP": return 25
    default:
        let sum = initials.unicodeScalars.reduce(0) { $0 + Int($1.value) }
        return Double(sum % 360)
    }
}
