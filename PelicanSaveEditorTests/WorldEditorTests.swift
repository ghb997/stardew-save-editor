import XCTest
@testable import PelicanSaveEditor

final class WorldEditorTests: XCTestCase {
    func testColorChannelsAndPackedValueRoundTripWithoutLosingMetadata() throws {
        let old = FarmerColor(red: 10, green: 20, blue: 30, alpha: 128)
        let colors = colorXML(.hair, old, packed: true, extra: "<custom keep=\"yes\">opaque</custom>")
        let parsed = try parse(colors: colors, infoColors: colors)
        XCTAssertEqual(parsed.draft.appearanceColors[.hair], old)
        var draft = parsed.draft
        draft.appearanceColors[.hair] = FarmerColor(red: 171, green: 205, blue: 239, alpha: 128)
        let pair = try SaveMutator.render(parsed: parsed, draft: draft)
        let result = try SaveParser.parse(mainData: pair.mainData, infoData: pair.infoData, catalog: [], recipeCatalog: [:])
        XCTAssertEqual(result.draft.appearanceColors[.hair]?.hex, "#ABCDEF")
        for player in [try XCTUnwrap(result.mainRoot.child(named: "player")), try XCTUnwrap(result.infoRoot)] {
            let node = try XCTUnwrap(player.child(named: "hairstyleColor"))
            XCTAssertEqual(node.value(named: "R"), "171")
            XCTAssertEqual(node.value(named: "A"), "128")
            XCTAssertEqual(node.value(named: "PackedValue"), String(0x80EFCDAB as UInt32))
            XCTAssertEqual(node.child(named: "custom")?.xmlString(), "<custom keep=\"yes\">opaque</custom>")
            XCTAssertEqual(node.attributes["keep"], "yes")
        }
    }

    func testPackedOnlyColorsPreserveRepresentationAndSummaryAlpha() throws {
        let parsed = try parse(colors: "<eyeColor><PackedValue>4278387201</PackedValue></eyeColor>",
                               infoColors: "<eyeColor><PackedValue>1073938945</PackedValue></eyeColor>")
        XCTAssertEqual(parsed.draft.appearanceColors[.eyes], FarmerColor(red: 1, green: 2, blue: 3))
        var draft = parsed.draft
        draft.appearanceColors[.eyes] = FarmerColor(red: 4, green: 5, blue: 6)
        let pair = try SaveMutator.render(parsed: parsed, draft: draft)
        let main = try root(pair.mainData)
        let info = try root(XCTUnwrap(pair.infoData))
        let mainColor = try XCTUnwrap(main.child(named: "player")?.child(named: "eyeColor"))
        XCTAssertEqual(mainColor.children.map(\.name), ["PackedValue"])
        XCTAssertEqual(mainColor.value(named: "PackedValue"), String(0xFF060504 as UInt32))
        XCTAssertEqual(AppearanceColorCodec.read(.eyes, from: info)?.alpha, 64)
        XCTAssertEqual(AppearanceColorCodec.read(.eyes, from: info)?.hex, "#040506")
    }

    func testInvalidOrMissingColorsStayReadOnlyAndUnchanged() throws {
        let invalid = [
            "", "<hairstyleColor xsi:nil=\"1\"><R>1</R><G>2</G><B>3</B><A>255</A></hairstyleColor>",
            "<hairstyleColor><R>1</R><G>2</G><B>3</B></hairstyleColor>",
            "<hairstyleColor><PackedValue>-1</PackedValue></hairstyleColor>",
            "<hairstyleColor><PackedValue>4294967296</PackedValue></hairstyleColor>",
            "<hairstyleColor><PackedValue>1</PackedValue><PackedValue>2</PackedValue></hairstyleColor>",
            "<hairstyleColor><R>1</R><R>2</R><G>2</G><B>3</B><A>255</A></hairstyleColor>",
            "<hairstyleColor><R xsi:nil=\"true\">1</R><G>2</G><B>3</B><A>255</A></hairstyleColor>",
            "<hairstyleColor><R><int>1</int></R><G>2</G><B>3</B><A>255</A></hairstyleColor>",
            "<hairstyleColor><R>256</R><G>2</G><B>3</B><A>255</A></hairstyleColor>",
            "<hairstyleColor><R>1</R><G>2</G><B>3</B><A>255</A><PackedValue>0</PackedValue></hairstyleColor>",
            "<hairstyleColor><PackedValue>1</PackedValue></hairstyleColor><hairstyleColor><PackedValue>1</PackedValue></hairstyleColor>"
        ]
        for colors in invalid {
            let parsed = try parse(colors: colors)
            XCTAssertNil(parsed.draft.appearanceColors[.hair], colors)
            var draft = parsed.draft
            draft.money += 1
            let result = try renderedRoot(parsed, draft)
            XCTAssertEqual(result.child(named: "player")?.children(named: "hairstyleColor").map { $0.xmlString() },
                           parsed.mainRoot.child(named: "player")?.children(named: "hairstyleColor").map { $0.xmlString() })
        }
    }

    func testColorChangeDoesNotInventOrRepairSummaryFields() throws {
        for summary in ["", "<hairstyleColor xsi:nil=\"true\"/>", "<hairstyleColor><R>bad</R></hairstyleColor>"] {
            let parsed = try parse(colors: colorXML(.hair, FarmerColor(red: 1, green: 2, blue: 3)), infoColors: summary)
            var draft = parsed.draft
            draft.appearanceColors[.hair] = FarmerColor(red: 50, green: 60, blue: 70)
            let pair = try SaveMutator.render(parsed: parsed, draft: draft)
            XCTAssertEqual(try root(XCTUnwrap(pair.infoData)).xmlString(), parsed.infoRoot?.xmlString())
        }
    }

    func testColorWriteBoundaryRejectsMissingAddedInvalidAndAlphaChanges() throws {
        let parsed = try parse(colors: colorXML(.hair, FarmerColor(red: 1, green: 2, blue: 3)))
        for replacement in [FarmerColor(red: -1, green: 2, blue: 3), FarmerColor(red: 1, green: 2, blue: 256),
                            FarmerColor(red: 1, green: 2, blue: 3, alpha: 0)] {
            var draft = parsed.draft
            draft.appearanceColors[.hair] = replacement
            XCTAssertThrowsError(try SaveMutator.render(parsed: parsed, draft: draft))
        }
        var draft = parsed.draft
        draft.appearanceColors.removeAll()
        XCTAssertThrowsError(try SaveMutator.render(parsed: parsed, draft: draft))
        draft = parsed.draft
        draft.appearanceColors[.pants] = FarmerColor(red: 0, green: 0, blue: 0)
        XCTAssertThrowsError(try SaveMutator.render(parsed: parsed, draft: draft))
    }

    func testColorDiffUndoRestoresOneFieldAndKeepsOtherDraftChanges() throws {
        let parsed = try parse(colors: colorXML(.hair, FarmerColor(red: 1, green: 2, blue: 3))
            + colorXML(.eyes, FarmerColor(red: 4, green: 5, blue: 6)))
        var draft = parsed.draft
        draft.appearanceColors[.hair] = FarmerColor(hex: "ABCDEF")
        draft.appearanceColors[.eyes] = FarmerColor(hex: "123456")
        draft.money += 1
        let diffs = SaveDiffBuilder.build(original: parsed.draft, draft: draft)
        let hair = try XCTUnwrap(diffs.first { $0.id == "appearance.color.hairstyleColor" })
        SaveDiffBuilder.undo(hair, original: parsed.draft, draft: &draft)
        XCTAssertEqual(draft.appearanceColors[.hair], parsed.draft.appearanceColors[.hair])
        XCTAssertEqual(draft.appearanceColors[.eyes]?.hex, "#123456")
        XCTAssertEqual(draft.money, 11)
        XCTAssertNoThrow(try SaveMutator.render(parsed: parsed, draft: draft))
    }

    func testHexColorValidationAcceptsSixDigitsOnly() {
        XCTAssertEqual(FarmerColor(hex: " #a1B2c3 \n")?.hex, "#A1B2C3")
        for invalid in ["FFF", "#12345678", "#12GG56", "0x123456", "１２３４５６", "", "12 456"] {
            XCTAssertNil(FarmerColor(hex: invalid), invalid)
        }
    }

    func testRoomBatchChangesSelectedRoomsOfSameSurfaceKindOnly() throws {
        let parsed = try parse(house: houseFields())
        var house = parsed.draft.farmhouse
        let source = try XCTUnwrap(house.decorations.first { $0.kind == .wallpaper && $0.roomKey == "Bedroom" })
        XCTAssertEqual(RoomStyleRules.targets(in: house, source: source, rooms: ["Bedroom", "Kitchen"]).map(\.roomKey), ["Kitchen"])
        house.applyStyle(from: source, rooms: ["Bedroom", "Kitchen"])
        for room in house.decorations {
            let old = try XCTUnwrap(parsed.draft.farmhouse.decorations.first { $0.id == room.id })
            XCTAssertEqual(room.styleIndex, room.roomKey == "Kitchen" && room.kind == .wallpaper ? source.styleIndex : old.styleIndex)
        }
        var draft = parsed.draft
        draft.farmhouse = house
        let roundTrip = try SaveParser.parse(mainData: SaveMutator.render(parsed: parsed, draft: draft).mainData, infoData: nil, catalog: [], recipeCatalog: [:])
        XCTAssertEqual(roundTrip.draft.farmhouse, house)
    }

    func testRoomRestoreKeepsOtherRoomsAndUpgradeDraft() throws {
        let parsed = try parse(house: houseFields())
        var draft = parsed.draft
        for index in draft.farmhouse.decorations.indices { draft.farmhouse.decorations[index].styleIndex = 9 }
        draft.farmhouse.upgradeLevel = 3
        draft.farmhouse.restoreRoom("Bedroom", from: parsed.draft.farmhouse)
        for room in draft.farmhouse.decorations {
            let old = try XCTUnwrap(parsed.draft.farmhouse.decorations.first { $0.id == room.id })
            XCTAssertEqual(room.styleIndex, room.roomKey == "Bedroom" ? old.styleIndex : 9)
        }
        XCTAssertEqual(draft.farmhouse.upgradeLevel, 3)
        XCTAssertNoThrow(try SaveMutator.render(parsed: parsed, draft: draft))
    }

    func testRoomEditPreservesUntouchedLexicalValuesAndFurniture() throws {
        let parsed = try parse(house: houseFields() + "<furniture><Furniture opaque=\"yes\"><heldObject>keep</heldObject></Furniture></furniture>")
        var draft = parsed.draft
        let index = try XCTUnwrap(draft.farmhouse.decorations.firstIndex { $0.roomKey == "Kitchen" && $0.kind == .flooring })
        draft.farmhouse.decorations[index].styleIndex = 5
        let before = try XCTUnwrap(location("FarmHouse", in: parsed.mainRoot))
        let after = try XCTUnwrap(location("FarmHouse", in: renderedRoot(parsed, draft)))
        XCTAssertEqual(before.child(named: "appliedWallpaper")?.xmlString(), after.child(named: "appliedWallpaper")?.xmlString())
        XCTAssertEqual(before.child(named: "furniture")?.xmlString(), after.child(named: "furniture")?.xmlString())
        let bedroom = after.child(named: "appliedFloor")?.firstDescendant(named: "item")
        XCTAssertEqual(bedroom?.child(named: "value")?.value(named: "string"), "0018")
    }

    func testNilUnknownAndAmbiguousRoomFieldsStayReadOnly() throws {
        let invalidFields = [
            "<appliedWallpaper xsi:nil=\"1\">7</appliedWallpaper>",
            "<appliedWallpaper><item><key><string>Bedroom</string></key><value xsi:nil=\"1\"><string>7</string></value></item></appliedWallpaper>",
            "<appliedWallpaper><item><key><string>Bedroom</string></key><value><string xsi:nil=\"true\">7</string></value></item></appliedWallpaper>",
            "<appliedWallpaper><item><key><string>Bedroom</string></key><value><unknown><string>7</string></unknown></value></item></appliedWallpaper>",
            "<appliedWallpaper><item><key><string>Bedroom</string></key><value><string>7</string><string>8</string></value></item></appliedWallpaper>",
            "<appliedWallpaper>\(roomEntry("Bedroom", "7"))\(roomEntry("Bedroom", "bad"))</appliedWallpaper>",
            "<appliedWallpaper>7</appliedWallpaper><appliedWallpaper>8</appliedWallpaper>"
        ]
        for house in invalidFields {
            let parsed = try parse(house: house, upgrade: "<houseUpgradeLevel xsi:nil=\"1\">2</houseUpgradeLevel>")
            XCTAssertTrue(parsed.draft.farmhouse.decorations.isEmpty, house)
            XCTAssertNil(parsed.draft.farmhouse.upgradeLevel)
            var draft = parsed.draft
            draft.money += 1
            XCTAssertEqual(location("FarmHouse", in: try renderedRoot(parsed, draft))?.xmlString(),
                           location("FarmHouse", in: parsed.mainRoot)?.xmlString())
        }
    }

    func testRoomWriteBoundaryRejectsAddedRemovedOrRelocatedSurfaces() throws {
        let parsed = try parse(house: houseFields())
        var draft = parsed.draft
        draft.farmhouse.decorations.removeLast()
        XCTAssertThrowsError(try SaveMutator.render(parsed: parsed, draft: draft))
        draft = parsed.draft
        draft.farmhouse.decorations.append(draft.farmhouse.decorations[0])
        XCTAssertThrowsError(try SaveMutator.render(parsed: parsed, draft: draft))
        draft = parsed.draft
        let surface = draft.farmhouse.decorations[0]
        draft.farmhouse.decorations[0] = RoomDecorationDraft(id: surface.id, kind: surface.kind, roomKey: "Unknown",
            storage: surface.storage, styleIndex: surface.styleIndex)
        XCTAssertThrowsError(try SaveMutator.render(parsed: parsed, draft: draft))
        draft = parsed.draft
        draft.farmhouse.upgradeLevel = nil
        XCTAssertThrowsError(try SaveMutator.render(parsed: parsed, draft: draft))
    }

    func testRoomSearchAndStyleLibraryCoverKnownRanges() throws {
        let house = try parse(house: houseFields()).draft.farmhouse
        XCTAssertEqual(RoomStyleRules.matchingRooms(in: house, query: " bedroom "), ["Bedroom"])
        XCTAssertTrue(RoomStyleRules.matchingRooms(in: house, query: "不存在").isEmpty)
        XCTAssertEqual(RoomStyleRules.standardStyles(for: .wallpaper).count, 112)
        XCTAssertEqual(RoomStyleRules.standardStyles(for: .flooring).last, 55)
        XCTAssertEqual(RoomStyleRules.standardStyles(for: .wallpaper, query: "111"), [111])
        XCTAssertTrue(RoomStyleRules.standardStyles(for: .flooring, query: "111").isEmpty)
    }

    func testSingleCropWateringChangesExactCoordinateOnly() throws {
        let parsed = try parse(terrain: crop(x: 14) + crop(x: 16))
        var draft = parsed.draft
        draft.farmActions.cropWateringKeys = ["crop:14:29"]
        XCTAssertTrue(draft.farmActions.hasChanges)
        let after = try renderedRoot(parsed, draft)
        XCTAssertEqual(feature(x: 14, in: after)?.value(named: "state"), "1")
        XCTAssertEqual(feature(x: 16, in: after)?.xmlString(), feature(x: 16, in: parsed.mainRoot)?.xmlString())
        XCTAssertEqual(feature(x: 14, in: after)?.child(named: "crop")?.xmlString(),
                       feature(x: 14, in: parsed.mainRoot)?.child(named: "crop")?.xmlString())
    }

    func testWateringPreservesWetDeadCustomNullableAndMissingStates() throws {
        let terrain = crop(x: 1) + crop(x: 2, state: "<state>1</state>")
            + crop(x: 3, dead: "true") + crop(x: 4, dead: "1")
            + crop(x: 5, state: "") + crop(x: 6, state: "<state xsi:nil=\"1\">0</state>")
            + crop(x: 7, type: "ModHoeDirt") + crop(x: 8, state: "<netState>0</netState>")
            + crop(x: 9, state: "<state>0</state><state>1</state>")
        let parsed = try parse(terrain: terrain, extraLocations: "<GameLocation xsi:type=\"Greenhouse\"><name>Greenhouse</name><terrainFeatures>\(crop(x: 1))</terrainFeatures></GameLocation>")
        let snapshot = FarmSnapshotExtractor.extract(from: parsed.mainRoot, cropCatalog: [])
        XCTAssertEqual(snapshot.unwateredCropCount, 2)
        var draft = parsed.draft
        draft.farmActions.waterAllCrops = true
        let after = try renderedRoot(parsed, draft)
        XCTAssertEqual(feature(x: 1, in: after)?.value(named: "state"), "1")
        XCTAssertEqual(feature(x: 8, in: after)?.value(named: "netState"), "1")
        XCTAssertNil(feature(x: 8, in: after)?.child(named: "state"))
        for x in [2, 3, 4, 5, 6, 7, 9] {
            XCTAssertEqual(feature(x: x, in: after)?.xmlString(), feature(x: x, in: parsed.mainRoot)?.xmlString(), "tile \(x)")
        }
        XCTAssertEqual(location("Greenhouse", in: after)?.xmlString(), location("Greenhouse", in: parsed.mainRoot)?.xmlString())
    }

    func testMapRegionFiltersBothActionsAndUndoKeepsOtherSelections() throws {
        let objects = object(x: 14, id: "343") + object(x: 40, id: "313")
        let parsed = try parse(terrain: crop(x: 14) + crop(x: 16), objects: objects)
        let snapshot = FarmSnapshotExtractor.extract(from: parsed.mainRoot, cropCatalog: [])
        let query = FarmMapQuery(region: FarmTileRegion(minX: 14, maxX: 14, minY: 29, maxY: 29))
        var draft = parsed.draft
        let matching = snapshot.entities.filter { query.matches($0, actions: draft.farmActions) }
        XCTAssertEqual(matching.count, 2)
        draft.farmActions.apply(.water, to: matching)
        draft.farmActions.apply(.clear, to: matching)
        XCTAssertEqual(draft.farmActions.cropWateringKeys, ["crop:14:29"])
        XCTAssertEqual(draft.farmActions.debrisRemovalKeys, ["debris:stone:14:29"])
        XCTAssertEqual(snapshot.affectedEntities(by: draft.farmActions).count, 2)
        XCTAssertTrue(FarmScopedAction.water.candidates(matching, actions: draft.farmActions).isEmpty)
        let after = try renderedRoot(parsed, draft)
        XCTAssertEqual(location("Farm", in: after)?.child(named: "objects")?.children(named: "item").count, 1)
        XCTAssertEqual(feature(x: 14, in: after)?.value(named: "state"), "1")
        let diff = try XCTUnwrap(SaveDiffBuilder.build(original: parsed.draft, draft: draft).first { $0.id == "farm.crop.crop:14:29" })
        XCTAssertFalse(diff.affectsSaveGameInfo)
        SaveDiffBuilder.undo(diff, original: parsed.draft, draft: &draft)
        XCTAssertTrue(draft.farmActions.cropWateringKeys.isEmpty)
        XCTAssertEqual(draft.farmActions.debrisRemovalKeys.count, 1)
        XCTAssertEqual(feature(x: 14, in: try renderedRoot(parsed, draft))?.value(named: "state"), "0")
    }

    func testMapSearchScopeAndToggleReflectDraftImmediately() throws {
        let parsed = try parse(terrain: crop(x: 14) + crop(x: 16, state: "<state>1</state>"))
        let snapshot = FarmSnapshotExtractor.extract(from: parsed.mainRoot, cropCatalog: [])
        let dry = try XCTUnwrap(snapshot.entities.first { $0.wateringKey != nil })
        var actions = FarmActionDraft()
        XCTAssertEqual(snapshot.entities.filter { FarmMapQuery(text: " X 14 ").matches($0, actions: actions) }.count, 1)
        XCTAssertEqual(snapshot.entities.filter { FarmMapQuery(text: "472").matches($0, actions: actions) }.count, 2)
        XCTAssertEqual(snapshot.entities.filter { FarmMapQuery(scope: .actionable).matches($0, actions: actions) }.count, 1)
        XCTAssertFalse(FarmMapQuery(scope: .pending).matches(dry, actions: actions))
        actions.toggle(dry)
        XCTAssertTrue(FarmMapQuery(scope: .pending).matches(dry, actions: actions))
        actions.toggle(dry)
        XCTAssertFalse(actions.hasChanges)
        actions.waterAllCrops = true
        actions.toggle(dry)
        XCTAssertTrue(actions.coveredByBulk(dry))
        XCTAssertTrue(actions.cropWateringKeys.isEmpty)
    }

    func testMapRejectsInvalidRegionsAndNonActionableKeys() throws {
        XCTAssertFalse(FarmTileRegion(minX: 2, maxX: 1, minY: 0, maxY: 1).isValid)
        XCTAssertFalse(FarmTileRegion(minX: 0, maxX: .infinity, minY: 0, maxY: 1).isValid)
        XCTAssertFalse(FarmTileRegion(minX: .nan, maxX: 1, minY: 0, maxY: 1).isValid)
        let parsed = try parse(terrain: crop(x: 14, state: "<state>1</state>"))
        var draft = parsed.draft
        draft.farmActions.cropWateringKeys = ["crop:14:29"]
        XCTAssertThrowsError(try SaveMutator.render(parsed: parsed, draft: draft))
        draft.farmActions.cropWateringKeys = ["crop:99:99"]
        XCTAssertThrowsError(try SaveMutator.render(parsed: parsed, draft: draft))
        draft.farmActions = FarmActionDraft()
        draft.farmActions.debrisRemovalKeys = ["debris:stone:14:29"]
        XCTAssertThrowsError(try SaveMutator.render(parsed: parsed, draft: draft))
    }

    private func parse(colors: String = "", infoColors: String = "", house: String = "",
                       upgrade: String = "<houseUpgradeLevel>2</houseUpgradeLevel>",
                       terrain: String = "", objects: String = "", extraLocations: String = "") throws -> ParsedSaveDocument {
        let xml = """
        <SaveGame xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"><player>
        <name>Test</name><farmName>Farm</farmName><favoriteThing>Tea</favoriteThing><uniqueMultiplayerID>123</uniqueMultiplayerID>
        <money>10</money><maxHealth>100</maxHealth><maxStamina>270</maxStamina>
        <hair>1</hair><skin>2</skin><accessory>-1</accessory>\(colors)\(upgrade)<items/><friendshipData/><cookingRecipes/><craftingRecipes/>
        </player><year>1</year><currentSeason>spring</currentSeason><dayOfMonth>1</dayOfMonth><gameVersion>1.6.8</gameVersion>
        <locations><GameLocation xsi:type="FarmHouse"><name>FarmHouse</name>\(house)</GameLocation>
        <GameLocation xsi:type="Farm"><name>Farm</name><terrainFeatures>\(terrain)</terrainFeatures><objects>\(objects)</objects></GameLocation>
        \(extraLocations)</locations></SaveGame>
        """
        let info = "<Farmer xmlns:xsi=\"http://www.w3.org/2001/XMLSchema-instance\"><uniqueMultiplayerID>123</uniqueMultiplayerID><name>Test</name><money>10</money>\(infoColors)</Farmer>"
        return try SaveParser.parse(mainData: Data(xml.utf8), infoData: Data(info.utf8), catalog: [], recipeCatalog: [:])
    }

    private func root(_ data: Data) throws -> XMLNode { try XMLTreeParser().parse(SaveCodec.decode(data).xmlData) }
    private func renderedRoot(_ parsed: ParsedSaveDocument, _ draft: SaveDraft) throws -> XMLNode {
        try root(SaveMutator.render(parsed: parsed, draft: draft).mainData)
    }
    private func colorXML(_ field: FarmerColorField, _ color: FarmerColor, packed: Bool = false, extra: String = "") -> String {
        "<\(field.rawValue) keep=\"yes\"><R>\(color.red)</R><G>\(color.green)</G><B>\(color.blue)</B><A>\(color.alpha)</A>"
            + (packed ? "<PackedValue>\(color.packed)</PackedValue>" : "") + extra + "</\(field.rawValue)>"
    }
    private func roomEntry(_ room: String, _ style: String) -> String {
        "<item><key><string>\(room)</string></key><value><string>\(style)</string></value></item>"
    }
    private func houseFields() -> String {
        "<appliedWallpaper><SerializableDictionaryOfStringString>\(roomEntry("Bedroom", "7"))\(roomEntry("Kitchen", "21"))\(roomEntry("FarmHouse", "34"))</SerializableDictionaryOfStringString></appliedWallpaper>"
            + "<appliedFloor><SerializableDictionaryOfStringString>\(roomEntry("Bedroom", "0018"))\(roomEntry("Kitchen", "3"))</SerializableDictionaryOfStringString></appliedFloor>"
    }
    private func crop(x: Int, state: String = "<state>0</state>", dead: String = "false", type: String = "HoeDirt") -> String {
        "<item><key><Vector2><X>\(x)</X><Y>29</Y></Vector2></key><value><TerrainFeature xsi:type=\"\(type)\">\(state)<crop><netSeedIndex>472</netSeedIndex><dead>\(dead)</dead><currentPhase>2</currentPhase><modData keep=\"yes\"/></crop></TerrainFeature></value></item>"
    }
    private func object(x: Int, id: String) -> String {
        "<item><key><Vector2><X>\(x)</X><Y>29</Y></Vector2></key><value><Object><name>Debris</name><itemId>\(id)</itemId><stack>1</stack></Object></value></item>"
    }
    private func location(_ name: String, in root: XMLNode) -> XMLNode? {
        root.child(named: "locations")?.children.first { $0.value(named: "name") == name }
    }
    private func feature(x: Int, in root: XMLNode) -> XMLNode? {
        location("Farm", in: root)?.child(named: "terrainFeatures")?.children.first {
            $0.child(named: "key")?.firstDescendant(named: "Vector2")?.value(named: "X") == String(x)
        }?.child(named: "value")?.children.first
    }
}
