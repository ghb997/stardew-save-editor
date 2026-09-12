import Foundation

enum SaveDiffBuilder {
    static func build(original: SaveDraft, draft: SaveDraft) -> [SaveDiff] {
        var result: [SaveDiff] = []

        func add(
            _ id: String,
            section: String,
            label: String,
            old: String,
            new: String,
            syncInfo: Bool = true
        ) {
            guard old != new else { return }
            result.append(SaveDiff(
                id: id,
                section: section,
                label: label,
                oldValue: old,
                newValue: new,
                affectsSaveGameInfo: syncInfo
            ))
        }

        add("player.name", section: "角色", label: "玩家名称", old: original.playerName, new: draft.playerName)
        add("player.farm", section: "角色", label: "农场名称", old: original.farmName, new: draft.farmName)
        add("player.favorite", section: "角色", label: "最喜欢的东西", old: original.favoriteThing, new: draft.favoriteThing)
        add("player.money", section: "角色", label: "金钱", old: String(original.money), new: String(draft.money))
        add("player.health", section: "角色", label: "最大生命", old: String(original.maxHealth), new: String(draft.maxHealth))
        add("player.stamina", section: "角色", label: "最大体力", old: String(original.maxStamina), new: String(draft.maxStamina))
        add("appearance.gender", section: "外观", label: "性别", old: original.gender.displayName, new: draft.gender.displayName)
        add("appearance.hair", section: "外观", label: "发型", old: String(original.hair), new: String(draft.hair))
        add("appearance.skin", section: "外观", label: "肤色", old: String(original.skin), new: String(draft.skin))
        add("appearance.accessory", section: "外观", label: "饰品", old: String(original.accessory), new: String(draft.accessory))
        for field in FarmerColorField.allCases {
            if let old = original.appearanceColors[field], let value = draft.appearanceColors[field] {
                add("appearance.color.\(field.rawValue)", section: "外观", label: field.title, old: old.hex, new: value.hex)
            }
        }
        add(
            "farmhouse.upgrade",
            section: "房屋",
            label: "农舍等级",
            old: farmhouseLevelName(original.farmhouse.upgradeLevel),
            new: farmhouseLevelName(draft.farmhouse.upgradeLevel)
        )
        add("date.year", section: "日期", label: "年份", old: String(original.year), new: String(draft.year))
        add("date.season", section: "日期", label: "季节", old: original.season.displayName, new: draft.season.displayName)
        add("date.day", section: "日期", label: "日期", old: String(original.day), new: String(draft.day))

        let progressScalars: [(String, String, Int?, Int?)] = [
            ("progress.qiGems", "齐钻", original.progress.qiGems, draft.progress.qiGems),
            ("progress.clubCoins", "齐币", original.progress.clubCoins, draft.progress.clubCoins),
            ("progress.totalMoney", "累计收入", original.progress.totalMoneyEarned, draft.progress.totalMoneyEarned),
            ("progress.walnuts", "金色核桃", original.progress.goldenWalnuts, draft.progress.goldenWalnuts),
            ("progress.hay", "干草", original.progress.piecesOfHay, draft.progress.piecesOfHay),
            ("progress.deepestMine", "个人矿洞最深层", original.progress.deepestMineLevel, draft.progress.deepestMineLevel),
            ("progress.worldMine", "世界矿井进度", original.progress.mineLowestLevelReached, draft.progress.mineLowestLevelReached)
        ]
        for (id, label, old, new) in progressScalars where old != new {
            add(
                id,
                section: label.contains("矿") ? "矿洞" : "财富",
                label: label,
                old: old.map(String.init) ?? "存档未提供",
                new: new.map(String.init) ?? "存档未提供",
                syncInfo: ["progress.qiGems", "progress.clubCoins", "progress.totalMoney", "progress.deepestMine"].contains(id)
            )
        }

        for skill in SkillKey.allCases {
            guard let old = original.skills.first(where: { $0.key == skill }),
                  let new = draft.skills.first(where: { $0.key == skill }) else { continue }
            add(
                "skill.\(skill.rawValue)",
                section: "技能",
                label: skill.displayName,
                old: "Lv.\(old.level) · \(old.originalExperience) XP",
                new: "Lv.\(new.level) · \(new.targetExperience) XP"
            )
        }

        if original.progress.professionIDs != draft.progress.professionIDs {
            add(
                "skills.professions",
                section: "技能",
                label: "职业选择",
                old: professionDescription(original.progress.professionIDs),
                new: professionDescription(draft.progress.professionIDs),
                syncInfo: true
            )
        }

        let originalWallet = Dictionary(
            original.progress.walletUnlocks.map { ($0.key, $0.isUnlocked) },
            uniquingKeysWith: { first, _ in first }
        )
        for unlock in draft.progress.walletUnlocks {
            let old = originalWallet[unlock.key] ?? false
            add(
                "wallet.\(unlock.key.rawValue)",
                section: "特殊能力",
                label: unlock.key.displayName,
                old: old ? "已获得" : "未获得",
                new: unlock.isUnlocked ? "已获得" : "未获得",
                syncInfo: true
            )
        }

        let oldDecorations = Dictionary(
            original.farmhouse.decorations.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        for decoration in draft.farmhouse.decorations {
            guard let old = oldDecorations[decoration.id] else { continue }
            add(
                "farmhouse.decoration.\(decoration.id)",
                section: "房屋",
                label: "\(localizedRoomName(decoration.roomKey))·\(decoration.kind.displayName)",
                old: String(old.styleIndex),
                new: String(decoration.styleIndex),
                syncInfo: false
            )
        }

        addFarmAction(
            id: "farm.water",
            label: "一键浇水",
            old: original.farmActions.waterAllCrops,
            new: draft.farmActions.waterAllCrops,
            into: &result
        )
        addFarmAction(
            id: "farm.stones",
            label: "清除散落石块",
            old: original.farmActions.clearStones,
            new: draft.farmActions.clearStones,
            into: &result
        )
        addFarmAction(
            id: "farm.weeds",
            label: "清除杂草",
            old: original.farmActions.clearWeeds,
            new: draft.farmActions.clearWeeds,
            into: &result
        )
        addFarmAction(
            id: "farm.twigs",
            label: "清除树枝",
            old: original.farmActions.clearTwigs,
            new: draft.farmActions.clearTwigs,
            into: &result
        )
        let debrisKeys = original.farmActions.debrisRemovalKeys.union(draft.farmActions.debrisRemovalKeys)
        for key in original.farmActions.cropWateringKeys.union(draft.farmActions.cropWateringKeys).sorted() {
            let parts = key.split(separator: ":")
            let coordinate = parts.count == 3 ? "X \(parts[1]) · Y \(parts[2])" : key
            add("farm.crop.\(key)", section: "农场", label: "作物浇水 · \(coordinate)",
                old: original.farmActions.cropWateringKeys.contains(key) ? "保存时浇水" : "保持原样",
                new: draft.farmActions.cropWateringKeys.contains(key) ? "保存时浇水" : "保持原样", syncInfo: false)
        }
        for key in debrisKeys.sorted() {
            let old = original.farmActions.debrisRemovalKeys.contains(key)
            let new = draft.farmActions.debrisRemovalKeys.contains(key)
            add(
                "farm.debris.\(key)", section: "农场", label: debrisDescription(key),
                old: old ? "保存时清理" : "保留", new: new ? "保存时清理" : "保留", syncInfo: false
            )
        }

        add("inventory.capacity", section: "背包", label: "背包容量（撤销时同时恢复新解锁槽位）",
            old: original.backpackCapacity.map { "\($0) 格" } ?? "未提供",
            new: draft.backpackCapacity.map { "\($0) 格" } ?? "未提供")
        let slotCount = max(original.inventory.count, draft.inventory.count)
        for index in 0..<slotCount {
            let old = original.inventory.indices.contains(index) ? original.inventory[index].item : nil
            let new = draft.inventory.indices.contains(index) ? draft.inventory[index].item : nil
            let oldDescription = itemDescription(old)
            let newDescription = itemDescription(new)
            if old != new {
                result.append(SaveDiff(
                    id: "inventory.\(index)",
                    section: "背包",
                    label: "槽位 \(index + 1)",
                    oldValue: oldDescription,
                    newValue: newDescription,
                    affectsSaveGameInfo: false
                ))
            }
        }

        let oldFriends = Dictionary(original.friendships.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })
        for friend in draft.friendships {
            guard let old = oldFriends[friend.name] else { continue }
            add(
                "friendship.\(friend.name).points",
                section: "关系",
                label: "\(friend.localizedName) 好感",
                old: String(old.points),
                new: String(friend.points),
                syncInfo: false
            )
            add(
                "friendship.\(friend.name).status",
                section: "关系",
                label: "\(friend.localizedName) 状态",
                old: old.status.displayName,
                new: friend.status.displayName,
                syncInfo: false
            )
            for (key, label, previous, value) in [
                ("giftsToday", "今日送礼", old.giftsToday, friend.giftsToday),
                ("giftsThisWeek", "本周送礼", old.giftsThisWeek, friend.giftsThisWeek)
            ] {
                add("friendship.\(friend.name).\(key)", section: "关系",
                    label: "\(friend.localizedName) \(label)",
                    old: previous.map { "\($0) 次" } ?? "未提供",
                    new: value.map { "\($0) 次" } ?? "未提供", syncInfo: false)
            }
        }

        let oldAnimals = Dictionary(original.animals.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for animal in draft.animals {
            guard let old = oldAnimals[animal.id] else { continue }
            add(
                "animal.\(animal.id).name",
                section: "动物",
                label: "\(old.name) 名称",
                old: old.name,
                new: animal.name,
                syncInfo: false
            )
            add(
                "animal.\(animal.id).friendship",
                section: "动物",
                label: "\(animal.name) 亲密度",
                old: String(old.friendship),
                new: String(animal.friendship),
                syncInfo: false
            )
            add(
                "animal.\(animal.id).happiness",
                section: "动物",
                label: "\(animal.name) 心情",
                old: String(old.happiness),
                new: String(animal.happiness),
                syncInfo: false
            )
            add(
                "animal.\(animal.id).fullness",
                section: "动物",
                label: "\(animal.name) 饱食度",
                old: String(old.fullness),
                new: String(animal.fullness),
                syncInfo: false
            )
            add(
                "animal.\(animal.id).daysOwned",
                section: "动物",
                label: "\(animal.name) 饲养天数",
                old: String(old.daysOwned),
                new: String(animal.daysOwned),
                syncInfo: false
            )
        }

        let oldRecipes = Dictionary(original.recipes.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for recipe in draft.recipes {
            guard let old = oldRecipes[recipe.id] else { continue }
            add(
                "recipe.\(recipe.id)",
                section: "配方",
                label: recipe.key,
                old: old.unlocked ? "已解锁 · 制作 \(old.timesMade) 次" : "未解锁",
                new: recipe.unlocked ? "已解锁 · 制作 \(recipe.timesMade) 次" : "未解锁",
                syncInfo: false
            )
        }

        result.append(contentsOf: EquipmentEditorRules.diffs(draft.equipment, original: original.equipment))
        result.append(contentsOf: ExpandedEditorChanges.diffs(original: original, draft: draft))
        return result
    }

    /// Every diff is included, including future sections not listed here.
    static func grouped(_ diffs: [SaveDiff]) -> [SaveDiffGroup] {
        let preferred = ["角色", "外观", "房屋", "日期", "财富", "矿洞", "技能", "特殊能力", "背包", "关系", "动物", "配方", "农场"]
        let bySection = Dictionary(grouping: diffs, by: \.section)
        let order = preferred.filter { bySection[$0] != nil }
            + bySection.keys.filter { !preferred.contains($0) }.sorted()
        return order.map { SaveDiffGroup(section: $0, diffs: bySection[$0] ?? []) }
    }

    /// Undo one displayed change using the immutable baseline. Coupled skill
    /// level/XP/profession values are restored together to remain consistent.
    static func undo(_ diff: SaveDiff, original: SaveDraft, draft: inout SaveDraft) {
        if diff.id.hasPrefix("equipment:") {
            for i in draft.equipment.indices where original.equipment.indices.contains(i) {
                for j in draft.equipment[i].fields.indices where original.equipment[i].fields.indices.contains(j) {
                    if diff.id == "equipment:\(draft.equipment[i].id):\(draft.equipment[i].fields[j].id)" {
                        draft.equipment[i].fields[j] = original.equipment[i].fields[j]
                    }
                }
            }
            return
        }
        if diff.id.hasPrefix("storage:") || diff.id.hasPrefix("machine:") || diff.id.hasPrefix("weather:") {
            ExpandedEditorChanges.undo(diff.id, original: original, draft: &draft)
            return
        }
        switch diff.id {
        case "player.name": draft.playerName = original.playerName
        case "player.farm": draft.farmName = original.farmName
        case "player.favorite": draft.favoriteThing = original.favoriteThing
        case "player.money": draft.money = original.money
        case "player.health": draft.maxHealth = original.maxHealth
        case "player.stamina": draft.maxStamina = original.maxStamina
        case "appearance.gender": draft.gender = original.gender
        case "appearance.hair": draft.hair = original.hair
        case "appearance.skin": draft.skin = original.skin
        case "appearance.accessory": draft.accessory = original.accessory
        case let id where id.hasPrefix("appearance.color."):
            if let field = FarmerColorField(rawValue: String(id.dropFirst("appearance.color.".count))) {
                draft.appearanceColors[field] = original.appearanceColors[field]
            }
        case let id where id.hasPrefix("farm.crop."):
            let key = String(id.dropFirst("farm.crop.".count))
            if original.farmActions.cropWateringKeys.contains(key) { draft.farmActions.cropWateringKeys.insert(key) }
            else { draft.farmActions.cropWateringKeys.remove(key) }
        case "inventory.capacity": draft.restoreBackpackCapacity(from: original)
        case "farmhouse.upgrade": draft.farmhouse.upgradeLevel = original.farmhouse.upgradeLevel
        case "date.year": draft.year = original.year
        case "date.season": draft.season = original.season
        case "date.day": draft.day = original.day
        case "progress.qiGems": draft.progress.qiGems = original.progress.qiGems
        case "progress.clubCoins": draft.progress.clubCoins = original.progress.clubCoins
        case "progress.totalMoney": draft.progress.totalMoneyEarned = original.progress.totalMoneyEarned
        case "progress.walnuts": draft.progress.goldenWalnuts = original.progress.goldenWalnuts
        case "progress.hay": draft.progress.piecesOfHay = original.progress.piecesOfHay
        case "progress.deepestMine": draft.progress.deepestMineLevel = original.progress.deepestMineLevel
        case "progress.worldMine": draft.progress.mineLowestLevelReached = original.progress.mineLowestLevelReached
        case "skills.professions":
            draft.progress.professionIDs = original.progress.professionIDs
            // Reapply current level constraints if the level edit is still pending.
            for skill in draft.skills {
                let unavailable = ProfessionCatalog.options(for: skill.key).filter { $0.tier > skill.level }
                draft.progress.professionIDs.subtract(unavailable.map(\.id))
            }
        case "farm.water": draft.farmActions.waterAllCrops = original.farmActions.waterAllCrops
        case "farm.stones": draft.farmActions.clearStones = original.farmActions.clearStones
        case "farm.weeds": draft.farmActions.clearWeeds = original.farmActions.clearWeeds
        case "farm.twigs": draft.farmActions.clearTwigs = original.farmActions.clearTwigs
        default:
            if diff.id.hasPrefix("farm.debris.") {
                let key = String(diff.id.dropFirst("farm.debris.".count))
                if original.farmActions.debrisRemovalKeys.contains(key) {
                    draft.farmActions.debrisRemovalKeys.insert(key)
                } else { draft.farmActions.debrisRemovalKeys.remove(key) }
            }
            for index in draft.skills.indices {
                let key = draft.skills[index].key
                guard diff.id == "skill.\(key.rawValue)",
                      let old = original.skills.first(where: { $0.key == key }) else { continue }
                draft.skills[index] = old
                let ids = Set(ProfessionCatalog.options(for: key).map(\.id))
                draft.progress.professionIDs.subtract(ids)
                draft.progress.professionIDs.formUnion(original.progress.professionIDs.intersection(ids))
            }
            for index in draft.progress.walletUnlocks.indices {
                let key = draft.progress.walletUnlocks[index].key
                if diff.id == "wallet.\(key.rawValue)",
                   let old = original.progress.walletUnlocks.first(where: { $0.key == key }) {
                    draft.progress.walletUnlocks[index] = old
                }
            }
            for index in draft.farmhouse.decorations.indices {
                let id = draft.farmhouse.decorations[index].id
                if diff.id == "farmhouse.decoration.\(id)",
                   let old = original.farmhouse.decorations.first(where: { $0.id == id }) {
                    draft.farmhouse.decorations[index] = old
                }
            }
            for index in draft.inventory.indices where diff.id == "inventory.\(index)" {
                draft.inventory[index].item = original.inventory.indices.contains(index)
                    ? original.inventory[index].item : nil
            }
            for index in draft.friendships.indices {
                let name = draft.friendships[index].name
                guard let old = original.friendships.first(where: { $0.name == name }) else { continue }
                if diff.id == "friendship.\(name).points" { draft.friendships[index].points = old.points }
                if diff.id == "friendship.\(name).status" { draft.friendships[index].status = old.status }
                if diff.id == "friendship.\(name).giftsToday" { draft.friendships[index].giftsToday = old.giftsToday }
                if diff.id == "friendship.\(name).giftsThisWeek" { draft.friendships[index].giftsThisWeek = old.giftsThisWeek }
            }
            for index in draft.animals.indices {
                let id = draft.animals[index].id
                guard let old = original.animals.first(where: { $0.id == id }) else { continue }
                switch diff.id {
                case "animal.\(id).name": draft.animals[index].name = old.name
                case "animal.\(id).friendship": draft.animals[index].friendship = old.friendship
                case "animal.\(id).happiness": draft.animals[index].happiness = old.happiness
                case "animal.\(id).fullness": draft.animals[index].fullness = old.fullness
                case "animal.\(id).daysOwned": draft.animals[index].daysOwned = old.daysOwned
                default: break
                }
            }
            for index in draft.recipes.indices {
                let id = draft.recipes[index].id
                if diff.id == "recipe.\(id)", let old = original.recipes.first(where: { $0.id == id }) {
                    draft.recipes[index] = old
                }
            }
        }
    }

    private static func debrisDescription(_ key: String) -> String {
        let parts = key.split(separator: ":").map(String.init)
        guard parts.count == 4 else { return "单项清理 · \(key)" }
        let kind = ["stone": "石块", "weed": "杂草", "twig": "树枝"][parts[1]] ?? "杂物"
        return "清理\(kind) · (\(parts[2]), \(parts[3]))"
    }

    private static func itemDescription(_ item: InventoryItemDraft?) -> String {
        guard let item else { return "空" }
        let quality: String = switch item.quality {
        case 1: "银"
        case 2: "金"
        case 4: "铱"
        default: "普通"
        }
        return "\(item.displayName) ×\(item.stack)（\(quality)）"
    }

    private static func professionDescription(_ ids: Set<Int>) -> String {
        let known = ids.intersection(ProfessionCatalog.knownIDs).sorted()
        guard !known.isEmpty else { return "未选择" }
        return known.map(ProfessionCatalog.name(for:)).joined(separator: "、")
    }

    private static func addFarmAction(
        id: String,
        label: String,
        old: Bool,
        new: Bool,
        into result: inout [SaveDiff]
    ) {
        guard old != new else { return }
        result.append(SaveDiff(
            id: id,
            section: "农场",
            label: label,
            oldValue: old ? "已加入草稿" : "保持原样",
            newValue: new ? "保存时执行" : "保持原样",
            affectsSaveGameInfo: false
        ))
    }

    private static func farmhouseLevelName(_ level: Int?) -> String {
        switch level {
        case 0: "0 级·基础农舍"
        case 1: "1 级·厨房"
        case 2: "2 级·额外房间"
        case 3: "3 级·地窖"
        case let value?: "\(value) 级"
        case nil: "存档未提供"
        }
    }

    private static func localizedRoomName(_ key: String) -> String {
        switch key.lowercased() {
        case "farmhouse", "main", "0": "主房间"
        case "bedroom", "1": "卧室"
        case "kitchen", "2": "厨房"
        case "nursery", "3": "婴儿房"
        case "southernroom", "southroom", "4": "南侧房间"
        case "upperleft": "左上房间"
        case "upperright": "右上房间"
        case "bottomright", "bottomright_left", "bottomright_right": "右下房间"
        case "bottomleft": "左下房间"
        case "entry", "hallway": "入口与走廊"
        default: key
        }
    }
}
