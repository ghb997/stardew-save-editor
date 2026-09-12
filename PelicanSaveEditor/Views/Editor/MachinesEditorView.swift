import SwiftUI

private enum MachineFilter: String, CaseIterable, Identifiable {
    case all = "全部", processing = "加工中", pending = "待保存"
    var id: String { rawValue }
}
private struct MachineSelection: Identifiable { let id = UUID(); let ids: Set<String> }

struct MachinesEditorView: View {
    @Bindable var session: SaveSession
    @State private var search = ""
    @State private var filter: MachineFilter = .all
    @State private var selected: Set<String> = []
    @State private var preview: MachineSelection?
    private var visible: [MachineDraft] {
        session.draft.machines.filter {
            (search.isEmpty || "\($0.name) \($0.location) \(ExistingSaveValue.locationTitle($0.location)) \($0.coordinate) \($0.output)".localizedCaseInsensitiveContains(search))
                && (filter != .processing || $0.canFinish && !$0.finish) && (filter != .pending || $0.finish)
        }
    }
    private var selectable: Set<String> { Set(visible.filter { $0.canFinish && !$0.finish }.map(\.id)) }
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("已识别 \(session.draft.machines.count) 台正在加工或可领取的设备").font(.headline)
                    Picker("机器筛选", selection: $filter) { ForEach(MachineFilter.allCases) { Text($0.rawValue).tag($0) } }
                        .adaptiveSegmentedPicker()
                    Button("选择当前可完成的 \(selectable.count) 台") { selected = selectable }
                        .disabled(selectable.isEmpty).accessibilityIdentifier("machines.selectVisible")
                    Button("预览完成 \(selected.intersection(selectable).count) 台", systemImage: "checklist") {
                        preview = MachineSelection(ids: selected.intersection(selectable))
                    }
                    .disabled(selected.intersection(selectable).isEmpty).accessibilityIdentifier("machines.preview")
                    Text("完成后保留产物，回游戏手动领取。空机器、陈酿桶、孵化器及未知机器不参加。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                ForEach(visible) { machine in
                    VStack(alignment: .leading, spacing: 8) {
                        Text("\(machine.name) · \(ExistingSaveValue.locationTitle(machine.location))").font(.headline)
                        Text("\(machine.coordinate) · \(machine.output)").font(.caption).foregroundStyle(.secondary)
                        if machine.finish {
                            Label("待保存：完成加工", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                            Button("撤销这台机器") {
                                if let i = session.draft.machines.firstIndex(where: { $0.id == machine.id }) { session.draft.machines[i].finish = false }
                            }.accessibilityIdentifier("machines.undo.\(machine.id)")
                        } else if machine.canFinish {
                            Toggle("剩余 \(machine.minutes) 分钟 · 选择完成", isOn: Binding(
                                get: { selected.contains(machine.id) },
                                set: { if $0 { selected.insert(machine.id) } else { selected.remove(machine.id) } }))
                        } else { Text(machine.wasReady ? "可回游戏领取" : "等待游戏更新").foregroundStyle(.secondary) }
                    }.padding(.vertical, 4)
                }
                if visible.isEmpty { ContentUnavailableView("没有符合条件的机器", systemImage: "gearshape.2", description: Text("支持小桶、熔炉、罐头瓶等 14 种标准设备。")) }
            }
            .navigationTitle("机器加工").navigationBarTitleDisplayMode(.inline)
            .searchable(text: $search, prompt: "设备、地点、产物或坐标")
            .onChange(of: search) { _, _ in selected = selected.intersection(selectable) }
            .onChange(of: filter) { _, _ in selected = selected.intersection(selectable) }
        }
        .sheet(item: $preview) { selection in
            MachineFinishPreview(session: session, ids: selection.ids) { selected = [] }
        }
    }
}

private struct MachineFinishPreview: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var session: SaveSession
    let ids: Set<String>
    let onApplied: () -> Void
    private var targets: [MachineDraft] { session.draft.machines.filter { ids.contains($0.id) && $0.canFinish && !$0.finish } }
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("将完成 \(targets.count) 台机器").font(.headline)
                    Text("计时归零并设为可领取，不增加产物数量。").font(.footnote).foregroundStyle(.secondary)
                }
                ForEach(targets) { machine in
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(machine.name) · \(ExistingSaveValue.locationTitle(machine.location))")
                        Text("\(machine.coordinate) · \(machine.output) · \(machine.minutes) → 0 分钟")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("完成加工预览").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("加入草稿") {
                        let current = Set(targets.map(\.id))
                        for i in session.draft.machines.indices where current.contains(session.draft.machines[i].id) { session.draft.machines[i].finish = true }
                        onApplied(); dismiss()
                    }.disabled(targets.isEmpty).accessibilityIdentifier("machines.apply")
                }
            }
        }
    }
}
