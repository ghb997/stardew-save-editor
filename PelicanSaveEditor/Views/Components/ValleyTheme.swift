import SwiftUI
import UIKit

/// Semantic colors shared by every screen, including presented editors.
enum AppTheme {
    static let canvas = adaptive(0xFFF9EF, 0x222820)
    static let card = adaptive(0xFFFCF5, 0x2B3329)
    static let header = adaptive(0xF3E5D0, 0x343C2F)
    static let headerSoft = adaptive(0xF7F0E3, 0x2B3329)
    static let ink = adaptive(0x493A2D, 0xEEE5D5)
    static let secondary = adaptive(0x796957, 0xBCAFA0)
    static let accent = adaptive(0x975832, 0xD29A72)
    static let onAccent = adaptive(0xFFFFFF, 0x241D17)
    static let border = adaptive(0xE8DCCB, 0x40493D)
    static let wood = adaptive(0xDDCCB5, 0x515B49)
    static let highlight = adaptive(0xFFFEFC, 0xC7BFAF)
    static let selection = adaptive(0xF0DFCB, 0x524634)
    static let progress = adaptive(0x598047, 0xA8C18A)
    static let danger = adaptive(0xA4392C, 0xFFA295)
    static let information = adaptive(0x315B76, 0x9ACDD9)
    static let inset = adaptive(0xF6F0E5, 0x263021)
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
    static let trackerRow = adaptive(0xEDF0E3, 0x303C2B)
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
        navigation.backgroundColor = UIColor(canvas)
        navigation.shadowColor = UIColor(border)
        navigation.titleTextAttributes = [.foregroundColor: UIColor(ink)]
        navigation.largeTitleTextAttributes = [.foregroundColor: UIColor(ink)]
        UINavigationBar.appearance().standardAppearance = navigation
        UINavigationBar.appearance().scrollEdgeAppearance = navigation
        UINavigationBar.appearance().compactAppearance = navigation
        let tab = UITabBarAppearance()
        tab.configureWithOpaqueBackground()
        tab.backgroundColor = UIColor(canvas)
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

/// Shared rounded geometry; the legacy name keeps existing editor surfaces consistent.
struct GamePixelShape: InsettableShape {
    var cornerRadius: CGFloat = 10
    var style: RoundedCornerStyle = .continuous
    private var insetAmount: CGFloat = 0

    init(cornerRadius: CGFloat = 10, style: RoundedCornerStyle = .continuous) {
        self.cornerRadius = cornerRadius
        self.style = style
    }

    func path(in rect: CGRect) -> Path {
        RoundedRectangle(cornerRadius: cornerRadius, style: style)
            .inset(by: insetAmount).path(in: rect)
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
        GamePixelShape().fill(fill)
        .overlay { GamePixelShape().strokeBorder(AppTheme.border, lineWidth: 0.6) }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct GameInset: View {
    var fill: Color = AppTheme.inset
    var body: some View {
        GamePixelShape(cornerRadius: 8).fill(fill)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

struct GamePageBackdrop: View {
    var body: some View {
        AppTheme.canvas
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Plain canvas for shared page headings.
struct ValleyHeaderBackdrop: View {
    var body: some View {
        AppTheme.canvas
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct GameButtonStyle: ButtonStyle {
    var prominent = false
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(configuration.role == .destructive ? AppTheme.danger : (prominent ? AppTheme.onAccent : AppTheme.accent))
            .padding(.horizontal, 14).padding(.vertical, 9)
            .frame(minHeight: 44)
            .background(GamePixelShape().fill(prominent ? AppTheme.accent : AppTheme.inset))
            .contentShape(GamePixelShape())
            .opacity(isEnabled ? (configuration.isPressed ? 0.76 : 1) : 0.45)
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
        Form { content.listRowBackground(AppTheme.card).listRowSeparatorTint(AppTheme.border) }
            .modifier(GameCollectionStyle())
    }
}

struct GameList<Content: View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View {
        List { content.listRowBackground(AppTheme.card).listRowSeparatorTint(AppTheme.border) }
            .modifier(GameCollectionStyle())
    }
}

struct GameProgressStyle: ProgressViewStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            configuration.label
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(AppTheme.inset)
                    Capsule().fill(AppTheme.progress)
                        .frame(width: max(0, geometry.size.width * min(1, max(0, configuration.fractionCompleted ?? 0))))
                }
            }
            .frame(height: 6)
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
        background(AppTheme.canvas)
            .overlay(alignment: .top) { Rectangle().fill(AppTheme.border).frame(height: 0.5).allowsHitTesting(false) }
    }
}
