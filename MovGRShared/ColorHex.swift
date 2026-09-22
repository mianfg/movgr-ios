import SwiftUI

public extension Color {
    init(hex: String?, fallback: Color = Color(.systemGray)) {
        guard let hex, !hex.isEmpty else {
            self = fallback
            return
        }
        var cleaned = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("#") { cleaned.removeFirst() }
        guard cleaned.count == 6, let value = UInt64(cleaned, radix: 16) else {
            self = fallback
            return
        }
        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}

public enum BrandColor {
    public static let metro = Color(hex: "e11d48")
    public static let live = Color(red: 16 / 255, green: 185 / 255, blue: 129 / 255)
    public static let ctagr = Color(hex: "15803d")
    public static let ctagrFill = Color.white
}
