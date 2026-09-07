import SwiftUI
import UIKit

private struct SlotSelection: Identifiable {
    let id: Int
}

struct InventoryEditorView: View {
    @Bindable var session: SaveSession
    let catalog: [CatalogItem]
    @State private var selection: SlotSelection?

    private let columns = [
        GridItem(.adaptive(minimum: 104, maximum: 150), spacing: 10)
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                if session.draft.inventory.isEmpty {
                    ContentUnavailableView("没有背包数据", systemImage: "shippingbox")
                        .padding(.top, 80)
                } else {
                    LazyVGrid(columns: columns, spacing: 10) {
                        ForEach(session.draft.inventory) { slot in
                            Button {
                                selection = SlotSelection(id: slot.id)
                            } label: {
                                InventorySlotCard(slot: slot)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding()
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("背包")
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
                    .lineLimit(2)
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
            $0 != slotIndex && session.draft.inventory[$0].item == nil
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

                    if item.isEditable {
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
                            GameLabel("特殊或未知物品保持只读，避免丢失工具升级、附件或专属字段。", systemImage: "lock.shield")
                                .font(.footnote)
                        }
                    }
                } else {
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
        .confirmationDialog("清空槽位？", isPresented: $showingClearConfirmation) {
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
