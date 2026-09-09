import SwiftUI

struct TrackerLabeledContentStyle: LabeledContentStyle {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    func makeBody(configuration: Configuration) -> some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 5) {
                configuration.label
                configuration.content.foregroundStyle(AppTheme.trackerSecondary)
            }
        } else {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                configuration.label
                Spacer(minLength: 8)
                configuration.content
                    .foregroundStyle(AppTheme.trackerSecondary)
                    .multilineTextAlignment(.trailing)
            }
        }
    }
}

/// A profile symbol identifies the character section without presenting an
/// undressed sprite layer as if it were the player's rendered appearance.
struct TrackerSectionArtwork: View {
    let section: SaveEditorSection
    let size: CGFloat

    var body: some View {
        if section == .character {
            Image(systemName: "person.crop.circle.fill")
                .resizable()
                .scaledToFit()
                .foregroundStyle(AppTheme.trackerAccent)
                .frame(width: size, height: size)
                .accessibilityHidden(true)
        } else {
            SaveSectionArtwork(section: section, size: size)
        }
    }
}

enum TrackerFilter: String, CaseIterable, Identifiable {
    case overview
    case basic
    case collections
    case life
    case status

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: "总览"
        case .basic: "基础"
        case .collections: "收藏"
        case .life: "农场生活"
        case .status: "状态"
        }
    }

    var group: TrackerGroup? {
        switch self {
        case .overview: nil
        case .basic: .basic
        case .collections: .collections
        case .life: .life
        case .status: .status
        }
    }

    func includes(_ group: TrackerGroup) -> Bool {
        self == .overview || self.group == group
    }
}

enum TrackerGroup: String, CaseIterable, Identifiable {
    case basic
    case collections
    case life
    case status

    var id: String { rawValue }

    var title: String {
        switch self {
        case .basic: "基础信息"
        case .collections: "收藏进度"
        case .life: "农场生活"
        case .status: "存档状态"
        }
    }

    var subtitle: String {
        switch self {
        case .basic: "角色、外观、房屋与背包"
        case .collections: "收藏、配方与钱包能力"
        case .life: "关系、技能与动物"
        case .status: "兼容性与未保存草稿"
        }
    }

    var artworkName: String {
        switch self {
        case .basic: "GameUIFarmhouse"
        case .collections: "GameUITrophy"
        case .life: "GameUIRelationships"
        case .status: "GameUIBackup"
        }
    }

    var sections: [SaveEditorSection] {
        switch self {
        case .basic: [.character, .appearance, .farmhouse, .inventory]
        case .collections: [.progress, .recipes, .wallet]
        case .life: [.relationships, .skills, .animals]
        case .status: [.review]
        }
    }
}

struct TrackerSummaryMetric: View {
    let value: String
    let label: String
    let artworkName: String

    var body: some View {
        VStack(spacing: 5) {
            GameAssetIcon(assetName: artworkName, size: 25)
            Text(value)
                .font(.subheadline.monospacedDigit().bold())
                .foregroundStyle(AppTheme.trackerTitle)
                .fixedSize(horizontal: false, vertical: true)
            Text(label)
                .font(.caption2)
                .foregroundStyle(AppTheme.trackerTitle.opacity(0.80))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

struct TrackerDetailCard<Content: View>: View {
    let title: String
    let artworkName: String
    let content: Content
    @State private var isExpanded = true

    init(title: String, artworkName: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.artworkName = artworkName
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 11) {
                    GameAssetIcon(assetName: artworkName, size: 30)
                    Text(title)
                        .font(.headline)
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption.bold())
                        .foregroundStyle(AppTheme.trackerSecondary)
                }
                .foregroundStyle(.primary)
                .padding(.horizontal, 18)
                .padding(.vertical, 15)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(isExpanded ? "已展开" : "已折叠")
            .accessibilityHint("双击展开或折叠\(title)")

            if isExpanded {
                Divider()
                VStack(spacing: 10) {
                    content
                }
                .padding(14)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 21, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 21, style: .continuous)
                .stroke(Color(.separator).opacity(0.38), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 21, style: .continuous))
    }
}

struct TrackerDetailDataRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let title: String
    let value: String
    var artworkName: String? = nil
    var systemImage: String? = nil

    var body: some View {
        HStack(spacing: 12) {
            Group {
                if let artworkName {
                    GameAssetIcon(assetName: artworkName, size: 34)
                } else if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(AppTheme.progress)
                }
            }
            .frame(width: 42, height: 42)
            .background(Color(.systemBackground).opacity(0.78), in: RoundedRectangle(cornerRadius: 11))

            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 5) {
                    Text(title).font(.subheadline.weight(.medium))
                    Text(value)
                        .font(.subheadline.monospacedDigit().weight(.semibold))
                        .foregroundStyle(AppTheme.trackerSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text(title).font(.subheadline.weight(.medium))
                Spacer(minLength: 8)
                Text(value)
                    .font(.subheadline.monospacedDigit().weight(.semibold))
                    .foregroundStyle(AppTheme.trackerSecondary)
                    .multilineTextAlignment(.trailing)
            }
        }
        .accessibilityElement(children: .combine)
        .padding(12)
        .background(AppTheme.trackerRow, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .stroke(Color(.separator).opacity(0.22), lineWidth: 1)
        }
    }
}
