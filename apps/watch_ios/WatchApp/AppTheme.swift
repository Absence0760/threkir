import SwiftUI

/// App-wide color palette: "Dusk, refined" (decisions § 1772), the dark half.
/// Mirrors `packages/ui_kit/lib/src/theme/app_theme.dart` and the Wear OS
/// `DuskPalette`. Keep hex values in sync when either side changes.
enum AppTheme {
    static let night = Color(red: 0x12 / 255, green: 0x11 / 255, blue: 0x17 / 255)
    static let nightRaised = Color(red: 0x1C / 255, green: 0x1A / 255, blue: 0x24 / 255)
    static let coral = Color(red: 0xF0 / 255, green: 0x8A / 255, blue: 0x5D / 255)
    /// The deep coral, used as a button fill under white type (4.77:1).
    static let coralDeep = Color(red: 0xC2 / 255, green: 0x4E / 255, blue: 0x24 / 255)
    static let lilac = Color(red: 0xB9 / 255, green: 0xA7 / 255, blue: 0xE8 / 255)
    static let mist = Color(red: 0xF3 / 255, green: 0xF1 / 255, blue: 0xF7 / 255)
    static let mistMuted = Color(red: 0xC6 / 255, green: 0xC2 / 255, blue: 0xCF / 255)
    static let error = Color(red: 0xD8 / 255, green: 0x59 / 255, blue: 0x4C / 255)
}
