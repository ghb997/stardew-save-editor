import Foundation

enum SaveValidationError: LocalizedError {
    case invalid(String)

    var errorDescription: String? {
        switch self {
        case let .invalid(message): message
        }
    }
}

struct RenderedSavePair: Sendable {
    let mainData: Data
    let infoData: Data?
}

enum SaveMutator {
    static func render(parsed: ParsedSaveDocument, draft: SaveDraft) throws -> RenderedSavePair {
        try validate(draft, comparedTo: parsed.draft)
        if !draft.farmActions.cropWateringKeys.isEmpty || !draft.farmActions.debrisRemovalKeys.isEmpty {
            let snapshot = FarmSnapshotExtractor.extract(from: parsed.mainRoot, cropCatalog: [])
            guard draft.farmActions.cropWateringKeys.isSubset(of: Set(snapshot.entities.compactMap(\.wateringKey))),
                  draft.farmActions.debrisRemovalKeys.isSubset(of: Set(snapshot.entities.compactMap(\.actionKey))) else {
                throw SaveValidationError.invalid("地图操作包含不存在或不可操作的坐标，请重新选择对象。")
            }
        }

        let main = parsed.mainRoot.deepCopy()
        guard let player = main.child(named: "player") else {
            throw SaveParseError.missingField("SaveGame/player")
        }
        try EquipmentEditorRules.apply(draft.equipment, original: parsed.draft.equipment, to: main)
        applyPlayerScalars(draft, original: parsed.draft, to: player)
        applyDate(draft, original: parsed.draft, root: main, player: player)
        try ExpandedEditorChanges.apply(draft, original: parsed.draft, to: main)
        if draft.inventory != parsed.draft.inventory {
            try applyInventory(draft.inventory, original: parsed.draft.inventory, to: player)
        }
        if draft.friendships != parsed.draft.friendships {
            applyFriendships(draft.friendships, original: parsed.draft.friendships, to: player)
        }
        if draft.recipes != parsed.draft.recipes {
            RecipeWriteRules.apply(draft.recipes, original: parsed.draft.recipes, to: player)
        }
        if draft.progress.professionIDs != parsed.draft.progress.professionIDs {
            applyProfessions(draft.progress.professionIDs, to: player)
        }
        if draft.progress.walletUnlocks != parsed.draft.progress.walletUnlocks {
            applyWalletUnlocks(draft.progress.walletUnlocks, original: parsed.draft.progress.walletUnlocks, to: player)
        }
        applyWorldProgress(draft.progress, original: parsed.draft.progress, to: main)
        if draft.animals != parsed.draft.animals {
            applyAnimals(draft.animals, original: parsed.draft.animals, to: main)
        }
        if draft.farmhouse.decorations != parsed.draft.farmhouse.decorations {
            applyFarmhouseDecorations(draft.farmhouse.decorations, original: parsed.draft.farmhouse.decorations, to: main)
        }
        if draft.farmActions.hasChanges {
            applyFarmActions(draft.farmActions, to: main)
        }

        let mainXML = Data(main.xmlString(includeDeclaration: true).utf8)
        _ = try XMLTreeParser().parse(mainXML)
        let mainData = try SaveCodec.encode(
            xmlData: mainXML,
            encoding: parsed.mainPayload.encoding,
            includeBOM: parsed.mainPayload.hadUTF8BOM
        )

        var infoData: Data?
        if let originalInfo = parsed.infoRoot, let payload = parsed.infoPayload {
            let info = originalInfo.deepCopy()
            applyPlayerScalars(draft, original: parsed.draft, to: info)
            applyDate(draft, original: parsed.draft, root: nil, player: info)
            if draft.progress.professionIDs != parsed.draft.progress.professionIDs {
                applyProfessions(draft.progress.professionIDs, to: info)
            }
            if draft.progress.walletUnlocks != parsed.draft.progress.walletUnlocks {
                applyWalletUnlocks(draft.progress.walletUnlocks, original: parsed.draft.progress.walletUnlocks, to: info)
            }
            let infoXML = Data(info.xmlString(includeDeclaration: true).utf8)
            _ = try XMLTreeParser().parse(infoXML)
            infoData = try SaveCodec.encode(
                xmlData: infoXML,
                encoding: payload.encoding,
                includeBOM: payload.hadUTF8BOM
            )
        }

        return RenderedSavePair(mainData: mainData, infoData: infoData)
    }

    static func validate(_ draft: SaveDraft, comparedTo original: SaveDraft? = nil) throws {
        if let original {
            try ExpandedEditorChanges.validate(draft, original: original)
            try InventoryWriteRules.validate(draft.inventory, original: original.inventory)
            try RecipeWriteRules.validate(draft.recipes, original: original.recipes)
            try EquipmentEditorRules.validate(draft.equipment, original: original.equipment)
            guard draft.skills.map(\.key) == original.skills.map(\.key),
                  draft.friendships.map(\.name) == original.friendships.map(\.name),
                  draft.animals.map(\.id) == original.animals.map(\.id),
                  draft.progress.walletUnlocks.map(\.key) == original.progress.walletUnlocks.map(\.key),
                  draft.progress.insights == original.progress.insights else {
                throw SaveValidationError.invalid("人物、技能、动物或统计记录的范围已改变，请重新读取存档。")
            }
        }
        func shouldValidate<T: Equatable>(_ value: T, originalValue: T?) -> Bool {
            guard let originalValue else { return true }
            return value != originalValue
        }

        let trimmedName = draft.playerName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedFarm = draft.farmName.trimmingCharacters(in: .whitespacesAndNewlines)
        if shouldValidate(draft.playerName, originalValue: original?.playerName),
           (trimmedName.isEmpty || trimmedName.count > 64) {
            throw SaveValidationError.invalid("玩家名称不能为空且不能超过 64 个字符。")
        }
        if shouldValidate(draft.farmName, originalValue: original?.farmName),
           (trimmedFarm.isEmpty || trimmedFarm.count > 64) {
            throw SaveValidationError.invalid("农场名称不能为空且不能超过 64 个字符。")
        }
        if shouldValidate(draft.favoriteThing, originalValue: original?.favoriteThing),
           draft.favoriteThing.count > 64 {
            throw SaveValidationError.invalid("最喜欢的东西不能超过 64 个字符。")
        }
        if shouldValidate(draft.money, originalValue: original?.money),
           !(0...Int(Int32.max)).contains(draft.money) {
            throw SaveValidationError.invalid("金钱必须在 0 到 \(Int32.max) 之间。")
        }
        if shouldValidate(draft.maxHealth, originalValue: original?.maxHealth),
           !(1...999).contains(draft.maxHealth) {
            throw SaveValidationError.invalid("最大生命必须在 1 到 999 之间。")
        }
        if shouldValidate(draft.maxStamina, originalValue: original?.maxStamina),
           !(1...9_999).contains(draft.maxStamina) {
            throw SaveValidationError.invalid("最大体力必须在 1 到 9999 之间。")
        }
        if shouldValidate(draft.year, originalValue: original?.year),
           !(1...99).contains(draft.year) {
            throw SaveValidationError.invalid("年份必须在 1 到 99 之间。")
        }
        if shouldValidate(draft.day, originalValue: original?.day),
           !(1...28).contains(draft.day) {
            throw SaveValidationError.invalid("日期必须在 1 到 28 之间。")
        }
        if shouldValidate(draft.hair, originalValue: original?.hair),
           !(0...73).contains(draft.hair) {
            throw SaveValidationError.invalid("发型编号必须在 0 到 73 之间。")
        }
        if shouldValidate(draft.skin, originalValue: original?.skin),
           !(0...23).contains(draft.skin) {
            throw SaveValidationError.invalid("肤色编号必须在 0 到 23 之间。")
        }
        if shouldValidate(draft.accessory, originalValue: original?.accessory),
           !(-1...29).contains(draft.accessory) {
            throw SaveValidationError.invalid("饰品编号必须在 -1 到 29 之间。")
        }
        if let original {
            guard Set(draft.appearanceColors.keys) == Set(original.appearanceColors.keys) else {
                throw SaveValidationError.invalid("不能添加或删除存档中未提供的外观颜色字段。")
            }
            guard draft.farmhouse.decorations.count == original.farmhouse.decorations.count,
                  Set(draft.farmhouse.decorations.map(\.id)).count == draft.farmhouse.decorations.count,
                  draft.farmhouse.decorations.allSatisfy({ value in
                      original.farmhouse.decorations.contains {
                          $0.id == value.id && $0.roomKey == value.roomKey && $0.kind == value.kind && $0.storage == value.storage
                      }
                  }), (draft.farmhouse.upgradeLevel == nil) == (original.farmhouse.upgradeLevel == nil) else {
                throw SaveValidationError.invalid("房屋编辑只能修改存档已有的等级和房间表面。")
            }
        }
        for (field, color) in draft.appearanceColors {
            let originalAlpha = original?.appearanceColors[field]?.alpha ?? color.alpha
            guard color.isValid, originalAlpha == color.alpha else {
                throw SaveValidationError.invalid("\(field.title)的 RGB 必须为 0 到 255，透明度需保持原值。")
            }
        }
        if let upgradeLevel = draft.farmhouse.upgradeLevel,
           shouldValidate(upgradeLevel, originalValue: original?.farmhouse.upgradeLevel),
           !(0...3).contains(upgradeLevel) {
            throw SaveValidationError.invalid("农舍等级必须在 0 到 3 之间。")
        }
        for decoration in draft.farmhouse.decorations {
            let originalValue = original?.farmhouse.decorations
                .first(where: { $0.id == decoration.id })?.styleIndex
            if shouldValidate(decoration.styleIndex, originalValue: originalValue),
               !(0...9_999).contains(decoration.styleIndex) {
                throw SaveValidationError.invalid("房间装饰编号必须在 0 到 9999 之间。")
            }
        }

        for skill in draft.skills {
            let originalLevel = original?.skills.first(where: { $0.key == skill.key })?.level
            if shouldValidate(skill.level, originalValue: originalLevel),
               !(0...10).contains(skill.level) {
                throw SaveValidationError.invalid("\(skill.key.displayName)技能等级必须在 0 到 10 之间。")
            }
            let originalExperience = original?.skills.first(where: { $0.key == skill.key })?.originalExperience
            if shouldValidate(skill.targetExperience, originalValue: originalExperience),
               !(0...99_999).contains(skill.targetExperience) {
                throw SaveValidationError.invalid("\(skill.key.displayName)经验值必须在 0 到 99999 之间。")
            }
        }

        let progressValues: [(String, Int?, Int?)] = [
            ("齐钻", draft.progress.qiGems, original?.progress.qiGems),
            ("齐币", draft.progress.clubCoins, original?.progress.clubCoins),
            ("累计收入", draft.progress.totalMoneyEarned, original?.progress.totalMoneyEarned),
            ("金色核桃", draft.progress.goldenWalnuts, original?.progress.goldenWalnuts),
            ("干草", draft.progress.piecesOfHay, original?.progress.piecesOfHay)
        ]
        for (name, value, originalValue) in progressValues {
            if let value, shouldValidate(value, originalValue: originalValue),
               !(0...Int(Int32.max)).contains(value) {
                throw SaveValidationError.invalid("\(name)必须在 0 到 \(Int32.max) 之间。")
            }
        }
        for (name, value, originalValue) in [
            ("个人矿洞最深层", draft.progress.deepestMineLevel, original?.progress.deepestMineLevel),
            ("世界矿井进度", draft.progress.mineLowestLevelReached, original?.progress.mineLowestLevelReached)
        ] {
            if let value, shouldValidate(value, originalValue: originalValue), !(0...77_376).contains(value) {
                throw SaveValidationError.invalid("\(name)必须在 0 到 77376 之间。")
            }
        }
        if let original {
            let changedProfessionIDs = draft.progress.professionIDs
                .symmetricDifference(original.progress.professionIDs)
            if !changedProfessionIDs.isSubset(of: ProfessionCatalog.knownIDs) {
                throw SaveValidationError.invalid("职业草稿包含未知编号，无法安全写入。")
            }
        }

        // Validate the affected skill domain at the write boundary as well as
        // in UI bindings. Preserve pre-existing extended combinations on an
        // unrelated edit, but never introduce a level/XP/profession mismatch.
        for skill in draft.skills {
            let old = original?.skills.first(where: { $0.key == skill.key })
            let options = ProfessionCatalog.options(for: skill.key)
            let knownIDs = Set(options.map(\.id))
            let selected = draft.progress.professionIDs.intersection(knownIDs)
            let previous = original?.progress.professionIDs.intersection(knownIDs)
            let skillChanged = old?.level != skill.level || old?.originalExperience != skill.targetExperience
            guard skillChanged || previous != selected else { continue }
            if skillChanged, SkillKey.level(forExperience: skill.targetExperience) != skill.level {
                throw SaveValidationError.invalid("\(skill.key.displayName)的经验值与等级不一致。")
            }
            let chosen = options.filter { selected.contains($0.id) }
            guard chosen.filter({ $0.tier == 5 }).count <= 1,
                  chosen.filter({ $0.tier == 10 }).count <= 1,
                  chosen.allSatisfy({ $0.tier <= skill.level && ($0.parentID == nil || selected.contains($0.parentID!)) }) else {
                throw SaveValidationError.invalid("\(skill.key.displayName)职业必须符合技能等级及对应的 5/10 级分支。")
            }
        }
        for recipe in draft.recipes {
            let old = original?.recipes.first(where: { $0.id == recipe.id })
            if old?.timesMade != recipe.timesMade, !(0...Int(Int32.max)).contains(recipe.timesMade) {
                throw SaveValidationError.invalid("配方制作次数必须在 0 到 \(Int32.max) 之间。")
            }
        }

        for animal in draft.animals {
            let originalAnimal = original?.animals.first(where: { $0.id == animal.id })
            guard originalAnimal != animal else { continue }
            let trimmedAnimalName = animal.name.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedAnimalName.isEmpty || trimmedAnimalName.count > 64 {
                throw SaveValidationError.invalid("动物名称不能为空且不能超过 64 个字符。")
            }
            guard (0...1_000).contains(animal.friendship) else {
                throw SaveValidationError.invalid("\(animal.name) 的亲密度必须在 0 到 1000 之间。")
            }
            guard (0...255).contains(animal.happiness), (0...255).contains(animal.fullness) else {
                throw SaveValidationError.invalid("\(animal.name) 的心情和饱食度必须在 0 到 255 之间。")
            }
            guard (0...Int(Int32.max)).contains(animal.daysOwned) else {
                throw SaveValidationError.invalid("\(animal.name) 的饲养天数无效。")
            }
        }

        if let original {
            guard draft.inventorySlotFloor == original.inventorySlotFloor else {
                throw SaveValidationError.invalid("背包原始槽位记录已改变，请重新读取存档。")
            }
            let capacityChanged = draft.backpackCapacity != original.backpackCapacity
            if capacityChanged {
                guard original.canResizeBackpack, let capacity = draft.backpackCapacity,
                      BackpackRules.capacities.contains(capacity),
                      !draft.inventory.dropFirst(capacity).contains(where: { $0.item != nil }) else {
                    throw SaveValidationError.invalid("背包容量无效或容量外仍有物品。")
                }
            }
            if draft.inventory != original.inventory || capacityChanged {
                let expectedCount = capacityChanged
                    ? max(draft.backpackCapacity ?? 0, original.inventorySlotFloor)
                    : original.inventory.count
                guard draft.inventory.count == expectedCount,
                      draft.inventory.enumerated().allSatisfy({ $0.offset == $0.element.id }) else {
                    throw SaveValidationError.invalid("背包槽位数量或顺序不正确。")
                }
                for slot in draft.inventory where !draft.canUseInventorySlot(slot.id) {
                    let old = original.inventory.indices.contains(slot.id) ? original.inventory[slot.id].item : nil
                    guard slot.item == old else {
                        throw SaveValidationError.invalid("请先扩容，再修改未解锁的背包槽位。")
                    }
                }
            }
        }

        for slot in draft.inventory {
            if let original,
               original.inventory.first(where: { $0.id == slot.id })?.item == slot.item {
                continue
            }
            guard let item = slot.item else { continue }
            // Unknown tools, equipment, and modded items are deliberately read-only.
            // Their original stack/quality values may be outside vanilla ranges and
            // must not prevent an unrelated supported edit from being saved.
            if original != nil, !item.isEditable { continue }
            guard (1...999).contains(item.stack) else {
                throw SaveValidationError.invalid("背包第 \(slot.id + 1) 格数量必须在 1 到 999 之间。")
            }
            guard item.allowedQualities.contains(item.quality) else {
                throw SaveValidationError.invalid("背包第 \(slot.id + 1) 格不允许所选品质。")
            }
        }
        for friendship in draft.friendships {
            let old = original?.friendships.first(where: { $0.name == friendship.name })
            if shouldValidate(friendship.points, originalValue: old?.points) {
                let limit = FriendshipRules.maximumEditablePoints(for: friendship)
                guard old?.hasEditablePoints != false, (0...limit).contains(friendship.points) else {
                    throw SaveValidationError.invalid("\(friendship.localizedName) 的好感度必须在 0 到 \(limit) 之间，且存档须有有效好感字段。")
                }
            }
            if let old, friendship.status != old.status {
                guard old.canEditStatus, FriendshipRules.dateableCharacters.contains(old.name),
                      friendship.status.safelyEditable,
                      friendship.points <= FriendshipRules.maximumEditablePoints(for: friendship) else {
                    throw SaveValidationError.invalid("该角色不能安全切换到所选关系状态。")
                }
            }
            if original != nil {
                for (value, previous) in [(friendship.giftsToday, old?.giftsToday),
                                          (friendship.giftsThisWeek, old?.giftsThisWeek)] where value != previous {
                    guard previous != nil, value == 0 else {
                        throw SaveValidationError.invalid("只能重置存档中已有的有效送礼次数。")
                    }
                }
            } else {
                for value in [friendship.giftsToday, friendship.giftsThisWeek].compactMap({ $0 }) {
                    guard (0...Int(Int32.max)).contains(value) else {
                        throw SaveValidationError.invalid("送礼次数无效。")
                    }
                }
            }
        }
    }

    private static func applyPlayerScalars(_ draft: SaveDraft, original: SaveDraft, to player: XMLNode) {
        AppearanceColorCodec.apply(draft.appearanceColors, original: original.appearanceColors, to: player)
        if draft.backpackCapacity != original.backpackCapacity, let capacity = draft.backpackCapacity {
            player.setValue(String(capacity), named: "maxItems")
        }
        if draft.playerName != original.playerName {
            player.setValue(draft.playerName, named: "name")
        }
        if draft.farmName != original.farmName {
            player.setValue(draft.farmName, named: "farmName")
        }
        if draft.favoriteThing != original.favoriteThing {
            player.setValue(draft.favoriteThing, named: "favoriteThing")
        }
        if draft.money != original.money {
            player.setValue(String(draft.money), named: "money")
        }
        if draft.maxHealth != original.maxHealth {
            player.setValue(String(draft.maxHealth), named: "maxHealth")
        }
        if draft.maxStamina != original.maxStamina {
            player.setValue(String(draft.maxStamina), named: "maxStamina")
        }
        if draft.gender != original.gender {
            player.setValue(draft.gender.rawValue, named: "Gender")
            player.setValue(draft.gender.rawValue, named: "gender")
        }
        if draft.hair != original.hair {
            let rawHair = draft.hair >= 56 ? draft.hair + 100 - 56 : draft.hair
            player.setValue(String(rawHair), named: "hair")
        }
        if draft.skin != original.skin {
            player.setValue(String(draft.skin), named: "skin")
        }
        if draft.accessory != original.accessory {
            player.setValue(String(draft.accessory), named: "accessory")
        }
        applyOptionalPlayerValue(
            draft.progress.qiGems,
            original: original.progress.qiGems,
            field: "qiGems",
            to: player
        )
        applyOptionalPlayerValue(
            draft.progress.clubCoins,
            original: original.progress.clubCoins,
            field: "clubCoins",
            to: player
        )
        applyOptionalPlayerValue(
            draft.progress.totalMoneyEarned,
            original: original.progress.totalMoneyEarned,
            field: "totalMoneyEarned",
            to: player
        )
        applyOptionalPlayerValue(
            draft.progress.deepestMineLevel,
            original: original.progress.deepestMineLevel,
            field: "deepestMineLevel",
            to: player
        )
        if draft.farmhouse.upgradeLevel != original.farmhouse.upgradeLevel,
           let upgradeLevel = draft.farmhouse.upgradeLevel {
            player.setValue(String(upgradeLevel), named: "houseUpgradeLevel")
        }

        let changedSkills = draft.skills.filter { skill in
            guard let old = original.skills.first(where: { $0.key == skill.key }) else { return false }
            return old.level != skill.level || old.originalExperience != skill.targetExperience
        }
        guard !changedSkills.isEmpty else { return }

        let experienceContainer: XMLNode
        if let existing = player.child(named: "experiencePoints") {
            experienceContainer = existing
        } else {
            experienceContainer = XMLNode(name: "experiencePoints")
            player.children.append(experienceContainer)
        }
        var experienceNodes = experienceContainer.children(named: "int")
        while experienceNodes.count < SkillKey.allCases.count {
            let node = XMLNode(name: "int", text: "0")
            experienceContainer.children.append(node)
            experienceNodes.append(node)
        }
        for skill in changedSkills {
            player.setValue(String(skill.level), named: skill.key.fieldName, createIfMissing: true)
            if experienceNodes.indices.contains(skill.key.experienceIndex) {
                experienceNodes[skill.key.experienceIndex].text = String(skill.targetExperience)
            }
        }
    }

    private static func applyOptionalPlayerValue(
        _ value: Int?,
        original: Int?,
        field: String,
        to player: XMLNode
    ) {
        guard value != original, let value else { return }
        player.setValue(String(value), named: field)
    }

    private static func applyWorldProgress(
        _ progress: ProgressDraft,
        original: ProgressDraft,
        to root: XMLNode
    ) {
        if progress.goldenWalnuts != original.goldenWalnuts, let value = progress.goldenWalnuts {
            root.setValue(String(value), named: "goldenWalnuts")
        }
        if progress.mineLowestLevelReached != original.mineLowestLevelReached,
           let value = progress.mineLowestLevelReached {
            root.setValue(String(value), named: "mine_lowestLevelReached")
        }
        if progress.piecesOfHay != original.piecesOfHay,
           let value = progress.piecesOfHay,
           let farm = location(in: root, named: "Farm", typeContaining: "farm") {
            farm.setValue(String(value), named: "piecesOfHay")
        }
    }

    private static func applyProfessions(_ professionIDs: Set<Int>, to player: XMLNode) {
        let container: XMLNode
        if let existing = player.child(named: "professions") {
            container = existing
        } else {
            container = XMLNode(name: "professions")
            player.children.append(container)
        }
        let preserved = container.children.filter { child in
            guard child.name == "int", let id = Int(child.text) else { return true }
            return !ProfessionCatalog.knownIDs.contains(id)
        }
        let known = professionIDs
            .intersection(ProfessionCatalog.knownIDs)
            .sorted()
            .map { XMLNode(name: "int", text: String($0)) }
        container.children = preserved + known
    }

    private static func applyWalletUnlocks(
        _ unlocks: [WalletUnlockDraft], original: [WalletUnlockDraft], to player: XMLNode
    ) {
        let previous = Dictionary(original.map { ($0.key, $0.isUnlocked) }, uniquingKeysWith: { first, _ in first })
        for unlock in unlocks where previous[unlock.key] != unlock.isUnlocked {
            // Migrate only the edited key. Unrelated legacy and mod flags remain intact.
            player.children.removeAll { $0.name == unlock.key.legacyFieldName }
            var mail = player.child(named: "mailReceived")
            if mail == nil, unlock.isUnlocked {
                let created = XMLNode(name: "mailReceived")
                player.children.append(created)
                mail = created
            }
            guard let mail else { continue }
            mail.children.removeAll { $0.name == "string" && $0.text == unlock.key.rawValue }
            if unlock.isUnlocked {
                mail.children.append(XMLNode(name: "string", text: unlock.key.rawValue))
            }
        }
    }

    private static func applyAnimals(
        _ animals: [FarmAnimalDraft], original: [FarmAnimalDraft], to root: XMLNode
    ) {
        let oldByID = Dictionary(original.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let byID = Dictionary(animals.filter { oldByID[$0.id] != $0 }.map { ($0.id, $0) },
                              uniquingKeysWith: { first, _ in first })
        for item in descendants(of: root) where item.name == "item" {
            guard let node = item.child(named: "value")?.child(named: "FarmAnimal") else { continue }
            guard let id = ExistingSaveValue.farmAnimalID(item), let animal = byID[id], let old = oldByID[id] else { continue }
            if animal.name != old.name {
                node.setValue(animal.name, named: "name", createIfMissing: true)
                node.setValue(animal.name, named: "displayName")
            }
            if animal.friendship != old.friendship {
                node.setValue(String(animal.friendship), named: "friendshipTowardFarmer", createIfMissing: true)
            }
            if animal.happiness != old.happiness {
                node.setValue(String(animal.happiness), named: "happiness", createIfMissing: true)
            }
            if animal.fullness != old.fullness {
                node.setValue(String(animal.fullness), named: "fullness", createIfMissing: true)
            }
            if animal.daysOwned != old.daysOwned {
                node.setValue(String(animal.daysOwned), named: "daysOwned", createIfMissing: true)
            }
            // age is independent of daysOwned and is never implicitly changed.
        }
    }

    private static func applyDate(_ draft: SaveDraft, original: SaveDraft, root: XMLNode?, player: XMLNode) {
        if draft.year != original.year {
            root?.setValue(String(draft.year), named: "year")
            player.setValue(String(draft.year), named: "yearForSaveGame")
        }
        if draft.season != original.season {
            root?.setValue(draft.season.rawValue, named: "currentSeason")
            player.setValue(String(draft.season.saveIndex), named: "seasonForSaveGame")
        }
        if draft.day != original.day {
            root?.setValue(String(draft.day), named: "dayOfMonth")
            player.setValue(String(draft.day), named: "dayOfMonthForSaveGame")
        }
    }

    private static func applyInventory(_ slots: [InventorySlotDraft], original: [InventorySlotDraft], to player: XMLNode) throws {
        guard let items = player.child(named: "items") else { return }
        let originalNodes = items.children(named: "Item")
        let updated = try slots.map { slot in
            if original.indices.contains(slot.id), originalNodes.indices.contains(slot.id),
               slot.item == original[slot.id].item {
                return originalNodes[slot.id]
            }
            guard let item = slot.item else {
                return XMLNode(name: "Item", attributes: ["xsi:nil": "true"])
            }
            let wrapper = "<Fragment xmlns:xsi=\"http://www.w3.org/2001/XMLSchema-instance\">\(item.templateXML)</Fragment>"
            let fragment = try XMLTreeParser().parse(Data(wrapper.utf8))
            guard let node = fragment.children.first else {
                throw SaveValidationError.invalid("背包第 \(slot.id + 1) 格模板无效。")
            }
            if ExistingSaveValue.field("stack", in: node).flatMap(Int.init) != item.stack {
                node.setValue(String(item.stack), named: "stack")
            }
            if ExistingSaveValue.field("quality", in: node).flatMap(Int.init) != item.quality {
                node.setValue(String(item.quality), named: "quality")
            }
            return node.deepCopy()
        }
        var next = 0
        var children: [XMLNode] = []
        for node in items.children {
            if node.name == "Item" {
                if updated.indices.contains(next) { children.append(updated[next]) }
                next += 1
            } else { children.append(node) }
        }
        children.append(contentsOf: updated.dropFirst(next))
        items.children = children
    }

    private static func applyFriendships(_ friendships: [FriendshipDraft], original: [FriendshipDraft], to player: XMLNode) {
        guard let container = player.child(named: "friendshipData") else { return }
        let byName = Dictionary(friendships.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })
        let oldByName = Dictionary(original.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })
        for item in container.children(named: "item") {
            guard let name = item.child(named: "key")?.value(named: "string"),
                  let draft = byName[name], let old = oldByName[name], draft != old,
                  let friendship = item.child(named: "value")?.child(named: "Friendship") else { continue }
            if draft.points != old.points { friendship.setValue(String(draft.points), named: "Points") }
            if draft.status != old.status, draft.canEditStatus, draft.status.safelyEditable {
                friendship.setValue(draft.status.rawValue, named: "Status")
            }
            if draft.giftsToday != old.giftsToday, let value = draft.giftsToday {
                friendship.setValue(String(value), named: "GiftsToday")
            }
            if draft.giftsThisWeek != old.giftsThisWeek, let value = draft.giftsThisWeek {
                friendship.setValue(String(value), named: "GiftsThisWeek")
            }
        }
    }

    private static func applyFarmhouseDecorations(
        _ decorations: [RoomDecorationDraft],
        original: [RoomDecorationDraft],
        to root: XMLNode
    ) {
        guard let farmhouse = location(in: root, named: "FarmHouse", typeContaining: "farmhouse") else {
            return
        }

        for decoration in decorations {
            guard original.first(where: { $0.id == decoration.id })?.styleIndex != decoration.styleIndex else { continue }
            switch decoration.storage {
            case let .scalar(fieldName):
                farmhouse.setValue(String(decoration.styleIndex), named: fieldName)
            case let .dictionary(containerName, key):
                guard let container = farmhouse.child(named: containerName) else { continue }
                for item in descendants(of: container) where item.name == "item" {
                    guard let keyNode = item.child(named: "key"),
                          dictionaryText(in: keyNode)?.trimmingCharacters(in: .whitespacesAndNewlines) == key,
                          let valueNode = item.child(named: "value") else { continue }
                    setDictionaryText(String(decoration.styleIndex), in: valueNode)
                    break
                }
            }
        }
    }

    private static func applyFarmActions(_ actions: FarmActionDraft, to root: XMLNode) {
        guard let farm = location(in: root, named: "Farm", typeContaining: "farm") else { return }

        if actions.waterAllCrops || !actions.cropWateringKeys.isEmpty, let terrain = farm.child(named: "terrainFeatures") {
            for item in terrain.children(named: "item") {
                let value = item.child(named: "value") ?? item
                let feature = value.children.first ?? value
                guard FarmCropRules.state(in: feature) == .dry,
                      actions.waterAllCrops || cropWateringKey(in: item).map(actions.cropWateringKeys.contains) == true else { continue }
                if !feature.setValue("1", named: "state") { feature.setValue("1", named: "netState") }
            }
        }

        if (actions.clearStones || actions.clearWeeds || actions.clearTwigs || !actions.debrisRemovalKeys.isEmpty),
           let objects = farm.child(named: "objects") {
            objects.children.removeAll { item in
                guard item.name == "item", let kind = debrisKind(in: item) else { return false }
                if let key = debrisActionKey(in: item, kind: kind),
                   actions.debrisRemovalKeys.contains(key) {
                    return true
                }
                switch kind {
                case .stone: return actions.clearStones
                case .weed: return actions.clearWeeds
                case .twig: return actions.clearTwigs
                }
            }
        }
    }

    private static func debrisKind(in item: XMLNode) -> FarmDebrisKind? {
        let value = item.child(named: "value") ?? item
        let object = value.children.first ?? value
        return FarmDebrisClassifier.kind(in: object)
    }

    private static func cropWateringKey(in item: XMLNode) -> String? {
        guard let vector = item.child(named: "key")?.firstDescendant(named: "Vector2"),
              let x = vector.value(named: "X").flatMap(Double.init), x.isFinite,
              let y = vector.value(named: "Y").flatMap(Double.init), y.isFinite else { return nil }
        return FarmActionKey.crop(x: x, y: y)
    }

    private static func debrisActionKey(in item: XMLNode, kind: FarmDebrisKind) -> String? {
        guard let vector = item.child(named: "key")?.firstDescendant(named: "Vector2"),
              let x = vector.value(named: "X").flatMap(Double.init),
              let y = vector.value(named: "Y").flatMap(Double.init) else { return nil }
        return FarmActionKey.debris(kind: kind, x: x, y: y)
    }

    private static func location(
        in root: XMLNode,
        named locationName: String,
        typeContaining typeFragment: String
    ) -> XMLNode? {
        guard let locations = root.child(named: "locations") else { return nil }
        let wantedName = locationName.lowercased()
        let wantedType = typeFragment.lowercased()
        let nodes = descendants(of: locations)
        if let named = nodes.first(where: { $0.value(named: "name")?.lowercased() == wantedName }) {
            return named
        }
        if let exactType = nodes.first(where: { normalizedType(of: $0).lowercased() == wantedType }) {
            return exactType
        }
        return nodes.first { normalizedType(of: $0).lowercased().contains(wantedType) }
    }

    private static func descendants(of node: XMLNode) -> [XMLNode] {
        node.children.flatMap { child in [child] + descendants(of: child) }
    }

    private static func normalizedType(of node: XMLNode) -> String {
        let raw = node.attributes["xsi:type"] ?? node.attributes["type"] ?? node.name
        return raw.split(separator: ":").last.map(String.init) ?? raw
    }

    private static func isNilNode(_ node: XMLNode) -> Bool {
        node.attributes["xsi:nil"] == "true" || node.attributes["nil"] == "true"
    }

    private static func dictionaryText(in node: XMLNode) -> String? {
        for name in ["string", "int", "unsignedInt", "long"] {
            if let text = node.firstDescendant(named: name)?.text, !text.isEmpty { return text }
        }
        return node.text.isEmpty ? nil : node.text
    }

    private static func setDictionaryText(_ text: String, in node: XMLNode) {
        for name in ["int", "unsignedInt", "long", "string"] {
            if let value = node.firstDescendant(named: name) {
                value.text = text
                value.children.removeAll()
                return
            }
        }
        node.text = text
        node.children.removeAll()
    }
}
