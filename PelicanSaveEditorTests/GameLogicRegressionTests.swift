import XCTest
@testable import PelicanSaveEditor

final class GameLogicRegressionTests: XCTestCase {
    func testDebrisCleanupPreservesTypeNamespacesContainersAndModObjects() throws {
        let entries = [
            objectEntry("Weeds", id: "0", x: 1),
            objectEntry("Stone", id: "StardewValley:(O)343", x: 2),
            objectEntry("Twig", id: "294", x: 3),
            objectEntry("House Plant", id: "0", x: 4, extra: "<bigCraftable>true</bigCraftable>"),
            objectEntry("Mod Stone", id: "my.mod:(O)343", x: 5),
            objectEntry("Stone", id: "343", x: 6, type: "CustomStone"),
            objectEntry("Chest", id: "0", x: 7, extra: "<items><Item xsi:nil=\"true\"/></items>"),
            objectEntry("Furniture", id: "0", x: 8, type: "Furniture"),
            objectEntry("Machine", id: "0", x: 9, extra: "<heldObject><Object><name>Weeds</name><itemId>0</itemId></Object></heldObject>")
        ].joined()
        let parsed = try parse(world: farm(objects: entries))
        let before = FarmSnapshotExtractor.extract(from: parsed.mainRoot, cropCatalog: [])
        XCTAssertEqual(before.weedCount, 1)
        XCTAssertEqual(before.stoneCount, 1)
        XCTAssertEqual(before.twigCount, 1)
        var draft = parsed.draft
        draft.farmActions.clearWeeds = true
        draft.farmActions.clearStones = true
        draft.farmActions.clearTwigs = true
        XCTAssertEqual(before.affectedEntities(by: draft.farmActions).count, 3)
        let root = try renderedRoot(parsed, draft: draft)
        let remaining = try XCTUnwrap(root.child(named: "locations")?.children.first?.child(named: "objects"))
        XCTAssertEqual(remaining.children.count, 6)
        XCTAssertEqual(remaining.children.compactMap {
            $0.child(named: "value")?.children.first?.value(named: "name")
        }, ["House Plant", "Mod Stone", "Stone", "Chest", "Furniture", "Machine"])
    }

    func testRenamingOneAnimalPreservesOtherAnimalsAndIndependentAges() throws {
        let a = animal(id: "1", name: "A", age: 2, owned: 20)
        let b = animal(id: "2", name: "B", age: 7, owned: 40)
        let parsed = try parse(world: farm(animals: a + b))
        let originalA = try XCTUnwrap(animalNode("1", in: parsed.mainRoot)).xmlString()
        var draft = parsed.draft
        let index = try XCTUnwrap(draft.animals.firstIndex { $0.id == "2" })
        draft.animals[index].name = "奶糖"
        let root = try renderedRoot(parsed, draft: draft)
        XCTAssertEqual(animalNode("1", in: root)?.xmlString(), originalA)
        XCTAssertEqual(animalNode("2", in: root)?.value(named: "age"), "7")
        XCTAssertEqual(animalNode("2", in: root)?.value(named: "daysOwned"), "40")
        XCTAssertEqual(animalNode("2", in: root)?.value(named: "name"), "奶糖")
        XCTAssertEqual(SaveDiffBuilder.build(original: parsed.draft, draft: draft).count, 1)
        draft.animals[index].daysOwned = 99
        let explicitlyEdited = try renderedRoot(parsed, draft: draft)
        XCTAssertEqual(animalNode("2", in: explicitlyEdited)?.value(named: "age"), "7")
        XCTAssertEqual(animalNode("2", in: explicitlyEdited)?.value(named: "daysOwned"), "99")
    }

    func testCodecAcceptsUTF8CharacterAcrossOldPrefixBoundary() throws {
        let opening = "<SaveGame><player><name>"
        let xml = opening + String(repeating: "a", count: 254 - opening.utf8.count)
            + "中文</name></player></SaveGame>"
        let source = Data(xml.utf8)
        XCTAssertNil(String(data: source.prefix(256), encoding: .utf8))
        for encoding in [SaveEncoding.plainXML, .zlib] {
            for includeBOM in [false, true] {
                let encoded = try SaveCodec.encode(xmlData: source, encoding: encoding, includeBOM: includeBOM)
                let decoded = try SaveCodec.decode(encoded)
                XCTAssertEqual(decoded.xmlData, source)
                XCTAssertEqual(decoded.encoding, encoding)
                XCTAssertEqual(decoded.hadUTF8BOM, includeBOM)
            }
        }
        let padded = Data((String(repeating: " \n", count: 150) + "<SaveGame/>").utf8)
        XCTAssertEqual(try SaveCodec.decode(padded).xmlData, padded)
    }

    func testPairingRejectsWrongRootAndDifferentFarmerButAllowsRenamedSameID() throws {
        XCTAssertThrowsError(try parse(info: "<SaveGame/>"))
        XCTAssertThrowsError(try parse(info: "<Farmer><uniqueMultiplayerID>456</uniqueMultiplayerID></Farmer>")) { error in
            guard case SaveParseError.mismatchedPair = error else { return XCTFail("Unexpected error: \(error)") }
        }
        XCTAssertNoThrow(try parse(info: "<Farmer><name>Renamed</name><uniqueMultiplayerID>123</uniqueMultiplayerID></Farmer>"))
        let missing = try parse(info: "<Farmer><name>Old summary</name></Farmer>")
        XCTAssertTrue(missing.warnings.contains { $0.contains("稳定玩家标识") })
    }

    func testWalletFalseIsFalseAndOnlyEditedLegacyKeyIsMigrated() throws {
        let legacy = """
        <hasRustyKey>false</hasRustyKey><hasSkullKey>true</hasSkullKey>
        <hasClubCard xsi:nil="true"/><hasMagicInk>1</hasMagicInk>
        <mailReceived><string>mod.unchanged</string></mailReceived>
        """
        let parsed = try parse(player: legacy)
        func unlocked(_ key: WalletUnlockKey) -> Bool {
            parsed.draft.progress.walletUnlocks.first { $0.key == key }?.isUnlocked == true
        }
        XCTAssertFalse(unlocked(.rustyKey))
        XCTAssertFalse(unlocked(.clubCard))
        XCTAssertTrue(unlocked(.skullKey))
        XCTAssertTrue(unlocked(.magicInk))
        var draft = parsed.draft
        let club = try XCTUnwrap(draft.progress.walletUnlocks.firstIndex { $0.key == .clubCard })
        draft.progress.walletUnlocks[club].isUnlocked = true
        let player = try XCTUnwrap(try renderedRoot(parsed, draft: draft).child(named: "player"))
        XCTAssertEqual(player.value(named: "hasRustyKey"), "false")
        XCTAssertEqual(player.value(named: "hasSkullKey"), "true")
        XCTAssertEqual(player.value(named: "hasMagicInk"), "1")
        XCTAssertNil(player.child(named: "hasClubCard"))
        XCTAssertEqual(player.child(named: "mailReceived")?.children.map(\.text), ["mod.unchanged", "HasClubCard"])
        let skull = try XCTUnwrap(draft.progress.walletUnlocks.firstIndex { $0.key == .skullKey })
        draft.progress.walletUnlocks[skull].isUnlocked = false
        let withoutSkull = try XCTUnwrap(try renderedRoot(parsed, draft: draft).child(named: "player"))
        XCTAssertNil(withoutSkull.child(named: "hasSkullKey"))
        XCTAssertFalse(withoutSkull.child(named: "mailReceived")!.children.contains { $0.text == "HasSkullKey" })
    }

    func testSkillLevelAndExperienceUseSameProfessionRules() throws {
        let parsed = try parse()
        var byXP = parsed.draft
        byXP.setSkillExperience(0, for: .farming)
        XCTAssertEqual(byXP.skills.first?.level, 0)
        XCTAssertTrue(byXP.progress.professionIDs.intersection([1, 4]).isEmpty)
        XCTAssertTrue(byXP.progress.professionIDs.contains(999), "Unknown original professions must survive")
        XCTAssertNoThrow(try SaveMutator.validate(byXP, comparedTo: parsed.draft))
        var byLevel = parsed.draft
        byLevel.setSkillLevel(0, for: .farming)
        XCTAssertEqual(byLevel, byXP)
        var malformed = parsed.draft
        malformed.skills[0].experience = 0
        malformed.skills[0].level = 0
        XCTAssertThrowsError(try SaveMutator.validate(malformed, comparedTo: parsed.draft))
        malformed = parsed.draft
        malformed.skills[0].experience = 100
        XCTAssertThrowsError(try SaveMutator.validate(malformed, comparedTo: parsed.draft))
        var secondary = parsed.draft
        secondary.setSecondaryProfession(2, for: .farming)
        XCTAssertEqual(secondary.progress.professionIDs.intersection(ProfessionCatalog.knownIDs), [0, 2])
        XCTAssertNoThrow(try SaveMutator.validate(secondary, comparedTo: parsed.draft))
    }

    func testProfessionValidationRejectsConflictsButPreservesUnrelatedExistingExtensions() throws {
        let parsed = try parse()
        let invalidSelections: [Set<Int>] = [[0, 1, 4, 999], [5, 999], [1, 4, 5, 999]]
        for selection in invalidSelections {
            var invalid = parsed.draft
            invalid.progress.professionIDs = selection
            XCTAssertThrowsError(try SaveMutator.validate(invalid, comparedTo: parsed.draft))
        }
        var existingExtended = parsed.draft
        existingExtended.progress.professionIDs = [0, 1, 4, 5, 999]
        var unrelated = existingExtended
        unrelated.money += 1
        XCTAssertNoThrow(try SaveMutator.validate(unrelated, comparedTo: existingExtended))

        var lowered = parsed.draft
        lowered.setSkillExperience(14_999, for: .farming)
        XCTAssertEqual(lowered.skills[0].level, 9)
        XCTAssertEqual(lowered.progress.professionIDs, [1, 999])
        XCTAssertNoThrow(try SaveMutator.validate(lowered, comparedTo: parsed.draft))
    }

    func testEveryDiffIsGroupedAndEachEditCanBeUndone() throws {
        let parsed = try parse(player: "<qiGems>2</qiGems><deepestMineLevel>10</deepestMineLevel>",
                               world: farm(animals: animal(id: "1", name: "A", age: 2, owned: 20)))
        var draft = parsed.draft
        draft.money += 1
        draft.progress.qiGems = 50
        draft.progress.deepestMineLevel = 20
        draft.animals[0].friendship = 900
        draft.progress.walletUnlocks[0].isUnlocked.toggle()
        draft.setSkillExperience(0, for: .farming)
        draft.recipes[0].unlocked = true
        draft.farmActions.debrisRemovalKeys = ["debris:stone:1:2", "debris:weed:3:4"]
        let diffs = SaveDiffBuilder.build(original: parsed.draft, draft: draft)
        let future = SaveDiff(id: "future", section: "未来分类", label: "Future", oldValue: "0", newValue: "1", affectsSaveGameInfo: false)
        let grouped = SaveDiffBuilder.grouped(diffs + [future])
        XCTAssertEqual(Set(grouped.flatMap(\.diffs).map(\.id)), Set((diffs + [future]).map(\.id)))
        XCTAssertEqual(grouped.flatMap(\.diffs).count, diffs.count + 1)
        XCTAssertEqual(diffs.filter { $0.id.hasPrefix("farm.debris.") }.count, 2)
        XCTAssertTrue(diffs.first { $0.id == "progress.qiGems" }!.affectsSaveGameInfo)
        XCTAssertTrue(diffs.first { $0.id == "progress.deepestMine" }!.affectsSaveGameInfo)
        for diff in diffs { SaveDiffBuilder.undo(diff, original: parsed.draft, draft: &draft) }
        XCTAssertEqual(draft, parsed.draft)
    }

    func testSingleDebrisUndoDoesNotUndoNeighborAndEqualCountSelectionIsVisible() throws {
        let parsed = try parse()
        var first = parsed.draft
        first.farmActions.debrisRemovalKeys = ["debris:stone:1:2"]
        var second = parsed.draft
        second.farmActions.debrisRemovalKeys = ["debris:stone:3:4"]
        let replacement = SaveDiffBuilder.build(original: first, draft: second)
        XCTAssertEqual(replacement.count, 2)
        var draft = parsed.draft
        draft.farmActions.debrisRemovalKeys = first.farmActions.debrisRemovalKeys.union(second.farmActions.debrisRemovalKeys)
        let diff = try XCTUnwrap(SaveDiffBuilder.build(original: parsed.draft, draft: draft).first { $0.id.hasSuffix("1:2") })
        SaveDiffBuilder.undo(diff, original: parsed.draft, draft: &draft)
        XCTAssertEqual(draft.farmActions.debrisRemovalKeys, ["debris:stone:3:4"])
    }

    func testEightStringIDObjectsHaveChineseNamesAndRoundTrip() throws {
        let catalog = try ItemCatalog.load()
        let added = catalog.filter { ItemCatalog.supportedStringIDs.contains($0.id) }
        XCTAssertEqual(Set(added.map(\.id)), ItemCatalog.supportedStringIDs)
        XCTAssertTrue(added.allSatisfy { $0.chineseName?.contains(where: { $0.unicodeScalars.contains(where: { $0.value >= 0x4E00 && $0.value <= 0x9FFF }) }) == true })
        let parsed = try parse()
        var draft = parsed.draft
        draft.inventory = added.enumerated().map { InventorySlotDraft(id: $0.offset, item: $0.element.makeInventoryItem(stack: 2)) }
        let rendered = try SaveMutator.render(parsed: parsed, draft: draft)
        let reread = try SaveParser.parse(mainData: rendered.mainData, infoData: nil, catalog: catalog, recipeCatalog: [:])
        XCTAssertEqual(Set(reread.draft.inventory.compactMap { $0.item?.itemID }), ItemCatalog.supportedStringIDs)
        XCTAssertTrue(reread.draft.inventory.allSatisfy { $0.item?.stack == 2 && $0.item?.isEditable == true })
    }

    private func parse(player: String = "", world: String = "", info: String? = nil) throws -> ParsedSaveDocument {
        let main = """
        <SaveGame xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"><player>
        <name>Test</name><farmName>Farm</farmName><favoriteThing>Tea</favoriteThing><uniqueMultiplayerID>123</uniqueMultiplayerID>
        <money>10</money><maxHealth>100</maxHealth><maxStamina>270</maxStamina>
        <farmingLevel>10</farmingLevel><fishingLevel>0</fishingLevel><foragingLevel>0</foragingLevel><miningLevel>0</miningLevel><combatLevel>0</combatLevel>
        <experiencePoints><int>15000</int><int>0</int><int>0</int><int>0</int><int>0</int></experiencePoints>
        <professions><int>1</int><int>4</int><int>999</int></professions>
        <items><Item xsi:nil="true"/></items><cookingRecipes/><craftingRecipes/>
        \(player)</player><year>1</year><currentSeason>spring</currentSeason><dayOfMonth>1</dayOfMonth><gameVersion>1.6.8</gameVersion>\(world)</SaveGame>
        """
        return try SaveParser.parse(mainData: Data(main.utf8), infoData: info.map { Data($0.utf8) }, catalog: [], recipeCatalog: [.cooking: ["Fried Egg"]])
    }

    private func renderedRoot(_ parsed: ParsedSaveDocument, draft: SaveDraft) throws -> XMLNode {
        let rendered = try SaveMutator.render(parsed: parsed, draft: draft)
        return try XMLTreeParser().parse(SaveCodec.decode(rendered.mainData).xmlData)
    }

    private func farm(objects: String = "", animals: String = "") -> String {
        "<locations><GameLocation xsi:type=\"Farm\"><name>Farm</name><objects>\(objects)</objects><animals>\(animals)</animals></GameLocation></locations>"
    }

    private func objectEntry(_ name: String, id: String, x: Int, extra: String = "", type: String? = nil) -> String {
        let attribute = type.map { " xsi:type=\"\($0)\"" } ?? ""
        return "<item><key><Vector2><X>\(x)</X><Y>1</Y></Vector2></key><value><Object\(attribute)><name>\(name)</name><itemId>\(id)</itemId>\(extra)</Object></value></item>"
    }

    private func animal(id: String, name: String, age: Int, owned: Int) -> String {
        "<item><key><long>\(id)</long></key><value><FarmAnimal><name>\(name)</name><displayName>\(name)</displayName><type>White Cow</type><age>\(age)</age><daysOwned>\(owned)</daysOwned><friendshipTowardFarmer>100</friendshipTowardFarmer><happiness>100</happiness><fullness>100</fullness><untouched custom=\"yes\">keep</untouched></FarmAnimal></value></item>"
    }

    private func animalNode(_ id: String, in root: XMLNode) -> XMLNode? {
        root.child(named: "locations")?.children.first?.child(named: "animals")?.children.first {
            $0.child(named: "key")?.value(named: "long") == id
        }?.child(named: "value")?.child(named: "FarmAnimal")
    }
}
