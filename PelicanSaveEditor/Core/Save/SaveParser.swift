import Foundation

struct ParsedSaveDocument {
    let mainRoot: XMLNode
    let infoRoot: XMLNode?
    let mainPayload: DecodedSave
    let infoPayload: DecodedSave?
    let draft: SaveDraft
    let gameVersion: String
    let playTimeMilliseconds: Int64?
    let farmType: Int?
    let warnings: [String]
}

enum SaveParseError: LocalizedError {
    case invalidRoot(String)
    case missingField(String)
    case unsupportedVersion(String)
    case invalidValue(String)
    case mismatchedPair

    var errorDescription: String? {
        switch self {
        case let .invalidRoot(name):
            "不是星露谷存档（根节点为 \(name)）。"
        case let .missingField(path):
            "存档缺少必需字段：\(path)"
        case let .unsupportedVersion(version):
            "当前主要支持星露谷物语 1.6.x，检测到版本 \(version)。"
        case let .invalidValue(path):
            "存档字段值无效：\(path)"
        case .mismatchedPair:
            "主存档与 SaveGameInfo 的玩家标识不同，请选择同一农场目录中的两份文件。"
        }
    }
}

enum SaveParser {
    static func parse(
        mainData: Data,
        infoData: Data?,
        catalog: [CatalogItem],
        recipeCatalog: [RecipeKind: [String]]
    ) throws -> ParsedSaveDocument {
        let mainPayload = try SaveCodec.decode(mainData)
        let mainRoot = try XMLTreeParser().parse(mainPayload.xmlData)
        guard mainRoot.name == "SaveGame" else {
            throw SaveParseError.invalidRoot(mainRoot.name)
        }

        let infoPayload = try infoData.map(SaveCodec.decode)
        let infoRoot = try infoPayload.map { try XMLTreeParser().parse($0.xmlData) }

        guard let player = mainRoot.child(named: "player") else {
            throw SaveParseError.missingField("SaveGame/player")
        }

        let version = mainRoot.value(named: "gameVersion")
            ?? infoRoot?.value(named: "gameVersion")
            ?? "未知"
        guard version == "未知" || version.hasPrefix("1.6") else {
            throw SaveParseError.unsupportedVersion(version)
        }

        var warnings = try validatePair(mainRoot: mainRoot, infoRoot: infoRoot)
        if infoRoot == nil {
            warnings.append("未载入 SaveGameInfo；可编辑主存档，但无法同步存档列表摘要。")
        }
        if version == "未知" {
            warnings.append("未找到游戏版本字段；保存前请确认这是 1.6.x 存档。")
        }

        let catalogByID = Dictionary(catalog.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var inventory = extractInventory(player: player, catalogByID: catalogByID, warnings: &warnings)
        let inventorySlotFloor = inventory.count
        let backpackCapacity = editableScalar(player.child(named: "maxItems")).flatMap(Int.init)
        if let capacity = backpackCapacity, BackpackRules.capacities.contains(capacity),
           player.child(named: "items") != nil, inventory.count < capacity {
            inventory.append(contentsOf: (inventory.count..<capacity).map {
                InventorySlotDraft(id: $0, item: nil)
            })
        }
        if let capacity = backpackCapacity, BackpackRules.capacities.contains(capacity),
           inventory.dropFirst(capacity).contains(where: { $0.item != nil }) {
            warnings.append("背包容量外仍有物品，已保留这些槽位；请在背包页检查后再调整容量。")
        }
        let friendships = extractFriendships(player: player)
        let recipes = extractRecipes(player: player, recipeCatalog: recipeCatalog)
        let farmhouse = extractFarmhouse(root: mainRoot, player: player)
        let progress = extractProgress(root: mainRoot, player: player)
        let animals = extractAnimals(root: mainRoot)

        let season: Season = {
            if let current = mainRoot.value(named: "currentSeason"),
               let parsed = Season(rawValue: current.lowercased()) {
                return parsed
            }
            return Season(saveIndex: player.int(named: "seasonForSaveGame") ?? 0)
        }()

        let rawHair = player.int(named: "hair") ?? 0
        let displayHair = rawHair >= 100 ? rawHair - 100 + 56 : rawHair
        let genderRaw = player.value(named: "Gender") ?? player.value(named: "gender") ?? "Male"
        let playTimeMilliseconds = mainRoot.value(named: "millisecondsPlayed").flatMap(Int64.init)
            ?? player.value(named: "millisecondsPlayed").flatMap(Int64.init)
            ?? infoRoot?.value(named: "millisecondsPlayed").flatMap(Int64.init)
        let farmType = mainRoot.int(named: "whichFarm")
            ?? player.int(named: "whichFarm")
            ?? infoRoot?.int(named: "whichFarm")

        let experienceNodes = player.child(named: "experiencePoints")?.children(named: "int") ?? []
        let skills = SkillKey.allCases.map { skill in
            let level = max(0, min(10, player.int(named: skill.fieldName) ?? 0))
            let experience = experienceNodes.indices.contains(skill.experienceIndex)
                ? Int(experienceNodes[skill.experienceIndex].text) ?? SkillKey.experienceForLevel[level]
                : SkillKey.experienceForLevel[level]
            return SkillDraft(
                key: skill,
                originalLevel: level,
                originalExperience: experience,
                level: level,
                experience: experience
            )
        }

        let draft = SaveDraft(
            playerName: player.value(named: "name") ?? "",
            farmName: player.value(named: "farmName") ?? "",
            favoriteThing: player.value(named: "favoriteThing") ?? "",
            money: player.int(named: "money") ?? 0,
            maxHealth: player.int(named: "maxHealth") ?? 100,
            maxStamina: player.int(named: "maxStamina") ?? 270,
            gender: FarmerGender(rawValue: genderRaw) ?? .male,
            hair: max(0, min(73, displayHair)),
            skin: max(0, min(23, player.int(named: "skin") ?? 0)),
            accessory: max(-1, min(29, player.int(named: "accessory") ?? -1)),
            year: mainRoot.int(named: "year") ?? player.int(named: "yearForSaveGame") ?? 1,
            season: season,
            day: mainRoot.int(named: "dayOfMonth") ?? player.int(named: "dayOfMonthForSaveGame") ?? 1,
            skills: skills,
            inventory: inventory,
            friendships: friendships,
            recipes: recipes,
            farmhouse: farmhouse,
            progress: progress,
            animals: animals,
            farmActions: FarmActionDraft(),
            backpackCapacity: backpackCapacity,
            inventorySlotFloor: inventorySlotFloor
        )

        return ParsedSaveDocument(
            mainRoot: mainRoot,
            infoRoot: infoRoot,
            mainPayload: mainPayload,
            infoPayload: infoPayload,
            draft: draft,
            gameVersion: version,
            playTimeMilliseconds: playTimeMilliseconds,
            farmType: farmType,
            warnings: warnings
        )
    }

    /// Names and balances are editable; use the saved farmer identity to detect
    /// accidentally selecting a summary from a different farm.
    static func validatePair(mainRoot: XMLNode, infoRoot: XMLNode?) throws -> [String] {
        guard let infoRoot else { return [] }
        guard infoRoot.name == "Farmer" else {
            throw SaveParseError.invalidRoot("SaveGameInfo/\(infoRoot.name)，应为 Farmer")
        }
        func identity(in node: XMLNode?) -> String? {
            guard let value = node?.value(named: "uniqueMultiplayerID")?
                .trimmingCharacters(in: .whitespacesAndNewlines),
                !value.isEmpty, value != "0" else { return nil }
            return value
        }
        let mainID = identity(in: mainRoot.child(named: "player"))
        let infoID = identity(in: infoRoot)
        if let mainID, let infoID {
            guard mainID == infoID else { throw SaveParseError.mismatchedPair }
            return []
        }
        return ["主存档或 SaveGameInfo 缺少稳定玩家标识，无法确认两份文件属于同一农场；请核对来源目录。"]
    }

    private static func extractInventory(
        player: XMLNode,
        catalogByID: [String: CatalogItem],
        warnings: inout [String]
    ) -> [InventorySlotDraft] {
        guard let items = player.child(named: "items") else {
            warnings.append("存档没有背包字段。")
            return []
        }

        var readOnlyCount = 0
        let slots = items.children(named: "Item").enumerated().map { index, node in
            let isNil = node.attributes["xsi:nil"] == "true" || node.attributes["nil"] == "true"
            guard !isNil else { return InventorySlotDraft(id: index, item: nil) }

            let objectType = node.attributes["xsi:type"] ?? node.attributes["type"] ?? "Unknown"
            let itemID = node.value(named: "itemId") ?? node.value(named: "parentSheetIndex") ?? "?"
            let name = node.value(named: "name") ?? "未知物品"
            let stack = node.int(named: "stack") ?? 1
            let quality = node.int(named: "quality") ?? 0
            let known = catalogByID[itemID]
            let special = node.value(named: "specialItem") == "true"
            let editable = ["Object", "ColoredObject", "Cask"].contains(objectType)
                && !special
                && node.child(named: "stack") != nil
                && node.child(named: "quality") != nil
                && !name.hasPrefix("Secret Note")

            if !editable { readOnlyCount += 1 }
            let allowedQualities = known?.allowedQualities
                ?? ([0, 1, 2, 4].contains(quality) ? Array(Set([0, quality])).sorted() : [quality])

            return InventorySlotDraft(
                id: index,
                item: InventoryItemDraft(
                    id: UUID(),
                    itemID: itemID,
                    name: name,
                    chineseName: known?.chineseName ?? ItemCatalog.chineseNames[name],
                    objectType: objectType,
                    stack: stack,
                    quality: quality,
                    spriteIndex: known?.spriteIndex,
                    texture: known?.texture,
                    allowedQualities: allowedQualities,
                    isEditable: editable,
                    templateXML: node.xmlString()
                )
            )
        }

        if readOnlyCount > 0 {
            warnings.append("背包中有 \(readOnlyCount) 个工具、装备或特殊物品；为防止专属字段损坏，它们保持只读。")
        }
        return slots
    }

    private static func extractFriendships(player: XMLNode) -> [FriendshipDraft] {
        guard let container = player.child(named: "friendshipData") else { return [] }
        return container.children(named: "item").compactMap { item in
            guard let name = item.child(named: "key")?.value(named: "string"),
                  let friendship = item.child(named: "value")?.child(named: "Friendship") else {
                return nil
            }
            let pointsValue = editableScalar(friendship.child(named: "Points")).flatMap(Int.init)
            let statusValue = editableScalar(friendship.child(named: "Status")).flatMap(RelationshipStatus.init(rawValue:))
            let points = pointsValue ?? 0
            let status = statusValue ?? .unknown
            return FriendshipDraft(
                name: name,
                points: points,
                status: status,
                originalPoints: points,
                originalStatus: status,
                giftsToday: editableScalar(friendship.child(named: "GiftsToday")).flatMap(Int.init).flatMap { $0 >= 0 ? $0 : nil },
                giftsThisWeek: editableScalar(friendship.child(named: "GiftsThisWeek")).flatMap(Int.init).flatMap { $0 >= 0 ? $0 : nil },
                hasEditablePoints: pointsValue != nil,
                hasEditableStatus: statusValue != nil
            )
        }.sorted {
            if $0.points != $1.points { return $0.points > $1.points }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    /// Nullable or structured values are not editable scalar fields. Keep their
    /// original XML instead of silently interpreting a missing value as zero.
    private static func editableScalar(_ node: XMLNode?) -> String? {
        guard let node, node.children.isEmpty else { return nil }
        let nilValue = node.attributes["xsi:nil"] ?? node.attributes["nil"] ?? "false"
        guard !["true", "1"].contains(nilValue.lowercased()) else { return nil }
        return node.text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func extractRecipes(
        player: XMLNode,
        recipeCatalog: [RecipeKind: [String]]
    ) -> [RecipeDraft] {
        RecipeKind.allCases.flatMap { kind -> [RecipeDraft] in
            let container = player.child(named: kind.containerName)
            var existing: [String: Int] = [:]
            for item in container?.children(named: "item") ?? [] {
                guard let key = item.child(named: "key")?.value(named: "string") else { continue }
                existing[key] = item.child(named: "value")?.int(named: "int") ?? 0
            }

            var keys = recipeCatalog[kind] ?? []
            for key in existing.keys where !keys.contains(key) { keys.append(key) }
            return keys.map { key in
                let times = existing[key]
                return RecipeDraft(
                    key: key,
                    kind: kind,
                    unlocked: times != nil,
                    timesMade: times ?? 0,
                    originallyUnlocked: times != nil,
                    originalTimesMade: times ?? 0
                )
            }
        }
    }

    private static func extractProgress(root: XMLNode, player: XMLNode) -> ProgressDraft {
        let professionIDs = Set(
            (player.child(named: "professions")?.children(named: "int") ?? [])
                .compactMap { Int($0.text) }
        )
        let mailFlags = Set(
            (player.child(named: "mailReceived")?.children(named: "string") ?? [])
                .map(\.text)
        )
        let walletUnlocks = WalletUnlockKey.allCases.map { key in
            let legacy = player.child(named: key.legacyFieldName)
            let legacyUnlocked = legacy.map { node in
                node.attributes["xsi:nil"] != "true" && node.attributes["nil"] != "true"
                    && ["true", "1"].contains(node.text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
            } ?? false
            return WalletUnlockDraft(
                key: key,
                isUnlocked: mailFlags.contains(key.rawValue) || legacyUnlocked
            )
        }
        let farm = location(in: root, named: "Farm", typeContaining: "farm")
        let stats = player.child(named: "stats")

        let insights = SaveInsights(
            weatherForTomorrow: root.value(named: "weatherForTomorrow"),
            dailyLuck: root.value(named: "dailyLuck").flatMap(Double.init),
            activeQuestCount: player.child(named: "questLog")?.children.filter {
                $0.attributes["xsi:nil"] != "true" && $0.attributes["nil"] != "true"
            }.count ?? 0,
            achievementCount: player.child(named: "achievements")?.children(named: "int").count ?? 0,
            shippedItemKinds: dictionaryEntryCount(player.child(named: "basicShipped")),
            caughtFishKinds: dictionaryEntryCount(player.child(named: "fishCaught")),
            mineralKinds: dictionaryEntryCount(player.child(named: "mineralsFound")),
            artifactKinds: dictionaryEntryCount(player.child(named: "archaeologyFound")),
            secretNoteCount: player.child(named: "secretNotesSeen")?.children(named: "int").count ?? 0,
            eventCount: player.child(named: "eventsSeen")?.children(named: "int").count ?? 0,
            mailFlagCount: mailFlags.count,
            daysPlayed: statsValue(named: "daysPlayed", in: stats),
            questsCompleted: statsValue(named: "questsCompleted", in: stats),
            monstersKilled: statsValue(named: "monstersKilled", in: stats),
            itemsShipped: statsValue(named: "itemsShipped", in: stats),
            fishCaught: statsValue(named: "fishCaught", in: stats)
        )

        return ProgressDraft(
            qiGems: player.child(named: "qiGems") == nil ? nil : player.int(named: "qiGems") ?? 0,
            clubCoins: player.child(named: "clubCoins") == nil ? nil : player.int(named: "clubCoins") ?? 0,
            totalMoneyEarned: player.child(named: "totalMoneyEarned") == nil
                ? nil : player.int(named: "totalMoneyEarned") ?? 0,
            goldenWalnuts: root.child(named: "goldenWalnuts") == nil
                ? nil : root.int(named: "goldenWalnuts") ?? 0,
            piecesOfHay: farm?.child(named: "piecesOfHay") == nil
                ? nil : farm?.int(named: "piecesOfHay") ?? 0,
            deepestMineLevel: player.child(named: "deepestMineLevel") == nil
                ? nil : player.int(named: "deepestMineLevel") ?? 0,
            mineLowestLevelReached: root.child(named: "mine_lowestLevelReached") == nil
                ? nil : root.int(named: "mine_lowestLevelReached") ?? 0,
            professionIDs: professionIDs,
            walletUnlocks: walletUnlocks,
            insights: insights
        )
    }

    private static func extractAnimals(root: XMLNode) -> [FarmAnimalDraft] {
        var animalsByID: [String: FarmAnimalDraft] = [:]
        var order: [String] = []

        for item in descendants(of: root) where item.name == "item" {
            guard let animal = item.child(named: "value")?.child(named: "FarmAnimal") else { continue }
            let rawID = item.child(named: "key")?.firstDescendant(named: "long")?.text
                ?? animal.value(named: "myID")
            let type = animal.value(named: "type") ?? ""
            let name = animal.value(named: "name") ?? animal.value(named: "displayName") ?? type
            let id = rawID?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                ? rawID!
                : "\(type)|\(name)|\(order.count)"
            guard animalsByID[id] == nil else { continue }

            animalsByID[id] = FarmAnimalDraft(
                id: id,
                type: type,
                home: animal.value(named: "buildingTypeILiveIn") ?? "农场",
                name: name,
                friendship: animal.int(named: "friendshipTowardFarmer") ?? 0,
                happiness: animal.int(named: "happiness") ?? 0,
                fullness: animal.int(named: "fullness") ?? 0,
                daysOwned: animal.int(named: "daysOwned") ?? animal.int(named: "age") ?? 0
            )
            order.append(id)
        }

        return order.compactMap { animalsByID[$0] }.sorted {
            if $0.home != $1.home {
                return $0.home.localizedCaseInsensitiveCompare($1.home) == .orderedAscending
            }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    private static func dictionaryEntryCount(_ container: XMLNode?) -> Int {
        guard let container else { return 0 }
        return descendants(of: container).filter {
            $0.name == "item" && $0.child(named: "key") != nil && $0.child(named: "value") != nil
        }.count
    }

    private static func statsValue(named name: String, in stats: XMLNode?) -> Int? {
        guard let stats else { return nil }
        if let direct = stats.value(named: name).flatMap(Int.init) { return direct }
        guard let values = stats.child(named: "Values") else { return nil }
        for item in values.children(named: "item") {
            guard dictionaryText(in: item.child(named: "key") ?? item) == name,
                  let value = item.child(named: "value"),
                  let text = dictionaryText(in: value) else { continue }
            return Int(text)
        }
        return nil
    }

    private static func extractFarmhouse(root: XMLNode, player: XMLNode) -> FarmhouseDraft {
        let upgradeLevel = player.int(named: "houseUpgradeLevel")
        guard let farmhouse = farmhouseLocation(in: root) else {
            return FarmhouseDraft(upgradeLevel: upgradeLevel, decorations: [])
        }

        let fields: [(RoomDecorationKind, [String])] = [
            (.wallpaper, ["appliedWallpaper", "wallPaper", "wallpaper", "wallpapers"]),
            (.flooring, ["appliedFloor", "floor", "flooring", "floors"])
        ]
        var decorations: [RoomDecorationDraft] = []

        for (kind, candidateNames) in fields {
            guard let fieldName = candidateNames.first(where: { farmhouse.child(named: $0) != nil }),
                  let container = farmhouse.child(named: fieldName) else { continue }

            let trimmed = container.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if let value = Int(trimmed) {
                decorations.append(RoomDecorationDraft(
                    id: "\(kind.rawValue).scalar.\(fieldName)",
                    kind: kind,
                    roomKey: "主房间",
                    storage: .scalar(fieldName: fieldName),
                    styleIndex: value
                ))
                continue
            }

            for item in dictionaryItems(in: container) {
                guard let keyNode = item.child(named: "key"),
                      let valueNode = item.child(named: "value"),
                      let key = dictionaryText(in: keyNode),
                      let valueText = dictionaryText(in: valueNode),
                      let value = Int(valueText) else { continue }
                decorations.append(RoomDecorationDraft(
                    id: "\(kind.rawValue).dictionary.\(fieldName).\(key)",
                    kind: kind,
                    roomKey: key,
                    storage: .dictionary(containerName: fieldName, key: key),
                    styleIndex: value
                ))
            }
        }

        return FarmhouseDraft(
            upgradeLevel: upgradeLevel,
            decorations: decorations.sorted {
                if $0.kind.rawValue != $1.kind.rawValue {
                    return $0.kind.rawValue < $1.kind.rawValue
                }
                return $0.roomKey.localizedCaseInsensitiveCompare($1.roomKey) == .orderedAscending
            }
        )
    }

    private static func farmhouseLocation(in root: XMLNode) -> XMLNode? {
        guard let locations = root.child(named: "locations") else { return nil }
        let topLevelLocations = locations.children(named: "GameLocation")
        return (topLevelLocations + descendants(of: locations)).first { node in
            if node.value(named: "name")?.lowercased() == "farmhouse" { return true }
            let type = node.attributes["xsi:type"] ?? node.attributes["type"] ?? node.name
            return type.lowercased().contains("farmhouse")
        }
    }

    private static func descendants(of node: XMLNode) -> [XMLNode] {
        node.children.flatMap { child in [child] + descendants(of: child) }
    }

    private static func dictionaryItems(in container: XMLNode) -> [XMLNode] {
        descendants(of: container).filter {
            $0.name == "item" && $0.child(named: "key") != nil && $0.child(named: "value") != nil
        }
    }

    private static func location(
        in root: XMLNode,
        named locationName: String,
        typeContaining typeFragment: String
    ) -> XMLNode? {
        guard let locations = root.child(named: "locations") else { return nil }
        let nodes = locations.children(named: "GameLocation") + descendants(of: locations)
        let wantedName = locationName.lowercased()
        if let named = nodes.first(where: { $0.value(named: "name")?.lowercased() == wantedName }) {
            return named
        }
        let wantedType = typeFragment.lowercased()
        return nodes.first { node in
            let raw = node.attributes["xsi:type"] ?? node.attributes["type"] ?? node.name
            return raw.lowercased().contains(wantedType)
        }
    }

    private static func dictionaryText(in node: XMLNode) -> String? {
        let candidates = ["string", "int", "unsignedInt", "long"]
        for name in candidates {
            if let value = node.firstDescendant(named: name)?.text,
               !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return value
            }
        }
        let trimmed = node.text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
