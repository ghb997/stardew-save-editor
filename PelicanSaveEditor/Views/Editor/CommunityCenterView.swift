import SwiftUI

private struct SupplySelection: Identifiable { let id = UUID(); let ids: Set<String> }

struct CommunityCenterView: View {
    @Bindable var session: SaveSession
    let catalog: [CatalogItem]
    @State private var search = ""
    @State private var incompleteOnly = true
    @State private var area = "全部区域"
    @State private var selected: Set<String> = []
    @State private var preview: SupplySelection?
    @State private var error: String?
    private var data: CommunityCenterData { session.draft.communityCenter }
    private var visible: [CommunityBundle] {
        data.bundles.filter { bundle in
            (!incompleteOnly || !bundle.isComplete) && (area == "全部区域" || bundle.areaTitle == area)
                && (search.isEmpty || "\(bundle.title) \(bundle.name) \(bundle.areaTitle)".localizedCaseInsensitiveContains(search)
                    || bundle.requirements.contains { req in
                        "\(req.itemID) \(catalog.first { $0.id == req.itemID }?.displayName ?? "")".localizedCaseInsensitiveContains(search)
                    })
        }
    }
    private var visibleIDs: Set<String> { Set(visible.filter { !$0.isComplete }.flatMap(\.requirements).filter { !$0.donated }.map(\.id)) }
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("\(data.bundles.filter(\.isComplete).count) / \(data.bundles.count) 个收集包已完成")
                        .font(.headline).accessibilityIdentifier("bundles.progress")
                    Text(data.isJojaMember ? "存档记录为 Joja 会员，保留献祭信息供查看。" : "从存档读取普通或混合收集包。选择缺失材料，预览后补给到背包；回游戏交付可正常触发奖励与修复。")
                        .font(.footnote).foregroundStyle(.secondary)
                    Toggle("仅显示未完成", isOn: $incompleteOnly)
                    Picker("区域", selection: $area) {
                        Text("全部区域").tag("全部区域")
                        ForEach(Set(data.bundles.map(\.areaTitle)).sorted(), id: \.self) { Text($0).tag($0) }
                    }
                    Button("预览补给 \(selected.count) 项材料", systemImage: "backpack") { prepare() }
                        .disabled(selected.isEmpty || data.isJojaMember).accessibilityIdentifier("bundles.preview")
                    if !selected.isEmpty { Button("清空材料选择") { selected = [] } }
                    if let error { Text(error).foregroundStyle(.red).accessibilityIdentifier("bundles.error") }
                    if data.unreadableCount > 0 {
                        Text("另有 \(data.unreadableCount) 条结构不明或缺少进度的记录，已原样保留。").font(.caption).foregroundStyle(.secondary)
                    }
                }
                ForEach(visible) { bundle in
                    Section {
                        Text(bundle.isComplete ? "已完成" : "已交付 \(bundle.donatedCount) / \(bundle.requiredCount) 项，还需 \(max(0, bundle.requiredCount - bundle.donatedCount)) 项")
                            .font(.caption).foregroundStyle(bundle.isComplete ? .green : .secondary)
                        if bundle.requiredCount < bundle.requirements.count {
                            Text("这是任选收集包，请自行选择剩余材料组合。").font(.caption).foregroundStyle(.secondary)
                        }
                        ForEach(bundle.requirements) { requirement in
                            BundleRequirementRow(requirement: requirement,
                                item: catalog.first { $0.id == requirement.itemID },
                                allowsSupply: !data.isJojaMember && !bundle.isComplete,
                                selected: $selected)
                        }
                    } header: { Text("\(bundle.areaTitle) · \(bundle.title)") }
                }
                if visible.isEmpty {
                    ContentUnavailableView(data.bundles.isEmpty ? "未找到可读取的收集包" : "没有符合条件的收集包",
                        systemImage: "leaf", description: Text("需要存档同时包含材料定义和交付进度；不会推测缺失记录。"))
                }
            }
            .navigationTitle("社区中心").navigationBarTitleDisplayMode(.inline)
            .searchable(text: $search, prompt: "收集包、区域或材料名称")
            .onChange(of: search) { _, _ in selected = selected.intersection(visibleIDs) }
            .onChange(of: area) { _, _ in selected = selected.intersection(visibleIDs) }
            .onChange(of: incompleteOnly) { _, _ in selected = selected.intersection(visibleIDs) }
        }
        .sheet(item: $preview) { selection in BundleSupplyPreview(session: session, catalog: catalog, ids: selection.ids) }
    }
    private func prepare() {
        do {
            _ = try BundleSupplyRules.plan(ids: selected, draft: session.draft, catalog: catalog)
            preview = SupplySelection(ids: selected); error = nil
        } catch { self.error = error.localizedDescription }
    }
}

private struct BundleRequirementRow: View {
    let requirement: BundleRequirement
    let item: CatalogItem?
    let allowsSupply: Bool
    @Binding var selected: Set<String>
    private var canSupply: Bool {
        allowsSupply && !requirement.donated && !requirement.isGold && (1...999).contains(requirement.quantity)
            && item?.allowedQualities.contains(requirement.quality) == true
    }
    var body: some View {
        HStack(spacing: 10) {
            if let item { CatalogItemArtworkView(item: item) }
            VStack(alignment: .leading, spacing: 4) {
                Text(requirement.isGold ? "\(requirement.quantity) 金" : "\(item?.displayName ?? "物品 \(requirement.itemID)") ×\(requirement.quantity)")
                Text(requirement.donated ? "已交付" : requirement.isGold ? "回游戏支付" : "未交付 · 最低品质 \(requirement.quality)")
                    .font(.caption).foregroundStyle(.secondary)
                if !canSupply && !requirement.donated && !requirement.isGold && allowsSupply {
                    Text("此材料需在游戏中准备").font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if requirement.donated { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green) }
            else if canSupply {
                Button {
                    if selected.contains(requirement.id) { selected.remove(requirement.id) } else { selected.insert(requirement.id) }
                } label: {
                    Image(systemName: selected.contains(requirement.id) ? "checkmark.circle.fill" : "circle")
                        .font(.title2).frame(minWidth: 44, minHeight: 44)
                }.buttonStyle(.borderless)
                .accessibilityLabel("补给 \(item?.displayName ?? requirement.itemID)")
                .accessibilityValue(selected.contains(requirement.id) ? "已选择" : "未选择")
                .accessibilityIdentifier("bundles.select.\(requirement.id)")
            }
        }
    }
}

private struct BundleSupplyPreview: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var session: SaveSession
    let catalog: [CatalogItem]
    let ids: Set<String>
    @State private var error: String?
    private var lines: [BundleSupplyLine] { (try? BundleSupplyRules.plan(ids: ids, draft: session.draft, catalog: catalog)) ?? [] }
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("将添加到 \(lines.count) 个背包空格").font(.headline)
                    Text("每项按完整献祭数量补给。已有背包物品保持原样，献祭状态在游戏内交付后更新。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                ForEach(lines) { line in
                    HStack {
                        CatalogItemArtworkView(item: line.item)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(line.item.displayName) ×\(line.requirement.quantity)")
                            Text("\(line.bundleTitle) · 品质 \(line.requirement.quality) · 第 \(line.slot + 1) 格")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                if let error { Text(error).foregroundStyle(.red) }
                if lines.isEmpty { Text("背包或材料选择已变化，请返回重新预览。").foregroundStyle(.secondary) }
            }
            .navigationTitle("材料补给预览").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("加入草稿") {
                        do {
                            var draft = session.draft
                            try BundleSupplyRules.apply(ids: ids, to: &draft, catalog: catalog)
                            session.draft = draft; dismiss()
                        } catch { self.error = error.localizedDescription }
                    }.disabled(lines.isEmpty).accessibilityIdentifier("bundles.apply")
                }
            }
        }
    }
}
