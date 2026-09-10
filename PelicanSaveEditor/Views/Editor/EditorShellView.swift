import SwiftUI

enum SaveEditorSection: String, CaseIterable, Identifiable {
    case character
    case appearance
    case farmhouse
    case inventory
    case progress
    case relationships
    case skills
    case wallet
    case animals
    case recipes
    case review

    var id: String { rawValue }

    var title: String {
        switch self {
        case .character: "角色与农场"
        case .appearance: "人物外观"
        case .farmhouse: "房屋与房间"
        case .inventory: "背包物品"
        case .progress: "财富与进度"
        case .relationships: "人物关系"
        case .skills: "技能与职业"
        case .wallet: "特殊物品与能力"
        case .animals: "农场动物"
        case .recipes: "配方解锁"
        case .review: "检查与保存"
        }
    }

    var trackerTitle: String {
        switch self {
        case .progress: "状态与收藏进度"
        case .recipes: "配方收集"
        case .review: "存档状态"
        default: title
        }
    }

    var systemImage: String {
        switch self {
        case .character: "person.crop.circle.fill"
        case .appearance: "person.crop.square.fill"
        case .farmhouse: "house.lodge.fill"
        case .inventory: "shippingbox.fill"
        case .progress: "chart.bar.fill"
        case .relationships: "heart.fill"
        case .skills: "star.circle.fill"
        case .wallet: "wallet.pass.fill"
        case .animals: "pawprint.fill"
        case .recipes: "book.closed.fill"
        case .review: "checkmark.circle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .character: .green
        case .appearance: .purple
        case .farmhouse: .indigo
        case .inventory: .brown
        case .progress: .blue
        case .relationships: .pink
        case .skills: .purple
        case .wallet: .teal
        case .animals: .orange
        case .recipes: .orange
        case .review: .blue
        }
    }

    var artworkName: String? {
        switch self {
        case .character, .appearance: nil
        case .farmhouse: "GameUIFarmhouse"
        case .inventory: "GameUIBackpack"
        case .progress: "GameUIProgress"
        case .relationships: "GameUIRelationships"
        case .skills: "GameUISkillFarming"
        case .wallet: "GameUIWallet"
        case .animals: "GameAnimalWhiteChicken"
        case .recipes: "GameUIRecipes"
        case .review: "GameUIReview"
        }
    }
}

struct SaveSectionArtwork: View {
    let section: SaveEditorSection
    var size: CGFloat = 40

    var body: some View {
        Group {
            if let artworkName = section.artworkName {
                GameAssetIcon(assetName: artworkName, size: size)
            } else {
                GameIcon(systemName: section.systemImage, size: size)
            }
        }
        .accessibilityLabel(section.title)
    }
}

struct EditorShellView: View {
    @Environment(EditorStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Bindable var session: SaveSession
    let section: SaveEditorSection
    @State private var showingReview = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                SaveSectionArtwork(section: section, size: 42)
                VStack(alignment: .leading, spacing: 2) {
                    Text(section.title)
                        .font(.headline)
                        .lineLimit(1)
                    Text("\(session.draft.farmName.isEmpty ? session.source.farmIdentifier : session.draft.farmName) · \(session.draft.playerName)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if session.hasChanges {
                    Text("\(session.diffs.count) 项待保存")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.orange)
                }
                Button("返回工具", systemImage: "xmark") {
                    dismiss()
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.bordered)
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
            .background(.bar)

            editorContent

            // Reserve layout space outside each editor's NavigationStack.
            // An outer safe-area inset can be lost at that boundary, leaving
            // the final Form row behind the review bar even at scroll end.
            if section != .review {
                DraftReviewBar(session: session) { showingReview = true }
            }
        }
        .fullScreenCover(isPresented: $showingReview) {
            EditorShellView(session: session, section: .review)
        }
        .disabled(store.isBusy)
        .interactiveDismissDisabled(store.isBusy)
        .operationFeedback()
    }

    @ViewBuilder
    private var editorContent: some View {
        switch section {
        case .character:
            CharacterEditorView(session: session)
        case .appearance:
            AppearanceEditorView(session: session)
        case .farmhouse:
            FarmhouseEditorView(session: session)
        case .inventory:
            InventoryEditorView(session: session, catalog: store.itemCatalog)
        case .progress:
            ProgressEditorView(session: session)
        case .relationships:
            RelationshipsEditorView(session: session)
        case .skills:
            SkillsEditorView(session: session)
        case .wallet:
            WalletEditorView(session: session)
        case .animals:
            AnimalsEditorView(session: session)
        case .recipes:
            RecipesEditorView(session: session)
        case .review:
            ReviewChangesView(session: session)
        }
    }
}
