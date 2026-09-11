import SwiftUI

struct FarmhouseEditorView: View {
    @Bindable var session: SaveSession
    @State private var selectedDecorationID: String?
    @State private var roomQuery = ""
    @State private var batchRequest: RoomStyleBatchRequest?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ZStack(alignment: .bottomLeading) {
                        Image("GameFarmBackdrop")
                            .resizable()
                            .interpolation(.none)
                            .scaledToFill()
                            .frame(height: 190)
                            .clipped()

                        LinearGradient(
                            colors: [.clear, .black.opacity(0.62)],
                            startPoint: .center,
                            endPoint: .bottom
                        )

                        VStack(alignment: .leading, spacing: 3) {
                            Text("农舍与房间")
                                .font(.title3.bold())
                            Text("选择房间，对照墙纸与地板的变化")
                                .font(.caption)
                        }
                        .foregroundStyle(.white)
                        .padding(16)
                    }
                    .frame(height: 190)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }

                if session.draft.farmhouse.upgradeLevel != nil {
                    Section {
                        Picker("农舍等级", selection: upgradeLevelBinding) {
                            if !(0...3).contains(upgradeLevelBinding.wrappedValue) {
                                Text("现有等级 \(upgradeLevelBinding.wrappedValue)").tag(upgradeLevelBinding.wrappedValue)
                            }
                            ForEach(0...3, id: \.self) { level in
                                Text(levelName(level)).tag(level)
                            }
                        }

                        LabeledContent("对应布局", value: levelDetail(upgradeLevelBinding.wrappedValue))
                            .foregroundStyle(.secondary)

                        if let originalLevel = session.originalDraft.farmhouse.upgradeLevel,
                           originalLevel != upgradeLevelBinding.wrappedValue {
                            HStack {
                                GameLabel("原始：\(levelName(originalLevel))", systemImage: "clock.arrow.circlepath")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                                Spacer()
                                Button("恢复") {
                                    session.draft.farmhouse.upgradeLevel = originalLevel
                                }
                                .font(.caption.weight(.semibold))
                            }
                        }
                    } header: {
                        Text("农舍扩建")
                    } footer: {
                        Text("修改等级后，游戏会在下次载入时使用对应农舍布局。此操作不会自动移动家具。")
                    }
                }

                if session.draft.farmhouse.decorations.isEmpty {
                    Section("房间装饰") {
                        GameLabel("这份存档没有可安全编辑的现有墙纸/地板字段。", systemImage: "paintbrush.pointed")
                            .foregroundStyle(.secondary)
                        Text("应用只编辑已经存在的房间条目，不会猜测或伪造未知 XML 结构。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Section {
                        TextField("搜索房间名称或键", text: $roomQuery)
                            .autocorrectionDisabled()
                            .accessibilityIdentifier("editor.house.roomSearch")
                        Text("\(Set(visibleDecorations.map(\.roomKey)).count) 个房间 · \(visibleDecorations.count) 个表面")
                            .font(.caption).foregroundStyle(.secondary)
                        FarmhouseBlueprint(
                            decorations: visibleDecorations,
                            selectedDecorationID: $selectedDecorationID
                        )
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                    } header: {
                        Text("房间与表面")
                    } footer: {
                        Text("按存档中的房间分类展示；点选后编辑已有的墙纸或地板。")
                    }

                    if let index = selectedDecorationIndex {
                        let decoration = session.draft.farmhouse.decorations[index]
                        Section {
                            roomSurfaceSelector(for: decoration)

                            HStack(alignment: .top) {
                                if let old = session.originalDraft.farmhouse.decorations.first(where: { $0.id == decoration.id }) {
                                    VStack { Text("原始").font(.caption); RoomSurfacePreview(decoration: old) }
                                }
                                VStack { Text("当前草稿").font(.caption); RoomSurfacePreview(decoration: decoration) }
                            }

                            LabeledContent("直接输入编号") {
                                TextField("样式编号", value: decorationBinding(index), format: .number.grouping(.never))
                                    .keyboardType(.numberPad)
                                    .multilineTextAlignment(.trailing)
                                    .accessibilityIdentifier("editor.house.style.number")
                            }

                            standardStylePicker(for: index)

                            Button("套用到当前筛选房间", systemImage: "square.on.square") {
                                let rooms = Set(visibleDecorations.map(\.roomKey))
                                batchRequest = RoomStyleBatchRequest(source: decoration,
                                    targets: RoomStyleRules.targets(in: session.draft.farmhouse, source: decoration, rooms: rooms))
                            }
                            .disabled(RoomStyleRules.targets(in: session.draft.farmhouse, source: decoration,
                                rooms: Set(visibleDecorations.map(\.roomKey))).isEmpty)
                            .accessibilityIdentifier("editor.house.style.batch")

                            Button("恢复本房间的墙纸与地板") {
                                session.draft.farmhouse.restoreRoom(decoration.roomKey, from: session.originalDraft.farmhouse)
                            }
                            .accessibilityIdentifier("editor.house.restoreRoom")

                            Stepper(
                                "精确样式编号：\(decoration.styleIndex)",
                                value: decorationBinding(index),
                                in: 0...9_999
                            )

                            if let originalStyle = originalStyle(for: decoration),
                               originalStyle != decoration.styleIndex {
                                HStack {
                                    GameLabel("原始编号：\(originalStyle)", systemImage: "clock.arrow.circlepath")
                                        .font(.caption)
                                        .foregroundStyle(.orange)
                                    Spacer()
                                    Button("恢复") {
                                        session.draft.farmhouse.decorations[index].styleIndex = originalStyle
                                    }
                                    .font(.caption.weight(.semibold))
                                }
                            }
                        } header: {
                            Text("\(decoration.localizedRoomName) · \(decoration.kind.displayName)")
                        } footer: {
                            Text("样式库使用已有游戏贴图；扩展样式可直接输入编号。批量套用会先展示房间和变化值。")
                        }
                    }
                }

                if hasHouseChanges {
                    Section("房屋草稿") {
                        GameLabel("房屋修改尚未写入存档", systemImage: "pencil.and.list.clipboard")
                            .foregroundStyle(.orange)
                        Button("撤销全部房屋修改", systemImage: "arrow.uturn.backward") {
                            session.draft.farmhouse = session.originalDraft.farmhouse
                        }
                        .accessibilityIdentifier("editor.house.restoreAll")
                    }
                }

                Section {
                    GameLabel("家具位置和容器内容仍保持原样", systemImage: "lock.shield.fill")
                        .foregroundStyle(.green)
                }
            }
            .accessibilityIdentifier("editor.house.form")
            .navigationTitle("房屋与房间")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear(perform: ensureSelection)
            .onChange(of: roomQuery) { _, _ in ensureSelection() }
            .onChange(of: session.draft.farmhouse.decorations.map(\.id)) { _, _ in
                ensureSelection()
            }
        }
        .sheet(item: $batchRequest) { request in RoomStyleBatchPreview(session: session, request: request) }
    }

    private var visibleDecorations: [RoomDecorationDraft] {
        let keys = Set(RoomStyleRules.matchingRooms(in: session.draft.farmhouse, query: roomQuery))
        return session.draft.farmhouse.decorations.filter { keys.contains($0.roomKey) }
    }

    private var selectedDecorationIndex: Int? {
        guard let selectedDecorationID else { return nil }
        return session.draft.farmhouse.decorations.firstIndex { $0.id == selectedDecorationID }
    }

    private func ensureSelection() {
        if !visibleDecorations.contains(where: { $0.id == selectedDecorationID }) {
            selectedDecorationID = visibleDecorations.first?.id
        }
    }

    @ViewBuilder
    private func roomSurfaceSelector(for decoration: RoomDecorationDraft) -> some View {
        let roomDecorations = session.draft.farmhouse.decorations.filter { $0.roomKey == decoration.roomKey }
        if roomDecorations.count > 1 {
            Picker("表面", selection: surfaceSelectionBinding) {
                ForEach(roomDecorations) { item in
                    Text(item.kind.displayName).tag(Optional(item.id))
                }
            }
            .adaptiveSegmentedPicker()
            .accessibilityIdentifier("editor.house.surface")
        } else {
            GameLabel(
                decoration.kind.displayName,
                systemImage: decoration.kind == .wallpaper ? "photo.artframe" : "square.grid.3x3.fill"
            )
        }
    }

    private var surfaceSelectionBinding: Binding<String?> {
        Binding(
            get: { selectedDecorationID },
            set: { selectedDecorationID = $0 }
        )
    }

    private func standardStylePicker(for index: Int) -> some View {
        NavigationLink {
            RoomStyleLibrary(session: session, decorationID: session.draft.farmhouse.decorations[index].id)
        } label: {
            Label("浏览标准样式库", systemImage: "square.grid.3x3")
        }
        .accessibilityIdentifier("editor.house.styles")
    }

    private var upgradeLevelBinding: Binding<Int> {
        Binding(
            get: { session.draft.farmhouse.upgradeLevel ?? 0 },
            set: { session.draft.farmhouse.upgradeLevel = $0 }
        )
    }

    private func decorationBinding(_ index: Int) -> Binding<Int> {
        Binding(
            get: { session.draft.farmhouse.decorations[index].styleIndex },
            set: { session.draft.farmhouse.decorations[index].styleIndex = max(0, min(9_999, $0)) }
        )
    }

    private var hasHouseChanges: Bool {
        session.draft.farmhouse != session.originalDraft.farmhouse
    }

    private func originalStyle(for decoration: RoomDecorationDraft) -> Int? {
        session.originalDraft.farmhouse.decorations
            .first(where: { $0.id == decoration.id })?
            .styleIndex
    }

    private func levelName(_ level: Int) -> String {
        switch level {
        case 0: "0 级·基础农舍"
        case 1: "1 级·厨房"
        case 2: "2 级·额外房间"
        case 3: "3 级·地窖"
        default: "现有等级 \(level)"
        }
    }

    private func levelDetail(_ level: Int) -> String {
        switch level {
        case 0: "单间基础布局"
        case 1: "增加厨房"
        case 2: "增加额外房间"
        case 3: "解锁地窖区域"
        default: "扩展等级，布局由游戏或模组决定"
        }
    }
}

private struct FarmhouseBlueprint: View {
    let decorations: [RoomDecorationDraft]
    @Binding var selectedDecorationID: String?

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 145))], spacing: 12) {
            ForEach(roomKeys, id: \.self) { roomKey in
                let surfaces = decorations.filter { $0.roomKey == roomKey }
                let selected = surfaces.contains { $0.id == selectedDecorationID }
                Button {
                    let kind = decorations.first(where: { $0.id == selectedDecorationID })?.kind
                    selectedDecorationID = surfaces.first(where: { $0.kind == kind })?.id ?? surfaces.first?.id
                } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(surfaces) { surface in
                            RoomTexturePreview(style: surface.styleIndex, kind: surface.kind)
                                .frame(height: 44)
                                .clipped()
                        }
                        Text(surfaces.first?.localizedRoomName ?? roomKey)
                            .font(.subheadline.bold())
                        Text(surfaces.map { "\($0.kind.displayName) #\($0.styleIndex)" }.joined(separator: " · "))
                            .font(.caption2)
                    }
                    .foregroundStyle(.primary)
                    .padding(10)
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(selected ? .orange : Color.primary.opacity(0.15), lineWidth: selected ? 3 : 1)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
    }

    private var roomKeys: [String] {
        var seen = Set<String>()
        return decorations.compactMap { seen.insert($0.roomKey).inserted ? $0.roomKey : nil }
    }
}

struct RoomStyleSwatch: View {
    @ScaledMetric(relativeTo: .caption2) private var tileSize: CGFloat = 58
    let style: Int
    let kind: RoomDecorationKind
    let isSelected: Bool

    var body: some View {
        RoomTexturePreview(style: style, kind: kind)
            .frame(width: tileSize, height: tileSize)
            .clipped()
            .overlay(alignment: .bottom) {
                Text("\(style)")
                    .font(.caption2.bold().monospacedDigit())
                    .padding(.horizontal, 5)
                    .background(.regularMaterial, in: Capsule())
                    .padding(3)
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? .orange : Color.primary.opacity(0.15), lineWidth: isSelected ? 3 : 1)
            }
    }
}

private struct RoomSurfacePreview: View {
    let decoration: RoomDecorationDraft

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            RoomTexturePreview(style: decoration.styleIndex, kind: decoration.kind)
                .frame(height: 96)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 12))
            Text("\(decoration.kind.displayName) \(decoration.styleIndex) · \(hasTexture ? "游戏原版贴图" : "无贴图预览")")
                .font(.caption2.weight(.medium))
                .fixedSize(horizontal: false, vertical: true)
        }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(decoration.localizedRoomName)\(decoration.kind.displayName)原版贴图")
            .accessibilityValue("编号 \(decoration.styleIndex)")
    }

    private var hasTexture: Bool {
        GameArtwork.surfaceImage(style: decoration.styleIndex, isFlooring: decoration.kind == .flooring) != nil
    }
}

private struct RoomTexturePreview: View {
    let style: Int
    let kind: RoomDecorationKind

    var body: some View {
        if let sprite = GameArtwork.surfaceImage(style: style, isFlooring: kind == .flooring) {
            Canvas { context, size in
                let width = max(1, sprite.size.width * 2)
                let height = max(1, sprite.size.height * 2)
                for y in stride(from: CGFloat.zero, to: size.height, by: height) {
                    for x in stride(from: CGFloat.zero, to: size.width, by: width) {
                        context.draw(Image(uiImage: sprite).interpolation(.none), in: CGRect(x: x, y: y, width: width, height: height))
                    }
                }
            }
        } else {
            VStack(spacing: 3) {
                GameIcon(systemName: "questionmark")
                Text("无贴图预览").font(.caption2)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.secondarySystemBackground))
        }
    }
}
