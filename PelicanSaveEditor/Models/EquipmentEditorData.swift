import Foundation

struct EquipmentField: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let originalText: String
    let minimum: Double
    let maximum: Double
    let isInteger: Bool
    var value: Double
    var formatted: String { isInteger && value.isFinite && abs(value) < Double(Int.max) ? String(Int(value)) : String(value) }
}

struct EquipmentDraft: Identifiable, Equatable, Sendable {
    var id: String { path.id }
    let path: SaveNodePath
    let name: String
    let type: String
    let location: String
    let sourceXML: String
    var fields: [EquipmentField]
}

enum EquipmentEditorRules {
    private struct Rule {
        let key: String
        let title: String
        let range: ClosedRange<Double>
        var integer = true
    }
    private static func rules(for type: String) -> [Rule] {
        switch type {
        case "Axe", "Pickaxe", "Hoe", "WateringCan":
            return [Rule(key: "upgradeLevel", title: "升级等级", range: 0...4)]
        case "MeleeWeapon":
            return [Rule(key: "minDamage", title: "最低伤害", range: 0...10_000),
                    Rule(key: "maxDamage", title: "最高伤害", range: 0...10_000),
                    Rule(key: "speed", title: "速度加成", range: -10...20),
                    Rule(key: "addedDefense", title: "防御加成", range: 0...1_000),
                    Rule(key: "precision", title: "精准加成", range: -10...100),
                    Rule(key: "critChance", title: "暴击概率（0–1）", range: 0...1, integer: false),
                    Rule(key: "critMultiplier", title: "暴击倍率", range: 0...100, integer: false),
                    Rule(key: "knockback", title: "击退倍率", range: 0...10, integer: false)]
        case "Boots":
            return [Rule(key: "defenseBonus", title: "防御加成", range: 0...1_000),
                    Rule(key: "immunityBonus", title: "免疫加成", range: 0...1_000)]
        default: return []
        }
    }

    static func extract(_ root: XMLNode, storages: [StorageDraft]) -> [EquipmentDraft] {
        var result: [EquipmentDraft] = []
        func inspect(_ node: XMLNode, path: SaveNodePath, location: String) {
            let rawType = ExistingSaveValue.type(node)
            let type = rawType == "boots" ? "Boots" : rawType
            guard ExistingSaveValue.bool(node.attributes["xsi:nil"] ?? node.attributes["nil"]) != true else { return }
            let fields = rules(for: type).compactMap { rule -> EquipmentField? in
                guard let raw = ExistingSaveValue.field(rule.key, in: node),
                      let value = Double(raw), value.isFinite,
                      !rule.integer || value.rounded() == value else { return nil }
                return EquipmentField(id: rule.key, title: rule.title, originalText: raw,
                    minimum: rule.range.lowerBound, maximum: rule.range.upperBound, isInteger: rule.integer, value: value)
            }
            guard !fields.isEmpty else { return }
            let rawName = ExistingSaveValue.field("name", in: node) ?? type
            result.append(EquipmentDraft(path: path, name: ItemCatalog.chineseNames[rawName] ?? rawName,
                type: type, location: location, sourceXML: node.xmlString(), fields: fields))
        }
        if root.children(named: "player").count == 1,
           let p = root.children.firstIndex(where: { $0.name == "player" }) {
            let player = root.children[p]
            if player.children(named: "items").count == 1,
               let i = player.children.firstIndex(where: { $0.name == "items" }) {
                var slot = 0
                for (n, item) in player.children[i].children.enumerated() where item.name == "Item" {
                    slot += 1
                    inspect(item, path: SaveNodePath(indices: [p, i, n]), location: "背包第 \(slot) 格")
                }
            }
            // Boots can be worn or kept in the backpack. Other equipment slots
            // use distinct game schemas and remain untouched.
            if player.children(named: "boots").count == 1,
               let n = player.children.firstIndex(where: { $0.name == "boots" }) {
                inspect(player.children[n], path: SaveNodePath(indices: [p, n]), location: "当前穿戴的鞋子")
            }
        }
        for storage in storages where storage.isEditable {
            guard let node = storage.path.resolve(in: root), node.children(named: "items").count == 1,
                  let i = node.children.firstIndex(where: { $0.name == "items" }) else { continue }
            var slot = 0
            for (n, item) in node.children[i].children.enumerated() where item.name == "Item" {
                slot += 1
                inspect(item, path: storage.path.child(i).child(n), location: "\(storage.location) · \(storage.coordinate) · 第 \(slot) 格")
            }
        }
        return result
    }

    static func validate(_ gear: [EquipmentDraft], original: [EquipmentDraft]) throws {
        guard gear.map(\.id) == original.map(\.id) else { throw SaveValidationError.invalid("装备来源已改变，请重新加载存档。") }
        for (item, old) in zip(gear, original) where item != old {
            guard item.fields.map(\.id) == old.fields.map(\.id) else { throw SaveValidationError.invalid("不能添加或移除装备字段。") }
            var metadata = item
            metadata.fields = old.fields
            guard metadata == old else { throw SaveValidationError.invalid("不能替换装备类型、位置或原始记录。") }
            for (field, previous) in zip(item.fields, old.fields) where field != previous {
                var fixed = field
                fixed.value = previous.value
                guard fixed == previous, field.value.isFinite,
                      (field.minimum...field.maximum).contains(field.value),
                      !field.isInteger || field.value.rounded() == field.value else {
                    throw SaveValidationError.invalid("\(item.name)的\(field.title)超出支持范围。")
                }
            }
            let damageChanged = zip(item.fields, old.fields).contains { ["minDamage", "maxDamage"].contains($0.0.id) && $0.0 != $0.1 }
            if damageChanged, let minimum = item.fields.first(where: { $0.id == "minDamage" }),
               let maximum = item.fields.first(where: { $0.id == "maxDamage" }), minimum.value > maximum.value {
                throw SaveValidationError.invalid("最低伤害不能大于最高伤害。")
            }
        }
    }

    static func apply(_ gear: [EquipmentDraft], original: [EquipmentDraft], to root: XMLNode) throws {
        try validate(gear, original: original)
        for (item, old) in zip(gear, original) where item != old {
            guard let node = old.path.resolve(in: root), node.xmlString() == old.sourceXML else {
                throw SaveValidationError.invalid("装备记录与读取时不一致，已取消保存。")
            }
            for (field, previous) in zip(item.fields, old.fields) where field.value != previous.value {
                guard node.setValue(field.formatted, named: field.id) else {
                    throw SaveValidationError.invalid("装备字段缺失，已取消保存。")
                }
            }
        }
    }

    static func diffs(_ gear: [EquipmentDraft], original: [EquipmentDraft]) -> [SaveDiff] {
        zip(gear, original).flatMap { item, old -> [SaveDiff] in
            zip(item.fields, old.fields).compactMap { field, previous -> SaveDiff? in
                guard field.value != previous.value else { return nil }
                return SaveDiff(id: "equipment:\(item.id):\(field.id)", section: "工具与装备",
                    label: "\(item.location) · \(item.name) · \(field.title)", oldValue: previous.formatted,
                    newValue: field.formatted, affectsSaveGameInfo: false)
            }
        }
    }
}
