import SwiftUI

/// Accessible counterpart of the pixel map, sharing exact draft action keys.
struct FarmEntityListView: View {
    let snapshot: FarmSnapshot
    @Binding var actions: FarmActionDraft
    var onLocate: ((FarmEntity) -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var query = FarmMapQuery()
    @State private var useRegion = false
    @State private var bounds = ["0", "80", "0", "65"]
    @State private var preview: FarmActionPreviewRequest?

    private var region: FarmTileRegion? {
        let values = bounds.map { Double($0.trimmingCharacters(in: .whitespaces)) }
        guard let minX = values[0], let maxX = values[1],
              let minY = values[2], let maxY = values[3] else { return nil }
        let region = FarmTileRegion(minX: minX, maxX: maxX, minY: minY, maxY: maxY)
        return region.isValid ? region : nil
    }

    private var validRange: Bool { !useRegion || region != nil }

    private var entities: [FarmEntity] {
        guard validRange else { return [] }
        var filter = query
        filter.region = useRegion ? region : nil
        return snapshot.entities.filter { filter.matches($0, actions: actions) }.sorted {
            if $0.tileY != $1.tileY { return ($0.tileY ?? .greatestFiniteMagnitude) < ($1.tileY ?? .greatestFiniteMagnitude) }
            if $0.tileX != $1.tileX { return ($0.tileX ?? .greatestFiniteMagnitude) < ($1.tileX ?? .greatestFiniteMagnitude) }
            return $0.id < $1.id
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("对象类型", selection: $query.kind) {
                        Text("全部类型").tag(nil as FarmEntityKind?)
                        ForEach(FarmEntityKind.allCases) { kind in
                            Text(kind.displayName).tag(kind as FarmEntityKind?)
                        }
                    }
                    Picker("操作状态", selection: $query.scope) {
                        ForEach(FarmMapScope.allCases) { scope in Text(scope.title).tag(scope) }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("editor.map.scope")
                    Toggle("限定坐标范围", isOn: $useRegion)
                        .accessibilityIdentifier("editor.map.region.enabled")
                    if useRegion {
                        rangeFields
                        if !validRange {
                            Text("请输入有效坐标，起点不能大于终点。")
                                .font(.caption).foregroundStyle(.red)
                        }
                    }
                    Text("匹配 \(entities.count) 个 · 全图待处理 \(snapshot.affectedEntities(by: actions).count) 个")
                        .font(.caption).foregroundStyle(.secondary)
                        .accessibilityIdentifier("editor.map.matchCount")
                    Text("范围操作只处理下方匹配对象；预览确认后加入草稿。")
                        .font(.caption).foregroundStyle(.secondary)
                    ForEach(FarmScopedAction.allCases) { action in
                        let candidates = action.candidates(entities, actions: actions)
                        Button("预览\(action.title)（\(candidates.count)）") {
                            preview = FarmActionPreviewRequest(action: action, entities: candidates)
                        }
                        .disabled(!validRange || candidates.isEmpty)
                        .accessibilityIdentifier("editor.map.batch.\(action.rawValue)")
                    }
                } header: {
                    GameAssetLabel("搜索与范围", assetName: "GameUIFarmComputer", iconSize: 24)
                }
                ForEach(entities) { entity in entityRow(entity) }
                if entities.isEmpty {
                    GameEmptyState(
                        title: "没有匹配的地图对象",
                        systemImage: "map.fill",
                        message: "请调整搜索词、对象类型、操作状态或坐标范围。"
                    )
                }
            }
            .accessibilityIdentifier("editor.map.list")
            .searchable(text: $query.text, prompt: "搜索名称、种子 ID 或坐标")
            .onSubmit(of: .search) { KeyboardReturnAction.dismiss() }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("地图对象")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } }
            }
            .sheet(item: $preview) { request in
                FarmActionPreview(request: request, actions: $actions)
            }
        }
    }

    private var rangeFields: some View {
        VStack(spacing: 10) {
            ForEach(0..<2) { axis in
                HStack {
                    Text(axis == 0 ? "X" : "Y").font(.subheadline.bold())
                    ForEach(0..<2) { edge in
                        let index = axis * 2 + edge
                        TextField(edge == 0 ? "起点" : "终点", text: $bounds[index])
                            .keyboardType(.numbersAndPunctuation)
                            .textFieldStyle(.roundedBorder)
                            .accessibilityLabel("\(axis == 0 ? "X" : "Y") \(edge == 0 ? "起点" : "终点")")
                            .accessibilityIdentifier("editor.map.region.\(index)")
                        if edge == 0 { Text("至").foregroundStyle(.secondary) }
                    }
                }
            }
        }
    }

    private func entityRow(_ entity: FarmEntity) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                if let sprite = GameArtwork.farmEntityImage(entity) {
                    Image(uiImage: sprite).resizable().interpolation(.none).scaledToFit()
                        .frame(width: 36, height: 36).accessibilityHidden(true)
                } else {
                    GameIcon(systemName: "questionmark", size: 32)
                }
                Text(entity.label).font(.headline)
                Spacer()
                if actions.affects(entity) {
                    Text("待处理").font(.caption.bold()).foregroundStyle(.orange)
                }
            }
            Text(entity.coordinateDescription).font(.subheadline.monospacedDigit())
            if let detail = entity.detail { Text(detail).font(.caption).foregroundStyle(.secondary) }
            FarmEntityActionButton(entity: entity, actions: $actions)
            if let onLocate, entity.tileX != nil, entity.tileY != nil {
                Button("在地图中定位", systemImage: "scope") {
                    onLocate(entity)
                    dismiss()
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("editor.map.locate.\(entity.id)")
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .contain)
    }
}

struct FarmEntityActionButton: View {
    let entity: FarmEntity
    @Binding var actions: FarmActionDraft

    private var covered: Bool { actions.coveredByBulk(entity) }
    private var selected: Bool { actions.individuallySelected(entity) }
    private var title: String {
        if covered { return "已由全图操作包含" }
        if selected { return "撤销此对象操作" }
        return entity.wateringKey != nil ? "给此作物浇水" : "清理此对象"
    }

    var body: some View {
        if entity.wateringKey != nil || entity.actionKey != nil {
            Button(title, systemImage: selected ? "arrow.uturn.backward" : (entity.wateringKey != nil ? "drop.fill" : "trash")) {
                actions.toggle(entity)
            }
            .font(.caption.weight(.semibold))
            .buttonStyle(.bordered)
            .disabled(covered)
            .accessibilityIdentifier("editor.map.entity.action.\(entity.id)")
        } else {
            Text("只读对象").font(.caption).foregroundStyle(.secondary)
        }
    }
}

private struct FarmActionPreviewRequest: Identifiable {
    let id = UUID()
    let action: FarmScopedAction
    let entities: [FarmEntity]
}

private struct FarmActionPreview: View {
    let request: FarmActionPreviewRequest
    @Binding var actions: FarmActionDraft
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("将\(request.action.title) \(request.entities.count) 个对象")
                        .font(.headline)
                        .accessibilityIdentifier("editor.map.preview.count")
                    Text("仅包含本次筛选中尚未加入草稿的可操作对象。确认后仍需检查并保存。")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("确认加入草稿") {
                        actions.apply(request.action, to: request.entities)
                        dismiss()
                    }
                    .accessibilityIdentifier("editor.map.preview.apply")
                }
                Section("本次处理明细") {
                    ForEach(request.entities) { entity in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(entity.label)
                            Text(entity.coordinateDescription).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .accessibilityIdentifier("editor.map.preview.list")
            .navigationTitle("\(request.action.title)预览")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
            }
        }
    }
}
