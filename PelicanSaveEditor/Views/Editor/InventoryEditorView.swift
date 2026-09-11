import SwiftUI
import UIKit

private struct SlotSelection: Identifiable {
    let id: Int
}

struct InventoryEditorView: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    @Bindable var session: SaveSession
    let catalog: [CatalogItem]
    @State private var selection: SlotSelection?
    @State private var searchText = ""
    @State private var filter: InventoryFilter = .all

    private var visibleSlots: [InventorySlotDraft] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return session.draft.inventory.filter { slot in
            guard session.draft.canUseInventorySlot(slot.id) || slot.item != nil else { return false }
            guard filter.includes(slot) else { return false }
            return query.isEmpty || "\(slot.id + 1)" == query
                || slot.item.map { "\($0.localizedName) \($0.name) \($0.itemID)".localizedCaseInsensitiveContains(query) } == true
        }
    }

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: typeSize.isAccessibilitySize ? 240 : 104), spacing: 10)]
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                InventoryCapacityCard(session: session)
                    .padding([.horizontal, .top])
                Picker("槽位筛选", selection: $filter) {
                    ForEach(InventoryFilter.allCases) { value in
                        Text(value.title).tag(value)
                    }
                }
                .adaptiveSegmentedPicker()
                .padding(.horizontal)
                .accessibilityIdentifier("editor.inventory.filter")
                if session.draft.inventory.isEmpty {
                    GameEmptyState(title: "没有背包数据", systemImage: "shippingbox")
                        .padding(.top, 80)
                } else {
                    LazyVGrid(columns: columns, spacing: 10) {
                        ForEach(visibleSlots) { slot in
                            Button {
                                selection = SlotSelection(id: slot.id)
                            } label: {
                                InventorySlotCard(slot: slot)
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("editor.inventory.slot.\(slot.id)")
                        }
                    }
                    .padding()
                    if visibleSlots.isEmpty {
                        ContentUnavailableView.search(text: searchText)
                    }
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("背包")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "搜索物品名称、ID 或槽位编号")
            .onSubmit(of: .search) { KeyboardReturnAction.dismiss() }
            .safeAreaInset(edge: .bottom) {
                Text("点按槽位编辑。工具、装备和未知特殊物品保持只读。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(10)
                    .frame(maxWidth: .infinity)
                    .background(.bar)
            }
        }
        .sheet(item: $selection) { selected in
            if session.draft.inventory.indices.contains(selected.id) {
                InventorySlotEditorView(session: session, slotIndex: selected.id, catalog: catalog)
            }
        }
    }
}

private enum InventoryFilter: String, CaseIterable, Identifiable {
    case all, occupied, empty
    var id: String { rawValue }
    var title: String {
        switch self {
        case .all: "全部"
        case .occupied: "有物品"
        case .empty: "空槽位"
        }
    }
    func includes(_ slot: InventorySlotDraft) -> Bool {
        switch self {
        case .all: true
        case .occupied: slot.item != nil
        case .empty: slot.item == nil
        }
    }
}

private struct InventoryCapacityCard: View {
    @Bindable var session: SaveSession
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                GameAssetLabel("背包容量", assetName: "GameUIBackpack", iconSize: 26)
                    .font(.headline)
                Spacer()
                Text("\(session.draft.inventory.prefix(session.draft.usableInventoryCount).filter { $0.item != nil }.count) / \(session.draft.usableInventoryCount) 格")
                    .font(.subheadline.monospacedDigit())
                    .accessibilityIdentifier("editor.inventory.capacitySummary")
            }
            if session.draft.canResizeBackpack {
                Picker("背包容量", selection: Binding(
                    get: { session.draft.backpackCapacity ?? 12 },
                    set: { value in
                        do {
                            var draft = session.draft
                            try draft.setBackpackCapacity(value)
                            session.draft = draft
                            errorMessage = nil
                        } catch { errorMessage = error.localizedDescription }
                    }
                )) {
                    ForEach(BackpackRules.capacities, id: \.self) { capacity in
                        Text("\(capacity) 格").tag(capacity)
                    }
                }
                .adaptiveSegmentedPicker()
                .accessibilityIdentifier("editor.inventory.capacity")
                Text("扩容后可编辑新槽位；缩容前请移走末尾物品。撤销扩容会同时恢复新解锁槽位。")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Text("存档未提供标准容量，保留现有槽位。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.circle")
                    .font(.footnote).foregroundStyle(.orange)
                    .accessibilityIdentifier("editor.inventory.capacityError")
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
    }
}

private struct InventorySlotCard: View {
    let slot: InventorySlotDraft

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text("#\(slot.id + 1)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                Spacer()
                if let item = slot.item, !item.isEditable {
                    GameIcon(systemName: "lock.fill", size: 12)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            if let item = slot.item {
                ItemArtworkView(item: item, size: 46)
                Text(item.chineseName ?? item.name)
                    .font(.subheadline.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Text("×\(item.stack)")
                    Spacer()
                    Text(qualityName(item.quality))
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            } else {
                GameIcon(systemName: "plus.circle.dashed", size: 28)
                    .font(.title2)
                    .foregroundStyle(.secondary)
                Text("空槽位")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 17)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 128, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.primary.opacity(0.06))
        }
    }
}

struct ItemArtworkView: View {
    let item: InventoryItemDraft
    var size: CGFloat = 46

    var body: some View {
        GameItemArtwork(
            name: item.name,
            objectType: item.objectType,
            quality: item.quality,
            spriteIndex: item.spriteIndex,
            texture: item.texture,
            size: size
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(item.localizedName)
    }
}

struct CatalogItemArtworkView: View {
    let item: CatalogItem
    var size: CGFloat = 44

    var body: some View {
        GameItemArtwork(
            name: item.name,
            objectType: item.objectType,
            quality: 0,
            spriteIndex: item.spriteIndex,
            texture: item.texture,
            size: size
        )
        .accessibilityHidden(true)
    }
}

/// Displays the original 16×16 game sprite when its source sheet is bundled.
/// Unknown textures or invalid indices use the original game question mark.
private struct GameItemArtwork: View {
    let name: String
    let objectType: String
    let quality: Int
    let spriteIndex: Int?
    let texture: String?
    let size: CGFloat

    var body: some View {
        if let sprite = GameItemSprite.sprite(index: spriteIndex, texture: texture) {
            ZStack {
                RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                    .fill(Color(.secondarySystemBackground))
                Image(uiImage: sprite)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .padding(size * 0.09)
                RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                    .stroke(qualityColor(quality).opacity(0.55), lineWidth: quality == 0 ? 1 : 2)
            }
            .frame(width: size, height: size)
        } else {
            ItemSymbolArtwork(
                name: name,
                objectType: objectType,
                quality: quality,
                size: size
            )
        }
    }
}

private enum GameItemSprite {
    private static let tileSize = 16

    @MainActor
    static func sprite(index: Int?, texture: String?) -> UIImage? {
        guard let index, index >= 0,
              let source = source(for: texture),
              let sheet = UIImage(named: source.assetName),
              let sheetImage = sheet.cgImage else { return nil }

        let column = index % source.columns
        let row = index / source.columns
        let pixelRect = CGRect(
            x: column * tileSize,
            y: row * tileSize,
            width: tileSize,
            height: tileSize
        )
        guard pixelRect.maxX <= CGFloat(sheetImage.width),
              pixelRect.maxY <= CGFloat(sheetImage.height),
              let cropped = sheetImage.cropping(to: pixelRect) else { return nil }
        return UIImage(cgImage: cropped, scale: 1, orientation: .up)
    }

    private static func source(for texture: String?) -> (assetName: String, columns: Int)? {
        guard let texture else { return nil }
        switch texture.lowercased() {
        case "springobjects", "springobjects.png":
            return ("GameSpringObjects", 24)
        case "objects_2", "objects_2.png":
            return ("GameObjects2", 8)
        default:
            return nil
        }
    }
}

private struct ItemSymbolArtwork: View {
    let name: String
    let objectType: String
    let quality: Int
    let size: CGFloat

    var body: some View {
        GameIcon(systemName: "questionmark", size: size * 0.6)
            .frame(width: size, height: size)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: size * 0.24))
            .overlay {
                RoundedRectangle(cornerRadius: size * 0.24)
                    .stroke(qualityColor(quality).opacity(0.5))
            }
            .accessibilityLabel("暂无可确认的原版物品贴图")
    }
}

private struct InventorySlotEditorView: View {
    @Bindable var session: SaveSession
    let slotIndex: Int
    let catalog: [CatalogItem]
    @Environment(\.dismiss) private var dismiss
    @State private var showingCatalog = false
    @State private var showingClearConfirmation = false
    @State private var targetSlot: Int?

    private var item: InventoryItemDraft? {
        session.draft.inventory[slotIndex].item
    }

    private var emptyTargets: [Int] {
        session.draft.inventory.indices.filter {
            $0 != slotIndex && session.draft.canUseInventorySlot($0) && session.draft.inventory[$0].item == nil
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                if let item {
                    Section("物品") {
                        LabeledContent("名称", value: item.displayName)
                        if item.chineseName != nil {
                            LabeledContent("原始名称", value: item.name)
                                .foregroundStyle(.secondary)
                        }
                        LabeledContent("标识", value: item.itemID)
                        LabeledContent("类型", value: item.objectType)
                    }

                    if item.isEditable, session.draft.canUseInventorySlot(slotIndex) {
                        Section("数量与品质") {
                            LabeledContent("直接输入数量") {
                                TextField("1…999", value: stackBinding, format: .number)
                                    .keyboardType(.numberPad)
                                    .multilineTextAlignment(.trailing)
                                    .accessibilityLabel("物品数量，1 至 999")
                            }
                            Stepper(
                                "数量：\(item.stack)",
                                value: stackBinding,
                                in: 1...999
                            )
                            HStack {
                                ForEach([1, 10, 99, 999], id: \.self) { quantity in
                                    Button("\(quantity)") { stackBinding.wrappedValue = quantity }
                                        .accessibilityLabel("数量设为 \(quantity)")
                                }
                            }
                            .buttonStyle(.bordered)
                            .font(.caption)
                            Picker("品质", selection: qualityBinding) {
                                ForEach(item.allowedQualities, id: \.self) { value in
                                    Text(qualityName(value)).tag(value)
                                }
                            }
                        }

                        if !emptyTargets.isEmpty {
                            Section("槽位操作") {
                                Picker("目标空槽", selection: $targetSlot) {
                                    Text("请选择").tag(nil as Int?)
                                    ForEach(emptyTargets, id: \.self) { index in
                                        Text("槽位 \(index + 1)").tag(index as Int?)
                                    }
                                }
                                Button("移动到目标槽位", systemImage: "arrow.right") {
                                    moveItem()
                                }
                                .disabled(targetSlot == nil)
                                Button("复制到目标槽位", systemImage: "doc.on.doc") {
                                    copyItem()
                                }
                                .disabled(targetSlot == nil)
                            }
                        }

                        Section {
                            Button("清空此槽位", systemImage: "trash", role: .destructive) {
                                showingClearConfirmation = true
                            }
                        }
                    } else {
                        Section {
                            GameLabel(session.draft.canUseInventorySlot(slotIndex)
                                ? "特殊或未知物品保持只读，避免丢失工具升级、附件或专属字段。"
                                : "此槽位超出当前容量，物品已保留。请先扩容后再编辑。", systemImage: "lock.shield")
                                .font(.footnote)
                        }
                    }
                } else if session.draft.canUseInventorySlot(slotIndex) {
                    Section {
                        Button {
                            showingCatalog = true
                        } label: {
                            GameLabel("从安全物品目录添加", systemImage: "plus.circle.fill")
                        }
                    } footer: {
                        Text("仅创建普通 Object 物品；工具、武器、服装与剧情物品不会在这里生成。")
                    }
                }
            }
            .navigationTitle("背包槽位 \(slotIndex + 1)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
        .sheet(isPresented: $showingCatalog) {
            CatalogPickerView(catalog: catalog) { selected in
                session.draft.inventory[slotIndex].item = selected.makeInventoryItem()
                showingCatalog = false
            }
        }
        .alert("清空槽位？", isPresented: $showingClearConfirmation) {
            Button("清空", role: .destructive) {
                session.draft.inventory[slotIndex].item = nil
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("该物品只会在最终保存时从存档中移除。")
        }
    }

    private var stackBinding: Binding<Int> {
        Binding(
            get: { session.draft.inventory[slotIndex].item?.stack ?? 1 },
            set: { session.draft.inventory[slotIndex].item?.stack = min(999, max(1, $0)) }
        )
    }

    private var qualityBinding: Binding<Int> {
        Binding(
            get: { session.draft.inventory[slotIndex].item?.quality ?? 0 },
            set: { session.draft.inventory[slotIndex].item?.quality = $0 }
        )
    }

    private func moveItem() {
        guard let targetSlot, emptyTargets.contains(targetSlot) else { return }
        session.draft.inventory[targetSlot].item = session.draft.inventory[slotIndex].item
        session.draft.inventory[slotIndex].item = nil
        dismiss()
    }

    private func copyItem() {
        guard let targetSlot,
              emptyTargets.contains(targetSlot),
              let item = session.draft.inventory[slotIndex].item else { return }
        session.draft.inventory[targetSlot].item = item.copied()
        self.targetSlot = nil
    }
}


func qualityName(_ value: Int) -> String {
    switch value {
    case 1: "银星"
    case 2: "金星"
    case 4: "铱星"
    default: "普通"
    }
}

private func qualityColor(_ value: Int) -> Color {
    switch value {
    case 1: .gray
    case 2: .yellow
    case 4: .purple
    default: .accentColor
    }
}
