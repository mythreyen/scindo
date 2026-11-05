import SwiftUI

/// Ultra-refined Liquid Glass: multi-layer chromatic refraction, specular caustic sheen,
/// luminous dual-tone border bevels, and atmospheric glass depth.
public struct LiquidGlassModifier<S: InsettableShape>: ViewModifier {
    let shape: S

    public func body(content: Content) -> some View {
        content
            .clipShape(shape)
            .background(
                ZStack {
                    // 1. Pure vector shape shadow BEHIND everything (completely decoupled from Material layer)
                    shape
                        .fill(Color.black.opacity(0.20))
                        .shadow(color: Color.black.opacity(0.24), radius: 10, x: 0, y: 5)
                        .shadow(color: Color.black.opacity(0.10), radius: 3, x: 0, y: 1)

                    // 2. Translucent dark base preventing raw desktop capture flash during window moves
                    shape.fill(Color(white: 0.14, opacity: 0.65))

                    // 3. Base refractive blur & ambient translucent body
                    shape.fill(.ultraThinMaterial)

                    // 4. Liquid Glass internal gradient & specular sheen
                    shape.fill(
                        LinearGradient(
                            stops: [
                                .init(color: Color.white.opacity(0.36), location: 0.0),
                                .init(color: Color.white.opacity(0.12), location: 0.35),
                                .init(color: Color.white.opacity(0.02), location: 0.65),
                                .init(color: Color.black.opacity(0.14), location: 1.0)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                }
            )
            // 5. Top-edge caustic refraction glow
            .overlay(
                shape.fill(
                    RadialGradient(
                        colors: [
                            Color.white.opacity(0.42),
                            Color.white.opacity(0.10),
                            Color.clear
                        ],
                        center: .top,
                        startRadius: 0,
                        endRadius: 200
                    )
                )
                .allowsHitTesting(false)
            )
            // 5. Inner refraction lens edge (beveled glass rim)
            .overlay(
                shape.inset(by: 0.5)
                    .strokeBorder(
                        LinearGradient(
                            stops: [
                                .init(color: Color.white.opacity(0.90), location: 0.0),
                                .init(color: Color.white.opacity(0.45), location: 0.30),
                                .init(color: Color.white.opacity(0.12), location: 0.65),
                                .init(color: Color.white.opacity(0.50), location: 1.0)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1.25
                    )
                    .allowsHitTesting(false)
            )
            // 6. Outer fine hairline rim
            .overlay(
                shape.strokeBorder(Color.black.opacity(0.16), lineWidth: 0.5)
                    .allowsHitTesting(false)
            )
    }
}

extension View {
    public func liquidGlass<S: InsettableShape>(in shape: S) -> some View {
        modifier(LiquidGlassModifier(shape: shape))
    }
}
