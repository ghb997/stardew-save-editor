import XCTest
@testable import PelicanSaveEditor

final class ExpandedEditorTests: XCTestCase {
    private func parse(_ xml: String = ExpandedEditorFixture.xml) throws -> ParsedSaveDocument {
        try SaveParser.parse(mainData: Data(xml.utf8), infoData: Data(ExpandedEditorFixture.info.utf8),
                             catalog: ItemCatalog.load(), recipeCatalog: [:])
    }
    private func rendered(_ parsed: ParsedSaveDocument, _ draft: SaveDraft) throws -> ParsedSaveDocument {
        let pair = try SaveMutator.render(parsed: parsed, draft: draft)
        return try SaveParser.parse(mainData: pair.mainData, infoData: pair.infoData, catalog: ItemCatalog.load(), recipeCatalog: [:])
    }

    func testDiscoversFarmNestedShedAndFridgeWithoutTreatingFurnitureAsChest() throws {
        let parsed = try parse()
        XCTAssertEqual(parsed.draft.storages.map(\.location), ["Farm", "Shed_abc", "FarmHouse"])
        XCTAssertEqual(parsed.draft.storages.map(\.slots.count), [36, 36, 36])
        XCTAssertEqual(parsed.draft.storages.map(\.serializedCount), [2, 2, 1])
        XCTAssertTrue(parsed.draft.storages.allSatisfy(\.isEditable))
        XCTAssertEqual(Set(parsed.draft.storages.map(\.id)).count, 3)
    }

    func testChestQuantityPreservesQualitySpellingMetadataOtherContainersAndSummary() throws {
        let parsed = try parse()
        var draft = parsed.draft
        draft.storages[0].slots[0].item?.stack = 25
        let result = try rendered(parsed, draft)
        XCTAssertEqual(result.draft.storages[0].slots[0].item?.stack, 25)
        let path = draft.storages[0].path
        let node = try XCTUnwrap(path.resolve(in: result.mainRoot))
        let item = try XCTUnwrap(node.child(named: "items")?.children(named: "Item").first)
        XCTAssertEqual(item.value(named: "quality"), "00")
        XCTAssertEqual(item.attributes["keep"], "item")
        XCTAssertEqual(item.child(named: "modData")?.xmlString(), "<modData><keep>unchanged</keep></modData>")
        XCTAssertEqual(node.child(named: "playerChoiceColor")?.xmlString(), path.resolve(in: parsed.mainRoot)?.child(named: "playerChoiceColor")?.xmlString())
        for other in draft.storages.dropFirst() { XCTAssertEqual(other.path.resolve(in: result.mainRoot)?.xmlString(), other.path.resolve(in: parsed.mainRoot)?.xmlString()) }
        XCTAssertEqual(result.infoRoot?.xmlString(), parsed.infoRoot?.xmlString())
    }

    func testAddingAtLastChestSlotPreservesOpaqueChildrenAndClearingKeepsSerializedFloor() throws {
        let parsed = try parse()
        var draft = parsed.draft
        let wood = try XCTUnwrap(try ItemCatalog.load().first { $0.id == "388" })
        draft.storages[0].slots[35].item = wood.makeInventoryItem()
        draft.storages[0].slots[35].item?.stack = 999
        draft.storages[0].slots[0].item = nil
        let result = try rendered(parsed, draft)
        XCTAssertEqual(result.draft.storages[0].serializedCount, 36)
        XCTAssertEqual(result.draft.storages[0].slots[35].item?.stack, 999)
        XCTAssertNil(result.draft.storages[0].slots[0].item)
        let items = result.draft.storages[0].path.resolve(in: result.mainRoot)?.child(named: "items")
        XCTAssertEqual(items?.value(named: "opaque"), "keep")
        XCTAssertEqual(items?.attributes["keep"], "slots")
    }

    func testBigChestSeventySlotsAndOrdinaryFridgeSupported() throws {
        let xml = ExpandedEditorFixture.xml.replacingOccurrences(of: "<itemId>130</itemId>", with: "<itemId>BigChest</itemId>")
            .replacingOccurrences(of: "<specialChestType>None</specialChestType>", with: "<specialChestType>BigChest</specialChestType>")
        let parsed = try parse(xml)
        XCTAssertEqual(parsed.draft.storages.map(\.capacity), [70, 70, 36])
        var draft = parsed.draft
        draft.storages[2].slots[0].item?.quality = 2
        let result = try rendered(parsed, draft)
        XCTAssertEqual(result.draft.storages[2].slots[0].item?.quality, 2)
        XCTAssertEqual(result.draft.storages[2].slots[0].item?.stack, 5)
    }

    func testSharedSpecialAndOversizedChestsRemainReadOnly() throws {
        for replacement in [
            ExpandedEditorFixture.chest.replacingOccurrences(of: "<globalInventoryId/>", with: "<globalInventoryId>Junimo</globalInventoryId>"),
            ExpandedEditorFixture.chest.replacingOccurrences(of: "<specialChestType>None</specialChestType>", with: "<specialChestType>JunimoChest</specialChestType>"),
            ExpandedEditorFixture.chest.replacingOccurrences(of: "<items keep=\"slots\">", with: "<items keep=\"slots\">" + String(repeating: "<Item xsi:nil=\"true\"/>", count: 40))
        ] {
            let parsed = try parse(ExpandedEditorFixture.xml.replacingOccurrences(of: ExpandedEditorFixture.chest, with: replacement))
            XCTAssertFalse(parsed.draft.storages[0].isEditable)
            var draft = parsed.draft
            draft.storages[0].slots[0].item = nil
            if draft.storages[0] == parsed.draft.storages[0] { draft.storages[0].slots[0].item = try ItemCatalog.load()[0].makeInventoryItem() }
            XCTAssertThrowsError(try SaveMutator.render(parsed: parsed, draft: draft))
        }
    }

    func testUnknownQuestAndMalformedItemsCannotBeEditedOrCleared() throws {
        for replacement in [
            ExpandedEditorFixture.item.replacingOccurrences(of: "xsi:type=\"Object\"", with: "xsi:type=\"Mod.Tool\""),
            ExpandedEditorFixture.item.replacingOccurrences(of: "<questItem>false</questItem>", with: "<questItem>true</questItem>"),
            ExpandedEditorFixture.item.replacingOccurrences(of: "<stack>0005</stack>", with: "<stack><value>5</value></stack>"),
            ExpandedEditorFixture.item.replacingOccurrences(of: "<quality>00</quality>", with: "<quality>0</quality><quality>1</quality>")
        ] {
            let parsed = try parse(ExpandedEditorFixture.xml.replacingOccurrences(of: ExpandedEditorFixture.item, with: replacement))
            XCTAssertFalse(try XCTUnwrap(parsed.draft.storages[0].slots[0].item).isEditable)
            var draft = parsed.draft; draft.storages[0].slots[0].item = nil
            XCTAssertThrowsError(try SaveMutator.render(parsed: parsed, draft: draft))
            draft = parsed.draft; draft.money += 1
            let result = try rendered(parsed, draft)
            XCTAssertEqual(result.draft.storages[0].slots[0].item?.templateXML, parsed.draft.storages[0].slots[0].item?.templateXML)
        }
    }

    func testStorageWriteBoundaryRejectsSlotLayoutTemplateAndItemMetadataTampering() throws {
        let parsed = try parse()
        var bad = parsed.draft; bad.storages[0].slots.removeLast()
        XCTAssertThrowsError(try SaveMutator.render(parsed: parsed, draft: bad))
        bad = parsed.draft; bad.storages.removeFirst()
        XCTAssertThrowsError(try SaveMutator.render(parsed: parsed, draft: bad))
        bad = parsed.draft; bad.storages[0].slots[0].item?.itemID = "388"
        XCTAssertThrowsError(try SaveMutator.render(parsed: parsed, draft: bad))
        bad = parsed.draft; bad.storages[0].slots[0].item?.templateXML = "<Item/>"
        XCTAssertThrowsError(try SaveMutator.render(parsed: parsed, draft: bad))
        bad = parsed.draft; bad.storages[0].slots[0].item?.stack = 1000
        XCTAssertThrowsError(try SaveMutator.render(parsed: parsed, draft: bad))
        bad = parsed.draft; bad.storages[0].slots[0].item?.quality = 3
        XCTAssertThrowsError(try SaveMutator.render(parsed: parsed, draft: bad))
    }

    func testUnrelatedEditsDoNotSerializeSyntheticStorageSlotsOrNormalizeWeather() throws {
        let parsed = try parse()
        var draft = parsed.draft; draft.money = 2000
        let result = try rendered(parsed, draft)
        for storage in parsed.draft.storages {
            XCTAssertEqual(storage.path.resolve(in: result.mainRoot)?.xmlString(), storage.path.resolve(in: parsed.mainRoot)?.xmlString())
        }
        XCTAssertEqual(result.mainRoot.value(named: "dailyLuck"), "0.0250")
        XCTAssertEqual(result.mainRoot.child(named: "locationWeather")?.xmlString(), parsed.mainRoot.child(named: "locationWeather")?.xmlString())
    }

    func testDuplicateObjectCoordinatesCannotTargetTheWrongContainer() throws {
        let xml = ExpandedEditorFixture.xml.replacingOccurrences(of: "<X>20</X><Y>21</Y>", with: "<X>10</X><Y>12</Y>")
        let parsed = try parse(xml)
        XCTAssertEqual(parsed.draft.storages.count, 2)
        XCTAssertTrue(parsed.draft.machines.isEmpty)
    }

    func testTomorrowWeatherSynchronizesDefaultAliasesAndPreservesCurrentWeatherAndIsland() throws {
        let parsed = try parse()
        var draft = parsed.draft
        let index = try XCTUnwrap(draft.weatherAndLuck.regions.firstIndex { $0.id == "Default" })
        draft.weatherAndLuck.regions[index].selected = .sun
        let result = try rendered(parsed, draft)
        XCTAssertEqual(result.mainRoot.value(named: "weatherForTomorrow"), "Sun")
        XCTAssertEqual(result.draft.weatherAndLuck.regions.first { $0.id == "Default" }?.selected, .sun)
        XCTAssertEqual(result.draft.weatherAndLuck.regions.first { $0.id == "Island" }?.selected, .sun)
        XCTAssertEqual(result.mainRoot.child(named: "locationWeather")?.firstDescendant(named: "isRaining")?.text, "false")
        XCTAssertEqual(result.infoRoot?.value(named: "weatherForTomorrow"), "keep-summary")
    }

    func testLegacyNumericWeatherRetainsNumericEncodingAndLuckRange() throws {
        let parsed = try parse(ExpandedEditorFixture.xml.replacingOccurrences(of: "<weatherForTomorrow>Rain</weatherForTomorrow>", with: "<weatherForTomorrow>1</weatherForTomorrow>"))
        var draft = parsed.draft; draft.weatherAndLuck.regions[0].selected = .storm; draft.weatherAndLuck.dailyLuck = -0.1
        let result = try rendered(parsed, draft)
        XCTAssertEqual(result.mainRoot.value(named: "weatherForTomorrow"), "3")
        XCTAssertEqual(result.draft.weatherAndLuck.dailyLuck, -0.1)
        for value in [0.1001, -.infinity, .nan] {
            draft.weatherAndLuck.dailyLuck = value
            XCTAssertThrowsError(try SaveMutator.render(parsed: parsed, draft: draft))
        }
    }

    func testSpecialConflictingDuplicateAndMissingWeatherRemainsUnavailable() throws {
        for xml in [
            ExpandedEditorFixture.xml.replacingOccurrences(of: ">Rain<", with: ">GreenRain<"),
            ExpandedEditorFixture.xml.replacingOccurrences(of: "<weatherForTomorrow>Rain</weatherForTomorrow><dailyLuck>", with: "<weatherForTomorrow>Sun</weatherForTomorrow><dailyLuck>"),
            ExpandedEditorFixture.xml.replacingOccurrences(of: "<weatherForTomorrow>Rain</weatherForTomorrow><dailyLuck>", with: "<weatherForTomorrow>Rain</weatherForTomorrow><weatherForTomorrow>Rain</weatherForTomorrow><dailyLuck>"),
            ExpandedEditorFixture.xml.replacingOccurrences(of: "<LocationWeather><weatherForTomorrow>Rain</weatherForTomorrow>", with: "<LocationWeather>"),
            ExpandedEditorFixture.xml.replacingOccurrences(of: "<locationWeather>", with: "<locationWeather><item><key><string>Default</string></key><value><LocationWeather><weatherForTomorrow>Rain</weatherForTomorrow></LocationWeather></value></item>")
        ] {
            let parsed = try parse(xml)
            XCTAssertFalse(parsed.draft.weatherAndLuck.regions.contains { $0.id == "Default" })
            var draft = parsed.draft; draft.money += 1
            let result = try rendered(parsed, draft)
            XCTAssertEqual(result.mainRoot.children(named: "weatherForTomorrow").map { $0.xmlString() }, parsed.mainRoot.children(named: "weatherForTomorrow").map { $0.xmlString() })
        }
    }

    func testMissingLuckCannotBeInventedAndIslandRejectsSnow() throws {
        let parsed = try parse(ExpandedEditorFixture.xml.replacingOccurrences(of: "<dailyLuck>0.0250</dailyLuck>", with: "<dailyLuck xsi:nil=\"true\"/>"))
        XCTAssertNil(parsed.draft.weatherAndLuck.dailyLuck)
        var draft = parsed.draft; draft.weatherAndLuck.dailyLuck = 0.1
        XCTAssertThrowsError(try SaveMutator.render(parsed: parsed, draft: draft))
        draft = parsed.draft
        let island = try XCTUnwrap(draft.weatherAndLuck.regions.firstIndex { $0.id == "Island" })
        draft.weatherAndLuck.regions[island].selected = .snow
        XCTAssertThrowsError(try SaveMutator.render(parsed: parsed, draft: draft))
    }

    func testFinishingMachineKeepsOutputIdentityQuantityQualityAndMetadata() throws {
        let parsed = try parse()
        XCTAssertEqual(parsed.draft.machines.count, 1)
        var draft = parsed.draft; draft.machines[0].finish = true
        let result = try rendered(parsed, draft)
        let old = draft.machines[0].path.resolve(in: parsed.mainRoot)
        let node = draft.machines[0].path.resolve(in: result.mainRoot)
        XCTAssertEqual(node?.value(named: "minutesUntilReady"), "0")
        XCTAssertEqual(node?.value(named: "readyForHarvest"), "true")
        XCTAssertEqual(node?.child(named: "heldObject")?.xmlString(), old?.child(named: "heldObject")?.xmlString())
        XCTAssertEqual(node?.child(named: "modData")?.xmlString(), old?.child(named: "modData")?.xmlString())
        XCTAssertFalse(result.draft.machines[0].canFinish)
        XCTAssertFalse(result.draft.machines[0].finish)
    }

    func testUnknownEmptyCaskAndMalformedMachinesAreExcluded() throws {
        for machine in [
            ExpandedEditorFixture.machine.replacingOccurrences(of: "<itemId>12</itemId>", with: "<itemId>ModMachine</itemId>"),
            ExpandedEditorFixture.machine.replacingOccurrences(of: "<name>Keg</name>", with: "<name>Keg</name><readyForHarvest>false</readyForHarvest>"),
            ExpandedEditorFixture.machine.replacingOccurrences(of: "xsi:type=\"Object\" keep=\"machine\"", with: "xsi:type=\"Cask\" keep=\"machine\""),
            ExpandedEditorFixture.machine.replacingOccurrences(of: "<heldObject xsi:type=\"Object\">", with: "<heldObject xsi:nil=\"true\" xsi:type=\"Object\">")
        ] {
            let parsed = try parse(ExpandedEditorFixture.xml.replacingOccurrences(of: ExpandedEditorFixture.machine, with: machine))
            XCTAssertTrue(parsed.draft.machines.isEmpty)
        }
    }

    func testReadyMachineCannotBeFinishedAgainAndForgedMachineRejected() throws {
        let parsed = try parse(ExpandedEditorFixture.xml.replacingOccurrences(of: "<readyForHarvest>false</readyForHarvest>", with: "<readyForHarvest>true</readyForHarvest>"))
        var draft = parsed.draft; draft.machines[0].finish = true
        XCTAssertThrowsError(try SaveMutator.render(parsed: parsed, draft: draft))
        draft = parsed.draft; draft.machines.append(draft.machines[0])
        XCTAssertThrowsError(try SaveMutator.render(parsed: parsed, draft: draft))
    }

    func testBundlesReadDefinitionsProgressChoicesAndGoldWithoutChangingCompletion() throws {
        let parsed = try parse()
        XCTAssertEqual(parsed.draft.communityCenter.bundles.count, 2)
        let crop = try XCTUnwrap(parsed.draft.communityCenter.bundles.first { $0.id == "0" })
        XCTAssertEqual(crop.title, "春季作物")
        XCTAssertEqual(crop.requirements.map(\.itemID), ["24", "190"])
        XCTAssertFalse(crop.isComplete)
        XCTAssertTrue(try XCTUnwrap(parsed.draft.communityCenter.bundles.first { $0.id == "23" }).requirements[0].isGold)
        let choiceXML = ExpandedEditorFixture.xml.replacingOccurrences(of: "/0/2</string>", with: "/0/1</string>")
            .replacingOccurrences(of: "<boolean>false</boolean><boolean>false</boolean>", with: "<boolean>true</boolean><boolean>false</boolean>")
        let choice = try parse(choiceXML)
        XCTAssertTrue(try XCTUnwrap(choice.draft.communityCenter.bundles.first { $0.id == "0" }).isComplete)
    }

    func testUnreadableDuplicateAndMissingBundleStateNeverAssumedIncomplete() throws {
        for xml in [
            ExpandedEditorFixture.xml.replacingOccurrences(of: "<boolean>false</boolean><boolean>false</boolean>", with: "<boolean>unknown</boolean><boolean>false</boolean>"),
            ExpandedEditorFixture.xml.replacingOccurrences(of: "<int>0</int>", with: "<int>99</int>"),
            ExpandedEditorFixture.xml.replacingOccurrences(of: "Pantry/0", with: "Pantry/23"),
            ExpandedEditorFixture.xml.replacingOccurrences(of: "24 1 0 190 1 0", with: "24 1 0 190 invalid 0")
        ] {
            let parsed = try parse(xml)
            XCTAssertFalse(parsed.draft.communityCenter.bundles.contains { $0.id == "0" })
            XCTAssertGreaterThan(parsed.draft.communityCenter.unreadableCount, 0)
        }
    }

    func testBundleSupplyAddsExactMaterialsToEmptySlotsAndLeavesAllQuestStateUnchanged() throws {
        let parsed = try parse()
        var draft = parsed.draft
        let catalog = try ItemCatalog.load()
        let plan = try BundleSupplyRules.plan(ids: ["0:0", "0:1"], draft: draft, catalog: catalog)
        XCTAssertEqual(plan.map(\.slot), [1, 2])
        try BundleSupplyRules.apply(ids: ["0:0", "0:1"], to: &draft, catalog: catalog)
        XCTAssertEqual(draft.inventory[0], parsed.draft.inventory[0])
        XCTAssertEqual(draft.inventory[1].item?.itemID, "24")
        XCTAssertEqual(draft.inventory[2].item?.itemID, "190")
        XCTAssertEqual(draft.inventory[2].item?.stack, 1)
        let result = try rendered(parsed, draft)
        for field in ["bundleData", "bundles", "bundleRewards", "locations"] {
            XCTAssertEqual(result.mainRoot.child(named: field)?.xmlString(), parsed.mainRoot.child(named: field)?.xmlString())
        }
        XCTAssertEqual(result.draft.communityCenter, parsed.draft.communityCenter)
    }

    func testBundleSupplyInsufficientSpaceInvalidSelectionsAndJojaAreAtomicFailures() throws {
        let parsed = try parse(); let catalog = try ItemCatalog.load()
        var draft = parsed.draft
        for i in draft.inventory.indices where i > 1 { draft.inventory[i].item = catalog[0].makeInventoryItem() }
        let before = draft
        XCTAssertThrowsError(try BundleSupplyRules.apply(ids: ["0:0", "0:1"], to: &draft, catalog: catalog))
        XCTAssertEqual(draft, before)
        let selections: [Set<String>] = [["23:0"], ["missing"], []]
        for ids in selections {
            XCTAssertThrowsError(try BundleSupplyRules.apply(ids: ids, to: &draft, catalog: catalog))
            XCTAssertEqual(draft, before)
        }
        let joja = try parse(ExpandedEditorFixture.xml.replacingOccurrences(of: "opaqueFlag", with: "JojaMember"))
        draft = joja.draft
        XCTAssertThrowsError(try BundleSupplyRules.apply(ids: ["0:0"], to: &draft, catalog: catalog))
        XCTAssertEqual(draft, joja.draft)
    }

    func testExpandedDiffsGroupAndUndoIndependentlyIncludingMaterialSupply() throws {
        let parsed = try parse(); var draft = parsed.draft
        draft.storages[0].slots[0].item?.stack = 20
        draft.machines[0].finish = true
        draft.weatherAndLuck.regions[0].selected = .sun
        draft.weatherAndLuck.dailyLuck = 0.1
        try BundleSupplyRules.apply(ids: ["0:0"], to: &draft, catalog: ItemCatalog.load())
        let diffs = SaveDiffBuilder.build(original: parsed.draft, draft: draft)
        XCTAssertEqual(diffs.count, 5)
        XCTAssertEqual(SaveDiffBuilder.grouped(diffs).flatMap(\.diffs).count, 5)
        for diff in diffs {
            var single = draft
            SaveDiffBuilder.undo(diff, original: parsed.draft, draft: &single)
            XCTAssertEqual(SaveDiffBuilder.build(original: parsed.draft, draft: single).count, 4)
            XCTAssertNoThrow(try SaveMutator.validate(single, comparedTo: parsed.draft))
        }
        for diff in diffs { SaveDiffBuilder.undo(diff, original: parsed.draft, draft: &draft) }
        XCTAssertEqual(draft, parsed.draft)
    }

    func testZlibExpandedEditsRoundTripWithoutChangingOriginalTree() throws {
        let xml = Data(ExpandedEditorFixture.xml.utf8)
        let compressed = try SaveCodec.encode(xmlData: xml, encoding: .zlib, includeBOM: false)
        let parsed = try SaveParser.parse(mainData: compressed, infoData: nil, catalog: ItemCatalog.load(), recipeCatalog: [:])
        let originalXML = parsed.mainRoot.xmlString()
        var draft = parsed.draft; draft.storages[0].slots[0].item?.stack = 9; draft.machines[0].finish = true
        let result = try rendered(parsed, draft)
        XCTAssertEqual(result.mainPayload.encoding, .zlib)
        XCTAssertEqual(result.draft.storages[0].slots[0].item?.stack, 9)
        XCTAssertEqual(parsed.mainRoot.xmlString(), originalXML)
    }

    func testWorkerReparsePreservesUneditedStorageUUIDBaseline() async throws {
        let parsed = try parse()
        let pair = SavePairData(main: Data(ExpandedEditorFixture.xml.utf8), info: Data(ExpandedEditorFixture.info.utf8))
        var draft = parsed.draft; draft.money += 1
        let result = try await SaveWorkService().render(original: pair, originalDraft: parsed.draft, draft: draft,
                                                       items: ItemCatalog.load(), recipes: [:])
        let root = try XMLTreeParser().parse(SaveCodec.decode(result.main).xmlData)
        for storage in parsed.draft.storages {
            XCTAssertEqual(storage.path.resolve(in: root)?.xmlString(), storage.path.resolve(in: parsed.mainRoot)?.xmlString())
        }
    }
}
