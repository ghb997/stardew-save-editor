import Foundation

struct StorageDraft: Identifiable, Equatable, Sendable {
    var id: String { "\(path.id)|\(location)|\(coordinate)" }
    let path: SaveNodePath
    let name: String
    let location: String
    let coordinate: String
    let capacity: Int
    let serializedCount: Int
    let readOnlyReason: String?
    var slots: [InventorySlotDraft]
    var isEditable: Bool { readOnlyReason == nil }
    var occupiedCount: Int { slots.filter { $0.item != nil }.count }
    var title: String { "\(ExistingSaveValue.locationTitle(location)) · \(name)" }
    var searchableText: String { "\(title) \(location) \(coordinate) " + slots.compactMap { $0.item?.localizedName }.joined(separator: " ") }
}

enum StorageEditorRules {
    static func extract(_ objects: [LocatedWorldObject], catalog: [String: CatalogItem]) -> [StorageDraft] {
        objects.compactMap { object in
            let node = object.node
            guard ExistingSaveValue.type(node) == "Chest" || (object.isFridge && ExistingSaveValue.type(node) == "fridge"),
                  node.children(named: "items").count == 1, let items = node.child(named: "items") else { return nil }
            let itemID = ExistingSaveValue.field("itemId", in: node) ?? ExistingSaveValue.field("parentSheetIndex", in: node) ?? ""
            let big = ["BigChest", "BigStoneChest"].contains(itemID)
            let capacity = big ? 70 : 36
            let special = ExistingSaveValue.field("specialChestType", in: node)
            let isShared = node.child(named: "globalInventoryId").map {
                // An empty scalar or an empty NetString wrapper denotes no global inventory.
                !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !$0.children.isEmpty
            } ?? false
            let supportedID = object.isFridge || ["130", "232", "216", "BigChest", "BigStoneChest"].contains(itemID)
            let supportedSpecial = special == nil && node.child(named: "specialChestType") == nil
                || ["None", "0"].contains(special ?? "") || (big && special == "BigChest")
            let known = supportedID && supportedSpecial && !isShared && node.children(named: "globalInventoryId").count <= 1
                && ExistingSaveValue.bool(node.attributes["xsi:nil"] ?? node.attributes["nil"]) != true
                && (object.isFridge || ExistingSaveValue.bool(ExistingSaveValue.field("playerChest", in: node)) == true)
            let itemNodes = items.children(named: "Item")
            let structurallyValid = ExistingSaveValue.bool(items.attributes["xsi:nil"] ?? items.attributes["nil"]) != true
                && itemNodes.count <= capacity
            let editable = known && structurallyValid
            var slots = itemNodes.enumerated().map { i, child in
                InventorySlotDraft(id: i, item: readItem(child, catalog: catalog))
            }
            if editable && slots.count < capacity {
                slots.append(contentsOf: (slots.count..<capacity).map { InventorySlotDraft(id: $0, item: nil) })
            }
            return StorageDraft(path: object.path, name: object.isFridge || itemID == "216" ? "冰箱" : big ? "大箱子" : "箱子",
                location: object.location, coordinate: object.coordinate, capacity: editable ? capacity : itemNodes.count,
                serializedCount: itemNodes.count,
                readOnlyReason: editable ? nil : "共享、特殊或扩展容器，保留原数据，仅供查看。", slots: slots)
        }
    }

    private static func readItem(_ node: XMLNode, catalog: [String: CatalogItem]) -> InventoryItemDraft? {
        if ExistingSaveValue.bool(node.attributes["xsi:nil"] ?? node.attributes["nil"]) == true,
           node.children.isEmpty, node.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return nil }
        let id = ExistingSaveValue.field("itemId", in: node) ?? ExistingSaveValue.field("parentSheetIndex", in: node) ?? "?"
        let known = catalog[id]
        let stack = ExistingSaveValue.field("stack", in: node).flatMap(Int.init)
        let quality = ExistingSaveValue.field("quality", in: node).flatMap(Int.init)
        let type = ExistingSaveValue.type(node)
        let editable = known != nil && InventoryWriteRules.canEdit(node, itemID: id)
        return InventoryItemDraft(id: UUID(), itemID: id, name: node.value(named: "name") ?? "未知物品",
            chineseName: known?.chineseName, objectType: type, stack: stack ?? 1, quality: quality ?? 0,
            spriteIndex: known?.spriteIndex, texture: known?.texture,
            allowedQualities: known?.allowedQualities ?? [quality ?? 0], isEditable: editable, templateXML: node.xmlString())
    }

    static func validate(_ storage: StorageDraft, original: StorageDraft) throws {
        var unchanged = storage
        unchanged.slots = original.slots
        guard unchanged == original, storage.slots.count == original.slots.count,
              storage.slots.map(\.id) == original.slots.map(\.id), storage.isEditable || storage == original else {
            throw SaveValidationError.invalid("容器结构或只读数据发生改变，请重新读取存档。")
        }
        try InventoryWriteRules.validate(storage.slots, original: original.slots)
    }

    static func apply(_ storage: StorageDraft, original: StorageDraft, to root: XMLNode) throws {
        guard storage != original else { return }
        guard let node = storage.path.resolve(in: root), let items = node.child(named: "items"),
              items.children(named: "Item").count == original.serializedCount else {
            throw SaveValidationError.invalid("容器来源已改变，无法写回。")
        }
        let existing = items.children(named: "Item")
        let lastOccupied = storage.slots.lastIndex(where: { $0.item != nil }).map { $0 + 1 } ?? 0
        let count = max(original.serializedCount, lastOccupied)
        var updated: [XMLNode] = []
        for index in 0..<count {
            let slot = storage.slots[index]
            if index < existing.count, slot == original.slots[index] { updated.append(existing[index]); continue }
            guard let item = slot.item else {
                updated.append(XMLNode(name: "Item", attributes: ["xsi:nil": "true"])); continue
            }
            let wrapper = "<Fragment xmlns:xsi=\"http://www.w3.org/2001/XMLSchema-instance\">\(item.templateXML)</Fragment>"
            let fragment = try XMLTreeParser().parse(Data(wrapper.utf8))
            guard let itemNode = fragment.children.first, itemNode.name == "Item" else {
                throw SaveValidationError.invalid("容器物品模板无法解析。")
            }
            // Changing quantity alone preserves the original spelling of quality and vice versa.
            let previous = original.slots[index].item
            if item.id != previous?.id || item.stack != previous?.stack { itemNode.setValue(String(item.stack), named: "stack") }
            if item.id != previous?.id || item.quality != previous?.quality { itemNode.setValue(String(item.quality), named: "quality") }
            updated.append(itemNode.deepCopy())
        }
        var next = 0
        items.children = items.children.compactMap { child in
            guard child.name == "Item" else { return child }
            defer { next += 1 }
            return updated.indices.contains(next) ? updated[next] : nil
        }
        items.children.append(contentsOf: updated.dropFirst(next))
    }
}
