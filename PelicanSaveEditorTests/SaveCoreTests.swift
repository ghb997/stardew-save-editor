import XCTest
import UIKit
@testable import PelicanSaveEditor

final class SaveCoreTests: XCTestCase {
    @MainActor
    func testGlobalKeyboardReturnAccessoryInstallsOnEveryUIKitTextInputKind() throws {
        GlobalKeyboardReturnInstaller.shared.start()

        let textField = UITextField()
        NotificationCenter.default.post(
            name: UITextField.textDidBeginEditingNotification,
            object: textField
        )
        let textFieldToolbar = try XCTUnwrap(textField.inputAccessoryView as? UIToolbar)
        XCTAssertEqual(
            textFieldToolbar.accessibilityIdentifier,
            GlobalKeyboardReturnInstaller.toolbarIdentifier
        )
        XCTAssertEqual(textFieldToolbar.items?.last?.title, "返回")
        XCTAssertEqual(
            textFieldToolbar.items?.last?.accessibilityIdentifier,
            GlobalKeyboardReturnInstaller.buttonIdentifier
        )

        let searchField = UISearchTextField()
        NotificationCenter.default.post(
            name: UITextField.textDidBeginEditingNotification,
            object: searchField
        )
        let searchFieldToolbar = try XCTUnwrap(searchField.inputAccessoryView as? UIToolbar)
        XCTAssertEqual(
            searchFieldToolbar.accessibilityIdentifier,
            GlobalKeyboardReturnInstaller.toolbarIdentifier
        )
        XCTAssertEqual(searchFieldToolbar.items?.last?.title, "返回")
        XCTAssertEqual(
            searchFieldToolbar.items?.last?.accessibilityIdentifier,
            GlobalKeyboardReturnInstaller.buttonIdentifier
        )

        let textView = UITextView()
        NotificationCenter.default.post(
            name: UITextView.textDidBeginEditingNotification,
            object: textView
        )
        let textViewToolbar = try XCTUnwrap(textView.inputAccessoryView as? UIToolbar)
        XCTAssertEqual(
            textViewToolbar.accessibilityIdentifier,
            GlobalKeyboardReturnInstaller.toolbarIdentifier
        )
        XCTAssertEqual(textViewToolbar.items?.last?.title, "返回")
        XCTAssertEqual(
            textViewToolbar.items?.last?.accessibilityIdentifier,
            GlobalKeyboardReturnInstaller.buttonIdentifier
        )
    }

    func testXMLTreePreservesUnknownElementsAndEscapesText() throws {
        let root = try XMLTreeParser().parse(Data(sampleMain.utf8))
        let player = try XCTUnwrap(root.child(named: "player"))
        XCTAssertTrue(player.setValue("A&B <农夫>", named: "name"))

        let rendered = Data(root.xmlString(includeDeclaration: true).utf8)
        let reparsed = try XMLTreeParser().parse(rendered)
        XCTAssertEqual(reparsed.child(named: "player")?.value(named: "name"), "A&B <农夫>")
        XCTAssertEqual(reparsed.child(named: "unknownSection")?.value(named: "keepMe"), "yes")
        XCTAssertEqual(
            reparsed.child(named: "unknownSection")?.child(named: "keepMe")?.attributes["custom"],
            "still-here"
        )
    }

    func testPlainAndZlibCodecRoundTrips() throws {
        let source = Data(sampleMain.utf8)
        let plain = try SaveCodec.decode(source)
        XCTAssertEqual(plain.encoding, .plainXML)

        let compressed = try SaveCodec.encode(xmlData: source, encoding: .zlib, includeBOM: true)
        XCTAssertNotEqual(compressed, source)
        let decoded = try SaveCodec.decode(compressed)
        XCTAssertEqual(decoded.encoding, .zlib)
        XCTAssertTrue(decoded.hadUTF8BOM)
        XCTAssertEqual(decoded.xmlData, source)
    }

    func testCodecReadsStandardZlibFixture() throws {
        // Produced independently with Python's zlib.compress(b"<SaveGame/>").
        let fixture = Data([0x78, 0x9c, 0xb3, 0x09, 0x4e, 0x2c, 0x4b, 0x75, 0x4f, 0xcc, 0x4d, 0xd5, 0xb7, 0x03, 0x00, 0x16, 0xc7, 0x03, 0xb3])
        let decoded = try SaveCodec.decode(fixture)
        XCTAssertEqual(decoded.encoding, .zlib)
        XCTAssertEqual(String(data: decoded.xmlData, encoding: .utf8), "<SaveGame/>")
    }

    func testParseEditRenderAndReparsePair() throws {
        let catalogItem = CatalogItem(
            id: "24",
            name: "Parsnip",
            chineseName: "防风草",
            objectType: "Basic",
            category: -75,
            price: 35,
            edibility: 10,
            spriteIndex: 24,
            texture: "springobjects.png",
            allowedQualities: [0, 1, 2, 4]
        )
        let recipes: [RecipeKind: [String]] = [
            .cooking: ["Fried Egg", "Pizza"],
            .crafting: ["Chest"]
        ]
        let parsed = try SaveParser.parse(
            mainData: Data(sampleMain.utf8),
            infoData: Data(sampleInfo.utf8),
            catalog: [catalogItem],
            recipeCatalog: recipes
        )

        XCTAssertEqual(parsed.draft.playerName, "Test")
        XCTAssertEqual(parsed.playTimeMilliseconds, 9_000_000)
        XCTAssertEqual(parsed.farmType, 0)
        XCTAssertEqual(parsed.draft.inventory.count, 2)
        XCTAssertEqual(parsed.draft.inventory[0].item?.chineseName, "防风草")
        XCTAssertEqual(parsed.draft.inventory[0].item?.spriteIndex, 24)
        XCTAssertEqual(parsed.draft.inventory[0].item?.texture, "springobjects.png")
        XCTAssertNil(parsed.draft.inventory[1].item)

        var draft = parsed.draft
        draft.playerName = "新农夫"
        draft.farmName = "新农场"
        draft.money = 999_999
        draft.year = 3
        draft.season = .winter
        draft.day = 28
        draft.skills[0].level = 10
        draft.progress.professionIDs = [1, 5]
        let rustyKeyIndex = try XCTUnwrap(
            draft.progress.walletUnlocks.firstIndex { $0.key == .rustyKey }
        )
        draft.progress.walletUnlocks[rustyKeyIndex].isUnlocked = true
        draft.inventory[0].item?.stack = 999
        draft.inventory[0].item?.quality = 4
        draft.friendships[0].points = 2_000
        if let pizzaIndex = draft.recipes.firstIndex(where: { $0.key == "Pizza" }) {
            draft.recipes[pizzaIndex].unlocked = true
        } else {
            XCTFail("Pizza should be present in the recipe catalog")
        }

        let rendered = try SaveMutator.render(parsed: parsed, draft: draft)
        let reparsed = try SaveParser.parse(
            mainData: rendered.mainData,
            infoData: rendered.infoData,
            catalog: [catalogItem],
            recipeCatalog: recipes
        )

        XCTAssertEqual(reparsed.draft.playerName, "新农夫")
        XCTAssertEqual(reparsed.draft.farmName, "新农场")
        XCTAssertEqual(reparsed.draft.money, 999_999)
        XCTAssertEqual(reparsed.draft.year, 3)
        XCTAssertEqual(reparsed.draft.season, .winter)
        XCTAssertEqual(reparsed.draft.day, 28)
        XCTAssertEqual(reparsed.draft.skills[0].level, 10)
        XCTAssertEqual(reparsed.draft.skills[0].originalExperience, 15_000)
        XCTAssertEqual(reparsed.draft.progress.professionIDs, [1, 5])
        XCTAssertTrue(try XCTUnwrap(reparsed.draft.progress.walletUnlocks.first {
            $0.key == .rustyKey
        }).isUnlocked)
        XCTAssertEqual(reparsed.draft.inventory[0].item?.stack, 999)
        XCTAssertEqual(reparsed.draft.inventory[0].item?.quality, 4)
        XCTAssertEqual(reparsed.draft.friendships[0].points, 2_000)
        XCTAssertTrue(try XCTUnwrap(reparsed.draft.recipes.first { $0.key == "Pizza" }).unlocked)

        let mainXML = try SaveCodec.decode(rendered.mainData).xmlData
        let root = try XMLTreeParser().parse(mainXML)
        XCTAssertEqual(root.child(named: "unknownSection")?.value(named: "keepMe"), "yes")
        let friedEggNode = root.child(named: "player")?
            .child(named: "cookingRecipes")?
            .children(named: "item")
            .first { $0.child(named: "key")?.value(named: "string") == "Fried Egg" }
        XCTAssertEqual(friedEggNode?.attributes["custom"], "preserve")
        XCTAssertEqual(friedEggNode?.child(named: "value")?.value(named: "modField"), "yes")

        let renderedInfo = try XCTUnwrap(rendered.infoData)
        let infoXML = try SaveCodec.decode(renderedInfo).xmlData
        let info = try XMLTreeParser().parse(infoXML)
        XCTAssertEqual(info.value(named: "name"), "新农夫")
        XCTAssertEqual(info.value(named: "farmName"), "新农场")
        XCTAssertEqual(info.value(named: "money"), "999999")
        XCTAssertEqual(info.value(named: "yearForSaveGame"), "3")
        XCTAssertEqual(info.value(named: "seasonForSaveGame"), "3")
        XCTAssertEqual(info.value(named: "dayOfMonthForSaveGame"), "28")
    }

    func testValidationRejectsUnsafeValues() throws {
        let parsed = try SaveParser.parse(
            mainData: Data(sampleMain.utf8),
            infoData: nil,
            catalog: [],
            recipeCatalog: [:]
        )
        var draft = parsed.draft
        draft.money = -1
        XCTAssertThrowsError(try SaveMutator.validate(draft))

        draft = parsed.draft
        draft.inventory[0].item?.stack = 10_000
        XCTAssertThrowsError(try SaveMutator.validate(draft))
    }

    func testUnchangedExtendedValuesSurviveAnUnrelatedEdit() throws {
        let extendedMain = sampleMain
            .replacingOccurrences(of: "<maxHealth>100</maxHealth>", with: "<maxHealth>5000</maxHealth>")
            .replacingOccurrences(of: "<Gender>Male</Gender>", with: "<Gender>Modded</Gender>")
            .replacingOccurrences(of: "<gender>Male</gender>", with: "<gender>Modded</gender>")
            .replacingOccurrences(of: "<hair>2</hair>", with: "<hair>250</hair>")
            .replacingOccurrences(of: "<farmingLevel>1</farmingLevel>", with: "<farmingLevel>15</farmingLevel>")
            .replacingOccurrences(of: "<stack>3</stack>", with: "<stack>10000</stack>")
            .replacingOccurrences(of: "<Points>500</Points>", with: "<Points>9000</Points>")
        let extendedInfo = sampleInfo
            .replacingOccurrences(of: "<maxHealth>100</maxHealth>", with: "<maxHealth>5000</maxHealth>")
            .replacingOccurrences(of: "<Gender>Male</Gender>", with: "<Gender>Modded</Gender>")
            .replacingOccurrences(of: "<gender>Male</gender>", with: "<gender>Modded</gender>")
            .replacingOccurrences(of: "<hair>2</hair>", with: "<hair>250</hair>")
            .replacingOccurrences(of: "<farmingLevel>1</farmingLevel>", with: "<farmingLevel>15</farmingLevel>")

        let parsed = try SaveParser.parse(
            mainData: Data(extendedMain.utf8),
            infoData: Data(extendedInfo.utf8),
            catalog: [],
            recipeCatalog: [:]
        )
        var draft = parsed.draft
        draft.money = 4_321

        let rendered = try SaveMutator.render(parsed: parsed, draft: draft)
        let main = try XMLTreeParser().parse(try SaveCodec.decode(rendered.mainData).xmlData)
        let player = try XCTUnwrap(main.child(named: "player"))
        XCTAssertEqual(player.value(named: "money"), "4321")
        XCTAssertEqual(player.value(named: "maxHealth"), "5000")
        XCTAssertEqual(player.value(named: "Gender"), "Modded")
        XCTAssertEqual(player.value(named: "gender"), "Modded")
        XCTAssertEqual(player.value(named: "hair"), "250")
        XCTAssertEqual(player.value(named: "farmingLevel"), "15")
        XCTAssertEqual(player.child(named: "items")?.child(named: "Item")?.value(named: "stack"), "10000")
        XCTAssertEqual(
            player.child(named: "friendshipData")?
                .child(named: "item")?
                .child(named: "value")?
                .child(named: "Friendship")?
                .value(named: "Points"),
            "9000"
        )

        let infoData = try XCTUnwrap(rendered.infoData)
        let info = try XMLTreeParser().parse(try SaveCodec.decode(infoData).xmlData)
        XCTAssertEqual(info.value(named: "money"), "4321")
        XCTAssertEqual(info.value(named: "maxHealth"), "5000")
        XCTAssertEqual(info.value(named: "Gender"), "Modded")
        XCTAssertEqual(info.value(named: "hair"), "250")
        XCTAssertEqual(info.value(named: "farmingLevel"), "15")
    }

    func testMovingEquivalentItemsStillProducesInventoryDiffs() throws {
        let parsed = try SaveParser.parse(
            mainData: Data(sampleMain.utf8),
            infoData: nil,
            catalog: [],
            recipeCatalog: [:]
        )
        var original = parsed.draft
        let repeatedItem = try XCTUnwrap(original.inventory[0].item).copied()
        original.inventory.append(InventorySlotDraft(id: 2, item: repeatedItem))

        var changed = original
        changed.inventory.swapAt(0, 2)
        let diffs = SaveDiffBuilder.build(original: original, draft: changed)
        XCTAssertEqual(diffs.filter { $0.section == "背包" }.count, 2)
    }

    func testBundledCatalogHasFullUpstreamData() throws {
        let catalog = try ItemCatalog.load()
        // Only verified standard Objects are constructible, including the eight
        // explicitly supported 1.6 crop/seed string IDs.
        XCTAssertEqual(catalog.count, 598)
        XCTAssertTrue(ItemCatalog.supportedStringIDs.isSubset(of: Set(catalog.map(\.id))))
        XCTAssertNotNil(catalog.first { $0.id == "24" && $0.name == "Parsnip" })
        XCTAssertTrue(catalog.allSatisfy { $0.chineseName != nil })
        XCTAssertEqual(catalog.first { $0.id == "30" }?.chineseName, "木料")
        XCTAssertEqual(catalog.first { $0.id == "24" }?.texture, "springobjects.png")
        XCTAssertEqual(catalog.first { $0.id == "348" }?.texture, "Objects_2.png")
        let recipes = try RecipeCatalog.load()
        XCTAssertGreaterThan(recipes[.cooking]?.count ?? 0, 70)
        XCTAssertGreaterThan(recipes[.crafting]?.count ?? 0, 100)
    }

    func testBundledRecipeCatalogHasCompleteChineseNames() throws {
        let recipes = try RecipeCatalog.load()
        let allKeys = RecipeKind.allCases.flatMap { recipes[$0] ?? [] }

        XCTAssertEqual(allKeys.count, 231)
        XCTAssertEqual(Set(RecipeCatalog.chineseNames.keys), Set(allKeys))
        XCTAssertTrue(allKeys.allSatisfy(RecipeCatalog.hasChineseName(for:)))
    }

    func testBundledCropCatalogIsCompleteAndInternallyConsistent() throws {
        let crops = try CropCatalog.load()

        XCTAssertEqual(crops.count, 47)
        XCTAssertEqual(Set(crops.map(\.id)).count, 47)
        XCTAssertTrue(crops.allSatisfy { $0.phaseDays.reduce(0, +) == $0.growDays })
        XCTAssertNotNil(crops.first { $0.name == "Carrot" && $0.growDays == 3 })
        XCTAssertNotNil(crops.first { $0.name == "Powdermelon" && $0.seasons == [.winter] })
        XCTAssertNotNil(crops.first { $0.name == "Tea Leaves" && $0.isTeaBush })

        let sunflower = try XCTUnwrap(crops.first { $0.name == "Sunflower" })
        XCTAssertEqual(sunflower.cheapestSeedPrice?.place, "JojaMart")
        XCTAssertEqual(sunflower.cheapestSeedPrice?.price, 125)

        let potato = try XCTUnwrap(crops.first { $0.name == "Potato" })
        XCTAssertEqual(potato.harvestQuantity, CropHarvestQuantity(min: 1, max: 1))
        XCTAssertEqual(potato.extraHarvestChance, 0.20, accuracy: 0.000_001)
    }

    func testCropGrowthSpeedMirrorsGamePhaseRules() {
        XCTAssertEqual(
            CropPlanner.adjustedGrowthDays(phaseDays: [1, 3, 3, 3], speedIncrease: 0.10),
            8,
            "10-day crops lose two days because the game multiplies single-precision floats"
        )
        XCTAssertEqual(
            CropPlanner.adjustedGrowthDays(phaseDays: [1, 1, 2, 3, 3], speedIncrease: 0.43),
            6,
            "A phase decremented below zero is skipped, not counted as a negative growth day"
        )
        XCTAssertEqual(
            CropPlanner.adjustedGrowthDays(phaseDays: [1, 2, 2, 3], speedIncrease: 0.25),
            6,
            "An irrigated rice shoot receives the game's 25 percent paddy bonus"
        )
    }

    func testCropPlannerSchedulesCrossSeasonRegrowthAndProfit() throws {
        let corn = try XCTUnwrap(try CropCatalog.load().first { $0.name == "Corn" })
        let plan = CropPlanner.makePlan(CropPlanInput(
            crop: corn,
            startDate: CropCalendarDate(year: 1, season: .summer, day: 1),
            planningDays: 56,
            quantity: 1,
            environment: .outdoors,
            fertilizer: .none,
            hasAgriculturist: false,
            hasPaddyWaterBonus: false,
            hasTiller: false
        ))

        XCTAssertEqual(plan.harvestCount, 11)
        XCTAssertEqual(plan.harvestDates.first, CropCalendarDate(year: 1, season: .summer, day: 15))
        XCTAssertEqual(plan.harvestDates.last, CropCalendarDate(year: 1, season: .fall, day: 27))
        XCTAssertEqual(plan.minimumProduce, 11)
        XCTAssertEqual(plan.minimumGrossRevenue, 550)
        XCTAssertEqual(plan.seedCost, 150)
        XCTAssertEqual(plan.minimumNetRevenue, 400)
    }

    func testCropPlannerChargesInitialSeedsBeforeFirstHarvest() throws {
        let parsnip = try XCTUnwrap(try CropCatalog.load().first { $0.name == "Parsnip" })
        let plan = CropPlanner.makePlan(CropPlanInput(
            crop: parsnip,
            startDate: CropCalendarDate(year: 1, season: .spring, day: 1),
            planningDays: 3,
            quantity: 2,
            environment: .outdoors,
            fertilizer: .none,
            hasAgriculturist: false,
            hasPaddyWaterBonus: false,
            hasTiller: false
        ))

        XCTAssertEqual(plan.harvestCount, 0)
        XCTAssertEqual(plan.seedCost, 40)
        XCTAssertEqual(plan.minimumNetRevenue, -40)
    }

    func testTeaBushGrowsAcrossOutdoorWinterButOnlyHarvestsInProducingSeasons() throws {
        let tea = try XCTUnwrap(try CropCatalog.load().first { $0.isTeaBush })
        let outdoor = CropPlanner.makePlan(CropPlanInput(
            crop: tea,
            startDate: CropCalendarDate(year: 1, season: .fall, day: 20),
            planningDays: 65,
            quantity: 1,
            environment: .outdoors,
            fertilizer: .hyperSpeedGro,
            hasAgriculturist: true,
            hasPaddyWaterBonus: false,
            hasTiller: false
        ))
        let protected = CropPlanner.makePlan(CropPlanInput(
            crop: tea,
            startDate: CropCalendarDate(year: 1, season: .fall, day: 20),
            planningDays: 65,
            quantity: 1,
            environment: .protected,
            fertilizer: .none,
            hasAgriculturist: false,
            hasPaddyWaterBonus: false,
            hasTiller: false
        ))

        XCTAssertEqual(outdoor.effectiveGrowthDays, 20)
        XCTAssertEqual(outdoor.harvestCount, 7)
        XCTAssertEqual(outdoor.harvestDates.first, CropCalendarDate(year: 2, season: .spring, day: 22))
        XCTAssertEqual(protected.harvestCount, 14)
        XCTAssertEqual(protected.harvestDates.first, CropCalendarDate(year: 1, season: .winter, day: 22))
    }

    func testFarmSnapshotExtractsActualEntitiesCountsAndCoordinates() throws {
        let root = try XMLTreeParser().parse(Data(sampleFarmMap.utf8))
        let snapshot = FarmSnapshotExtractor.extract(from: root, cropCatalog: try CropCatalog.load())

        XCTAssertEqual(snapshot.farmLocationName, "Farm")
        XCTAssertEqual(snapshot.entities.count, 8)
        XCTAssertEqual(snapshot.positionedEntities.count, 8)
        XCTAssertEqual(snapshot.tilledSoilCount, 3)
        XCTAssertEqual(snapshot.grassCount, 1)
        XCTAssertEqual(snapshot.count(for: .crop), 2)
        XCTAssertEqual(snapshot.unwateredCropCount, 0)
        XCTAssertEqual(snapshot.deadCropCount, 1)
        XCTAssertEqual(snapshot.count(for: .tree), 1)
        XCTAssertEqual(snapshot.count(for: .fruitTree), 1)
        XCTAssertEqual(snapshot.count(for: .object), 1)
        XCTAssertEqual(snapshot.count(for: .building), 1)
        XCTAssertEqual(snapshot.count(for: .animal), 1)
        XCTAssertEqual(snapshot.count(for: .resource), 1)

        let crop = try XCTUnwrap(snapshot.entities.first { $0.kind == .crop })
        XCTAssertEqual(crop.label, "防风草")
        XCTAssertEqual(crop.tileX, 2)
        XCTAssertEqual(crop.tileY, 3)
        // This fixture omits the serialized watering state. Keep the crop
        // visible, but never infer that it is dry or create a writable key.
        XCTAssertNil(crop.state)
        XCTAssertNil(crop.wateringKey)
        XCTAssertTrue(crop.detail?.contains("未知浇水状态，只读") == true)
        let animal = try XCTUnwrap(snapshot.entities.first { $0.kind == .animal })
        XCTAssertEqual(animal.tileX, 10)
        XCTAssertEqual(animal.tileY, 12)
    }

    func testFarmhouseAndMagicFarmActionsRoundTripWithoutRemovingNormalObjects() throws {
        let editableFarm = """
          <locations>
            <GameLocation xsi:type="FarmHouse">
              <name>FarmHouse</name>
              <wallPaper>2</wallPaper>
              <floor>
                <item><key><string>Bedroom</string></key><value><int>5</int></value></item>
              </floor>
            </GameLocation>
            <GameLocation xsi:type="Farm">
              <name>Farm</name>
              <objects>
                <item><key><Vector2><X>1</X><Y>1</Y></Vector2></key><value><Object><name>Stone</name><itemId>StardewValley:(O)343</itemId></Object></value></item>
                <item><key><Vector2><X>2</X><Y>1</Y></Vector2></key><value><Object><name>Weeds</name><itemId>313</itemId></Object></value></item>
                <item><key><Vector2><X>3</X><Y>1</Y></Vector2></key><value><Object><name>Twig</name><itemId>294</itemId></Object></value></item>
                <item><key><Vector2><X>4</X><Y>1</Y></Vector2></key><value><Object><name>Chest</name><itemId>130</itemId><bigCraftable>true</bigCraftable></Object></value></item>
              </objects>
              <terrainFeatures>
                <item>
                  <key><Vector2><X>8</X><Y>9</Y></Vector2></key>
                  <value><TerrainFeature><state>0</state><crop><netSeedIndex>472</netSeedIndex><dead>false</dead></crop></TerrainFeature></value>
                </item>
                <item>
                  <key><Vector2><X>9</X><Y>9</Y></Vector2></key>
                  <value><TerrainFeature xsi:type="HoeDirt"><state>0</state><crop><netSeedIndex>472</netSeedIndex><dead>true</dead></crop></TerrainFeature></value>
                </item>
              </terrainFeatures>
            </GameLocation>
          </locations>
        """
        let main = sampleMain
            .replacingOccurrences(
                of: "<accessory>-1</accessory>",
                with: "<accessory>-1</accessory><houseUpgradeLevel>1</houseUpgradeLevel>"
            )
            .replacingOccurrences(of: "<unknownSection>", with: editableFarm + "<unknownSection>")

        let parsed = try SaveParser.parse(
            mainData: Data(main.utf8),
            infoData: nil,
            catalog: [],
            recipeCatalog: [:]
        )
        XCTAssertEqual(parsed.draft.farmhouse.upgradeLevel, 1)
        XCTAssertEqual(parsed.draft.farmhouse.decorations.count, 2)
        XCTAssertEqual(
            parsed.draft.farmhouse.decorations.first { $0.kind == .wallpaper }?.styleIndex,
            2
        )
        XCTAssertEqual(
            parsed.draft.farmhouse.decorations.first { $0.kind == .flooring }?.styleIndex,
            5
        )

        let originalSnapshot = FarmSnapshotExtractor.extract(
            from: parsed.mainRoot,
            cropCatalog: try CropCatalog.load()
        )
        XCTAssertEqual(originalSnapshot.unwateredCropCount, 1)
        XCTAssertEqual(originalSnapshot.deadCropCount, 1)
        XCTAssertEqual(originalSnapshot.stoneCount, 1)
        XCTAssertEqual(originalSnapshot.weedCount, 1)
        XCTAssertEqual(originalSnapshot.twigCount, 1)

        var draft = parsed.draft
        draft.farmhouse.upgradeLevel = 3
        for index in draft.farmhouse.decorations.indices {
            draft.farmhouse.decorations[index].styleIndex += 10
        }
        draft.farmActions.waterAllCrops = true
        draft.farmActions.clearStones = true
        draft.farmActions.clearWeeds = true
        draft.farmActions.clearTwigs = true
        XCTAssertEqual(
            originalSnapshot.visiblePositionedEntities(after: draft.farmActions).count,
            3
        )
        XCTAssertEqual(originalSnapshot.affectedEntities(by: draft.farmActions).count, 4)

        let diffs = SaveDiffBuilder.build(original: parsed.draft, draft: draft)
        XCTAssertEqual(diffs.filter { $0.section == "农场" }.count, 4)
        XCTAssertEqual(diffs.filter { $0.section == "房屋" }.count, 3)

        let rendered = try SaveMutator.render(parsed: parsed, draft: draft)
        let root = try XMLTreeParser().parse(try SaveCodec.decode(rendered.mainData).xmlData)
        XCTAssertEqual(root.child(named: "player")?.value(named: "houseUpgradeLevel"), "3")

        let locations = try XCTUnwrap(root.child(named: "locations"))
        let farmhouse = try XCTUnwrap(locations.children.first { $0.value(named: "name") == "FarmHouse" })
        XCTAssertEqual(farmhouse.value(named: "wallPaper"), "12")
        XCTAssertEqual(
            farmhouse.child(named: "floor")?
                .child(named: "item")?
                .child(named: "value")?
                .value(named: "int"),
            "15"
        )

        let farm = try XCTUnwrap(locations.children.first { $0.value(named: "name") == "Farm" })
        let remainingNames = farm.child(named: "objects")?.children(named: "item").compactMap { item in
            item.child(named: "value")?.firstDescendant(named: "Object")?.value(named: "name")
        }
        XCTAssertEqual(remainingNames, ["Chest"])
        let soils = farm.child(named: "terrainFeatures")?.children(named: "item").compactMap { item in
            item.child(named: "value")?.children.first
        }
        XCTAssertEqual(soils?.first?.value(named: "state"), "1")
        XCTAssertEqual(soils?.last?.value(named: "state"), "0", "枯萎作物不应被一键浇水修改")

        let reparsed = try SaveParser.parse(
            mainData: rendered.mainData,
            infoData: nil,
            catalog: [],
            recipeCatalog: [:]
        )
        XCTAssertEqual(reparsed.draft.farmhouse.upgradeLevel, 3)
        XCTAssertFalse(reparsed.draft.farmActions.hasChanges)
    }

    func testModern16HouseProgressWalletProfessionsAndAnimalsRoundTrip() throws {
        let playerFeatures = """
            <qiGems>12</qiGems><clubCoins>34</clubCoins><totalMoneyEarned>567890</totalMoneyEarned>
            <deepestMineLevel>47</deepestMineLevel>
            <professions><int>0</int><int>2</int><int>999</int></professions>
            <mailReceived><string>HasRustyKey</string><string>mod.example.UnknownFlag</string></mailReceived>
            <questLog><Quest/><Quest xsi:nil="true"/></questLog>
            <achievements><int>1</int><int>2</int></achievements>
            <basicShipped><item><key><int>24</int></key><value><int>30</int></value></item></basicShipped>
            <fishCaught><item><key><int>128</int></key><value><int>1</int></value></item></fishCaught>
        """
        let modernLocations = """
          <goldenWalnuts>17</goldenWalnuts><mine_lowestLevelReached>85</mine_lowestLevelReached>
          <weatherForTomorrow>rain</weatherForTomorrow><dailyLuck>0.075</dailyLuck>
          <locations>
            <GameLocation xsi:type="FarmHouse">
              <name>FarmHouse</name>
              <appliedWallpaper><SerializableDictionaryOfStringString>
                <item><key><string>Bedroom</string></key><value><string>7</string></value></item>
                <item><key><string>Kitchen</string></key><value><string>18</string></value></item>
              </SerializableDictionaryOfStringString></appliedWallpaper>
              <appliedFloor><SerializableDictionaryOfStringString>
                <item><key><string>Bedroom</string></key><value><string>4</string></value></item>
                <item><key><string>Kitchen</string></key><value><string>12</string></value></item>
              </SerializableDictionaryOfStringString></appliedFloor>
            </GameLocation>
            <GameLocation xsi:type="Farm">
              <name>Farm</name><piecesOfHay>222</piecesOfHay>
              <animals><item>
                <key><long>42</long></key>
                <value><FarmAnimal>
                  <name>Bessie</name><displayName>Bessie</displayName><type>White Cow</type>
                  <buildingTypeILiveIn>Deluxe Barn</buildingTypeILiveIn>
                  <friendshipTowardFarmer>400</friendshipTowardFarmer><happiness>180</happiness>
                  <fullness>160</fullness><daysOwned>20</daysOwned><age>20</age>
                </FarmAnimal></value>
              </item></animals>
            </GameLocation>
          </locations>
        """
        let main = sampleMain
            .replacingOccurrences(of: "    <items>", with: playerFeatures + "\n    <items>")
            .replacingOccurrences(of: "  <unknownSection>", with: modernLocations + "\n  <unknownSection>")

        let parsed = try SaveParser.parse(
            mainData: Data(main.utf8),
            infoData: nil,
            catalog: [],
            recipeCatalog: [:]
        )

        XCTAssertEqual(parsed.draft.farmhouse.decorations.count, 4)
        XCTAssertEqual(
            parsed.draft.farmhouse.decorations.first {
                $0.kind == .wallpaper && $0.roomKey == "Bedroom"
            }?.styleIndex,
            7
        )
        XCTAssertEqual(parsed.draft.progress.qiGems, 12)
        XCTAssertEqual(parsed.draft.progress.goldenWalnuts, 17)
        XCTAssertEqual(parsed.draft.progress.piecesOfHay, 222)
        XCTAssertEqual(parsed.draft.progress.professionIDs, [0, 2, 999])
        XCTAssertTrue(try XCTUnwrap(parsed.draft.progress.walletUnlocks.first {
            $0.key == .rustyKey
        }).isUnlocked)
        XCTAssertEqual(parsed.draft.progress.insights.activeQuestCount, 1)
        XCTAssertEqual(parsed.draft.progress.insights.shippedItemKinds, 1)
        XCTAssertEqual(parsed.draft.animals.first?.name, "Bessie")
        XCTAssertEqual(parsed.draft.animals.first?.friendship, 400)

        var draft = parsed.draft
        let farmingIndex = try XCTUnwrap(draft.skills.firstIndex { $0.key == .farming })
        draft.skills[farmingIndex].level = 10
        draft.skills[farmingIndex].experience = 15_345
        draft.progress.qiGems = 99
        draft.progress.clubCoins = 88
        draft.progress.totalMoneyEarned = 999_999
        draft.progress.goldenWalnuts = 55
        draft.progress.piecesOfHay = 333
        draft.progress.deepestMineLevel = 120
        draft.progress.mineLowestLevelReached = 120
        draft.progress.professionIDs = [1, 5, 999]
        let rustyIndex = try XCTUnwrap(draft.progress.walletUnlocks.firstIndex { $0.key == .rustyKey })
        let glassIndex = try XCTUnwrap(draft.progress.walletUnlocks.firstIndex { $0.key == .magnifyingGlass })
        draft.progress.walletUnlocks[rustyIndex].isUnlocked = false
        draft.progress.walletUnlocks[glassIndex].isUnlocked = true
        for index in draft.farmhouse.decorations.indices {
            draft.farmhouse.decorations[index].styleIndex += 20
        }
        draft.animals[0].name = "奶糖"
        draft.animals[0].friendship = 1_000
        draft.animals[0].happiness = 255
        draft.animals[0].fullness = 255
        draft.animals[0].daysOwned = 88

        let diffs = SaveDiffBuilder.build(original: parsed.draft, draft: draft)
        XCTAssertTrue(diffs.contains { $0.section == "技能" })
        XCTAssertTrue(diffs.contains { $0.label == "职业选择" })
        XCTAssertTrue(diffs.contains { $0.section == "特殊能力" })
        XCTAssertTrue(diffs.contains { $0.section == "动物" })

        let rendered = try SaveMutator.render(parsed: parsed, draft: draft)
        let reparsed = try SaveParser.parse(
            mainData: rendered.mainData,
            infoData: nil,
            catalog: [],
            recipeCatalog: [:]
        )

        let farming = try XCTUnwrap(reparsed.draft.skills.first { $0.key == .farming })
        XCTAssertEqual(farming.level, 10)
        XCTAssertEqual(farming.originalExperience, 15_345)
        XCTAssertEqual(reparsed.draft.progress.qiGems, 99)
        XCTAssertEqual(reparsed.draft.progress.clubCoins, 88)
        XCTAssertEqual(reparsed.draft.progress.totalMoneyEarned, 999_999)
        XCTAssertEqual(reparsed.draft.progress.goldenWalnuts, 55)
        XCTAssertEqual(reparsed.draft.progress.piecesOfHay, 333)
        XCTAssertEqual(reparsed.draft.progress.deepestMineLevel, 120)
        XCTAssertEqual(reparsed.draft.progress.mineLowestLevelReached, 120)
        XCTAssertEqual(reparsed.draft.progress.professionIDs, [1, 5, 999])
        XCTAssertFalse(try XCTUnwrap(reparsed.draft.progress.walletUnlocks.first {
            $0.key == .rustyKey
        }).isUnlocked)
        XCTAssertTrue(try XCTUnwrap(reparsed.draft.progress.walletUnlocks.first {
            $0.key == .magnifyingGlass
        }).isUnlocked)
        XCTAssertTrue(reparsed.draft.farmhouse.decorations.allSatisfy { $0.styleIndex >= 24 })
        XCTAssertEqual(reparsed.draft.animals.first?.name, "奶糖")
        XCTAssertEqual(reparsed.draft.animals.first?.friendship, 1_000)
        XCTAssertEqual(reparsed.draft.animals.first?.daysOwned, 88)

        let root = try XMLTreeParser().parse(try SaveCodec.decode(rendered.mainData).xmlData)
        let player = try XCTUnwrap(root.child(named: "player"))
        XCTAssertTrue(player.child(named: "mailReceived")?.children(named: "string").contains {
            $0.text == "mod.example.UnknownFlag"
        } == true)
    }

    func testMagicMapCanRemoveOneSelectedDebrisWithoutTouchingNeighbors() throws {
        let farm = """
          <locations><GameLocation xsi:type="Farm"><name>Farm</name><objects>
            <item><key><Vector2><X>1</X><Y>1</Y></Vector2></key><value><Object><name>Stone</name><itemId>343</itemId></Object></value></item>
            <item><key><Vector2><X>2</X><Y>1</Y></Vector2></key><value><Object><name>Stone</name><itemId>343</itemId></Object></value></item>
            <item><key><Vector2><X>3</X><Y>1</Y></Vector2></key><value><Object><name>Chest</name><itemId>130</itemId><bigCraftable>true</bigCraftable></Object></value></item>
          </objects></GameLocation></locations>
        """
        let main = sampleMain.replacingOccurrences(
            of: "  <unknownSection>",
            with: farm + "\n  <unknownSection>"
        )
        let parsed = try SaveParser.parse(
            mainData: Data(main.utf8),
            infoData: nil,
            catalog: [],
            recipeCatalog: [:]
        )
        let snapshot = FarmSnapshotExtractor.extract(
            from: parsed.mainRoot,
            cropCatalog: try CropCatalog.load()
        )
        let stones = snapshot.entities.filter { $0.state == .stone }
        XCTAssertEqual(stones.count, 2)

        var draft = parsed.draft
        draft.farmActions.debrisRemovalKeys.insert(try XCTUnwrap(stones.first?.actionKey))
        XCTAssertEqual(snapshot.affectedEntities(by: draft.farmActions).count, 1)
        XCTAssertEqual(
            snapshot.visiblePositionedEntities(after: draft.farmActions).filter { $0.state == .stone }.count,
            1
        )

        let rendered = try SaveMutator.render(parsed: parsed, draft: draft)
        let root = try XMLTreeParser().parse(try SaveCodec.decode(rendered.mainData).xmlData)
        let location = try XCTUnwrap(root.child(named: "locations")?.child(named: "GameLocation"))
        let names = location.child(named: "objects")?.children(named: "item").compactMap {
            $0.child(named: "value")?.child(named: "Object")?.value(named: "name")
        }
        XCTAssertEqual(names, ["Stone", "Chest"])
    }

    func testTransactionWritesPairAndCreatesRestorableBackup() throws {
        let harness = try makeTransactionHarness()
        defer { try? FileManager.default.removeItem(at: harness.root) }

        let current = try harness.service.read(source: harness.source)
        let target = SavePairData(
            main: Data(sampleMain.replacingOccurrences(of: "<money>1285</money>", with: "<money>4321</money>").utf8),
            info: Data(sampleInfo.replacingOccurrences(of: "<money>1285</money>", with: "<money>4321</money>").utf8)
        )
        let result = try harness.service.replace(
            source: harness.source,
            expectedMainHash: current.mainHash,
            expectedInfoHash: current.infoHash,
            newData: target,
            reason: "unit test"
        )

        XCTAssertEqual(result.written.mainHash, target.mainHash)
        XCTAssertEqual(result.written.infoHash, target.infoHash)
        let backups = try harness.backupStore.list(farmIdentifier: harness.source.farmIdentifier)
        XCTAssertEqual(backups.count, 1)
        let backup = try harness.backupStore.data(for: backups[0])
        XCTAssertEqual(backup.main, current.main)
        XCTAssertEqual(backup.info, current.info)
    }

    func testCoordinatedWriteUpdatesSelectedFileWithoutReplacingIt() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("InPlaceWriteTests-\(UUID().uuidString)", isDirectory: true)
        let targetURL = root.appendingPathComponent("SelectedSave")
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("long original contents".utf8).write(to: targetURL)
        let originalFileNumber = try fileManager.attributesOfItem(atPath: targetURL.path)[.systemFileNumber]

        // Model a security-scoped file grant: the file itself is writable, while
        // its parent does not permit creating or renaming an atomic temp file.
        try fileManager.setAttributes([.posixPermissions: 0o500], ofItemAtPath: root.path)
        defer {
            try? fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: root.path)
            try? fileManager.removeItem(at: root)
        }

        let replacement = Data("new".utf8)
        try CoordinatedFileAccess.write(replacement, to: targetURL)

        XCTAssertEqual(try Data(contentsOf: targetURL), replacement)
        let updatedFileNumber = try fileManager.attributesOfItem(atPath: targetURL.path)[.systemFileNumber]
        XCTAssertEqual(originalFileNumber as? NSNumber, updatedFileNumber as? NSNumber)
    }

    func testBackupManifestDetectsTamperedData() throws {
        let harness = try makeTransactionHarness()
        defer { try? FileManager.default.removeItem(at: harness.root) }

        let current = try harness.service.read(source: harness.source)
        let manifest = try harness.backupStore.create(
            source: harness.source,
            mainData: current.main,
            infoData: current.info,
            reason: "tamper test"
        )
        let storedMain = harness.root
            .appendingPathComponent("Backups", isDirectory: true)
            .appendingPathComponent(harness.source.farmIdentifier, isDirectory: true)
            .appendingPathComponent(manifest.id.uuidString, isDirectory: true)
            .appendingPathComponent("MainSave", isDirectory: false)
        try Data("<SaveGame/>".utf8).write(to: storedMain, options: .atomic)

        XCTAssertThrowsError(try harness.backupStore.data(for: manifest)) { error in
            guard case BackupStoreError.corruptBackup = error else {
                return XCTFail("Expected corrupt backup error, got \(error)")
            }
        }
    }

    func testLegacyBackupManifestWithoutHashesRemainsReadable() throws {
        let harness = try makeTransactionHarness()
        defer { try? FileManager.default.removeItem(at: harness.root) }

        let current = try harness.service.read(source: harness.source)
        let backupID = UUID()
        let backupDirectory = harness.root
            .appendingPathComponent("Backups", isDirectory: true)
            .appendingPathComponent(harness.source.farmIdentifier, isDirectory: true)
            .appendingPathComponent(backupID.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: backupDirectory, withIntermediateDirectories: true)
        try current.main.write(to: backupDirectory.appendingPathComponent("MainSave"), options: .atomic)
        try current.info?.write(to: backupDirectory.appendingPathComponent("SaveGameInfo"), options: .atomic)
        let legacyManifest = """
        {
          "id": "\(backupID.uuidString)",
          "farmIdentifier": "\(harness.source.farmIdentifier)",
          "savedAt": "2026-08-19T00:00:00Z",
          "mainOriginalName": "\(harness.source.mainURL.lastPathComponent)",
          "infoOriginalName": "SaveGameInfo",
          "reason": "legacy backup"
        }
        """
        try Data(legacyManifest.utf8).write(
            to: backupDirectory.appendingPathComponent("manifest.json"),
            options: .atomic
        )

        let listed = try harness.backupStore.list(farmIdentifier: harness.source.farmIdentifier)
        let manifest = try XCTUnwrap(listed.first { $0.id == backupID })
        XCTAssertNil(manifest.mainHash)
        XCTAssertNil(manifest.infoHash)
        let restored = try harness.backupStore.data(for: manifest)
        XCTAssertEqual(restored.main, current.main)
        XCTAssertEqual(restored.info, current.info)
    }

    func testInterruptedMixedPairIsRecoveredFromBackup() throws {
        let harness = try makeTransactionHarness()
        defer { try? FileManager.default.removeItem(at: harness.root) }

        let original = try harness.service.read(source: harness.source)
        let target = SavePairData(
            main: Data(sampleMain.replacingOccurrences(of: "<money>1285</money>", with: "<money>9876</money>").utf8),
            info: Data(sampleInfo.replacingOccurrences(of: "<money>1285</money>", with: "<money>9876</money>").utf8)
        )
        let backup = try harness.backupStore.create(
            source: harness.source,
            mainData: original.main,
            infoData: original.info,
            reason: "interrupted test"
        )

        // Simulate process termination after writing only the main file.
        try target.main.write(to: harness.source.mainURL, options: .atomic)
        let journal = SaveTransactionJournal(
            id: UUID(),
            farmIdentifier: harness.source.farmIdentifier,
            backupID: backup.id,
            startedAt: Date(),
            originalMainHash: original.mainHash,
            originalInfoHash: original.infoHash,
            targetMainHash: target.mainHash,
            targetInfoHash: target.infoHash,
            phase: .mainWritten
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try FileManager.default.createDirectory(at: harness.journalDirectory, withIntermediateDirectories: true)
        let journalURL = harness.service.journalURL(for: harness.source.farmIdentifier)
        try encoder.encode(journal).write(
            to: journalURL,
            options: .atomic
        )

        let recovery = try harness.service.recoverInterruptedTransactionIfNeeded(source: harness.source)
        guard case let .restoredFromBackup(recoveredBackup) = recovery else {
            return XCTFail("Expected interrupted transaction recovery")
        }
        XCTAssertEqual(recoveredBackup.id, backup.id)
        let restored = try harness.service.read(source: harness.source)
        XCTAssertEqual(restored.mainHash, original.mainHash)
        XCTAssertEqual(restored.infoHash, original.infoHash)
        XCTAssertFalse(FileManager.default.fileExists(atPath: journalURL.path))
    }

    func testDiscoversSaveFoldersFromAuthorizedStardewRoot() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("SaveDiscoveryTests-\(UUID().uuidString)", isDirectory: true)
        let stardewRoot = root.appendingPathComponent("Stardew Valley", isDirectory: true)
        try fileManager.createDirectory(at: stardewRoot, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: root) }

        for farmID in ["SecondFarm_222", "FirstFarm_111"] {
            let farm = stardewRoot.appendingPathComponent(farmID, isDirectory: true)
            try fileManager.createDirectory(at: farm, withIntermediateDirectories: true)
            try Data(sampleMain.utf8).write(to: farm.appendingPathComponent(farmID))
            try Data(sampleInfo.utf8).write(to: farm.appendingPathComponent("SaveGameInfo"))
        }
        let incomplete = stardewRoot.appendingPathComponent("BrokenFarm_333", isDirectory: true)
        try fileManager.createDirectory(at: incomplete, withIntermediateDirectories: true)
        try Data(sampleInfo.utf8).write(to: incomplete.appendingPathComponent("SaveGameInfo"))

        let sources = try SaveSourceResolver.discoverDirectories(in: stardewRoot)

        XCTAssertEqual(sources.map(\.farmIdentifier), ["FirstFarm_111", "SecondFarm_222"])
        XCTAssertTrue(sources.allSatisfy { $0.accessURLs == [stardewRoot] })
        XCTAssertEqual(
            sources.first?.mainURL,
            stardewRoot
                .appendingPathComponent("FirstFarm_111", isDirectory: true)
                .appendingPathComponent("FirstFarm_111")
        )

        let restored = try SaveSourceResolver.directory(
            stardewRoot,
            farmIdentifier: "SecondFarm_222"
        )
        XCTAssertEqual(restored.farmIdentifier, "SecondFarm_222")
        XCTAssertEqual(restored.accessURLs, [stardewRoot])
    }

    func testSaveDiscoveryReportsRootWithoutValidSaves() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("EmptySaveDiscovery-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        XCTAssertThrowsError(try SaveSourceResolver.discoverDirectories(in: root)) { error in
            guard case SaveSourceError.noFarmDirectories = error else {
                return XCTFail("Expected noFarmDirectories, got \(error)")
            }
        }
    }

    func testCopyImportCreatesIndependentAppOwnedPair() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("CopyImportTests-\(UUID().uuidString)", isDirectory: true)
        let sourceRoot = root.appendingPathComponent("Source", isDirectory: true)
        let importRoot = root.appendingPathComponent("Imports", isDirectory: true)
        try fileManager.createDirectory(at: sourceRoot, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: root) }

        let farmIdentifier = "CopiedFarm_444"
        let mainURL = sourceRoot.appendingPathComponent(farmIdentifier)
        let infoURL = sourceRoot.appendingPathComponent("SaveGameInfo")
        let originalMain = Data(sampleMain.utf8)
        let originalInfo = Data(sampleInfo.utf8)
        try originalMain.write(to: mainURL)
        try originalInfo.write(to: infoURL)

        let imported = try SaveSourceResolver.copiedFiles(
            [mainURL, infoURL],
            importRootURL: importRoot
        )

        XCTAssertEqual(imported.mode, .importedCopy)
        XCTAssertEqual(imported.farmIdentifier, farmIdentifier)
        XCTAssertNotEqual(imported.mainURL, mainURL)
        XCTAssertEqual(try Data(contentsOf: imported.mainURL), originalMain)
        XCTAssertEqual(try Data(contentsOf: try XCTUnwrap(imported.infoURL)), originalInfo)

        try Data("changed source".utf8).write(to: mainURL, options: .atomic)
        XCTAssertEqual(try Data(contentsOf: imported.mainURL), originalMain)
        XCTAssertEqual(try SaveSourceResolver.files([mainURL, infoURL]).mode, .twoFiles)
    }

    @MainActor
    func testSessionEditingFreezeRejectsLateBindingsButCanInstallCommittedSnapshot() throws {
        let harness = try makeTransactionHarness()
        defer { try? FileManager.default.removeItem(at: harness.root) }
        let pair = try harness.service.read(source: harness.source)
        let parsed = try SaveParser.parse(mainData: pair.main, infoData: pair.info, catalog: [], recipeCatalog: [:])
        let session = SaveSession(source: harness.source, parsed: parsed, pair: pair)
        session.draft.money += 10
        let submitted = session.draft
        let diff = try XCTUnwrap(session.diffs.first)
        session.setEditingLocked(true)
        session.draft.money = 999
        session.draft.farmActions.clearWeeds = true
        session.discardChanges()
        session.revert(diff: diff)
        XCTAssertEqual(session.draft, submitted)
        let rendered = try SaveMutator.render(parsed: parsed, draft: submitted)
        let committedPair = SavePairData(main: rendered.mainData, info: rendered.infoData)
        let committed = try SaveParser.parse(mainData: committedPair.main, infoData: committedPair.info, catalog: [], recipeCatalog: [:])
        session.replaceParsed(committed, pair: committedPair)
        XCTAssertEqual(session.draft.money, submitted.money)
        XCTAssertFalse(session.hasChanges)
        XCTAssertTrue(session.isEditingLocked)
        session.setEditingLocked(false)
        session.draft.money += 1
        XCTAssertTrue(session.hasChanges)
    }

    @MainActor
    func testWorkerTransfersOnlyFreshParsedTreesAndReturnsVerifiedPair() async throws {
        let harness = try makeTransactionHarness()
        defer { try? FileManager.default.removeItem(at: harness.root) }
        let worker = SaveWorkService(backupRootURL: harness.root.appendingPathComponent("Backups"),
                                     transactionDirectoryURL: harness.journalDirectory)
        let loaded = try await worker.load(source: harness.source, items: [], recipes: [:])
        let session = SaveSession(source: loaded.source, parsed: loaded.parsed, pair: loaded.pair)
        session.draft.money = 777
        let original = session.pair
        let submitted = session.draft
        let target = try await worker.render(original: original, originalDraft: session.originalDraft, draft: submitted, items: [], recipes: [:])
        let committed = try await worker.write(source: harness.source, expected: original, target: target,
                                                reason: "worker transfer test", items: [], recipes: [:])
        session.replaceParsed(committed.parsed, pair: committed.pair)
        XCTAssertEqual(session.draft.money, 777)
        XCTAssertFalse(session.hasChanges)
        XCTAssertEqual(session.mainHash, target.mainHash)
        XCTAssertEqual(try harness.service.read(source: harness.source).mainHash, target.mainHash)
        XCTAssertEqual(loaded.parsed.draft.money, 1285, "Previously transferred trees are not retained or mutated by the worker")
    }

    @MainActor
    func testWorkerPreservesInventoryBaselineWhenReparsingForUnrelatedEdit() async throws {
        let extendedMain = sampleMain.replacingOccurrences(of: "<stack>3</stack>", with: "<stack>1200</stack>")
        let original = SavePairData(main: Data(extendedMain.utf8), info: Data(sampleInfo.utf8))
        let parsed = try SaveParser.parse(mainData: original.main, infoData: original.info, catalog: [], recipeCatalog: [:])
        let worker = SaveWorkService()
        var draft = parsed.draft
        draft.money += 1
        let target = try await worker.render(original: original, originalDraft: parsed.draft, draft: draft,
                                              items: [], recipes: [:])
        let root = try XMLTreeParser().parse(SaveCodec.decode(target.main).xmlData)
        XCTAssertEqual(root.child(named: "player")?.child(named: "items")?.xmlString(),
                       parsed.mainRoot.child(named: "player")?.child(named: "items")?.xmlString())
        XCTAssertEqual(root.child(named: "player")?.int(named: "money"), draft.money)
    }

    @MainActor
    func testWorkerRejectsInvalidTargetBeforeCreatingBackupOrWritingSource() async throws {
        let harness = try makeTransactionHarness()
        defer { try? FileManager.default.removeItem(at: harness.root) }
        let worker = SaveWorkService(backupRootURL: harness.root.appendingPathComponent("Backups"),
                                     transactionDirectoryURL: harness.journalDirectory)
        let original = try harness.service.read(source: harness.source)
        let invalid = SavePairData(main: Data("<SaveGame/>".utf8), info: original.info)
        do {
            _ = try await worker.write(source: harness.source, expected: original, target: invalid,
                                       reason: "invalid target", items: [], recipes: [:])
            XCTFail("Invalid target unexpectedly committed")
        } catch {
            XCTAssertEqual(try harness.service.read(source: harness.source).mainHash, original.mainHash)
            let backups = try await worker.listBackups()
            XCTAssertTrue(backups.isEmpty)
        }
    }

    @MainActor
    func testCatalogAndBackupInitializationSurviveUnavailableTransactionDirectory() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("IndependentInit-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let blocked = root.appendingPathComponent("not-a-directory")
        try Data("occupied".utf8).write(to: blocked)
        let worker = SaveWorkService(backupRootURL: root.appendingPathComponent("Backups"),
                                     transactionDirectoryURL: blocked)
        let catalogs = await worker.initialize()
        XCTAssertFalse(catalogs.items.isEmpty)
        XCTAssertFalse(catalogs.recipes.isEmpty)
        XCTAssertFalse(catalogs.crops.isEmpty)
        XCTAssertTrue(catalogs.warnings.contains { $0.contains("安全写回与中断恢复暂不可用") })
        let backups = try await worker.listBackups()
        XCTAssertTrue(backups.isEmpty, "Backup access does not require a working transaction directory")

        let unavailableBackups = SaveWorkService(backupRootURL: blocked, transactionDirectoryURL: root.appendingPathComponent("Transactions"))
        let degraded = await unavailableBackups.initialize()
        XCTAssertEqual(degraded.items.count, catalogs.items.count)
        XCTAssertEqual(degraded.crops.count, catalogs.crops.count)
        XCTAssertTrue(degraded.warnings.contains { $0.contains("本地备份暂不可用") })
    }

    private func makeTransactionHarness() throws -> (
        root: URL,
        source: SaveSource,
        backupStore: BackupStore,
        service: SaveTransactionService,
        journalDirectory: URL
    ) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("PelicanSaveEditorTests-\(UUID().uuidString)", isDirectory: true)
        let farm = root.appendingPathComponent("UnitFarm_123456", isDirectory: true)
        try FileManager.default.createDirectory(at: farm, withIntermediateDirectories: true)
        try Data(sampleMain.utf8).write(to: farm.appendingPathComponent("UnitFarm_123456"))
        try Data(sampleInfo.utf8).write(to: farm.appendingPathComponent("SaveGameInfo"))

        let backupStore = try BackupStore(
            rootURL: root.appendingPathComponent("Backups", isDirectory: true)
        )
        let journalDirectory = root.appendingPathComponent("Transactions", isDirectory: true)
        let service = try SaveTransactionService(
            backupStore: backupStore,
            journalDirectoryURL: journalDirectory
        )
        return (
            root,
            try SaveSourceResolver.directory(farm),
            backupStore,
            service,
            journalDirectory
        )
    }
}

private let sampleMain = """
<?xml version="1.0" encoding="utf-8"?>
<SaveGame xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:xsd="http://www.w3.org/2001/XMLSchema">
  <player>
    <name>Test</name>
    <farmName>Test Farm</farmName>
    <favoriteThing>Apples</favoriteThing>
    <money>1285</money>
    <maxHealth>100</maxHealth>
    <maxStamina>270</maxStamina>
    <Gender>Male</Gender>
    <gender>Male</gender>
    <hair>2</hair>
    <skin>1</skin>
    <accessory>-1</accessory>
    <yearForSaveGame>1</yearForSaveGame>
    <seasonForSaveGame>0</seasonForSaveGame>
    <dayOfMonthForSaveGame>6</dayOfMonthForSaveGame>
    <farmingLevel>1</farmingLevel>
    <fishingLevel>2</fishingLevel>
    <foragingLevel>3</foragingLevel>
    <miningLevel>4</miningLevel>
    <combatLevel>5</combatLevel>
    <experiencePoints><int>100</int><int>380</int><int>770</int><int>1300</int><int>2150</int></experiencePoints>
    <items>
      <Item xsi:type="Object">
        <isLostItem>false</isLostItem><category>-75</category><hasBeenInInventory>true</hasBeenInInventory>
        <name>Parsnip</name><parentSheetIndex>24</parentSheetIndex><itemId>24</itemId>
        <specialItem>false</specialItem><isRecipe>false</isRecipe><quality>0</quality><stack>3</stack>
        <unknownItemField>preserve</unknownItemField>
      </Item>
      <Item xsi:nil="true"/>
    </items>
    <friendshipData>
      <item><key><string>Abigail</string></key><value><Friendship>
        <Points>500</Points><GiftsThisWeek>0</GiftsThisWeek><GiftsToday>0</GiftsToday>
        <TalkedToToday>false</TalkedToToday><ProposalRejected>false</ProposalRejected>
        <Status>Friendly</Status><Proposer>0</Proposer><RoommateMarriage>false</RoommateMarriage>
      </Friendship></value></item>
    </friendshipData>
    <cookingRecipes><item custom="preserve"><key><string>Fried Egg</string></key><value><int>1</int><modField>yes</modField></value></item></cookingRecipes>
    <craftingRecipes><item><key><string>Chest</string></key><value><int>2</int></value></item></craftingRecipes>
  </player>
  <year>1</year><currentSeason>spring</currentSeason><dayOfMonth>6</dayOfMonth>
  <millisecondsPlayed>9000000</millisecondsPlayed><whichFarm>0</whichFarm>
  <gameVersion>1.6.8</gameVersion>
  <unknownSection><keepMe custom="still-here">yes</keepMe></unknownSection>
</SaveGame>
"""

private let sampleInfo = """
<?xml version="1.0" encoding="utf-8"?>
<Farmer xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
  <name>Test</name><farmName>Test Farm</farmName><favoriteThing>Apples</favoriteThing>
  <money>1285</money><maxHealth>100</maxHealth><maxStamina>270</maxStamina>
  <Gender>Male</Gender><gender>Male</gender><hair>2</hair><skin>1</skin><accessory>-1</accessory>
  <yearForSaveGame>1</yearForSaveGame><seasonForSaveGame>0</seasonForSaveGame><dayOfMonthForSaveGame>6</dayOfMonthForSaveGame>
  <farmingLevel>1</farmingLevel><fishingLevel>2</fishingLevel><foragingLevel>3</foragingLevel><miningLevel>4</miningLevel><combatLevel>5</combatLevel>
  <experiencePoints><int>100</int><int>380</int><int>770</int><int>1300</int><int>2150</int></experiencePoints>
  <gameVersion>1.6.8</gameVersion>
</Farmer>
"""

private let sampleFarmMap = """
<?xml version="1.0" encoding="utf-8"?>
<SaveGame xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
  <locations>
    <GameLocation xsi:type="Farm">
      <name>Farm</name>
      <objects>
        <item>
          <key><Vector2><X>10</X><Y>12</Y></Vector2></key>
          <value><Object><name>Chest</name><itemId>130</itemId><stack>2</stack><bigCraftable>true</bigCraftable></Object></value>
        </item>
      </objects>
      <terrainFeatures>
        <item>
          <key><Vector2><X>2</X><Y>3</Y></Vector2></key>
          <value><TerrainFeature xsi:type="HoeDirt"><crop><netSeedIndex>472</netSeedIndex><currentPhase>1</currentPhase><dead>false</dead></crop></TerrainFeature></value>
        </item>
        <item>
          <key><Vector2><X>4</X><Y>5</Y></Vector2></key>
          <value><TerrainFeature xsi:type="Tree"><treeType>1</treeType></TerrainFeature></value>
        </item>
        <item>
          <key><Vector2><X>3</X><Y>3</Y></Vector2></key>
          <value><TerrainFeature xsi:type="HoeDirt"><state>0</state><crop><netSeedIndex>472</netSeedIndex><currentPhase>1</currentPhase><dead>true</dead></crop></TerrainFeature></value>
        </item>
        <item>
          <key><Vector2><X>6</X><Y>7</Y></Vector2></key>
          <value><TerrainFeature xsi:type="FruitTree"><treeId>628</treeId><growthStage>4</growthStage></TerrainFeature></value>
        </item>
        <item>
          <key><Vector2><X>8</X><Y>9</Y></Vector2></key>
          <value><TerrainFeature xsi:type="Grass"><numberOfWeeds>4</numberOfWeeds></TerrainFeature></value>
        </item>
        <item>
          <key><Vector2><X>9</X><Y>9</Y></Vector2></key>
          <value><TerrainFeature xsi:type="HoeDirt"><crop xsi:nil="true"/></TerrainFeature></value>
        </item>
      </terrainFeatures>
      <buildings>
        <Building xsi:type="Barn"><buildingType>Deluxe Barn</buildingType><tileX>20</tileX><tileY>10</tileY><daysOfConstructionLeft>0</daysOfConstructionLeft></Building>
      </buildings>
      <animals>
        <item>
          <key><long>1</long></key>
          <value><FarmAnimal><name>Bessie</name><type>White Cow</type><position><X>640</X><Y>768</Y></position></FarmAnimal></value>
        </item>
      </animals>
      <resourceClumps>
        <ResourceClump><parentSheetIndex>600</parentSheetIndex><tile><X>30</X><Y>31</Y></tile></ResourceClump>
      </resourceClumps>
    </GameLocation>
  </locations>
</SaveGame>
"""
