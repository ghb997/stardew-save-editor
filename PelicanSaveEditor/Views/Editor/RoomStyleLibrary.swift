import SwiftUI

struct RoomStyleLibrary: View {
    @Bindable var session: SaveSession
    let decorationID: String
    @State private var searchText = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            if let index = session.draft.farmhouse.decorations.firstIndex(where: { $0.id == decorationID }) {
                let surface = session.draft.farmhouse.decorations[index]
                VStack(alignment: .leading, spacing: 16) {
                    Text("\(surface.localizedRoomName) · \(surface.kind.displayName) #\(surface.styleIndex)")
                        .font(.headline)
                        .accessibilityIdentifier("editor.house.style.current")
                    Text("点选样式后立即更新草稿，可继续比较或返回房间页。")
                        .font(.caption).foregroundStyle(.secondary)
                    TextField("搜索样式编号", text: $searchText)
                        .textFieldStyle(.roundedBorder)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.search)
                        .onSubmit { KeyboardReturnAction.dismiss() }
                        .accessibilityIdentifier("editor.house.style.search")
                    let styles = RoomStyleRules.standardStyles(for: surface.kind, query: searchText)
                    if styles.isEmpty { ContentUnavailableView.search(text: searchText) }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 70))], spacing: 14) {
                        ForEach(styles, id: \.self) { style in
                            Button { session.draft.farmhouse.decorations[index].styleIndex = style } label: {
                                RoomStyleSwatch(style: style, kind: surface.kind, isSelected: style == surface.styleIndex)
                                    .padding(4)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("\(surface.kind.displayName)样式 \(style)")
                            .accessibilityIdentifier("editor.house.style.\(style)")
                            .accessibilityAddTraits(style == surface.styleIndex ? .isSelected : [])
                        }
                    }
                }
                .padding()
            }
        }
        .accessibilityIdentifier("editor.house.style.library")
        .background(Color(.systemGroupedBackground))
        .navigationTitle("样式库")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
    }
}

struct RoomStyleBatchRequest: Identifiable {
    let id = UUID()
    let source: RoomDecorationDraft
    let targets: [RoomDecorationDraft]
}

struct RoomStyleBatchPreview: View {
    @Bindable var session: SaveSession
    let request: RoomStyleBatchRequest
    @State private var selectedRooms: Set<String>
    @Environment(\.dismiss) private var dismiss

    init(session: SaveSession, request: RoomStyleBatchRequest) {
        self.session = session; self.request = request
        _selectedRooms = State(initialValue: Set(request.targets.map(\.roomKey)))
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("将修改 \(selectedRooms.count) 个房间").font(.headline)
                        .accessibilityIdentifier("editor.house.batch.count")
                    Text("套用\(request.source.kind.displayName) #\(request.source.styleIndex)，可以取消勾选个别房间。")
                    HStack {
                        Button("全选") { selectedRooms = Set(request.targets.map(\.roomKey)) }
                        Spacer()
                        Button("清空选择") { selectedRooms.removeAll() }
                    }
                }
                Section("本次范围") {
                    ForEach(request.targets) { target in
                        Toggle(isOn: Binding(get: { selectedRooms.contains(target.roomKey) }, set: { selected in
                            if selected { selectedRooms.insert(target.roomKey) } else { selectedRooms.remove(target.roomKey) }
                        })) {
                            VStack(alignment: .leading) {
                                Text(target.localizedRoomName)
                                Text("#\(target.styleIndex) → #\(request.source.styleIndex)").font(.caption.monospaced())
                            }
                        }
                        .accessibilityIdentifier("editor.house.batch.room.\(target.roomKey)")
                    }
                }
                Section {
                    Button("加入草稿") {
                        session.draft.farmhouse.applyStyle(from: request.source, rooms: selectedRooms)
                        dismiss()
                    }
                    .disabled(selectedRooms.isEmpty || session.isEditingLocked)
                    .accessibilityIdentifier("editor.house.batch.apply")
                } footer: {
                    Text("只修改勾选房间的\(request.source.kind.displayName)，可在检查页逐项撤销。")
                }
            }
            .accessibilityIdentifier("editor.house.batch.list")
            .navigationTitle("批量套用样式")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } } }
        }
    }
}
