import SwiftUI
import UIKit

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
            .foregroundStyle(AppTheme.ink)
            .padding(18)
            .gamePanel(AppTheme.card)
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
            .foregroundStyle(AppTheme.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var accessory: some View {
        GameIcon(systemName: disabled ? "lock.fill" : "chevron.right", size: 20)
            .font(.headline)
            .foregroundStyle(AppTheme.secondary)
    }

    private var icon: some View {
        Group {
            if let artworkName {
                GameAssetIcon(assetName: artworkName, size: 48)
            } else {
                GameIcon(systemName: systemImage, size: 28)
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(disabled ? AppTheme.secondary : iconColor)
            }
        }
        .frame(width: 58, height: 58)
        .gameInset(AppTheme.inset)
    }
}

struct LargePageHeader: View {
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    let title: String
    var artworkName: String? = nil
    var systemImage: String? = nil
    var headerColor: Color = AppTheme.header
    var titleColor: Color = AppTheme.title
    var verticalPadding: CGFloat = 12
    var minimumHeight: CGFloat = 82

    var body: some View {
        HStack(spacing: 14) {
            if let artworkName {
                GameAssetIcon(assetName: artworkName, size: isShortWindow ? 28 : 34)
            } else if let systemImage {
                GameIcon(systemName: systemImage, size: isShortWindow ? 28 : 34)
            }
            Text(title)
                .font(.system(isShortWindow ? .headline : .title2, design: .monospaced).bold())
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
            .foregroundStyle(titleColor)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(GamePanel(fill: AppTheme.headerSoft, raised: false))
            .padding(.horizontal, 20)
            .padding(.vertical, isShortWindow ? 5 : min(verticalPadding, 10))
            .frame(maxWidth: AppLayout.pageWidth, minHeight: isShortWindow ? 58 : minimumHeight)
            .frame(maxWidth: .infinity)
            .background(ValleyHeaderBackdrop())
    }

    private var isShortWindow: Bool { verticalSizeClass == .compact }
}

extension View {
    func appCard() -> some View {
        background(GamePanel())
    }
}
