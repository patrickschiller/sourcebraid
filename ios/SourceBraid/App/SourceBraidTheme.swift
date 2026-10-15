import SwiftUI
import UIKit

/// SourceBraid's paper-and-teal palette, resolved by the system for appearance
/// and increased contrast. Keep native controls, typography and safe areas.
enum SourceBraidTheme {
    static let canvas = Color("BrandCanvas")
    static let surface = Color("BrandSurface")
    static let ink = Color("BrandInk")
    static let secondaryInk = Color("BrandSecondaryInk")
    static let mutedSurface = Color("BrandMutedSurface")
    static let separator = Color("BrandSeparator")
    static let onAccent = Color("BrandOnAccent")

    static var uiSurface: UIColor { UIColor(named: "BrandSurface") ?? .systemBackground }
}
