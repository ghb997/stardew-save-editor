import SwiftUI

/// Accessible counterpart of the pixel map, with the same draft and exact action keys.
struct FarmEntityListView: View {
    let snapshot: FarmSnapshot
    @Binding var actions: FarmActionDraft
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var selectedKind: FarmEntityKind?
    @State private var onlyCleanable = false

    private var entities: [FarmEntity] {
        snapshot.entities.filter { entity in
            (selectedKind == nil || entity.kind == selectedKind)
                && (!onlyCleanable || entity.actionKey != nil)
                && (searchText.isEmpty
                    || entity.label.localizedCaseInsensitiveContains(searchText)
                    || entity.coordinateDescription.localizedCaseInsensitiveContains(searchText))
        }.sorted {
            if $0.tileY != $1.tileY { return ($0.tileY ?? .greatestFiniteMagnitude) < ($1.tileY ?? .greatestFiniteMagnitude) }
            if $0.tileX != $1.tileX { return ($0.tileX ?? .greatestFiniteMagnitude) < ($1.tileX ?? .greatestFiniteMagnitude) }
            return $0.id < $1.id
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("对象类型", selection: $selectedKind) {
                        Text("全部类型").tag(nil as FarmEntityKind?)
                        ForEach(FarmEntityKind.allCases) { kind in
                            Text(kind.displayName).tag(kind as FarmEntityKind?)
                        }
                    }
                    Toggle(isOn: $onlyCleanable) {
                        GameAssetLabel("仅显示可清理对象", assetName: "GameUITrash", iconSize: 24)
                    }
                    Text("共 \(entities.count) 个对象。清理会先加入草稿，确认保存后才执行。")
                        .font(.caption).foregroundStyle(.secondary)
                } header: {
                    GameAssetLabel("对象筛选", assetName: "GameUIFarmComputer", iconSize: 24)
                }
                ForEach(entities) { entity in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 10) {
                            if let sprite = GameArtwork.farmEntityImage(entity) {
                                Image(uiImage: sprite).resizable().interpolation(.none).scaledToFit()
                                    .frame(width: 36, height: 36)
                                    .accessibilityHidden(true)
                            } else {
                                GameIcon(systemName: "questionmark", size: 32)
                            }
                            Text(entity.label).font(.headline)
                        }
                        Text(entity.coordinateDescription)
                            .font(.subheadline.monospacedDigit())
                        if let detail = entity.detail { Text(detail).font(.caption).foregroundStyle(.secondary) }
                        if let key = entity.actionKey {
                            let covered = coveredByBulkAction(entity)
                            let selected = actions.debrisRemovalKeys.contains(key)
                            Button(covered ? "已由批量清理包含" : (selected ? "撤销此对象清理" : "清理此对象")) {
                                if selected { actions.debrisRemovalKeys.remove(key) }
                                else { actions.debrisRemovalKeys.insert(key) }
                            }
                            .buttonStyle(.bordered)
                            .disabled(covered)
                            .accessibilityLabel("\(entity.label)，\(entity.coordinateDescription)，\(selected ? "撤销清理" : "加入清理草稿")")
                        } else {
                            Text("只读对象").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                    .accessibilityElement(children: .contain)
                }
                if entities.isEmpty {
                    GameEmptyState(
                        title: "没有匹配的地图对象",
                        systemImage: "map.fill",
                        message: searchText.isEmpty
                            ? "请调整对象类型或可清理筛选。"
                            : "请调整搜索词或筛选条件。"
                    )
                }
            }
            .searchable(text: $searchText, prompt: "搜索名称或坐标")
            .navigationTitle("地图对象")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }

    private func coveredByBulkAction(_ entity: FarmEntity) -> Bool {
        switch entity.state {
        case .stone: actions.clearStones
        case .weed: actions.clearWeeds
        case .twig: actions.clearTwigs
        default: false
        }
    }
}
