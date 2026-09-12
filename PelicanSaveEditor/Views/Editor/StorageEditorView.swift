import SwiftUI

struct StorageEditorView: View {
    @Bindable var session: SaveSession
    let catalog: [CatalogItem]
    @State private var search = ""
    @State private var editedOnly = false
    private var visible: [StorageDraft] {
        session.draft.storages.filter { storage in
            (search.isEmpty || storage.searchableText.localizedCaseInsensitiveContains(search))
                && (!editedOnly || session.originalDraft.storages.first(where: { $0.id == storage.id }) != storage)
        }
    }
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("找到 \(session.draft.storages.count) 个容器").font(.headline)
                    Toggle("仅显示已修改", isOn: $editedOnly)
                    Text("包含农场、室内及其他存档地点。标准箱子和冰箱为 36 格，大箱子为 70 格。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                ForEach(visible) { storage in
                    NavigationLink {
                        StorageContentsView(session: session, storageID: storage.id, catalog: catalog)
                    } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            Label(storage.title, systemImage: storage.isEditable ? "shippingbox" : "lock")
                                .font(.headline)
                            Text("\(storage.coordinate) · \(storage.occupiedCount) / \(storage.capacity) 格")
                                .font(.caption).foregroundStyle(.secondary)
                            if let reason = storage.readOnlyReason { Text(reason).font(.caption).foregroundStyle(.secondary) }
                        }.padding(.vertical, 4)
                    }
                    .accessibilityIdentifier("storage.container.\(storage.id)")
                }
                if visible.isEmpty {
                    ContentUnavailableView(session.draft.storages.isEmpty ? "未找到箱子或冰箱" : "没有符合条件的容器",
                        systemImage: "shippingbox", description: Text("仅显示存档中已有的容器。可按地点、坐标或物品名称搜索。"))
                }
            }
            .navigationTitle("容器列表").navigationBarTitleDisplayMode(.inline)
            .searchable(text: $search, prompt: "地点、坐标或物品名称")
            .onSubmit(of: .search) { KeyboardReturnAction.dismiss() }
        }
    }
}

private struct StorageSlotSelection: Identifiable { let id: Int }

private struct StorageContentsView: View {
    @Bindable var session: SaveSession
    let storageID: String
    let catalog: [CatalogItem]
    @State private var search = ""
    @State private var selection: StorageSlotSelection?
    @State private var occupiedOnly = false
    private var storage: StorageDraft? { session.draft.storages.first { $0.id == storageID } }
    var body: some View {
        List {
            if let storage {
                Section {
                    Text(storage.coordinate).font(.caption).foregroundStyle(.secondary)
                    Toggle("只看有物品的格子", isOn: $occupiedOnly)
                    if storage.isEditable, let empty = storage.slots.first(where: { $0.item == nil }) {
                        Button("添加到第 \(empty.id + 1) 格", systemImage: "plus.circle") { selection = StorageSlotSelection(id: empty.id) }
                            .accessibilityIdentifier("storage.add")
                    }
                    if let reason = storage.readOnlyReason { Text(reason).foregroundStyle(.secondary) }
                }
                Section("\(storage.occupiedCount) / \(storage.capacity) 格") {
                    ForEach(storage.slots.filter { slot in
                        (!occupiedOnly || slot.item != nil) && (search.isEmpty || String(slot.id + 1) == search
                            || slot.item.map { "\($0.localizedName) \($0.name) \($0.itemID)".localizedCaseInsensitiveContains(search) } == true)
                    }) { slot in
                        Button { selection = StorageSlotSelection(id: slot.id) } label: {
                            HStack(spacing: 12) {
                                if let item = slot.item { ItemArtworkView(item: item, size: 38) }
                                else { Image(systemName: "square.dashed").frame(width: 38).foregroundStyle(.secondary) }
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(slot.item?.localizedName ?? "空槽位").foregroundStyle(.primary)
                                    Text("第 \(slot.id + 1) 格" + (slot.item.map { " · ×\($0.stack) · 品质 \($0.quality)" } ?? ""))
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if slot.item?.isEditable == false || !storage.isEditable { Image(systemName: "lock").foregroundStyle(.secondary) }
                            }.padding(.vertical, 3)
                        }
                        .accessibilityIdentifier("storage.slot.\(slot.id)")
                    }
                }
                if storage.isEditable {
                    Section {
                        Button("恢复此容器的全部修改", role: .destructive) {
                            if let i = session.draft.storages.firstIndex(where: { $0.id == storageID }),
                               let old = session.originalDraft.storages.first(where: { $0.id == storageID }) { session.draft.storages[i] = old }
                        }
                        .accessibilityIdentifier("storage.restore")
                    }
                }
            } else {
                ContentUnavailableView("容器列表已更新", systemImage: "arrow.clockwise",
                    description: Text("保存后地点记录可能重新排序，请返回容器列表重新选择。"))
            }
        }
        .navigationTitle(storage?.title ?? "容器").navigationBarTitleDisplayMode(.inline)
        .searchable(text: $search, prompt: "物品名称、ID 或格子编号")
        .sheet(item: $selection) { selected in
            if let storage, storage.slots.indices.contains(selected.id) {
                StorageSlotSheet(session: session, storage: storage, index: selected.id, catalog: catalog)
            }
        }
    }
}

private struct StorageSlotSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var session: SaveSession
    let storage: StorageDraft
    let index: Int
    let catalog: [CatalogItem]
    @State private var item: InventoryItemDraft?
    @State private var quantityText: String
    @State private var picking = false
    @State private var error: String?
    private var editable: Bool { storage.isEditable && storage.slots[index].item?.isEditable != false }

    init(session: SaveSession, storage: StorageDraft, index: Int, catalog: [CatalogItem]) {
        self.session = session; self.storage = storage; self.index = index; self.catalog = catalog
        _item = State(initialValue: storage.slots[index].item)
        _quantityText = State(initialValue: String(storage.slots[index].item?.stack ?? 1))
    }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if let item {
                        HStack { ItemArtworkView(item: item, size: 48); Text(item.localizedName).font(.headline) }
                        LabeledContent("物品 ID", value: item.itemID)
                    } else { Label("空槽位", systemImage: "square.dashed") }
                }
                if editable {
                    if item != nil {
                        Section("数量与品质") {
                            HStack {
                                TextField("数量（1–999）", text: $quantityText)
                                    .keyboardType(.numberPad).accessibilityIdentifier("storage.quantity")
                                Button("清空数量输入", systemImage: "xmark.circle.fill") { quantityText = "" }
                                    .labelStyle(.iconOnly).buttonStyle(.borderless).frame(minWidth: 44, minHeight: 44)
                                    .accessibilityIdentifier("storage.quantity.clear")
                            }
                            Picker("品质", selection: Binding(get: { item?.quality ?? 0 }, set: { item?.quality = $0 })) {
                                ForEach(Array(Set((item?.allowedQualities ?? [0]) + [item?.quality ?? 0])).sorted(), id: \.self) { quality in
                                    Text([0: "普通", 1: "银星", 2: "金星", 4: "铱星"][quality] ?? "原值 \(quality)").tag(quality)
                                }
                            }
                            Button("清空这一格", role: .destructive) { item = nil }
                                .accessibilityIdentifier("storage.clear")
                        }
                    }
                    Section {
                        Button(item == nil ? "选择物品" : "替换为其他物品", systemImage: "plus") { picking = true }
                            .accessibilityIdentifier("storage.pick")
                        Text("加入草稿后可在检查页逐项撤销；保存时才写入容器。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                } else {
                    Text("此物品或容器保持只读，专属字段将原样保留。").foregroundStyle(.secondary)
                }
                if let error { Text(error).foregroundStyle(.red).accessibilityIdentifier("storage.error") }
            }
            .navigationTitle("第 \(index + 1) 格").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                if editable {
                    ToolbarItem(placement: .confirmationAction) { Button("加入草稿") { apply() }.accessibilityIdentifier("storage.apply") }
                }
            }
            .sheet(isPresented: $picking) {
                CatalogPickerView(catalog: catalog) { selected in item = selected.makeInventoryItem(); quantityText = "1"; picking = false }
            }
        }
    }
    private func apply() {
        guard let i = session.draft.storages.firstIndex(where: { $0.id == storage.id }),
              let original = session.originalDraft.storages.first(where: { $0.id == storage.id }) else { return }
        do {
            if item != nil {
                guard let quantity = Int(quantityText.trimmingCharacters(in: .whitespacesAndNewlines)), (1...999).contains(quantity) else {
                    error = "请输入 1–999 之间的整数。"; return
                }
                item?.stack = quantity
            }
            var value = session.draft.storages[i]
            value.slots[index].item = item
            try StorageEditorRules.validate(value, original: original)
            session.draft.storages[i] = value
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}
