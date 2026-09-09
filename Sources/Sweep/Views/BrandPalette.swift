import AppKit
import SwiftUI

struct BrandCategoryTokens {
    let top: Color
    let bottom: Color
    let glow: Color
}

enum BrandPalette {
    static func hex(_ value: UInt32, opacity: Double = 1) -> Color {
        Color(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
        .opacity(opacity)
    }

    static func adaptive(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(srgb: isDark ? dark : light)
        })
    }

    static func resolve(light: Double, dark: Double, in scheme: ColorScheme) -> Double {
        scheme == .dark ? dark : light
    }
}

extension BrandPalette {
    enum Brand {
        static let deep = hex(0x0A0E2E)
        static let midnight = hex(0x0C1134)
        static let indigo = hex(0x4634CE)
        static let violet = hex(0x7F52FF)
        static let ice = hex(0xDFE8FF)
        static let halo = hex(0xA9C4FF)
        static let primary = hex(0x1F6BFA)
        static let primaryDeep = hex(0x0F46C4)

        static let signature = LinearGradient(
            colors: [deep, midnight, indigo, violet],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    enum Category {
        static let caches = BrandCategoryTokens(
            top: adaptive(0x5CBDFF, 0x6FC2FF),
            bottom: adaptive(0x1F6BFA, 0x2E7BFF),
            glow: adaptive(0x3D8BFF, 0x5C9CFF)
        )

        static let logs = BrandCategoryTokens(
            top: adaptive(0x9EADC7, 0xA8B4CC),
            bottom: adaptive(0x59667F, 0x6E7A94),
            glow: adaptive(0x75859E, 0x8E99B5)
        )

        static let trash = BrandCategoryTokens(
            top: adaptive(0xFF756B, 0xFF8A7E),
            bottom: adaptive(0xDE2E47, 0xF03A52),
            glow: adaptive(0xF2575C, 0xFF6B72)
        )

        static let developer = BrandCategoryTokens(
            top: adaptive(0xB88FFF, 0xC3ACFF),
            bottom: adaptive(0x664FF0, 0x7A62FF),
            glow: adaptive(0x8A6BFF, 0x9B7EFF)
        )

        static let largeFiles = BrandCategoryTokens(
            top: adaptive(0xFFBD52, 0xFFC96B),
            bottom: adaptive(0xF5701A, 0xFA8226),
            glow: adaptive(0xFA9232, 0xFFA544)
        )
    }

    enum Semantic {
        static let neutral = BrandCategoryTokens(
            top: adaptive(0x7AA3FF, 0x8DB7FF),
            bottom: adaptive(0x5766F5, 0x6A62FF),
            glow: adaptive(0x4D7BFF, 0x6A92FF)
        )

        static let brand = BrandCategoryTokens(
            top: adaptive(0x7F52FF, 0x8F66FF),
            bottom: adaptive(0x4634CE, 0x5A45E8),
            glow: adaptive(0x6A4BFF, 0x8464FF)
        )

        static let success = BrandCategoryTokens(
            top: adaptive(0x57DB80, 0x63E68C),
            bottom: adaptive(0x1F9E4D, 0x28B85C),
            glow: adaptive(0x34C759, 0x3ED967)
        )

        static let warning = BrandCategoryTokens(
            top: adaptive(0xFFB847, 0xFFC96B),
            bottom: adaptive(0xF25C1F, 0xFA7E22),
            glow: adaptive(0xFA9232, 0xFFA544)
        )

        static let danger = Category.trash

        static let caution = adaptive(0xB45309, 0xFF9F0A)
    }

    enum Radius {
        static let tileFactor: CGFloat = 0.30
        static let inset: CGFloat = 7
        static let chip: CGFloat = 10
        static let field: CGFloat = 12
        static let card: CGFloat = 18
    }

    enum Surface {
        static let softGradientOpacity: Double = 0.18
        static let tileStrokeLight: Double = 0.42
        static let tileStrokeDark: Double = 0.20
        static let glassStrokeLight: Double = 0.60
        static let glassStrokeDark: Double = 0.22
        static let glassStrokeFade: Double = 0.02
        static let hairline: CGFloat = 0.8
        static let trackOpacity: Double = 0.08
    }

    enum Elevation {
        static let tileGlowLight: Double = 0.26
        static let tileGlowDark: Double = 0.38
        static let tileGlowRadiusFactor: CGFloat = 0.24
        static let tileGlowOffsetFactor: CGFloat = 0.11
        static let tileSymbolShadowOpacity: Double = 0.18
        static let tileSymbolShadowRadius: CGFloat = 1
        static let tileSymbolShadowOffset: CGFloat = 0.5
        static let glassShadowLight: Double = 0.09
        static let glassShadowDark: Double = 0.34
        static let glassShadowRadius: CGFloat = 12
        static let glassShadowOffset: CGFloat = 5
    }
}

private extension NSColor {
    convenience init(srgb value: UInt32) {
        self.init(
            srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: 1
        )
    }
}
