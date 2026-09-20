import SwiftUI
import UIKit

/// Semantic colors shared by every screen, including presented editors.
enum AppTheme {
    static let canvas = adaptive(0xE8C486, 0x202C2B)
    static let card = adaptive(0xFFE6B0, 0x393C31)
    static let header = adaptive(0xDDA45B, 0x514B36)
    static let headerSoft = adaptive(0xF6D18C, 0x494B36)
    static let ink = adaptive(0x512E1D, 0xFFE7B8)
    static let secondary = adaptive(0x795B38, 0xCEC19D)
    static let accent = adaptive(0x783D23, 0xF5C879)
    static let border = adaptive(0x673D24, 0x141F1E)
    static let wood = adaptive(0xBD793D, 0x8A7249)
    static let highlight = adaptive(0xFFF4CE, 0xA08B60)
    static let selection = adaptive(0xF2BD62, 0x65603D)
    static let progress = adaptive(0x497239, 0xA5CD80)
    static let danger = adaptive(0xA4392C, 0xFFA295)
    static let information = adaptive(0x315B76, 0x9ACDD9)
    static let inset = adaptive(0xF3D399, 0x2D372E)
    static let sky = adaptive(0x85C9D5, 0x223C4B)
    static let mountain = adaptive(0x679A8A, 0x32594F)
    static let meadow = adaptive(0x719A46, 0x405D3B)
    static let title = ink
    static let muted = secondary
    static let trackerHeader = header
    static let trackerHeaderSoft = headerSoft
    static let trackerSelection = selection
    static let trackerTitle = ink
    static let trackerAccent = accent
    static let trackerRow = adaptive(0xE5DEAA, 0x354333)
    static let trackerWarning = adaptive(0x874516, 0xF5C879)
    static let trackerSecondary = secondary

    private static func adaptive(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            let hex = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: CGFloat((hex >> 16) & 255) / 255,
                           green: CGFloat((hex >> 8) & 255) / 255,
                           blue: CGFloat(hex & 255) / 255, alpha: 1)
        })
    }

    @MainActor static func installNativeAppearance() {
        let navigation = UINavigationBarAppearance()
        navigation.configureWithOpaqueBackground()
        navigation.backgroundColor = UIColor(card)
        navigation.shadowColor = UIColor(wood)
        navigation.titleTextAttributes = [.foregroundColor: UIColor(ink)]
        navigation.largeTitleTextAttributes = [.foregroundColor: UIColor(ink)]
        UINavigationBar.appearance().standardAppearance = navigation
        UINavigationBar.appearance().scrollEdgeAppearance = navigation
        UINavigationBar.appearance().compactAppearance = navigation
        let tab = UITabBarAppearance()
        tab.configureWithOpaqueBackground()
        tab.backgroundColor = UIColor(card)
        tab.shadowColor = UIColor(border)
        for layout in [tab.stackedLayoutAppearance, tab.inlineLayoutAppearance, tab.compactInlineLayoutAppearance] {
            layout.normal.titleTextAttributes = [.foregroundColor: UIColor(secondary)]
            layout.selected.titleTextAttributes = [.foregroundColor: UIColor(accent)]
        }
        UITabBar.appearance().standardAppearance = tab
        UITabBar.appearance().scrollEdgeAppearance = tab
        UISegmentedControl.appearance().selectedSegmentTintColor = UIColor(selection)
        UISegmentedControl.appearance().backgroundColor = UIColor(inset)
        UISegmentedControl.appearance().setTitleTextAttributes([.foregroundColor: UIColor(ink)], for: .normal)
    }

    /// Tab bars use UIImage intrinsic size; never pass an uncapped sprite sheet.
    @MainActor static func tabImage(_ asset: String) -> UIImage {
        guard let source = UIImage(named: asset) else { return UIImage() }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 3
        let side: CGFloat = 26
        return UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { context in
            context.cgContext.interpolationQuality = .none
            let scale = min(side / source.size.width, side / source.size.height)
            let size = CGSize(width: source.size.width * scale, height: source.size.height * scale)
            source.draw(in: CGRect(x: (side - size.width) / 2, y: (side - size.height) / 2,
                                   width: size.width, height: size.height))
        }.withRenderingMode(.alwaysOriginal)
    }
}

/// Stepped corners keep edges square at every screen scale.
struct GamePixelShape: InsettableShape {
    var cornerRadius: CGFloat = 8
    var style: RoundedCornerStyle = .continuous
    private var insetAmount: CGFloat = 0

    init(cornerRadius: CGFloat = 8, style: RoundedCornerStyle = .continuous) {
        self.cornerRadius = cornerRadius
        self.style = style
    }

    func path(in rect: CGRect) -> Path {
        let r = rect.insetBy(dx: insetAmount, dy: insetAmount)
        guard r.width > 0, r.height > 0 else { return Path() }
        let step = max(0, min(4, cornerRadius / 2, r.width / 4, r.height / 4))
        let x = r.minX, y = r.minY, w = r.maxX, h = r.maxY
        return Path { p in
            p.move(to: CGPoint(x: x + step * 2, y: y))
            for point in [CGPoint(x: w - step * 2, y: y), CGPoint(x: w - step * 2, y: y + step),
                          CGPoint(x: w - step, y: y + step), CGPoint(x: w - step, y: y + step * 2),
                          CGPoint(x: w, y: y + step * 2), CGPoint(x: w, y: h - step * 2),
                          CGPoint(x: w - step, y: h - step * 2), CGPoint(x: w - step, y: h - step),
                          CGPoint(x: w - step * 2, y: h - step), CGPoint(x: w - step * 2, y: h),
                          CGPoint(x: x + step * 2, y: h), CGPoint(x: x + step * 2, y: h - step),
                          CGPoint(x: x + step, y: h - step), CGPoint(x: x + step, y: h - step * 2),
                          CGPoint(x: x, y: h - step * 2), CGPoint(x: x, y: y + step * 2),
                          CGPoint(x: x + step, y: y + step * 2), CGPoint(x: x + step, y: y + step),
                          CGPoint(x: x + step * 2, y: y + step)] { p.addLine(to: point) }
            p.closeSubpath()
        }
    }

    func inset(by amount: CGFloat) -> GamePixelShape {
        var result = self
        result.insetAmount += amount
        return result
    }
}

struct GamePanel: View {
    var fill: Color = AppTheme.card
    var raised = true
    var body: some View {
        ZStack {
            GamePixelShape().fill(AppTheme.border)
            GamePixelShape().inset(by: 2).fill(AppTheme.wood)
            GamePixelShape().inset(by: 4).fill(AppTheme.highlight)
            GamePixelShape().inset(by: 6).fill(fill)
        }
        .shadow(color: AppTheme.border.opacity(0.3), radius: 0, x: 0, y: raised ? 3 : 0)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct GameInset: View {
    var fill: Color = AppTheme.inset
    var body: some View {
        GamePixelShape(cornerRadius: 4).fill(fill)
            .overlay { GamePixelShape(cornerRadius: 4).strokeBorder(AppTheme.wood.opacity(0.7), lineWidth: 2) }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

struct GamePageBackdrop: View {
    var body: some View {
        AppTheme.canvas.overlay {
            Canvas { context, size in
                for row in stride(from: 0, through: Int(size.height), by: 32) {
                    for column in stride(from: 0, through: Int(size.width), by: 40) {
                        let offset = (row / 32 % 2) * 16
                        context.fill(Path(CGRect(x: column + offset, y: row, width: 3, height: 2)),
                                     with: .color(AppTheme.wood.opacity(0.16)))
                    }
                }
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Decorative landscape; farm data stays in the labeled content above it.
struct ValleyHeaderBackdrop: View {
    @Environment(\.colorScheme) private var colorScheme
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottom) {
                AppTheme.sky
                Image("GameFarmBackdrop")
                    .resizable().interpolation(.none).scaledToFill()
                    .frame(width: geometry.size.width, height: geometry.size.height, alignment: .bottom)
                    .clipped()
                    .overlay { Color.black.opacity(colorScheme == .dark ? 0.48 : 0.08) }
                Rectangle().fill(AppTheme.border).frame(height: 3)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .ignoresSafeArea(edges: .top)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct GameButtonStyle: ButtonStyle {
    var prominent = false
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(configuration.role == .destructive ? AppTheme.danger : AppTheme.ink)
            .padding(.horizontal, 12).padding(.vertical, 8)
            .frame(minHeight: 44)
            .background(GamePanel(fill: prominent ? AppTheme.selection : AppTheme.card, raised: !configuration.isPressed))
            .contentShape(GamePixelShape())
            .offset(y: configuration.isPressed ? 2 : 0)
            .opacity(isEnabled ? 1 : 0.48)
    }
}

struct GameTextFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration.padding(.horizontal, 10).padding(.vertical, 9)
            .background(GameInset())
    }
}

/// Native Form/List retain keyboard, selection, section and accessibility behavior.
struct GameForm<Content: View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View {
        Form { content.listRowBackground(GameInset(fill: AppTheme.card)).listRowSeparatorTint(AppTheme.wood.opacity(0.4)) }
            .modifier(GameCollectionStyle())
    }
}

struct GameList<Content: View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View {
        List { content.listRowBackground(GameInset(fill: AppTheme.card)).listRowSeparatorTint(AppTheme.wood.opacity(0.4)) }
            .modifier(GameCollectionStyle())
    }
}

struct GameProgressStyle: ProgressViewStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            configuration.label
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Rectangle().fill(AppTheme.inset)
                    Rectangle().fill(AppTheme.progress)
                        .frame(width: max(0, geometry.size.width * min(1, max(0, configuration.fractionCompleted ?? 0))))
                    Rectangle().strokeBorder(AppTheme.wood, lineWidth: 2)
                }
            }
            .frame(height: 10)
            configuration.currentValueLabel
        }
    }
}

private struct GameCollectionStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .scrollContentBackground(.hidden)
            .background(GamePageBackdrop())
            .foregroundStyle(AppTheme.ink)
            .tint(AppTheme.accent)
            .environment(\.defaultMinListRowHeight, 48)
            .toolbarBackground(AppTheme.card, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
    }
}

extension View {
    func gameInset(_ fill: Color = AppTheme.inset) -> some View { background(GameInset(fill: fill)) }
    func gamePanel(_ fill: Color = AppTheme.card) -> some View { background(GamePanel(fill: fill)) }
    func gameBar() -> some View {
        background(AppTheme.card)
            .overlay(alignment: .top) { Rectangle().fill(AppTheme.wood).frame(height: 2).allowsHitTesting(false) }
    }
}
