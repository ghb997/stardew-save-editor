import SwiftUI
import UIKit

enum AppTheme {
    static let header = Color(red: 1.00, green: 0.79, blue: 0.47)
    static let headerSoft = Color(red: 1.00, green: 0.84, blue: 0.61)
    static let accent = Color(red: 0.56, green: 0.15, blue: 0.05)
    static let title = Color(red: 0.24, green: 0.07, blue: 0.03)
    static let canvas = Color(.systemGroupedBackground)
    static let card = Color(.secondarySystemGroupedBackground)
    static let muted = Color(red: 0.72, green: 0.66, blue: 0.58)
    // Tracker colors are kept separate so editor controls retain their existing tint.
    static let trackerHeader = adaptive(light: (1, 0.79, 0.47), dark: (0.18, 0.17, 0.15))
    static let trackerHeaderSoft = adaptive(light: (1, 0.88, 0.69), dark: (0.23, 0.21, 0.17))
    static let trackerSelection = adaptive(light: (1, 0.79, 0.47), dark: (0.40, 0.28, 0.12))
    static let trackerTitle = adaptive(light: (0.24, 0.07, 0.03), dark: (0.99, 0.91, 0.78))
    static let trackerAccent = adaptive(light: (0.56, 0.15, 0.05), dark: (1, 0.77, 0.43))
    static let trackerRow = adaptive(light: (0.93, 0.96, 0.91), dark: (0.13, 0.20, 0.15))
    static let progress = adaptive(light: (0.12, 0.43, 0.22), dark: (0.49, 0.82, 0.54))
    static let trackerWarning = adaptive(light: (0.53, 0.26, 0.02), dark: (1, 0.77, 0.43))
    static let trackerSecondary = adaptive(light: (0.37, 0.37, 0.39), dark: (0.72, 0.72, 0.75))

    private static func adaptive(
        light: (Double, Double, Double),
        dark: (Double, Double, Double)
    ) -> Color {
        Color(uiColor: UIColor { traits in
            let components = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(
                red: CGFloat(components.0),
                green: CGFloat(components.1),
                blue: CGFloat(components.2),
                alpha: 1
            )
        })
    }
}

struct ToolRowButton: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    let title: String
    let subtitle: String
    let systemImage: String
    let iconColor: Color
    var artworkName: String? = nil
    var disabled = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Group {
                if typeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 16) {
                            icon
                            rowTitle.frame(maxWidth: .infinity, alignment: .leading)
                            accessory
                        }
                        detail
                    }
                } else {
                    HStack(spacing: 16) {
                        icon
                        VStack(alignment: .leading, spacing: 5) {
                            rowTitle
                            detail
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        accessory
                    }
                }
            }
            .multilineTextAlignment(.leading)
            .foregroundStyle(.primary)
            .padding(18)
            .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(Color(.separator).opacity(0.35), lineWidth: 1)
            }
            .opacity(disabled ? 0.58 : 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }

    private var rowTitle: some View {
        Text(title)
            .font(.title3.bold())
            .fixedSize(horizontal: false, vertical: true)
    }

    private var detail: some View {
        Text(subtitle)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var accessory: some View {
        GameIcon(systemName: disabled ? "lock.fill" : "chevron.right", size: 20)
            .font(.headline)
            .foregroundStyle(.secondary)
    }

    private var icon: some View {
        Group {
            if let artworkName {
                GameAssetIcon(assetName: artworkName, size: 48)
            } else {
                GameIcon(systemName: systemImage, size: 28)
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(disabled ? Color.secondary : iconColor)
            }
        }
        .frame(width: 58, height: 58)
        .background(Color(.tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color(.separator).opacity(0.35), lineWidth: 1)
        }
    }
}

struct LargePageHeader: View {
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    let title: String
    var artworkName: String? = nil
    var systemImage: String? = nil
    var headerColor: Color = AppTheme.header
    var titleColor: Color = AppTheme.title
    var verticalPadding: CGFloat = 24
    var minimumHeight: CGFloat = 110

    var body: some View {
        HStack(spacing: 14) {
            if let artworkName {
                GameAssetIcon(assetName: artworkName, size: isShortWindow ? 32 : 46)
            } else if let systemImage {
                GameIcon(systemName: systemImage, size: isShortWindow ? 30 : 42)
            }
            Text(title)
                .font(isShortWindow ? .title2.bold() : .largeTitle.bold())
                .fixedSize(horizontal: false, vertical: true)
        }
            .foregroundStyle(titleColor)
            .padding(.horizontal, 24)
            .padding(.vertical, isShortWindow ? 8 : verticalPadding)
            .frame(maxWidth: AppLayout.pageWidth, minHeight: isShortWindow ? 60 : minimumHeight, alignment: .bottomLeading)
            .frame(maxWidth: .infinity)
            .background(headerColor.ignoresSafeArea(edges: .top))
    }

    private var isShortWindow: Bool { verticalSizeClass == .compact }
}

extension View {
    func appCard() -> some View {
        background(AppTheme.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}
