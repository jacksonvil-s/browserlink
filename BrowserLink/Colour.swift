import SwiftUI
import AppKit

extension Color {
    /// Parses a 6-digit hex string like "FF6B35" into a Color.
    /// Returns nil for anything malformed, so callers can fall back safely.
    init?(hex: String) {
        var sanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        sanitized = sanitized.replacingOccurrences(of: "#", with: "")

        guard sanitized.count == 6, let value = UInt32(sanitized, radix: 16) else {
            return nil
        }

        let r = Double((value >> 16) & 0xFF) / 255
        let g = Double((value >> 8) & 0xFF) / 255
        let b = Double(value & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }

    /// Converts back to a "RRGGBB" hex string for persisting.
    func toHex() -> String? {
        // sRGB, because that's what `init?(hex:)` reads the value back as.
        guard let components = NSColor(self).usingColorSpace(.sRGB)?.cgColor.components,
              components.count >= 3 else { return nil }
        // Round (don't truncate) so 0.2 * 255 = 50.999… becomes 51, not 50.
        func byte(_ value: CGFloat) -> Int { min(255, max(0, Int((value * 255).rounded()))) }
        return String(format: "%02X%02X%02X", byte(components[0]), byte(components[1]), byte(components[2]))
    }
}
