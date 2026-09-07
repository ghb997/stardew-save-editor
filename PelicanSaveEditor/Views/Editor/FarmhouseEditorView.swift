import SwiftUI

struct FarmhouseEditorView: View {
    @Bindable var session: SaveSession
    @State private var selectedDecorationID: String?

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
                            Text("点选蓝图房间，再选择墙纸或地板")
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
                        FarmhouseBlueprint(
                            decorations: session.draft.farmhouse.decorations,
                            selectedDecorationID: $selectedDecorationID
                        )
                        .frame(height: blueprintHeight)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                    } header: {
                        Text("互动房间蓝图")
                    } footer: {
                        Text("蓝图按存档中的房间键生成；点任一房间即可编辑该房间已有的表面字段。")
                    }

                    if let index = selectedDecorationIndex {
                        let decoration = session.draft.farmhouse.decorations[index]
                        Section {
                            roomSurfaceSelector(for: decoration)

                            RoomSurfacePreview(decoration: decoration)

                            standardStylePicker(for: index)

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
                            Text("标准色板用于快速选编号；高编号模组样式仍可用精确编号调整。示意颜色不替代游戏实际贴图。")
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
                    }
                }

                Section {
                    GameLabel("家具位置和容器内容仍保持原样", systemImage: "lock.shield.fill")
                        .foregroundStyle(.green)
                }
            }
            .navigationTitle("房屋与房间")
            .onAppear(perform: ensureSelection)
            .onChange(of: session.draft.farmhouse.decorations.map(\.id)) { _, _ in
                ensureSelection()
            }
        }
    }

    private var blueprintHeight: CGFloat {
        let rooms = Set(session.draft.farmhouse.decorations.map(\.roomKey)).count
        return CGFloat(max(1, (rooms + 1) / 2)) * 116 + 18
    }

    private var selectedDecorationIndex: Int? {
        guard let selectedDecorationID else { return nil }
        return session.draft.farmhouse.decorations.firstIndex { $0.id == selectedDecorationID }
    }

    private func ensureSelection() {
        if selectedDecorationIndex == nil {
            selectedDecorationID = session.draft.farmhouse.decorations.first?.id
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
            .pickerStyle(.segmented)
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
        let decoration = session.draft.farmhouse.decorations[index]
        let styles = decoration.kind == .wallpaper ? Array(0...111) : Array(0...55)
        let rows = Array(repeating: GridItem(.fixed(46), spacing: 8), count: 4)

        return VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text("标准样式库")
                    .font(.subheadline.bold())
                Spacer()
                Text("\(styles.count) 款")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ScrollView(.horizontal) {
                LazyHGrid(rows: rows, spacing: 8) {
                    ForEach(styles, id: \.self) { style in
                        Button {
                            session.draft.farmhouse.decorations[index].styleIndex = style
                        } label: {
                            RoomStyleSwatch(
                                style: style,
                                kind: decoration.kind,
                                isSelected: decoration.styleIndex == style
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(decoration.kind.displayName)样式 \(style)")
                    }
                }
                .padding(.vertical, 3)
            }
            .scrollIndicators(.visible)
            .frame(height: 208)
        }
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
            set: { session.draft.farmhouse.decorations[index].styleIndex = $0 }
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
        default: "3 级·地窖"
        }
    }

    private func levelDetail(_ level: Int) -> String {
        switch level {
        case 0: "单间基础布局"
        case 1: "增加厨房"
        case 2: "增加额外房间"
        default: "解锁地窖区域"
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

private struct RoomStyleSwatch: View {
    let style: Int
    let kind: RoomDecorationKind
    let isSelected: Bool

    var body: some View {
        RoomTexturePreview(style: style, kind: kind)
            .frame(width: 58, height: 58)
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
        RoomTexturePreview(style: decoration.styleIndex, kind: decoration.kind)
            .frame(height: 96)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(alignment: .bottomLeading) {
                Text("\(decoration.kind.displayName) \(decoration.styleIndex) · \(hasTexture ? "游戏原版贴图" : "无贴图预览")")
                    .font(.caption2.weight(.medium))
                    .padding(6)
                    .background(.regularMaterial, in: Capsule())
                    .padding(6)
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
