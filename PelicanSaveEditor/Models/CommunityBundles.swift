import Foundation

struct BundleRequirement: Identifiable, Equatable, Sendable {
    let id: String
    let itemID: String
    let quantity: Int
    let quality: Int
    let donated: Bool
    var isGold: Bool { itemID == "-1" }
}

struct CommunityBundle: Identifiable, Equatable, Sendable {
    let id: String
    let area: String
    let name: String
    let requiredCount: Int
    let requirements: [BundleRequirement]
    var donatedCount: Int { requirements.filter(\.donated).count }
    var isComplete: Bool { donatedCount >= requiredCount }
    var title: String { Self.names[name] ?? name }
    var areaTitle: String {
        ["Crafts Room": "工艺室", "Pantry": "茶水间", "Fish Tank": "鱼缸", "Boiler Room": "锅炉房",
         "Bulletin Board": "布告栏", "Vault": "金库", "Abandoned Joja Mart": "废弃 Joja 超市"][area] ?? area
    }
    static let names = [
        "Spring Foraging": "春季采集", "Summer Foraging": "夏季采集", "Fall Foraging": "秋季采集", "Winter Foraging": "冬季采集",
        "Construction": "建筑材料", "Exotic Foraging": "异域采集", "Spring Crops": "春季作物", "Summer Crops": "夏季作物",
        "Fall Crops": "秋季作物", "Quality Crops": "高品质作物", "Animal": "动物产品", "Artisan": "工匠物品",
        "River Fish": "河鱼", "Lake Fish": "湖鱼", "Ocean Fish": "海鱼", "Night Fishing": "夜间垂钓",
        "Crab Pot": "蟹笼", "Specialty Fish": "特色鱼类", "Blacksmith's": "铁匠", "Geologist's": "地质学家",
        "Adventurer's": "冒险家", "Chef's": "厨师", "Dye": "染料", "Field Research": "实地研究",
        "Fodder": "饲料", "Enchanter's": "魔法师", "2,500g": "2,500 金", "5,000g": "5,000 金",
        "10,000g": "10,000 金", "25,000g": "25,000 金", "The Missing": "遗失的收集包"
    ]
}

struct CommunityCenterData: Equatable, Sendable {
    var bundles: [CommunityBundle] = []
    var unreadableCount = 0
    var isJojaMember = false

    static func extract(_ root: XMLNode) -> Self {
        var result = Self()
        let mail = root.child(named: "player")?.child(named: "mailReceived")?.children(named: "string").map(\.text) ?? []
        result.isJojaMember = mail.contains("JojaMember")
        let definitions = ExistingSaveValue.dictionary(root.child(named: "bundleData"))
        let stateEntries = ExistingSaveValue.dictionary(root.child(named: "bundles"))
        var states: [String: [[Bool]?]] = [:]
        for entry in stateEntries {
            guard let id = entry.child(named: "key")?.value(named: "int") else { continue }
            let array = entry.child(named: "value")?.child(named: "ArrayOfBoolean")
            let children = array?.children ?? []
            let parsed = children.map { ExistingSaveValue.bool(ExistingSaveValue.scalar($0)) }
            let valid = array != nil && !children.isEmpty && children.allSatisfy { $0.name == "boolean" }
                && parsed.allSatisfy { $0 != nil }
            states[id, default: []].append(valid ? parsed.compactMap { $0 } : nil)
        }
        let definitionIDs = definitions.compactMap { $0.child(named: "key")?.value(named: "string")?.split(separator: "/").last.map(String.init) }
        let counts = Dictionary(definitionIDs.map { ($0, 1) }, uniquingKeysWith: +)
        for entry in definitions {
            guard let key = entry.child(named: "key")?.value(named: "string"),
                  let valueNode = entry.child(named: "value")?.child(named: "string"),
                  let value = ExistingSaveValue.scalar(valueNode) else { result.unreadableCount += 1; continue }
            let keyParts = key.split(separator: "/", omittingEmptySubsequences: false)
            let parts = value.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
            guard keyParts.count == 2, parts.count >= 4, let id = keyParts.last.map(String.init),
                  counts[id] == 1, let variants = states[id], variants.count == 1,
                  let flags = variants[0] else { result.unreadableCount += 1; continue }
            let tokens = parts[2].split(whereSeparator: \.isWhitespace).map(String.init)
            guard !tokens.isEmpty, tokens.count % 3 == 0, flags.count == tokens.count / 3 else { result.unreadableCount += 1; continue }
            var requirements: [BundleRequirement] = []
            for index in stride(from: 0, to: tokens.count, by: 3) {
                guard let count = Int(tokens[index + 1]), count > 0, count <= Int(Int32.max),
                      let quality = Int(tokens[index + 2]), [0, 1, 2, 4].contains(quality) else { continue }
                requirements.append(BundleRequirement(id: "\(id):\(index / 3)", itemID: tokens[index], quantity: count,
                    quality: quality, donated: flags[index / 3]))
            }
            let required: Int
            if parts.count > 4 && !parts[4].isEmpty { required = Int(parts[4]) ?? -1 }
            else { required = requirements.count }
            guard requirements.count == flags.count, (1...requirements.count).contains(required) else {
                result.unreadableCount += 1; continue
            }
            result.bundles.append(CommunityBundle(id: id, area: String(keyParts[0]), name: parts[0],
                                                  requiredCount: required, requirements: requirements))
        }
        result.bundles.sort { ($0.area, Int($0.id) ?? 0) < ($1.area, Int($1.id) ?? 0) }
        return result
    }
}

struct BundleSupplyLine: Identifiable, Sendable {
    let id: String
    let bundleTitle: String
    let requirement: BundleRequirement
    let item: CatalogItem
    let slot: Int
}

enum BundleSupplyRules {
    static func plan(ids: Set<String>, draft: SaveDraft, catalog: [CatalogItem]) throws -> [BundleSupplyLine] {
        guard !draft.communityCenter.isJojaMember else { throw SaveValidationError.invalid("当前为 Joja 路线，材料补给不可用。") }
        let known = Dictionary(catalog.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let empty = draft.inventory.filter { $0.item == nil && draft.canUseInventorySlot($0.id) }.map(\.id)
        var lines: [BundleSupplyLine] = []
        for bundle in draft.communityCenter.bundles where !bundle.isComplete {
            for requirement in bundle.requirements where ids.contains(requirement.id) {
                guard !requirement.donated, !requirement.isGold, (1...999).contains(requirement.quantity),
                      let item = known[requirement.itemID], item.allowedQualities.contains(requirement.quality) else {
                    throw SaveValidationError.invalid("所选材料已交付或不支持自动补给，请重新选择。")
                }
                guard lines.count < empty.count else { throw SaveValidationError.invalid("背包空位不足，需要 \(ids.count) 格，当前有 \(empty.count) 格。") }
                lines.append(BundleSupplyLine(id: requirement.id, bundleTitle: bundle.title,
                                              requirement: requirement, item: item, slot: empty[lines.count]))
            }
        }
        guard !lines.isEmpty, Set(lines.map(\.id)) == ids else {
            throw SaveValidationError.invalid("材料选择已失效，请重新打开预览。")
        }
        return lines
    }

    static func apply(ids: Set<String>, to draft: inout SaveDraft, catalog: [CatalogItem]) throws {
        // Plan entirely before mutation; insufficient space never leaves a partial supply.
        let lines = try plan(ids: ids, draft: draft, catalog: catalog)
        for line in lines {
            draft.inventory[line.slot].item = line.item.makeInventoryItem(stack: line.requirement.quantity, quality: line.requirement.quality)
        }
    }
}
