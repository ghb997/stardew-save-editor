import XCTest
@testable import PelicanSaveEditor

final class ReferenceFeatureTests: XCTestCase {
    func testCapacityExpansionRoundTripsBothFilesAndPreservesOpaqueItems() throws {
        let tool = "<Item xsi:type=\"Axe\" custom=\"keep\"><name>Axe</name><upgradeLevel>4</upgradeLevel><stack>3000</stack><modData><value>untouched</value></modData></Item>"
        let parsed = try parse(items: tool + "<extension flag=\"keep\"/>")
        var draft = parsed.draft
        XCTAssertEqual(draft.inventory.count, 12)
        try draft.setBackpackCapacity(36)
        draft.inventory[35].item = try stone(stack: 99)
        let pair = try SaveMutator.render(parsed: parsed, draft: draft)
        let roundTrip = try SaveParser.parse(mainData: pair.mainData, infoData: pair.infoData, catalog: [], recipeCatalog: [:])
        XCTAssertEqual(roundTrip.draft.backpackCapacity, 36)
        XCTAssertEqual(roundTrip.draft.inventory.count, 36)
        XCTAssertEqual(roundTrip.draft.inventory[35].item?.stack, 99)
        XCTAssertEqual(roundTrip.infoRoot?.value(named: "maxItems"), "36")
        XCTAssertEqual(roundTrip.mainRoot.child(named: "player")?.child(named: "items")?.children.first?.xmlString(),
                       parsed.mainRoot.child(named: "player")?.child(named: "items")?.children.first?.xmlString())
        XCTAssertEqual(roundTrip.mainRoot.child(named: "player")?.child(named: "items")?.child(named: "extension")?.attributes["flag"], "keep")
    }

    func testUnrelatedEditDoesNotSerializeSyntheticEmptySlotsOrInventSummaryCapacity() throws {
        let parsed = try parse(infoCapacity: "")
        XCTAssertEqual(parsed.draft.inventory.count, 12)
        var draft = parsed.draft
        draft.money += 1
        let rendered = try SaveMutator.render(parsed: parsed, draft: draft)
        let root = try XMLTreeParser().parse(SaveCodec.decode(rendered.mainData).xmlData)
        XCTAssertEqual(root.child(named: "player")?.child(named: "items")?.children(named: "Item").count, 1)
        try draft.setBackpackCapacity(24)
        let expanded = try SaveMutator.render(parsed: parsed, draft: draft)
        let info = try XMLTreeParser().parse(SaveCodec.decode(XCTUnwrap(expanded.infoData)).xmlData)
        XCTAssertNil(info.child(named: "maxItems"))
    }

    func testShrinkWithOccupiedTailFailsWithoutChangingDraft() throws {
        let parsed = try parse(capacity: "<maxItems>36</maxItems>")
        var draft = parsed.draft
        draft.inventory[35].item = try stone()
        let before = draft
        XCTAssertThrowsError(try draft.setBackpackCapacity(12))
        XCTAssertEqual(draft, before)
        draft.inventory[0].item = draft.inventory[35].item
        draft.inventory[35].item = nil
        try draft.setBackpackCapacity(12)
        XCTAssertEqual(draft.inventory.count, 12)
        XCTAssertEqual(draft.inventory[0].item?.itemID, "390")
        XCTAssertNoThrow(try SaveMutator.render(parsed: parsed, draft: draft))
    }

    func testCapacityUndoRemovesNewSlotEditsAndKeepsOldSlotEdits() throws {
        let parsed = try parse()
        var draft = parsed.draft
        try draft.setBackpackCapacity(36)
        draft.inventory[0].item = try stone(stack: 10)
        draft.inventory[35].item = try stone(stack: 20)
        let capacityDiff = try XCTUnwrap(SaveDiffBuilder.build(original: parsed.draft, draft: draft).first { $0.id == "inventory.capacity" })
        SaveDiffBuilder.undo(capacityDiff, original: parsed.draft, draft: &draft)
        XCTAssertEqual(draft.backpackCapacity, 12)
        XCTAssertEqual(draft.inventory.count, 12)
        XCTAssertEqual(draft.inventory[0].item?.stack, 10)
        XCTAssertEqual(SaveDiffBuilder.build(original: parsed.draft, draft: draft).map(\.id), ["inventory.0"])
        XCTAssertNoThrow(try SaveMutator.render(parsed: parsed, draft: draft))
    }

    func testOriginalSerializedSlotsSurviveShrinkAndCannotReceiveNewHiddenItems() throws {
        let parsed = try parse(items: String(repeating: "<Item xsi:nil=\"true\"/>", count: 36))
        var draft = parsed.draft
        try draft.setBackpackCapacity(24)
        XCTAssertEqual(draft.inventory.count, 36)
        XCTAssertEqual(draft.usableInventoryCount, 24)
        XCTAssertFalse(draft.canUseInventorySlot(24))
        draft.inventory[24].item = try stone()
        XCTAssertThrowsError(try SaveMutator.render(parsed: parsed, draft: draft))
        draft.inventory[24].item = nil
        let root = try renderedRoot(parsed, draft: draft)
        XCTAssertEqual(root.child(named: "player")?.child(named: "items")?.children(named: "Item").count, 36)
    }

    func testMissingMalformedAndModdedCapacitiesRemainUnchanged() throws {
        for field in ["", "<maxItems>bad</maxItems>", "<maxItems>48</maxItems>", "<maxItems xsi:nil=\"true\">12</maxItems>"] {
            let parsed = try parse(capacity: field)
            var draft = parsed.draft
            XCTAssertFalse(draft.canResizeBackpack)
            XCTAssertThrowsError(try draft.setBackpackCapacity(36))
            draft.money += 1
            let root = try renderedRoot(parsed, draft: draft)
            XCTAssertEqual(root.child(named: "player")?.value(named: "maxItems"), parsed.mainRoot.child(named: "player")?.value(named: "maxItems"))
        }
    }

    func testWriteBoundaryRejectsInvalidCapacityAndSlotLayout() throws {
        let parsed = try parse()
        var draft = parsed.draft
        draft.backpackCapacity = 18
        XCTAssertThrowsError(try SaveMutator.render(parsed: parsed, draft: draft))
        draft.backpackCapacity = 36
        XCTAssertThrowsError(try SaveMutator.render(parsed: parsed, draft: draft))
        draft = parsed.draft
        draft.inventory.swapAt(0, 1)
        XCTAssertThrowsError(try SaveMutator.render(parsed: parsed, draft: draft))
    }

    func testScopedFullHeartsRespectsRelationshipsAndPreservesHigherAndUnknownPoints() throws {
        let friends = friendship("Abigail", points: 100) + friendship("Robin", points: 100)
            + friendship("Shane", points: 200, status: "Dating") + friendship("Leah", points: 200, status: "Married")
            + friendship("Emily", points: 200, status: "Engaged") + friendship("Haley", points: 200, status: "Divorced")
            + friendship("Linus", points: 4000) + friendship("ModNPC", points: 50)
        let parsed = try parse(friends: friends)
        var draft = parsed.draft
        XCTAssertEqual(draft.applyRelationshipBatch(.fillHearts, names: ["Abigail", "Shane", "Leah", "Emily", "Haley", "Linus", "ModNPC"]), 3)
        func points(_ name: String) -> Int? { draft.friendships.first { $0.name == name }?.points }
        XCTAssertEqual(points("Abigail"), 2000)
        XCTAssertEqual(points("Shane"), 2500)
        XCTAssertEqual(points("Leah"), 3500)
        XCTAssertEqual(points("Robin"), 100)
        XCTAssertEqual(points("Emily"), 200)
        XCTAssertEqual(points("Haley"), 200)
        XCTAssertEqual(points("Linus"), 4000)
        XCTAssertEqual(points("ModNPC"), 50)
        XCTAssertNoThrow(try SaveMutator.render(parsed: parsed, draft: draft))
        XCTAssertEqual(draft.friendships.map(\.status), parsed.draft.friendships.map(\.status))
    }

    func testGiftResetChangesOnlyExistingCountersAndEachDiffCanBeUndone() throws {
        let gifts = "<GiftsToday>1</GiftsToday><GiftsThisWeek>2</GiftsThisWeek><TalkedToToday>true</TalkedToToday><LastGiftDate><Year>2</Year><DayOfMonth>12</DayOfMonth></LastGiftDate>"
        let parsed = try parse(friends: friendship("Abigail", points: 1750, extra: gifts)
            + friendship("Robin", points: 100, extra: "<GiftsThisWeek>1</GiftsThisWeek>"))
        XCTAssertNoThrow(try SaveMutator.validate(parsed.draft))
        var draft = parsed.draft
        XCTAssertEqual(draft.applyRelationshipBatch(.resetGifts, names: ["Abigail"]), 1)
        let diffs = SaveDiffBuilder.build(original: parsed.draft, draft: draft)
        XCTAssertEqual(Set(diffs.map(\.id)), ["friendship.Abigail.giftsToday", "friendship.Abigail.giftsThisWeek"])
        XCTAssertTrue(diffs.allSatisfy { !$0.affectsSaveGameInfo })
        let root = try renderedRoot(parsed, draft: draft)
        let edited = try XCTUnwrap(friendNode("Abigail", root: root))
        XCTAssertEqual(edited.value(named: "GiftsToday"), "0")
        XCTAssertEqual(edited.value(named: "GiftsThisWeek"), "0")
        XCTAssertEqual(edited.value(named: "Points"), "1750")
        XCTAssertEqual(edited.value(named: "Status"), "Friendly")
        XCTAssertEqual(edited.child(named: "LastGiftDate")?.xmlString(), friendNode("Abigail", root: parsed.mainRoot)?.child(named: "LastGiftDate")?.xmlString())
        XCTAssertEqual(edited.value(named: "TalkedToToday"), "true")
        XCTAssertEqual(friendNode("Robin", root: root)?.xmlString(), friendNode("Robin", root: parsed.mainRoot)?.xmlString())
        for diff in diffs { SaveDiffBuilder.undo(diff, original: parsed.draft, draft: &draft) }
        XCTAssertEqual(draft, parsed.draft)
    }

    func testMissingGiftFieldsAreNotCreatedAndMalformedValuesArePreserved() throws {
        let parsed = try parse(friends: friendship("Abigail", points: 50, extra: "<GiftsToday>bad</GiftsToday><GiftsThisWeek>-5</GiftsThisWeek>"))
        var draft = parsed.draft
        XCTAssertEqual(draft.applyRelationshipBatch(.resetGifts, names: ["Abigail"]), 0)
        XCTAssertTrue(SaveDiffBuilder.build(original: parsed.draft, draft: draft).isEmpty)
        draft.friendships[0].points = 250
        let node = try XCTUnwrap(friendNode("Abigail", root: renderedRoot(parsed, draft: draft)))
        XCTAssertEqual(node.value(named: "GiftsToday"), "bad")
        XCTAssertEqual(node.value(named: "GiftsThisWeek"), "-5")
        draft.friendships[0].giftsToday = 0
        XCTAssertThrowsError(try SaveMutator.render(parsed: parsed, draft: draft))
        let nullable = try parse(friends: friendship("Abigail", points: 50,
            extra: "<GiftsToday xsi:nil=\"true\">1</GiftsToday><GiftsThisWeek xsi:nil=\"1\">2</GiftsThisWeek>"))
        var nullableDraft = nullable.draft
        XCTAssertEqual(nullableDraft.applyRelationshipBatch(.resetGifts, names: ["Abigail"]), 0)
        XCTAssertEqual(nullableDraft, nullable.draft)
    }

    func testUneditedFriendshipXMLIsNotNormalizedWhenAnotherFriendChanges() throws {
        let parsed = try parse(friends: friendship("Abigail", points: 100)
            + "<item><key><string>Robin</string></key><value><Friendship><Points>00100</Points><Status>Friendly</Status><future keep=\"yes\"/></Friendship></value></item>")
        var draft = parsed.draft
        draft.applyRelationshipBatch(.fillHearts, names: ["Abigail"])
        let root = try renderedRoot(parsed, draft: draft)
        XCTAssertEqual(friendNode("Robin", root: root)?.xmlString(), friendNode("Robin", root: parsed.mainRoot)?.xmlString())
    }

    func testRelationshipWriteBoundaryRejectsUnsupportedStatusAndFriendshipLimits() throws {
        let parsed = try parse(friends: friendship("Abigail", points: 100) + friendship("Robin", points: 100))
        var draft = parsed.draft
        let abigail = try XCTUnwrap(draft.friendships.firstIndex { $0.name == "Abigail" })
        draft.friendships[abigail].points = 2500
        XCTAssertThrowsError(try SaveMutator.render(parsed: parsed, draft: draft))
        draft.friendships[abigail].status = .dating
        XCTAssertNoThrow(try SaveMutator.render(parsed: parsed, draft: draft))
        draft.friendships[abigail].status = .married
        XCTAssertThrowsError(try SaveMutator.render(parsed: parsed, draft: draft))
        draft = parsed.draft
        let robin = try XCTUnwrap(draft.friendships.firstIndex { $0.name == "Robin" })
        draft.friendships[robin].status = .dating
        XCTAssertThrowsError(try SaveMutator.render(parsed: parsed, draft: draft))
    }

    func testRelationshipFiltersReflectGiftResetAndUndo() throws {
        let parsed = try parse(friends: friendship("Abigail", points: 100, extra: "<GiftsThisWeek>2</GiftsThisWeek>"))
        var draft = parsed.draft
        let old = draft.friendships[0]
        XCTAssertTrue(RelationshipFilter.dateable.includes(old, original: old))
        XCTAssertTrue(RelationshipFilter.gifting.includes(old, original: old))
        XCTAssertFalse(RelationshipFilter.edited.includes(old, original: old))
        draft.applyRelationshipBatch(.resetGifts, names: ["Abigail"])
        XCTAssertFalse(RelationshipFilter.gifting.includes(draft.friendships[0], original: old))
        XCTAssertTrue(RelationshipFilter.edited.includes(draft.friendships[0], original: old))
        for diff in SaveDiffBuilder.build(original: parsed.draft, draft: draft) {
            SaveDiffBuilder.undo(diff, original: parsed.draft, draft: &draft)
        }
        XCTAssertFalse(RelationshipFilter.edited.includes(draft.friendships[0], original: old))
    }

    func testMissingPointsAndStatusStayReadOnly() throws {
        let parsed = try parse(friends: "<item><key><string>Abigail</string></key><value><Friendship><GiftsThisWeek>1</GiftsThisWeek></Friendship></value></item>")
        var draft = parsed.draft
        XCTAssertFalse(draft.friendships[0].hasEditablePoints)
        XCTAssertFalse(draft.friendships[0].canEditStatus)
        XCTAssertEqual(draft.applyRelationshipBatch(.fillHearts, names: ["Abigail"]), 0)
        XCTAssertEqual(draft.applyRelationshipBatch(.resetGifts, names: ["Abigail"]), 1)
        let root = try renderedRoot(parsed, draft: draft)
        XCTAssertNil(friendNode("Abigail", root: root)?.child(named: "Points"))
        XCTAssertNil(friendNode("Abigail", root: root)?.child(named: "Status"))
    }

    private func parse(capacity: String = "<maxItems>12</maxItems>", items: String = "<Item xsi:nil=\"true\"/>", friends: String = "", infoCapacity: String = "<maxItems>12</maxItems>") throws -> ParsedSaveDocument {
        let main = """
        <SaveGame xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"><player>
        <name>Test</name><farmName>Farm</farmName><favoriteThing>Tea</favoriteThing><uniqueMultiplayerID>123</uniqueMultiplayerID>
        <money>10</money><maxHealth>100</maxHealth><maxStamina>270</maxStamina>
        \(capacity)<items>\(items)</items><friendshipData>\(friends)</friendshipData><cookingRecipes/><craftingRecipes/>
        </player><year>1</year><currentSeason>spring</currentSeason><dayOfMonth>1</dayOfMonth><gameVersion>1.6.8</gameVersion></SaveGame>
        """
        let info = "<Farmer><uniqueMultiplayerID>123</uniqueMultiplayerID><name>Test</name><money>10</money>\(infoCapacity)</Farmer>"
        return try SaveParser.parse(mainData: Data(main.utf8), infoData: Data(info.utf8), catalog: [], recipeCatalog: [:])
    }

    private func renderedRoot(_ parsed: ParsedSaveDocument, draft: SaveDraft) throws -> XMLNode {
        let pair = try SaveMutator.render(parsed: parsed, draft: draft)
        return try XMLTreeParser().parse(SaveCodec.decode(pair.mainData).xmlData)
    }

    private func friendship(_ name: String, points: Int, status: String = "Friendly", extra: String = "") -> String {
        "<item><key><string>\(name)</string></key><value><Friendship><Points>\(points)</Points><Status>\(status)</Status>\(extra)</Friendship></value></item>"
    }

    private func friendNode(_ name: String, root: XMLNode) -> XMLNode? {
        root.child(named: "player")?.child(named: "friendshipData")?.children.first {
            $0.child(named: "key")?.value(named: "string") == name
        }?.child(named: "value")?.child(named: "Friendship")
    }

    private func stone(stack: Int = 1) throws -> InventoryItemDraft {
        // Exercise the same canonical template offered by the production picker.
        try XCTUnwrap(try ItemCatalog.load().first { $0.id == "390" }).makeInventoryItem(stack: stack)
    }
}
