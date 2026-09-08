import SwiftUI

private enum CatalogCollection: String, CaseIterable, Identifiable {
    case all = "全部"
    case favorites = "收藏"
    case recent = "最近添加"
    var id: String { rawValue }
}

struct CatalogPickerView: View {
    let catalog: [CatalogItem]
    let onPick: @MainActor (CatalogItem) -> Void
    @Environment(\.dismiss) private var dismiss
    @AppStorage("catalog.favoriteIDs") private var favoritesJSON = "[]"
    @AppStorage("catalog.recentIDs") private var recentJSON = "[]"
    @State private var searchText = ""
    @State private var selectedCollection: CatalogCollection = .all
    @State private var selectedCategory = "全部分类"

    private var favoriteIDs: Set<String> { Set(decodeIDs(favoritesJSON)) }
    private var recentIDs: [String] { decodeIDs(recentJSON) }
    private var categories: [String] {
        ["全部分类"] + Set(catalog.map(categoryName)).sorted()
    }
    private var filtered: [CatalogItem] {
        let matches = catalog.filter { item in
            (searchText.isEmpty || item.searchableText.localizedCaseInsensitiveContains(searchText))
                && (selectedCategory == "全部分类" || categoryName(item) == selectedCategory)
                && (selectedCollection != .favorites || favoriteIDs.contains(item.id))
                && (selectedCollection != .recent || recentIDs.contains(item.id))
        }
        if selectedCollection == .recent {
            let positions = Dictionary(uniqueKeysWithValues: recentIDs.enumerated().map { ($0.element, $0.offset) })
            return matches.sorted { (positions[$0.id] ?? .max) < (positions[$1.id] ?? .max) }
        }
        return matches
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("浏览方式", selection: $selectedCollection) {
                        ForEach(CatalogCollection.allCases) { collection in
                            Text(collection.rawValue).tag(collection)
                        }
                    }
                    .pickerStyle(.segmented)
                    Picker("物品分类", selection: $selectedCategory) {
                        ForEach(categories, id: \.self) { category in Text(category).tag(category) }
                    }
                    Text("显示 \(filtered.count) / \(catalog.count) 项安全物品")
                        .font(.caption).foregroundStyle(.secondary)
                }
                ForEach(filtered) { item in
                    HStack(spacing: 12) {
                        Button {
                            var recent = recentIDs.filter { $0 != item.id }
                            recent.insert(item.id, at: 0)
                            recentJSON = encodeIDs(Array(recent.prefix(30)))
                            onPick(item)
                        } label: {
                            HStack(spacing: 12) {
                                CatalogItemArtworkView(item: item)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(item.displayName).foregroundStyle(.primary)
                                    Text("\(item.name) · ID \(item.id)")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 0)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("添加 \(item.displayName)")
                        Button {
                            var favorites = favoriteIDs
                            if favorites.contains(item.id) { favorites.remove(item.id) }
                            else { favorites.insert(item.id) }
                            favoritesJSON = encodeIDs(favorites.sorted())
                        } label: {
                            GameIcon(systemName: favoriteIDs.contains(item.id) ? "star.fill" : "star")
                                .frame(minWidth: 44, minHeight: 44)
                        }
                        .buttonStyle(.borderless)
                        .tint(.orange)
                        .accessibilityLabel("\(favoriteIDs.contains(item.id) ? "取消收藏" : "收藏")\(item.displayName)")
                    }
                }
                if filtered.isEmpty {
                    GameEmptyState(
                        title: selectedCollection == .favorites ? "还没有匹配的收藏" : "没有匹配的物品",
                        systemImage: "magnifyingglass",
                        message: "可切换到“全部”，或调整分类与搜索条件。"
                    )
                }
            }
            .searchable(text: $searchText, prompt: "搜索中文、英文或 ID")
            .onSubmit(of: .search) { KeyboardReturnAction.dismiss() }
            .navigationTitle("安全物品目录")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
        }
    }

    private func decodeIDs(_ value: String) -> [String] {
        (try? JSONDecoder().decode([String].self, from: Data(value.utf8))) ?? []
    }

    private func encodeIDs(_ ids: [String]) -> String {
        guard let data = try? JSONEncoder().encode(ids) else { return "[]" }
        return String(decoding: data, as: UTF8.self)
    }

    private func categoryName(_ item: CatalogItem) -> String {
        switch item.category {
        case -74: "种子"
        case -75: "蔬菜"
        case -79: "水果"
        case -80: "花卉"
        case -81: "采集物"
        case -4: "鱼类"
        case -2: "宝石"
        case -12: "矿物"
        case -15, -16: "资源材料"
        case -7: "烹饪"
        case -26: "工艺品"
        case -19: "肥料"
        case -5, -6, -14, -18: "动物与农场产品"
        default: "其他物品"
        }
    }
}
