import Foundation

struct CatalogItem: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let chineseName: String?
    let objectType: String
    let category: Int
    let price: Int
    let edibility: Int
    let spriteIndex: Int
    /// Source game texture containing this item's 16×16 sprite.
    let texture: String
    let allowedQualities: [Int]

    var displayName: String {
        guard let chineseName else { return name }
        return chineseName
    }

    var searchableText: String {
        "\(id) \(name) \(chineseName ?? "")"
    }

    func makeInventoryItem(stack: Int = 1, quality: Int = 0) -> InventoryItemDraft {
        let node = XMLNode(
            name: "Item",
            attributes: ["xsi:type": "Object"],
            children: [
                XMLNode(name: "isLostItem", text: "false"),
                XMLNode(name: "category", text: String(category)),
                XMLNode(name: "hasBeenInInventory", text: "true"),
                XMLNode(name: "name", text: name),
                XMLNode(name: "parentSheetIndex", text: String(spriteIndex)),
                XMLNode(name: "itemId", text: id),
                XMLNode(name: "specialItem", text: "false"),
                XMLNode(name: "isRecipe", text: "false"),
                XMLNode(name: "quality", text: String(quality)),
                XMLNode(name: "stack", text: String(stack)),
                XMLNode(name: "SpecialVariable", text: "0"),
                XMLNode(name: "tileLocation", children: [
                    XMLNode(name: "X", text: "0"),
                    XMLNode(name: "Y", text: "0")
                ]),
                XMLNode(name: "owner", text: "0"),
                XMLNode(name: "type", text: objectType),
                XMLNode(name: "canBeSetDown", text: "true"),
                XMLNode(name: "canBeGrabbed", text: "true"),
                XMLNode(name: "isSpawnedObject", text: "false"),
                XMLNode(name: "questItem", text: "false"),
                XMLNode(name: "isOn", text: "true"),
                XMLNode(name: "fragility", text: "0"),
                XMLNode(name: "price", text: String(price)),
                XMLNode(name: "edibility", text: String(edibility)),
                XMLNode(name: "bigCraftable", text: "false"),
                XMLNode(name: "setOutdoors", text: "false"),
                XMLNode(name: "setIndoors", text: "false"),
                XMLNode(name: "readyForHarvest", text: "false"),
                XMLNode(name: "showNextIndex", text: "false"),
                XMLNode(name: "flipped", text: "false"),
                XMLNode(name: "isLamp", text: "false"),
                XMLNode(name: "minutesUntilReady", text: "0"),
                XMLNode(name: "boundingBox", children: [
                    XMLNode(name: "X", text: "0"),
                    XMLNode(name: "Y", text: "0"),
                    XMLNode(name: "Width", text: "0"),
                    XMLNode(name: "Height", text: "0"),
                    XMLNode(name: "Location", children: [
                        XMLNode(name: "X", text: "0"),
                        XMLNode(name: "Y", text: "0")
                    ]),
                    XMLNode(name: "Size", children: [
                        XMLNode(name: "X", text: "0"),
                        XMLNode(name: "Y", text: "0")
                    ])
                ]),
                XMLNode(name: "scale", children: [
                    XMLNode(name: "X", text: "0"),
                    XMLNode(name: "Y", text: "0")
                ]),
                XMLNode(name: "uses", text: "0"),
                XMLNode(name: "destroyOvernight", text: "false")
            ]
        )

        return InventoryItemDraft(
            id: UUID(),
            itemID: id,
            name: name,
            chineseName: chineseName,
            objectType: "Object",
            stack: stack,
            quality: quality,
            spriteIndex: spriteIndex,
            texture: texture,
            allowedQualities: allowedQualities,
            isEditable: true,
            templateXML: node.xmlString()
        )
    }
}

enum ItemCatalogError: LocalizedError {
    case resourceMissing
    case invalidData

    var errorDescription: String? {
        switch self {
        case .resourceMissing: "内置物品目录不存在。"
        case .invalidData: "内置物品目录格式无效。"
        }
    }
}

enum ItemCatalog {
    // Verified 1.6 string IDs using the standard Object schema.
    static let supportedStringIDs: Set<String> = [
        "Carrot", "CarrotSeeds", "SummerSquash", "SummerSquashSeeds",
        "Broccoli", "BroccoliSeeds", "Powdermelon", "PowdermelonSeeds"
    ]

    private static let qualityCategories: Set<Int> = [
        -4, -5, -6, -7, -8, -14, -18, -26, -75, -79, -80, -81
    ]

    /// Types that the game safely reconstructs from the standard Object schema
    /// emitted below. Rings, quest objects, litter, interactive placeholders,
    /// and unknown/decompiler placeholder types require extra runtime fields.
    private static let safeObjectTypes: Set<String> = [
        "Arch", "Basic", "Cooking", "Crafting", "Fish", "Minerals", "Seeds"
    ]

    static func load(bundle: Bundle = .main) throws -> [CatalogItem] {
        guard let url = bundle.url(forResource: "iteminfo", withExtension: "json"),
              let namesURL = bundle.url(forResource: "itemnames_zh", withExtension: "json") else {
            throw ItemCatalogError.resourceMissing
        }
        let data = try Data(contentsOf: url)
        let namesData = try Data(contentsOf: namesURL)
        guard let entries = try JSONSerialization.jsonObject(with: data) as? [[Any]],
              let localizedNames = try? JSONDecoder().decode([String: String].self, from: namesData),
              !localizedNames.isEmpty else {
            throw ItemCatalogError.invalidData
        }

        let result: [CatalogItem] = entries.compactMap { pair in
            guard pair.count == 2,
                  let metadata = pair[1] as? [String: Any],
                  metadata["_type"] as? String == "Object",
                  let key = metadata["_key"] as? String,
                  (Int(key) != nil || supportedStringIDs.contains(key)),
                  metadata["unpreservedItemId"] == nil,
                  metadata["preservedItemName"] == nil,
                  metadata["color"] == nil,
                  let name = metadata["name"] as? String,
                  let type = metadata["type"] as? String,
                  safeObjectTypes.contains(type),
                  !name.isEmpty,
                  name != "???" else { return nil }

            let category = (metadata["category"] as? Int) ?? 0
            let spriteIndex = (metadata["spriteIndex"] as? Int) ?? Int(key) ?? 0
            // Older object data omits `texture`; those entries live in the
            // original springobjects sheet.
            let texture = (metadata["texture"] as? String) ?? "springobjects.png"
            return CatalogItem(
                id: key,
                name: name,
                chineseName: localizedNames[key] ?? chineseNames[name],
                objectType: type,
                category: category,
                price: (metadata["price"] as? Int) ?? 0,
                edibility: (metadata["edibility"] as? Int) ?? -300,
                spriteIndex: spriteIndex,
                texture: texture,
                allowedQualities: qualityCategories.contains(category) ? [0, 1, 2, 4] : [0]
            )
        }

        guard !result.isEmpty else { throw ItemCatalogError.invalidData }
        return result.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    static let chineseNames: [String: String] = [
        "Parsnip": "防风草", "Sap": "树液", "Hay": "干草", "Potato": "土豆",
        "Blueberry": "蓝莓", "Cranberries": "蔓越莓", "Coal": "煤炭", "Wood": "木材",
        "Stone": "石头", "Hardwood": "硬木", "Mixed Seeds": "混合种子", "Fiber": "纤维",
        "Clay": "黏土", "Copper Ore": "铜矿石", "Iron Ore": "铁矿石",
        "Gold Ore": "金矿石", "Iridium Ore": "铱矿石", "Radioactive Ore": "放射性矿石",
        "Battery Pack": "电池组", "Prismatic Shard": "五彩碎片", "Diamond": "钻石",
        "Ruby": "红宝石", "Emerald": "绿宝石", "Aquamarine": "海蓝宝石",
        "Jade": "翡翠", "Amethyst": "紫水晶", "Topaz": "黄水晶",
        "Ancient Fruit": "上古水果", "Starfruit": "杨桃", "Sweet Gem Berry": "宝石甜莓",
        "Pumpkin": "南瓜", "Melon": "甜瓜", "Cauliflower": "花椰菜",
        "Iridium Sprinkler": "铱制洒水器", "Quality Sprinkler": "优质洒水器",
        "Sprinkler": "洒水器", "Cherry Bomb": "樱桃炸弹", "Bomb": "炸弹",
        "Mega Bomb": "超级炸弹", "Warp Totem: Farm": "传送图腾：农场",
        "Warp Totem: Beach": "传送图腾：海滩", "Warp Totem: Desert": "传送图腾：沙漠",
        "Farm Computer": "农场电脑", "Furnace": "熔炉", "Keg": "小桶",
        "Preserves Jar": "罐头瓶", "Seed Maker": "种子生产器", "Scarecrow": "稻草人",
        "Deluxe Scarecrow": "豪华稻草人", "Chest": "木箱", "Stone Chest": "石箱",
        "Big Chest": "大箱子", "Moss": "苔藓", "Truffle": "松露",
        "Truffle Oil": "松露油", "Coffee": "咖啡", "Triple Shot Espresso": "三倍浓缩咖啡",
        "Pizza": "披萨", "Fried Egg": "煎鸡蛋", "Sashimi": "生鱼片", "Maki Roll": "生鱼寿司"
    ]
}
