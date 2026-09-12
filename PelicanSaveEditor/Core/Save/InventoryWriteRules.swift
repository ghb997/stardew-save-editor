import Foundation

/// Keep the same item identity and opaque XML at the UI and serialization boundaries.
enum InventoryWriteRules {
    private static let canonicalItems = (try? ItemCatalog.load()) ?? []

    static func canEdit(_ node: XMLNode, itemID: String) -> Bool {
        guard ["Object", "ColoredObject"].contains(ExistingSaveValue.type(node)),
              ExistingSaveValue.bool(node.attributes["xsi:nil"] ?? node.attributes["nil"]) != true,
              node.children(named: "itemId").count <= 1, node.children(named: "parentSheetIndex").count <= 1,
              (ExistingSaveValue.field("itemId", in: node) ?? ExistingSaveValue.field("parentSheetIndex", in: node)) == itemID,
              Int(itemID).map({ $0 >= 0 }) == true || ItemCatalog.supportedStringIDs.contains(itemID),
              let stack = ExistingSaveValue.field("stack", in: node).flatMap(Int.init),
              let quality = ExistingSaveValue.field("quality", in: node).flatMap(Int.init),
              (1...999).contains(stack), [0, 1, 2, 4].contains(quality) else { return false }
        for key in ["specialItem", "questItem", "isRecipe", "bigCraftable"] {
            if !node.children(named: key).isEmpty,
               ExistingSaveValue.bool(ExistingSaveValue.field(key, in: node)) != false { return false }
        }
        return !(ExistingSaveValue.field("name", in: node) ?? "").hasPrefix("Secret Note")
    }

    static func validate(_ slots: [InventorySlotDraft], original: [InventorySlotDraft]) throws {
        let items = slots.compactMap(\.item)
        guard Set(items.map(\.id)).count == items.count else {
            throw SaveValidationError.invalid("背包物品身份重复，请撤销复制并重新操作。")
        }
        for old in original where old.item?.isEditable == false {
            guard slots.first(where: { $0.id == old.id })?.item == old.item else {
                throw SaveValidationError.invalid("背包中的工具、装备与未知物品不能移除、移动或替换；请使用工具与装备入口。")
            }
        }
        let previousItems = original.compactMap(\.item)
        for slot in slots {
            if let old = original.first(where: { $0.id == slot.id }), old.item == slot.item { continue }
            guard let item = slot.item else { continue }
            guard item.isEditable, (1...999).contains(item.stack), item.allowedQualities.contains(item.quality) else {
                throw SaveValidationError.invalid("背包物品数量、品质或可编辑状态无效。")
            }
            // Moving/copying a supported item preserves every unexposed field.
            let source = previousItems.first(where: { $0.id == item.id })
                ?? previousItems.first(where: { metadataMatches(item, $0) })
            if let source {
                guard source.isEditable, metadataMatches(item, source) else {
                    throw SaveValidationError.invalid("现有背包物品只能修改数量和品质，其他字段必须保留。")
                }
            } else {
                guard let known = canonicalItems.first(where: { $0.id == item.itemID }),
                      canonicalMatches(item, known: known) else {
                    throw SaveValidationError.invalid("新增背包物品必须来自内置目录，不能使用未知模板。")
                }
            }
        }
    }

    private static func canonicalMatches(_ item: InventoryItemDraft, known: CatalogItem) -> Bool {
        let wrapper = "<Fragment xmlns:xsi=\"http://www.w3.org/2001/XMLSchema-instance\">\(item.templateXML)</Fragment>"
        guard let fragment = try? XMLTreeParser().parse(Data(wrapper.utf8)), fragment.children.count == 1,
              let node = fragment.children.first, node.name == "Item",
              let stack = ExistingSaveValue.field("stack", in: node).flatMap(Int.init),
              let quality = ExistingSaveValue.field("quality", in: node).flatMap(Int.init),
              (1...999).contains(stack), known.allowedQualities.contains(quality) else { return false }
        return metadataMatches(item, known.makeInventoryItem(stack: stack, quality: quality))
    }

    private static func metadataMatches(_ item: InventoryItemDraft, _ source: InventoryItemDraft) -> Bool {
        var metadata = item
        metadata.id = source.id
        metadata.stack = source.stack
        metadata.quality = source.quality
        return metadata == source
    }
}
