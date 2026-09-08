import SwiftUI

struct CategoryStyle {
    let colors: [Color]
    let glow: Color

    init(colors: [Color], glow: Color) {
        self.colors = colors
        self.glow = glow
    }

    init(tokens: BrandCategoryTokens) {
        self.init(colors: [tokens.top, tokens.bottom], glow: tokens.glow)
    }

    var gradient: LinearGradient {
        LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    var softGradient: LinearGradient {
        LinearGradient(
            colors: colors.map { $0.opacity(BrandPalette.Surface.softGradientOpacity) },
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    var angularGradient: AngularGradient {
        AngularGradient(colors: colors + [colors[0]], center: .center)
    }

    static func of(_ category: SpaceCategory) -> CategoryStyle {
        switch category {
        case .caches: CategoryStyle(tokens: BrandPalette.Category.caches)
        case .logs: CategoryStyle(tokens: BrandPalette.Category.logs)
        case .trash: CategoryStyle(tokens: BrandPalette.Category.trash)
        case .developer: CategoryStyle(tokens: BrandPalette.Category.developer)
        case .largeFiles: CategoryStyle(tokens: BrandPalette.Category.largeFiles)
        }
    }

    static let neutral = CategoryStyle(tokens: BrandPalette.Semantic.neutral)

    static let brand = CategoryStyle(tokens: BrandPalette.Semantic.brand)

    static let success = CategoryStyle(tokens: BrandPalette.Semantic.success)

    static let warning = CategoryStyle(tokens: BrandPalette.Semantic.warning)

    static let danger = CategoryStyle(tokens: BrandPalette.Semantic.danger)
}

struct GradientIconTile: View {
    let symbol: String
    let style: CategoryStyle
    var size: CGFloat = 28

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * BrandPalette.Radius.tileFactor, style: .continuous)

        shape
            .fill(style.gradient)
            .frame(width: size, height: size)
            .overlay {
                Image(systemName: symbol)
                    .font(.system(size: size * 0.46, weight: .semibold))
                    .foregroundStyle(.white)
                    .shadow(
                        color: .black.opacity(BrandPalette.Elevation.tileSymbolShadowOpacity),
                        radius: BrandPalette.Elevation.tileSymbolShadowRadius,
                        y: BrandPalette.Elevation.tileSymbolShadowOffset
                    )
            }
            .overlay {
                shape.strokeBorder(
                    .white.opacity(BrandPalette.resolve(
                        light: BrandPalette.Surface.tileStrokeLight,
                        dark: BrandPalette.Surface.tileStrokeDark,
                        in: colorScheme
                    )),
                    lineWidth: BrandPalette.Surface.hairline
                )
            }
            .shadow(
                color: style.glow.opacity(BrandPalette.resolve(
                    light: BrandPalette.Elevation.tileGlowLight,
                    dark: BrandPalette.Elevation.tileGlowDark,
                    in: colorScheme
                )),
                radius: size * BrandPalette.Elevation.tileGlowRadiusFactor,
                y: size * BrandPalette.Elevation.tileGlowOffsetFactor
            )
    }
}

struct IconMedallion: View {
    let symbol: String
    let style: CategoryStyle
    var size: CGFloat = 64

    var body: some View {
        ZStack {
            Circle()
                .fill(style.softGradient)
                .frame(width: size * 1.45, height: size * 1.45)
                .blur(radius: size * 0.16)
            GradientIconTile(symbol: symbol, style: style, size: size)
        }
        .frame(width: size * 1.45, height: size * 1.45)
    }
}

struct SpinningRing: View {
    var size: CGFloat = 22
    var lineWidth: CGFloat = 2.5
    let gradient: AngularGradient

    @State private var spinning = false

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.primary.opacity(BrandPalette.Surface.trackOpacity), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: 0.30)
                .stroke(gradient, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(spinning ? 360 : 0))
                .animation(.linear(duration: 0.9).repeatForever(autoreverses: false), value: spinning)
        }
        .frame(width: size, height: size)
        .onAppear { spinning = true }
    }
}

private struct GlassSurfaceModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.ultraThinMaterial)
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                .white.opacity(BrandPalette.resolve(
                                    light: BrandPalette.Surface.glassStrokeLight,
                                    dark: BrandPalette.Surface.glassStrokeDark,
                                    in: colorScheme
                                )),
                                .white.opacity(BrandPalette.Surface.glassStrokeFade)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: BrandPalette.Surface.hairline
                    )
            }
            .shadow(
                color: .black.opacity(BrandPalette.resolve(
                    light: BrandPalette.Elevation.glassShadowLight,
                    dark: BrandPalette.Elevation.glassShadowDark,
                    in: colorScheme
                )),
                radius: BrandPalette.Elevation.glassShadowRadius,
                y: BrandPalette.Elevation.glassShadowOffset
            )
    }
}

extension View {
    func glassSurface(cornerRadius: CGFloat = BrandPalette.Radius.card) -> some View {
        modifier(GlassSurfaceModifier(cornerRadius: cornerRadius))
    }
}
