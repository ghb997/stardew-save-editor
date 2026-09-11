import SwiftUI

enum AppLayout {
    static let pageWidth: CGFloat = 960
    static let editorWidth: CGFloat = 1_040

    static func pairedColumns(for typeSize: DynamicTypeSize) -> [GridItem] {
        Array(repeating: GridItem(.flexible(), alignment: .top),
              count: typeSize.isAccessibilitySize ? 1 : 2)
    }

    static func mapSize(in viewport: CGSize, zoom: CGFloat) -> CGSize {
        let width = max(1, min(viewport.width - 32, (viewport.height - 32) * 1.28))
        return CGSize(width: width * zoom, height: width * zoom / 1.28)
    }
}

extension View {
    /// Keep the background full width while limiting text and controls to a
    /// readable column. The proposed width still follows Split View resizing.
    func readablePageWidth(_ maximum: CGFloat = AppLayout.pageWidth) -> some View {
        frame(maxWidth: maximum).frame(maxWidth: .infinity)
    }

    func adaptiveSegmentedPicker() -> some View {
        modifier(AdaptiveSegmentedPicker())
    }
}

private struct AdaptiveSegmentedPicker: ViewModifier {
    @Environment(\.dynamicTypeSize) private var typeSize

    @ViewBuilder
    func body(content: Content) -> some View {
        if typeSize.isAccessibilitySize {
            content.pickerStyle(.menu)
        } else {
            content.pickerStyle(.segmented)
        }
    }
}

#if DEBUG
/// Deterministic narrow-window coverage on Simulator. Release layouts always
/// receive the actual window proposal from iPadOS.
struct DebugLayoutViewport: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if let width = requestedWidth {
            GeometryReader { proxy in
                content
                    .environment(\.horizontalSizeClass, .compact)
                    .frame(width: min(width, proxy.size.width))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(AppTheme.canvas)
        } else {
            content
        }
    }

    private var requestedWidth: CGFloat? {
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: "--ui-layout-width"),
              args.indices.contains(index + 1), let width = Double(args[index + 1]),
              width >= 320, width.isFinite else { return nil }
        return CGFloat(width)
    }
}
#endif
