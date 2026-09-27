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
                        HStack(spacing: 12) {
                            icon
                            rowTitle.frame(maxWidth: .infinity, alignment: .leading)
                            accessory
                        }
                        detail
                    }
                } else {
                    HStack(spacing: 12) {
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
            .padding(16)
            .gamePanel(AppTheme.card)
            .opacity(disabled ? 0.58 : 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }

    private var rowTitle: some View {
        Text(title)
            .font(.headline)
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
                GameAssetIcon(assetName: artworkName, size: 34)
            } else {
                GameIcon(systemName: systemImage, size: 28)
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(disabled ? AppTheme.secondary : iconColor)
            }
        }
        .frame(width: 38, height: 38)
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
        HStack(spacing: 10) {
            Text(title)
                .font(.system(isShortWindow ? .title3 : .largeTitle).bold())
                .fixedSize(horizontal: false, vertical: true)
            if let artworkName {
                GameAssetIcon(assetName: artworkName, size: 26)
            } else if let systemImage {
                Image(systemName: systemImage).font(.title3).foregroundStyle(AppTheme.progress)
            }
            Spacer(minLength: 0)
        }
            .foregroundStyle(titleColor)
            .padding(.horizontal, 20)
            .padding(.vertical, isShortWindow ? 8 : verticalPadding)
            .frame(maxWidth: AppLayout.pageWidth, minHeight: isShortWindow ? 58 : minimumHeight)
            .frame(maxWidth: .infinity)
            .background(ValleyHeaderBackdrop())
    }

    private var isShortWindow: Bool { verticalSizeClass == .compact }
}

/// Compact content shortcuts keep game artwork, while navigation uses SF Symbols.
struct JournalToolButton: View {
    let entry: EditorToolEntry
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                artwork.frame(width: 34, height: 38)
                VStack(alignment: .leading, spacing: 5) {
                    Text(entry.compactTitle).font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.ink)
                    Text(entry.compactSubtitle).font(.caption)
                        .foregroundStyle(AppTheme.secondary)
                }
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .multilineTextAlignment(.leading)
            .padding(.horizontal, 10).padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: 68, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(entry.compactTitle)
        .accessibilityHint(entry.subtitle)
    }

    @ViewBuilder private var artwork: some View {
        if case .editor(.character) = entry {
            GameAssetIcon(assetName: "JournalFarmerIcon", size: 38)
        } else if case .editor(.inventory) = entry {
            GameAssetIcon(assetName: "JournalBackpackIcon", size: 46)
        } else if case .editor(.relationships) = entry {
            GameAssetIcon(assetName: "JournalRelationshipsIcon", size: 38)
        } else if case .map = entry {
            GameAssetIcon(assetName: "JournalMapIcon", size: 38)
        } else if case .expanded(.equipment) = entry {
            GameAssetIcon(assetName: "GameUISkillMining", size: 34)
        } else if case .expanded(.weather) = entry {
            GameAssetIcon(assetName: "JournalWeatherIcon", size: 38)
        } else if let name = entry.artworkName {
            GameAssetIcon(assetName: name, size: 34)
        } else {
            GameIcon(systemName: entry.symbol, size: 34)
        }
    }
}

struct JournalActionRow: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: systemImage).font(.title2.weight(.regular))
                    .foregroundStyle(AppTheme.secondary).frame(width: 32)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(AppTheme.ink)
                    Text(subtitle).font(.caption).foregroundStyle(AppTheme.secondary)
                }
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right").font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.secondary)
            }
            .multilineTextAlignment(.leading)
            .padding(.vertical, 14).frame(minHeight: 60)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

extension View {
    func appCard() -> some View {
        background(GamePanel())
    }
}
