import SwiftUI

struct EquipmentEditorView: View {
    @Bindable var session: SaveSession
    @State private var search = ""
    @State private var selected: EquipmentDraft?

    private var visible: [EquipmentDraft] {
        session.draft.equipment.filter {
            search.isEmpty || "\($0.name) \($0.type) \($0.location)".localizedCaseInsensitiveContains(search)
        }
    }
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("编辑已有斧头、镐、锄头、喷壶的升级等级，以及武器和鞋子的现有属性。")
                    Text("数量、附魔、锻造和未列出的专属字段保持原样。保存后重新加载游戏，核对属性是否保留。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("可编辑装备 \(session.draft.equipment.count) 件") {
                    ForEach(visible) { item in
                        Button { selected = item } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(item.name).font(.headline)
                                Text(item.location).font(.caption).foregroundStyle(.secondary)
                                Text(item.fields.map { "\($0.title) \($0.formatted)" }.joined(separator: " · "))
                                    .font(.caption).foregroundStyle(.secondary).lineLimit(3)
                            }
                            .padding(.vertical, 4)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }.buttonStyle(.plain).accessibilityIdentifier("equipment.item.\(item.id)")
                    }
                    if visible.isEmpty {
                        ContentUnavailableView("没有符合条件的装备", systemImage: "wrench.and.screwdriver",
                            description: Text("请检查背包或标准箱子；未知类型、共享容器和缺失属性的装备不会开放修改。"))
                    }
                }
            }
            .navigationTitle("工具与装备").navigationBarTitleDisplayMode(.inline)
            .searchable(text: $search, prompt: "搜索装备名称或位置")
        }
        .sheet(item: $selected) { item in EquipmentEditSheet(session: session, item: item) }
    }
}

private struct EquipmentEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var session: SaveSession
    @State var item: EquipmentDraft
    @State private var error: String?
    @State private var input: [String: String] = [:]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(item.location).font(.subheadline)
                    ForEach(item.fields.indices, id: \.self) { index in
                        let field = item.fields[index]
                        if field.id == "upgradeLevel" {
                            Picker(field.title, selection: $item.fields[index].value) {
                                ForEach(0...4, id: \.self) { level in
                                    Text(["基础", "铜", "钢", "金", "铱"][level]).tag(Double(level))
                                }
                            }.accessibilityIdentifier("equipment.field.upgradeLevel")
                        } else {
                            VStack(alignment: .leading) {
                                LabeledContent(field.title) {
                                    TextField("数值", text: Binding(
                                        get: { input[field.id] ?? item.fields[index].formatted },
                                        set: { input[field.id] = $0 }
                                    ))
                                        .keyboardType(.numbersAndPunctuation).multilineTextAlignment(.trailing)
                                        .accessibilityIdentifier("equipment.field.\(field.id)")
                                    Button { input[field.id] = "" } label: { Image(systemName: "xmark.circle") }
                                        .buttonStyle(.borderless).accessibilityLabel("清空\(field.title)")
                                        .accessibilityIdentifier("equipment.clear.\(field.id)")
                                }
                                Text("范围 \(field.minimum.formatted())–\(field.maximum.formatted())")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                Section {
                    Button("恢复读取时的属性") {
                        if let original = session.originalDraft.equipment.first(where: { $0.id == item.id }) { item = original }
                        input = [:]
                        error = nil
                    }.accessibilityIdentifier("equipment.restore")
                    Text("加入草稿后，可在检查与保存中逐项撤销。取消此弹窗会放弃本次输入。")
                        .font(.caption).foregroundStyle(.secondary)
                    if let error { Text(error).foregroundStyle(.red).accessibilityIdentifier("equipment.error") }
                }
            }
            .navigationTitle(item.name).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("加入草稿") {
                        guard let index = session.draft.equipment.firstIndex(where: { $0.id == item.id }) else { return }
                        do {
                            var edited = item
                            for fieldIndex in edited.fields.indices {
                                let field = edited.fields[fieldIndex]
                                guard let text = input[field.id] else { continue }
                                let separator = Locale.current.decimalSeparator ?? "."
                                let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
                                    .replacingOccurrences(of: separator, with: ".")
                                guard let value = Double(normalized), value.isFinite else {
                                    throw SaveValidationError.invalid("请输入有效的\(field.title)数值。")
                                }
                                edited.fields[fieldIndex].value = value
                            }
                            var next = session.draft
                            next.equipment[index] = edited
                            try EquipmentEditorRules.validate(next.equipment, original: session.originalDraft.equipment)
                            session.draft = next
                            dismiss()
                        } catch { self.error = error.localizedDescription }
                    }.accessibilityIdentifier("equipment.apply")
                }
            }
        }
    }
}
