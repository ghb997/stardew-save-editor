import XCTest
@testable import PelicanSaveEditor

final class RepairRegressionTests: XCTestCase {
    private let recipes: [RecipeKind: [String]] = [.cooking: ["Fried Egg", "Omelet", "Salad"], .crafting: ["Chest"]]
    private func parse(items: String = "<Item xsi:nil=\"true\"/>", player: String = "", world: String = "") throws -> ParsedSaveDocument {
        let xml = """
        <SaveGame xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"><player><name>Test</name><farmName>Farm</farmName>
        <money>100</money><maxHealth>100</maxHealth><maxStamina>270</maxStamina><maxItems>12</maxItems>
        <items>\(items)</items>\(player)</player><year>2</year><currentSeason>spring</currentSeason><dayOfMonth>3</dayOfMonth>
        <gameVersion>1.6.15</gameVersion>\(world)<opaque>unchanged</opaque></SaveGame>
        """
        return try SaveParser.parse(mainData: Data(xml.utf8), infoData: nil, catalog: ItemCatalog.load(), recipeCatalog: recipes)
    }
    private func render(_ parsed: ParsedSaveDocument, _ draft: SaveDraft) throws -> ParsedSaveDocument {
        let pair = try SaveMutator.render(parsed: parsed, draft: draft)
        return try SaveParser.parse(mainData: pair.mainData, infoData: pair.infoData, catalog: ItemCatalog.load(), recipeCatalog: recipes)
    }
    private func object(_ extra: String = "", stack: String = "0005", quality: String = "00") -> String {
        "<Item xsi:type=\"Object\"><name>Parsnip</name><itemId>24</itemId><stack>\(stack)</stack><quality>\(quality)</quality>\(extra)<custom keep=\"yes\"/></Item>"
    }
    private var axe: String {
        "<Item xsi:type=\"Axe\"><name>Axe</name><itemId>Axe</itemId><upgradeLevel>01</upgradeLevel><stack>1</stack><quality>0</quality><enchantments keep=\"original\"/><unknown>keep</unknown></Item>"
    }
    private var weapon: String {
        "<Item xsi:type=\"MeleeWeapon\"><name>Galaxy Sword</name><itemId>4</itemId><minDamage>60</minDamage><maxDamage>80</maxDamage><critChance>0.0200</critChance><critMultiplier>3</critMultiplier><speed>4</speed><enchantments><BaseEnchantment xsi:type=\"RubyEnchantment\"><level>2</level></BaseEnchantment></enchantments></Item>"
    }
    private func recipe(_ key: String, _ count: String) -> String {
        "<item><key><string>\(key)</string></key><value><int>\(count)</int></value><extra>keep</extra></item>"
    }

    func testQuestUnknownAndMalformedInventoryAreReadOnly() throws {
        let xml = object("<questItem>true</questItem>") + object(stack: "broken")
            + object("<quality>2</quality>") + object().replacingOccurrences(of: ">24<", with: ">mod.object<")
            + "<Item xsi:nil=\"1\"/>"
        let parsed = try parse(items: xml)
        XCTAssertEqual(parsed.draft.inventory.prefix(4).compactMap(\.item).map(\.isEditable), [false, false, false, false])
        XCTAssertNil(parsed.draft.inventory[4].item)
        var draft = parsed.draft; draft.money += 1
        let result = try render(parsed, draft)
        XCTAssertEqual(result.mainRoot.child(named: "player")?.child(named: "items")?.xmlString(),
                       parsed.mainRoot.child(named: "player")?.child(named: "items")?.xmlString())
    }

    func testReadOnlyInventoryCannotBeRemovedMovedOrForged() throws {
        let parsed = try parse(items: axe + "<Item xsi:nil=\"true\"/>")
        var draft = parsed.draft; draft.inventory[0].item = nil
        XCTAssertThrowsError(try SaveMutator.render(parsed: parsed, draft: draft))
        draft = parsed.draft; draft.inventory.swapAt(0, 1)
        XCTAssertThrowsError(try SaveMutator.render(parsed: parsed, draft: draft))
        draft = parsed.draft; draft.inventory[0].item?.isEditable = true
        XCTAssertThrowsError(try SaveMutator.render(parsed: parsed, draft: draft))
    }

    func testInventoryQuantityPreservesQualitySpellingAndOpaqueMetadata() throws {
        let parsed = try parse(items: object())
        var draft = parsed.draft; draft.inventory[0].item?.stack = 19
        let result = try render(parsed, draft)
        let node = try XCTUnwrap(result.mainRoot.child(named: "player")?.child(named: "items")?.children.first)
        XCTAssertEqual(node.value(named: "stack"), "19")
        XCTAssertEqual(node.value(named: "quality"), "00")
        XCTAssertEqual(node.child(named: "custom")?.attributes["keep"], "yes")
    }

    func testCopyMoveAndCanonicalNondefaultQuantityRemainSupported() throws {
        let parsed = try parse(items: object() + "<Item xsi:nil=\"true\"/>")
        var draft = parsed.draft
        draft.inventory[1].item = draft.inventory[0].item?.copied()
        draft.inventory[0].item = nil
        XCTAssertNoThrow(try render(parsed, draft))
        draft = parsed.draft
        let parsnip = try XCTUnwrap(try ItemCatalog.load().first { $0.id == "24" })
        draft.inventory[1].item = parsnip.makeInventoryItem(stack: 37, quality: 4)
        let result = try render(parsed, draft)
        XCTAssertEqual(result.draft.inventory[1].item?.stack, 37)
        XCTAssertEqual(result.draft.inventory[1].item?.quality, 4)
        draft.inventory[1].item?.templateXML += "<Item xsi:nil=\"true\"/>"
        XCTAssertThrowsError(try render(parsed, draft))
    }

    func testInventoryMetadataAndDuplicateIdentityAreRejected() throws {
        let parsed = try parse(items: object() + "<Item xsi:nil=\"true\"/>")
        var draft = parsed.draft; draft.inventory[0].item?.itemID = "390"
        XCTAssertThrowsError(try render(parsed, draft))
        draft = parsed.draft; draft.inventory[1].item = draft.inventory[0].item
        XCTAssertThrowsError(try render(parsed, draft))
    }

    func testRecipeUnlockPreservesOtherCountsAndMalformedRecordsExactly() throws {
        let preserved = recipe("Fried Egg", "0007") + recipe("Omelet", "bad")
        let parsed = try parse(player: "<cookingRecipes>\(preserved)</cookingRecipes>")
        var draft = parsed.draft
        let salad = try XCTUnwrap(draft.recipes.firstIndex { $0.key == "Salad" })
        draft.recipes[salad].unlocked = true
        let result = try render(parsed, draft)
        let before = try XCTUnwrap(parsed.mainRoot.child(named: "player")?.child(named: "cookingRecipes"))
        let after = try XCTUnwrap(result.mainRoot.child(named: "player")?.child(named: "cookingRecipes"))
        XCTAssertEqual(Array(after.children.prefix(2)).map { $0.xmlString() }, before.children.map { $0.xmlString() })
        XCTAssertEqual(after.children.count, 3)
        XCTAssertFalse(try XCTUnwrap(parsed.draft.recipes.first { $0.key == "Omelet" }).isEditable)
    }

    func testMissingRecipeContainerCanBeCreatedAndDuplicateRecipeCannotBeEdited() throws {
        let parsed = try parse()
        var draft = parsed.draft
        let index = try XCTUnwrap(draft.recipes.firstIndex { $0.key == "Salad" })
        draft.recipes[index].unlocked = true
        let after = try render(parsed, draft)
        XCTAssertTrue(try XCTUnwrap(after.draft.recipes.first { $0.key == "Salad" }).unlocked)
        let ambiguous = try parse(player: "<cookingRecipes>\(recipe("Salad", "1"))\(recipe("Salad", "2"))</cookingRecipes>")
        var bad = ambiguous.draft
        let duplicate = try XCTUnwrap(bad.recipes.firstIndex { $0.key == "Salad" })
        XCTAssertFalse(bad.recipes[duplicate].isEditable)
        bad.recipes[duplicate].unlocked = false
        XCTAssertThrowsError(try render(ambiguous, bad))
    }

    func testRecipeInvalidCountAndChangedScopeAreRejected() throws {
        let parsed = try parse()
        var draft = parsed.draft; draft.recipes[0].timesMade = -1
        XCTAssertThrowsError(try render(parsed, draft))
        draft = parsed.draft; draft.recipes.removeLast()
        XCTAssertThrowsError(try render(parsed, draft))
    }

    func testDuplicateFriendshipsAreExcludedWithoutModifyingTheirXML() throws {
        let friend = "<item><key><string>Abigail</string></key><value><Friendship><Points>100</Points><Status>Friendly</Status></Friendship></value></item>"
        let parsed = try parse(player: "<friendshipData>\(friend)\(friend)</friendshipData>")
        XCTAssertTrue(parsed.draft.friendships.isEmpty)
        var draft = parsed.draft; draft.money += 10
        XCTAssertEqual(try render(parsed, draft).mainRoot.child(named: "player")?.child(named: "friendshipData")?.xmlString(),
                       parsed.mainRoot.child(named: "player")?.child(named: "friendshipData")?.xmlString())
    }

    func testEquivalentCoordinateSpellingsCannotTargetTwoContainers() throws {
        func entry(_ x: String) -> String {
            "<item><key><Vector2><X>\(x)</X><Y>2</Y></Vector2></key><value>\(ExpandedEditorFixture.chest)</value></item>"
        }
        let parsed = try parse(world: "<locations><GameLocation xsi:type=\"Farm\"><name>Farm</name><objects>\(entry("1"))\(entry("01.0"))</objects></GameLocation></locations>")
        XCTAssertTrue(parsed.draft.storages.isEmpty)
    }

    func testEquipmentChangesOnlySelectedFieldAndPreservesEnchantments() throws {
        let parsed = try parse(items: axe + weapon)
        XCTAssertEqual(parsed.draft.equipment.count, 2)
        var draft = parsed.draft
        draft.equipment[0].fields[0].value = 4
        let after = try render(parsed, draft)
        let beforeItems = try XCTUnwrap(parsed.mainRoot.child(named: "player")?.child(named: "items"))
        let afterItems = try XCTUnwrap(after.mainRoot.child(named: "player")?.child(named: "items"))
        XCTAssertEqual(afterItems.children[0].value(named: "upgradeLevel"), "4")
        XCTAssertEqual(afterItems.children[0].child(named: "enchantments")?.xmlString(), beforeItems.children[0].child(named: "enchantments")?.xmlString())
        XCTAssertEqual(afterItems.children[1].xmlString(), beforeItems.children[1].xmlString())
        XCTAssertNoThrow(try SaveIntentVerifier.verify(original: parsed.draft, intended: draft, reloaded: after, originalRoot: parsed.mainRoot))
    }

    func testEquipmentAndOrdinaryInventoryEditsCanBeSavedTogether() throws {
        let parsed = try parse(items: axe + object())
        var draft = parsed.draft
        draft.equipment[0].fields[0].value = 3
        draft.inventory[1].item?.stack = 21
        let after = try render(parsed, draft)
        XCTAssertEqual(after.draft.equipment[0].fields[0].value, 3)
        XCTAssertEqual(after.draft.inventory[1].item?.stack, 21)
        XCTAssertNoThrow(try SaveIntentVerifier.verify(original: parsed.draft, intended: draft, reloaded: after, originalRoot: parsed.mainRoot))
    }

    func testEquipmentBoundsNaNAndDamageOrderAreRejected() throws {
        let parsed = try parse(items: axe + weapon)
        var draft = parsed.draft; draft.equipment[0].fields[0].value = 5
        XCTAssertThrowsError(try render(parsed, draft))
        draft = parsed.draft; draft.equipment[0].fields[0].value = .nan
        XCTAssertThrowsError(try render(parsed, draft))
        draft = parsed.draft
        let minimum = try XCTUnwrap(draft.equipment[1].fields.firstIndex { $0.id == "minDamage" })
        draft.equipment[1].fields[minimum].value = 90
        XCTAssertThrowsError(try render(parsed, draft))
    }

    func testEquipmentUndoRestoresOneFieldWithoutLosingOtherChanges() throws {
        let parsed = try parse(items: axe + weapon)
        var draft = parsed.draft; draft.equipment[0].fields[0].value = 4; draft.money += 5
        let diff = try XCTUnwrap(SaveDiffBuilder.build(original: parsed.draft, draft: draft).first { $0.id.hasPrefix("equipment:") })
        SaveDiffBuilder.undo(diff, original: parsed.draft, draft: &draft)
        XCTAssertEqual(draft.equipment, parsed.draft.equipment)
        XCTAssertEqual(draft.money, 105)
    }

    func testEquippedBootsWithoutExplicitTypeAndUnknownGearHandling() throws {
        let parsed = try parse(items: axe.replacingOccurrences(of: "xsi:type=\"Axe\"", with: "xsi:type=\"ModAxe\""),
                               player: "<boots><name>Space Boots</name><defenseBonus>4</defenseBonus><immunityBonus>4</immunityBonus></boots>")
        XCTAssertEqual(parsed.draft.equipment.count, 1)
        XCTAssertEqual(parsed.draft.equipment[0].type, "Boots")
    }

    func testMuseumUsesDonationRecordsInsteadOfDiscoveryRecords() throws {
        let discoveries = "<archaeologyFound><item><key><int>96</int></key><value><int>1</int></value></item></archaeologyFound>"
        let world = "<locations><GameLocation xsi:type=\"LibraryMuseum\"><name>ArchaeologyHouse</name><museumPieces/></GameLocation></locations>"
        let parsed = try parse(player: discoveries, world: world)
        let sections = CollectionLibrary.extract(parsed.mainRoot, catalog: try ItemCatalog.load())
        let museum = try XCTUnwrap(sections.first { $0.kind == .museum })
        XCTAssertEqual(museum.entries.count, 95)
        XCTAssertEqual(museum.entries.first { $0.item.id == "96" }?.state, .missing)
        XCTAssertEqual(sections.first { $0.kind == .artifacts }?.entries.first { $0.item.id == "96" }?.state, .recorded)
    }

    func testMissingCollectionDataIsUnknownNotZeroProgress() throws {
        let parsed = try parse()
        let sections = CollectionLibrary.extract(parsed.mainRoot, catalog: try ItemCatalog.load())
        XCTAssertTrue(sections.flatMap(\.entries).allSatisfy { $0.state == .unknown })
    }

    func testMalformedDuplicateAndQualifiedCollectionIDs() throws {
        let records = """
        <basicShipped><item><key><string>(O)24</string></key><value><int>2</int></value></item>
        <item><key><int>24</int></key><value><int>3</int></value></item>
        <item><key><int>390</int></key><value><int>broken</int></value></item></basicShipped>
        """
        let parsed = try parse(player: records)
        let section = try XCTUnwrap(CollectionLibrary.extract(parsed.mainRoot, catalog: try ItemCatalog.load()).first { $0.kind == .shipping })
        XCTAssertEqual(section.entries.first { $0.item.id == "24" }?.state, .unknown)
        XCTAssertEqual(section.entries.first { $0.item.id == "390" }?.state, .unknown)
        XCTAssertFalse(section.notes.isEmpty)
    }

    func testIntentVerifierRejectsMissingScalarWriteBeforeAnyFileWrite() throws {
        let parsed = try parse()
        var draft = parsed.draft; draft.favoriteThing = "Tea"
        let after = try render(parsed, draft)
        XCTAssertThrowsError(try SaveIntentVerifier.verify(original: parsed.draft, intended: draft, reloaded: after, originalRoot: parsed.mainRoot))
        XCTAssertEqual(parsed.mainRoot.child(named: "player")?.value(named: "money"), "100")
    }

    func testDuplicatePlayersAreNotSilentlyAccepted() throws {
        let xml = "<SaveGame><player><name>A</name></player><player><name>B</name></player></SaveGame>"
        XCTAssertThrowsError(try SaveParser.parse(mainData: Data(xml.utf8), infoData: nil, catalog: [], recipeCatalog: [:]))
    }

    func testDuplicateInventoryContainerAndNilWithDataAreNotWritable() throws {
        let duplicate = try parse(player: "<items>\(object())</items>")
        XCTAssertTrue(duplicate.draft.inventory.isEmpty)
        XCTAssertNil(duplicate.draft.backpackCapacity)
        let malformed = try parse(items: "<Item xsi:nil=\"true\"><custom>keep</custom></Item>")
        XCTAssertEqual(malformed.draft.inventory[0].item?.isEditable, false)
        var draft = malformed.draft; draft.inventory[0].item = nil
        XCTAssertThrowsError(try render(malformed, draft))
    }

    func testWrappedRecipesKeepStructureAndMalformedValuesStayReadOnly() throws {
        let parsed = try parse(player: "<cookingRecipes><SerializableDictionaryOfStringInt>\(recipe("Fried Egg", "0007"))</SerializableDictionaryOfStringInt></cookingRecipes>")
        var draft = parsed.draft
        let index = try XCTUnwrap(draft.recipes.firstIndex { $0.key == "Salad" })
        draft.recipes[index].unlocked = true
        let after = try render(parsed, draft)
        let container = try XCTUnwrap(after.mainRoot.child(named: "player")?.child(named: "cookingRecipes"))
        XCTAssertEqual(container.children.map(\.name), ["SerializableDictionaryOfStringInt"])
        XCTAssertEqual(container.children[0].children.count, 2)
        XCTAssertNoThrow(try SaveIntentVerifier.verify(original: parsed.draft, intended: draft, reloaded: after, originalRoot: parsed.mainRoot))
        let malformed = try parse(player: "<cookingRecipes>\(recipe("Salad", "1").replacingOccurrences(of: "</value>", with: "</value><value><int>9</int></value>"))</cookingRecipes>")
        XCTAssertFalse(try XCTUnwrap(malformed.draft.recipes.first { $0.key == "Salad" }).isEditable)
    }

    func testDuplicateAndMismatchedAnimalIDsRemainUntouched() throws {
        func animal(_ key: String, _ myID: String) -> String {
            "<item><key><long>\(key)</long></key><value><FarmAnimal><myID>\(myID)</myID><name>Hen</name><type>White Chicken</type><friendshipTowardFarmer>10</friendshipTowardFarmer><happiness>20</happiness><fullness>30</fullness><daysOwned>2</daysOwned></FarmAnimal></value></item>"
        }
        let parsed = try parse(world: "<locations><GameLocation><name>Farm</name><animals>\(animal("01", "1"))\(animal("1", "1"))\(animal("2", "3"))\(animal("004", "4"))</animals></GameLocation></locations>")
        XCTAssertEqual(parsed.draft.animals.map(\.id), ["4"])
        var draft = parsed.draft; draft.animals[0].friendship = 500
        let after = try render(parsed, draft)
        let beforeNodes = Array(parsed.mainRoot.descendants.filter { $0.name == "FarmAnimal" })
        let afterNodes = Array(after.mainRoot.descendants.filter { $0.name == "FarmAnimal" })
        XCTAssertEqual(beforeNodes.prefix(3).map { $0.xmlString() }, afterNodes.prefix(3).map { $0.xmlString() })
        XCTAssertEqual(afterNodes[3].value(named: "friendshipTowardFarmer"), "500")
        XCTAssertNoThrow(try SaveIntentVerifier.verify(original: parsed.draft, intended: draft, reloaded: after, originalRoot: parsed.mainRoot))
    }

    func testEquipmentChestMachineWateringAndDebrisRemovalSaveTogether() throws {
        func entry(_ x: Int, _ node: String) -> String {
            "<item><key><Vector2><X>\(x)</X><Y>2</Y></Vector2></key><value>\(node)</value></item>"
        }
        let stone = "<Object><name>Stone</name><itemId>343</itemId><bigCraftable>false</bigCraftable></Object>"
        let chest = ExpandedEditorFixture.chest.replacingOccurrences(of: ExpandedEditorFixture.item, with: axe + ExpandedEditorFixture.item)
        let crop = "<TerrainFeature xsi:type=\"HoeDirt\"><state>0</state><crop><seedIndex>472</seedIndex><dead>false</dead></crop></TerrainFeature>"
        let world = "<locations><GameLocation xsi:type=\"Farm\"><name>Farm</name><objects>\(entry(1, stone))\(entry(2, chest))\(entry(3, ExpandedEditorFixture.machine))</objects><terrainFeatures>\(entry(4, crop))</terrainFeatures></GameLocation></locations>"
        let parsed = try parse(items: axe, world: world)
        XCTAssertEqual(parsed.draft.equipment.count, 2)
        var draft = parsed.draft
        draft.equipment[0].fields[0].value = 3
        draft.equipment[1].fields[0].value = 4
        draft.storages[0].slots[1].item?.stack = 22
        draft.machines[0].finish = true
        draft.farmActions.clearStones = true
        draft.farmActions.waterAllCrops = true
        let after = try render(parsed, draft)
        XCTAssertNotEqual(after.draft.machines[0].path, parsed.draft.machines[0].path)
        XCTAssertEqual(after.draft.equipment.map { $0.fields[0].value }, [3, 4])
        XCTAssertEqual(after.draft.storages[0].slots[1].item?.stack, 22)
        XCTAssertFalse(FarmSnapshotExtractor.extract(from: after.mainRoot, cropCatalog: []).entities.contains { $0.state == .dry || $0.state == .stone })
        XCTAssertNoThrow(try SaveIntentVerifier.verify(original: parsed.draft, intended: draft, reloaded: after, originalRoot: parsed.mainRoot))
    }

    func testEquipmentVerificationSurvivesLegacyWalletFieldRemoval() throws {
        let parsed = try parse(items: axe, player: "<hasRustyKey>false</hasRustyKey>")
        // Put the removable legacy flag before items so the equipment path shifts.
        let shiftedXML = parsed.mainRoot.xmlString().replacingOccurrences(of: "<hasRustyKey>false</hasRustyKey>", with: "")
            .replacingOccurrences(of: "<items>", with: "<hasRustyKey>false</hasRustyKey><items>")
        let shifted = try SaveParser.parse(mainData: Data(shiftedXML.utf8), infoData: nil, catalog: ItemCatalog.load(), recipeCatalog: recipes)
        var draft = shifted.draft
        draft.equipment[0].fields[0].value = 4
        let key = try XCTUnwrap(draft.progress.walletUnlocks.firstIndex { $0.key == .rustyKey })
        draft.progress.walletUnlocks[key].isUnlocked = true
        let after = try render(shifted, draft)
        XCTAssertNotEqual(after.draft.equipment[0].path, shifted.draft.equipment[0].path)
        XCTAssertNoThrow(try SaveIntentVerifier.verify(original: shifted.draft, intended: draft, reloaded: after, originalRoot: shifted.mainRoot))
    }

    func testStorageAcceptsCanonicalInitialQuantityAndRejectsDuplicateIDs() throws {
        let parsed = try SaveParser.parse(mainData: Data(ExpandedEditorFixture.xml.utf8), infoData: nil,
                                         catalog: ItemCatalog.load(), recipeCatalog: recipes)
        var draft = parsed.draft
        let parsnip = try XCTUnwrap(try ItemCatalog.load().first { $0.id == "24" })
        draft.storages[0].slots[1].item = parsnip.makeInventoryItem(stack: 37, quality: 4)
        let after = try render(parsed, draft)
        XCTAssertEqual(after.draft.storages[0].slots[1].item?.stack, 37)
        XCTAssertNoThrow(try SaveIntentVerifier.verify(original: parsed.draft, intended: draft, reloaded: after, originalRoot: parsed.mainRoot))
        draft.storages[0].slots[2].item = draft.storages[0].slots[1].item
        XCTAssertThrowsError(try render(parsed, draft))
    }

    func testArtifactAndFishArrayCountsAndMalformedArrayAreDistinguished() throws {
        func record(_ id: Int, _ content: String) -> String {
            "<item><key><string>(O)\(id)</string></key><value><ArrayOfInt>\(content)</ArrayOfInt></value></item>"
        }
        let parsed = try parse(player: "<archaeologyFound>\(record(96, "<int>3</int><int>1</int>"))</archaeologyFound><fishCaught>\(record(128, "<int>4</int><int>20</int>"))\(record(129, "<int>5</int><int>bad</int>"))</fishCaught>")
        let sections = CollectionLibrary.extract(parsed.mainRoot, catalog: try ItemCatalog.load())
        let artifact = sections.first { $0.kind == .artifacts }?.entries.first { $0.item.id == "96" }
        XCTAssertEqual(artifact?.state, .recorded)
        XCTAssertEqual(artifact?.count, 3)
        let fish = try XCTUnwrap(sections.first { $0.kind == .fish })
        XCTAssertEqual(fish.entries.first { $0.item.id == "128" }?.count, 4)
        XCTAssertEqual(fish.entries.first { $0.item.id == "129" }?.state, .unknown)
    }

    func testMuseumCoordinatesAndNilCollectionsDoNotReportFalseCompletion() throws {
        func piece(_ x: String, _ id: Int) -> String {
            "<item><key><Vector2><X>\(x)</X><Y>2</Y></Vector2></key><value><string>(O)\(id)</string></value></item>"
        }
        let world = "<locations><GameLocation xsi:type=\"LibraryMuseum\"><name>ArchaeologyHouse</name><museumPieces>\(piece("1", 96))\(piece("01.0", 97))\(piece("3", 98))</museumPieces></GameLocation></locations>"
        let parsed = try parse(player: "<basicShipped nil=\"1\"/>", world: world)
        let sections = CollectionLibrary.extract(parsed.mainRoot, catalog: try ItemCatalog.load())
        let museum = try XCTUnwrap(sections.first { $0.kind == .museum })
        XCTAssertEqual(museum.entries.first { $0.item.id == "96" }?.state, .unknown)
        XCTAssertEqual(museum.entries.first { $0.item.id == "97" }?.state, .unknown)
        XCTAssertEqual(museum.entries.first { $0.item.id == "98" }?.state, .recorded)
        XCTAssertTrue(try XCTUnwrap(sections.first { $0.kind == .shipping }).entries.allSatisfy { $0.state == .unknown })
    }

    func testIntentVerifierChecksItemIDInsteadOfOnlyDisplayText() throws {
        let parsed = try parse(items: object())
        var intended = parsed.draft; intended.inventory[0].item?.stack = 12
        let rendered = try SaveMutator.render(parsed: parsed, draft: intended)
        let xml = try XCTUnwrap(String(data: rendered.mainData, encoding: .utf8))
            .replacingOccurrences(of: "<itemId>24</itemId>", with: "<itemId>999999</itemId>")
        let wrong = try SaveParser.parse(mainData: Data(xml.utf8), infoData: nil, catalog: ItemCatalog.load(), recipeCatalog: recipes)
        XCTAssertThrowsError(try SaveIntentVerifier.verify(original: parsed.draft, intended: intended, reloaded: wrong, originalRoot: parsed.mainRoot))
    }

    @MainActor
    func testBackgroundRenderVerifiesEquipmentRecipeAndExpandedBackpack() async throws {
        let catalog = try ItemCatalog.load()
        let data = Data(RepairEditorFixture.xml.utf8)
        let parsed = try SaveParser.parse(mainData: data, infoData: nil, catalog: catalog, recipeCatalog: recipes)
        var draft = parsed.draft
        draft.equipment[0].fields[0].value = 4
        try draft.setBackpackCapacity(36)
        draft.inventory[35].item = try XCTUnwrap(catalog.first { $0.id == "24" }).makeInventoryItem(stack: 50, quality: 4)
        let recipe = try XCTUnwrap(draft.recipes.firstIndex { $0.key == "Salad" })
        draft.recipes[recipe].unlocked = true
        let pair = try await SaveWorkService().render(original: SavePairData(main: data, info: nil),
            originalDraft: parsed.draft, draft: draft, items: catalog, recipes: recipes)
        let after = try SaveParser.parse(mainData: pair.main, infoData: nil, catalog: catalog, recipeCatalog: recipes)
        XCTAssertEqual(after.draft.backpackCapacity, 36)
        XCTAssertEqual(after.draft.inventory[35].item?.stack, 50)
        XCTAssertEqual(after.draft.equipment[0].fields[0].value, 4)
        XCTAssertTrue(try XCTUnwrap(after.draft.recipes.first { $0.key == "Salad" }).unlocked)
    }

    @MainActor
    func testBackgroundRenderRejectsUnappliedEdit() async throws {
        let parsed = try parse()
        let data = Data(parsed.mainRoot.xmlString().utf8)
        var draft = parsed.draft; draft.favoriteThing = "Tea"
        do {
            _ = try await SaveWorkService().render(original: SavePairData(main: data, info: nil),
                originalDraft: parsed.draft, draft: draft, items: ItemCatalog.load(), recipes: recipes)
            XCTFail("A missing field must not silently lose the reviewed edit")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("写回验证"))
        }
        XCTAssertNil(parsed.mainRoot.child(named: "player")?.child(named: "favoriteThing"))
    }
}
