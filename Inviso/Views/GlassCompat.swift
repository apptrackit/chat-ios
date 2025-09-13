import SwiftUI

/// A forward-compatible container that mimics Liquid Glass grouping.
/// On iOS 26+, replace usages with `GlassEffectContainer(spacing:content:)`
/// and apply `.glassEffect(_, in:)` to child shapes as needed.
struct GlassLikeContainer<Content: View>: View {
    let spacing: CGFloat?
    @ViewBuilder var content: Content

    init(spacing: CGFloat? = nil, @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.content = content()
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity)
            .background(
                // Edge-to-edge translucent backdrop to approximate glass
                Rectangle()
                    .fill(.ultraThinMaterial)
            )
    }
}

// Modifier to conditionally wrap content in the appropriate glass container.
struct GlassContainerModifier: ViewModifier {
    func body(content: Content) -> some View {
        Group {
            if #available(iOS 26.0, *) {
                // When iOS 26 is available, use the native container and default shapes
                GlassEffectContainer(spacing: nil) {
                    content
                }
            } else {
                GlassLikeContainer(spacing: nil) {
                    content
                }
            }
        }
    }
}
