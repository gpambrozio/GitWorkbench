import SwiftUI

/// OKLCH → sRGB conversion (Björn Ottosson's matrices). Used for author avatar discs.
enum OKLCH {
    /// Returns gamma-encoded sRGB components in 0...1 for OKLCH (L in 0...1, C, H in degrees).
    static func srgb(l: Double, c: Double, h: Double) -> (r: Double, g: Double, b: Double) {
        let hr = h * .pi / 180
        let a = c * cos(hr)
        let bb = c * sin(hr)

        // OKLab → LMS (nonlinear), then cube
        let l_ = l + 0.3963377774 * a + 0.2158037573 * bb
        let m_ = l - 0.1055613458 * a - 0.0638541728 * bb
        let s_ = l - 0.0894841775 * a - 1.2914855480 * bb
        let lc = l_ * l_ * l_
        let mc = m_ * m_ * m_
        let sc = s_ * s_ * s_

        // LMS → linear sRGB
        let rl =  4.0767416621 * lc - 3.3077115913 * mc + 0.2309699292 * sc
        let gl = -1.2684380046 * lc + 2.6097574011 * mc - 0.3413193965 * sc
        let bl = -0.0041960863 * lc - 0.7034186147 * mc + 1.7076147010 * sc

        return (gamma(rl), gamma(gl), gamma(bl))
    }

    /// Convenience: an sRGB `Color` for the given OKLCH.
    static func color(l: Double, c: Double, h: Double) -> Color {
        let (r, g, b) = srgb(l: l, c: c, h: h)
        return Color(.sRGB, red: r, green: g, blue: b, opacity: 1)
    }

    private static func gamma(_ x: Double) -> Double {
        let v = max(0, min(1, x))
        return v <= 0.0031308 ? 12.92 * v : 1.055 * pow(v, 1 / 2.4) - 0.055
    }
}
