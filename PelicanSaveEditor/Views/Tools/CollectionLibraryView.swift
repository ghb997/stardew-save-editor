import SwiftUI

struct CollectionLibraryView: View {
    @Bindable var session: SaveSession
    let catalog: [CatalogItem]
    @State private var kind: CollectionKind = .museum
    @State private var state: CollectionState?
    @State private var search = ""
    @State private var sections: [CollectionSection] = []
    @State private var selected: CollectionEntry?

    private var current: CollectionSection? { sections.first { $0.kind == kind } }
    private var visible: [CollectionEntry] {
        current?.entries.filter {
            (state == nil || $0.state == state) && (search.isEmpty || $0.item.searchableText.localizedCaseInsensitiveContains(search))
        } ?? []
    }
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("收藏分类", selection: $kind) {
                        ForEach(CollectionKind.allCases) { Text($0.rawValue).tag($0) }
                    }.accessibilityIdentifier("collection.kind")
                    Picker("记录状态", selection: $state) {
                        Text("全部").tag(CollectionState?.none)
                        ForEach(CollectionState.allCases) { Text($0.rawValue).tag(Optional($0)) }
                    }.accessibilityIdentifier("collection.state")
                    Text(kind.scope).font(.caption).foregroundStyle(.secondary)
                    if let current {
                        LabeledContent("目录内已有记录", value: "\(current.entries.filter { $0.state == .recorded }.count) / \(current.entries.count)")
                        ForEach(current.notes, id: \.self) { Text($0).font(.caption).foregroundStyle(.orange) }
                    }
                }
                Section("\(visible.count) 项") {
                    ForEach(visible) { entry in
                        Button { selected = entry } label: {
                            HStack(spacing: 12) {
                                CatalogItemArtworkView(item: entry.item)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(entry.item.displayName).font(.headline)
                                    Text("\(entry.state.rawValue) · ID \(entry.item.id)").font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if entry.state == .recorded { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green) }
                            }
                        }.buttonStyle(.plain).accessibilityIdentifier("collection.item.\(entry.item.id)")
                    }
                    if visible.isEmpty { ContentUnavailableView.search(text: search) }
                }
            }
            .navigationTitle("收藏与缺失清单").navigationBarTitleDisplayMode(.inline)
            .searchable(text: $search, prompt: "搜索名称或物品 ID")
            .task(id: session.mainHash) { sections = CollectionLibrary.extract(session.parsed.mainRoot, catalog: catalog) }
        }
        .sheet(item: $selected) { entry in CollectionItemSheet(session: session, entry: entry) }
    }
}

private struct CollectionItemSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var session: SaveSession
    let entry: CollectionEntry
    @State private var message: String?
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack { Spacer(); CatalogItemArtworkView(item: entry.item, size: 80); Spacer() }
                    LabeledContent("物品", value: entry.item.displayName)
                    LabeledContent("英文名称", value: entry.item.name)
                    LabeledContent("当前分类", value: entry.kind.rawValue)
                    LabeledContent("记录", value: entry.state.rawValue)
                    if let count = entry.count { LabeledContent("记录数量", value: String(count)) }
                    LabeledContent("基础售价", value: "\(entry.item.price) 金")
                }
                Section {
                    Button("补给 1 个到背包") {
                        guard let index = session.draft.inventory.firstIndex(where: {
                            $0.item == nil && session.draft.canUseInventorySlot($0.id)
                        }) else { message = "背包没有可用空位。"; return }
                        session.draft.inventory[index].item = entry.item.makeInventoryItem()
                        message = "已加入背包草稿，请在检查与保存中确认。"
                    }.accessibilityIdentifier("collection.supply")
                    Text("补给物品不会直接更改发现、捕获、出货或捐赠记录；请在游戏内完成相应操作。")
                        .font(.caption).foregroundStyle(.secondary)
                    if let message { Text(message).accessibilityIdentifier("collection.feedback") }
                }
            }
            .navigationTitle(entry.item.displayName).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        }
    }
}
