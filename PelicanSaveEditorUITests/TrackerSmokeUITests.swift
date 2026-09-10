import XCTest

final class TrackerSmokeUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testOverviewFiltersAndGroupExpansion() throws {
        let app = try launchTracker()
        defer { app.terminate() }
        try selectHomeFilter("overview", app: app)

        let groups = [("basic", "character"), ("collections", "progress"),
                      ("life", "relationships"), ("status", "review")]
        for (group, firstSection) in groups {
            try selectHomeFilter(group, app: app)
            let header = app.buttons["tracker.group.\(group)"]
            try revealVertically(header, app: app)
            try check(header.value as? String == "已展开", "\(group) should start expanded", app: app)
            try tap(header, app: app)
            try wait(header, predicate: NSPredicate(format: "value == %@", "已折叠"), app: app)
            try wait(app.buttons["tracker.section.\(firstSection)"],
                     predicate: NSPredicate(format: "exists == false"), app: app)
            try tap(header, app: app)
            try wait(header, predicate: NSPredicate(format: "value == %@", "已展开"), app: app)
            try check(app.buttons["tracker.section.\(firstSection)"].exists,
                      "Expanding \(group) must restore its first module", app: app)
            for (other, _) in groups where other != group {
                try check(!app.buttons["tracker.group.\(other)"].exists,
                          "The \(group) filter must hide \(other)", app: app)
            }
        }
        try selectHomeFilter("overview", app: app)
        attachScreenshot("tracker-overview-after-filters", app: app)
    }

    @MainActor
    func testAllElevenModulesOpenAndClose() throws {
        let app = try launchTracker()
        defer { app.terminate() }
        let modules: [(String, [(String, String)])] = [
            ("basic", [("character", "角色与农场"), ("appearance", "人物外观"),
                       ("farmhouse", "房屋与房间"), ("inventory", "背包物品")]),
            ("collections", [("progress", "状态与收藏进度"), ("recipes", "配方收集"),
                             ("wallet", "特殊物品与能力")]),
            ("life", [("relationships", "人物关系"), ("skills", "技能与职业"), ("animals", "农场动物")]),
            ("status", [("review", "存档状态")])
        ]
        for (group, sections) in modules {
            try selectHomeFilter(group, app: app)
            for (section, title) in sections {
                let row = app.buttons["tracker.section.\(section)"]
                try revealVertically(row, app: app)
                try tap(row, app: app)
                try require(app.navigationBars[title], app: app)
                let selectedChip = app.buttons["tracker.detail.filter.\(section)"]
                try require(selectedChip, app: app)
                try check(selectedChip.isSelected, "Opening \(section) must select its detail chip", app: app)
                attachScreenshot("tracker-detail-\(section)", app: app)
                let close = app.buttons["tracker.detail.close"]
                try tap(close, app: app)
                try wait(close, predicate: NSPredicate(format: "exists == false"), app: app)
            }
        }
    }

    @MainActor
    func testDetailSwitchingRecipeFiltersAndSearchEmptyState() throws {
        let app = try launchTracker()
        defer { app.terminate() }
        try selectHomeFilter("basic", app: app)
        let character = app.buttons["tracker.section.character"]
        try revealVertically(character, app: app)
        try tap(character, app: app)
        try require(app.navigationBars["角色与农场"], app: app)
        try selectChip("recipes", prefix: "tracker.detail.filter.", anchor: "character", app: app)
        try require(app.navigationBars["配方收集"], app: app)

        let status = app.buttons["tracker.recipeStatus"]
        try revealVertically(status, app: app)
        try tap(status, app: app)
        try tap(app.buttons["已解锁"], app: app)
        try require(app.staticTexts["Fried Egg"], app: app)

        try tap(status, app: app)
        try tap(app.buttons["未解锁"], app: app)
        try wait(app.staticTexts["Fried Egg"], predicate: NSPredicate(format: "exists == false"), app: app)

        let search = app.searchFields.firstMatch
        for _ in 0..<4 {
            if search.exists && search.isHittable { break }
            app.swipeDown()
        }
        try tap(search, app: app)
        search.typeText("tracker-no-matching-recipe-95831")
        let returnButton = app.buttons["global.keyboardReturn.button"]
        if returnButton.exists && returnButton.isHittable { returnButton.tap() }
        try require(app.staticTexts["没有匹配的配方，请试试其他名称或筛选"], app: app)
        attachScreenshot("tracker-recipes-search-empty", app: app)
    }

    @MainActor
    func testEmptyTrackerOpensToolsWithoutImportingFiles() throws {
        let app = try launchTracker(demo: false)
        defer { app.terminate() }
        try tap(app.buttons["tracker.loadFarm"], app: app)
        try wait(app.tabBars.buttons["工具"], predicate: NSPredicate(format: "selected == true"), app: app)
        let loadFarm = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "加载农场")).firstMatch
        try require(loadFarm, app: app)
        attachScreenshot("tracker-empty-state-tools-entry", app: app)
    }

    @MainActor
    private func launchTracker(demo: Bool = true) throws -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-tab", "tracker", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        if demo { app.launchArguments.append("--ui-demo") }
        app.launch()
        let ready = demo ? app.buttons["tracker.filter.overview"] : app.buttons["tracker.loadFarm"]
        try require(ready, app: app, timeout: 30)
        return app
    }

    @MainActor
    func testEditorCapacityAndInventorySearchUseDraft() throws {
        let app = try launchEditor("inventory")
        defer { app.terminate() }
        let capacity = app.segmentedControls["editor.inventory.capacity"]
        try require(capacity, app: app)
        try tap(capacity.buttons["36 格"], app: app)
        try wait(app.staticTexts["editor.inventory.capacitySummary"],
                 predicate: NSPredicate(format: "label CONTAINS %@", "/ 36"), app: app)
        attachScreenshot("editor-backpack-expanded", app: app)
        let search = app.searchFields.firstMatch
        try require(search, app: app)
        try tap(search, app: app)
        search.typeText("Diamond")
        try require(app.buttons["editor.inventory.slot.2"], app: app)
        try check(!app.buttons["editor.inventory.slot.0"].exists, "Search must hide other item slots", app: app)
        attachScreenshot("editor-backpack-search", app: app)
    }

    @MainActor
    func testRelationshipBatchPreviewCanCancelAndApplyOnlySearchedCharacter() throws {
        let app = try launchEditor("relationships")
        defer { app.terminate() }
        let search = app.searchFields.firstMatch
        try tap(search, app: app)
        search.typeText("Abigail\n")
        let batch = app.buttons["editor.relationships.batch.fillHearts"]
        try revealEditorControl(batch, app: app, viewportID: "editor.relationships.list")
        try tap(batch, app: app)
        try require(app.staticTexts["将修改 1 位角色"], app: app)
        attachScreenshot("editor-relationship-batch-preview", app: app)
        try tap(app.navigationBars["补满好感"].buttons["取消"], app: app)
        try wait(app.navigationBars["补满好感"], predicate: NSPredicate(format: "exists == false"), app: app)
        try tap(batch, app: app)
        let apply = app.buttons["editor.relationships.batch.apply"]
        try revealEditorControl(apply, app: app, viewportID: "editor.relationships.preview.list")
        try tap(apply, app: app)
        try wait(apply, predicate: NSPredicate(format: "exists == false"), app: app)
        let points = app.textFields["editor.relationship.Abigail.points"]
        try revealEditorControl(points, app: app, viewportID: "editor.relationships.list")
        try wait(points, predicate: NSPredicate(format: "value == %@ OR value == %@", "2,000", "2000"), app: app)
        attachScreenshot("editor-relationship-applied", app: app)
    }

    @MainActor
    func testGiftBatchResetShowsChangedCountersWithoutChangingHearts() throws {
        let app = try launchEditor("relationships")
        defer { app.terminate() }
        let batch = app.buttons["editor.relationships.batch.resetGifts"]
        try revealEditorControl(batch, app: app, viewportID: "editor.relationships.list")
        try tap(batch, app: app)
        try require(app.staticTexts["将修改 1 位角色"], app: app)
        attachScreenshot("editor-gift-reset-preview", app: app)
        let apply = app.buttons["editor.relationships.batch.apply"]
        try revealEditorControl(apply, app: app, viewportID: "editor.relationships.preview.list")
        try tap(apply, app: app)
        try wait(apply, predicate: NSPredicate(format: "exists == false"), app: app)
        let points = app.textFields["editor.relationship.Abigail.points"]
        try revealEditorControl(points, app: app, viewportID: "editor.relationships.list")
        try wait(points, predicate: NSPredicate(format: "value == %@ OR value == %@", "1,750", "1750"), app: app)
        let reset = app.buttons["editor.relationship.Abigail.resetGifts"]
        try revealEditorControl(reset, app: app, viewportID: "editor.relationships.list")
        try check(!reset.isEnabled, "No gifts should remain to reset", app: app)
        attachScreenshot("editor-gift-reset-applied", app: app)
    }

    @MainActor
    func testAppearanceColorsSupportPresetHexAndRestore() throws {
        let app = try launchEditor("appearance")
        defer { app.terminate() }
        let colors = app.buttons["editor.appearance.colors"]
        try revealEditorControl(colors, app: app, viewportID: "editor.appearance.form")
        try tap(colors, app: app)
        try require(app.navigationBars["外观颜色"], app: app)
        let preset = app.buttons["editor.appearance.color.preset.604020"]
        try revealEditorControl(preset, app: app, viewportID: "editor.appearance.colorForm")
        try tap(preset, app: app)
        let current = app.staticTexts["editor.appearance.color.current"]
        try revealEditorControl(current, app: app, viewportID: "editor.appearance.colorForm")
        try wait(current, predicate: NSPredicate(format: "label == %@", "#604020"), app: app)
        let hex = app.textFields["editor.appearance.color.hex"]
        let clearHex = app.buttons["editor.appearance.color.clearHex"]
        try revealEditorControl(clearHex, app: app, viewportID: "editor.appearance.colorForm")
        try tap(clearHex, app: app)
        try wait(hex, predicate: NSPredicate(format: "value == %@ OR value == %@", "", "#RRGGBB"), app: app)
        try check(!clearHex.isEnabled, "Cleared input must offer no further clearing", app: app)
        try wait(current, predicate: NSPredicate(format: "label == %@", "#604020"), app: app)
        try revealEditorControl(hex, app: app, viewportID: "editor.appearance.colorForm")
        try tap(hex, app: app)
        hex.typeText("123456")
        try wait(hex, predicate: NSPredicate(format: "value == %@", "123456"), app: app)
        try tap(app.buttons["global.keyboardReturn.button"], app: app)
        let applyHex = app.buttons["editor.appearance.color.applyHex"]
        try revealEditorControl(applyHex, app: app, viewportID: "editor.appearance.colorForm")
        try tap(applyHex, app: app)
        try revealEditorControl(current, app: app, viewportID: "editor.appearance.colorForm")
        try wait(current, predicate: NSPredicate(format: "label == %@", "#123456"), app: app)
        attachScreenshot("editor-appearance-color-hex", app: app)
        let restore = app.buttons["editor.appearance.color.restore"]
        try revealEditorControl(restore, app: app, viewportID: "editor.appearance.colorForm")
        try tap(restore, app: app)
        try check(!restore.isEnabled, "Restored hair color must have no remaining color change", app: app)
        try revealEditorControl(current, app: app, viewportID: "editor.appearance.colorForm")
        try wait(current, predicate: NSPredicate(format: "label == %@", "#B77C43"), app: app)
    }

    @MainActor
    func testRoomStyleLibraryBatchPreviewAndRoomRestore() throws {
        let app = try launchEditor("farmhouse")
        defer { app.terminate() }
        let number = app.textFields["editor.house.style.number"]
        try revealEditorControl(number, app: app, viewportID: "editor.house.form")
        let initialStyle = try XCTUnwrap(number.value as? String)
        let library = app.buttons["editor.house.styles"]
        try revealEditorControl(library, app: app, viewportID: "editor.house.form")
        try tap(library, app: app)
        try require(app.navigationBars["样式库"], app: app)
        let search = app.textFields["editor.house.style.search"]
        try revealEditorControl(search, app: app, viewportID: "editor.house.style.library")
        try tap(search, app: app)
        search.typeText("5\n")
        let style = app.buttons["editor.house.style.5"]
        try revealEditorControl(style, app: app, viewportID: "editor.house.style.library")
        try tap(style, app: app)
        try wait(app.staticTexts["editor.house.style.current"],
                 predicate: NSPredicate(format: "label ENDSWITH %@", "#5"), app: app)
        attachScreenshot("editor-room-style-library", app: app)
        try tap(app.navigationBars["样式库"].buttons["完成"], app: app)
        let batch = app.buttons["editor.house.style.batch"]
        try revealEditorControl(batch, app: app, viewportID: "editor.house.form")
        try tap(batch, app: app)
        try wait(app.staticTexts["editor.house.batch.count"],
                 predicate: NSPredicate(format: "label == %@", "将修改 4 个房间"), app: app)
        attachScreenshot("editor-room-style-batch-preview", app: app)
        try tap(app.navigationBars["批量套用样式"].buttons["取消"], app: app)
        try wait(app.navigationBars["批量套用样式"], predicate: NSPredicate(format: "exists == false"), app: app)
        try tap(batch, app: app)
        let apply = app.buttons["editor.house.batch.apply"]
        try revealEditorControl(apply, app: app, viewportID: "editor.house.batch.list")
        try tap(apply, app: app)
        try wait(apply, predicate: NSPredicate(format: "exists == false"), app: app)
        let restore = app.buttons["editor.house.restoreRoom"]
        try revealEditorControl(restore, app: app, viewportID: "editor.house.form")
        try tap(restore, app: app)
        try revealEditorControl(number, app: app, viewportID: "editor.house.form")
        try wait(number, predicate: NSPredicate(format: "value == %@", initialStyle), app: app)
        attachScreenshot("editor-room-restored-with-other-drafts", app: app)
        let restoreAll = app.buttons["editor.house.restoreAll"]
        try revealEditorControl(restoreAll, app: app, viewportID: "editor.house.form")
        try tap(restoreAll, app: app)
        try wait(restoreAll, predicate: NSPredicate(format: "exists == false"), app: app)
    }

    @MainActor
    func testMapScopedWaterPreviewPendingLocateAndUndo() throws {
        let app = try launchEditor("map")
        defer { app.terminate() }
        try tap(app.buttons["editor.map.objects"], app: app)
        try require(app.collectionViews["editor.map.list"], app: app)
        let search = app.searchFields.firstMatch
        try tap(search, app: app)
        search.typeText("X 14\n")
        let water = app.buttons["editor.map.batch.water"]
        try revealEditorControl(water, app: app, viewportID: "editor.map.list")
        try tap(water, app: app)
        try wait(app.staticTexts["editor.map.preview.count"],
                 predicate: NSPredicate(format: "label == %@", "将浇水 1 个对象"), app: app)
        attachScreenshot("editor-map-scoped-water-preview", app: app)
        try tap(app.navigationBars["浇水预览"].buttons["取消"], app: app)
        try wait(app.navigationBars["浇水预览"], predicate: NSPredicate(format: "exists == false"), app: app)
        try tap(water, app: app)
        let apply = app.buttons["editor.map.preview.apply"]
        try revealEditorControl(apply, app: app, viewportID: "editor.map.preview.list")
        try tap(apply, app: app)
        try wait(apply, predicate: NSPredicate(format: "exists == false"), app: app)
        let scope = app.segmentedControls["editor.map.scope"]
        try revealEditorControl(scope, app: app, viewportID: "editor.map.list")
        try tap(scope.buttons["待处理"], app: app)
        try wait(app.staticTexts["editor.map.matchCount"],
                 predicate: NSPredicate(format: "label == %@", "匹配 1 个 · 全图待处理 1 个"), app: app)
        attachScreenshot("editor-map-pending-search", app: app)
        let locate = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "editor.map.locate.")).firstMatch
        try revealEditorControl(locate, app: app, viewportID: "editor.map.list")
        try tap(locate, app: app)
        try wait(app.navigationBars["地图对象"], predicate: NSPredicate(format: "exists == false"), app: app)
        let action = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "editor.map.entity.action.")).firstMatch
        try revealEditorControl(action, app: app, viewportID: "editor.map.main")
        try check(action.label.contains("撤销"), "Located pending crop must offer undo on the map", app: app)
        attachScreenshot("editor-map-located-crop", app: app)
        try tap(action, app: app)
        try wait(action, predicate: NSPredicate(format: "label CONTAINS %@", "给此作物浇水"), app: app)
    }

    @MainActor
    private func launchEditor(_ section: String) throws -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-tab", "tools", "--ui-demo", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()
        let tool = app.buttons["editor.tool.\(section)"]
        try require(app.tabBars.buttons["工具"], app: app, timeout: 30)
        try require(tool, app: app, timeout: 30)
        try revealEditorControl(tool, app: app, viewportID: "editor.tools.list")
        try tap(tool, app: app)
        return app
    }

    @MainActor
    private func revealEditorControl(_ element: XCUIElement, app: XCUIApplication,
                                     viewportID: String) throws {
        // A lazy Form row may not exist in the AX tree yet, so querying its
        // elementType or identifier here can throw before any scrolling occurs.
        // Select the viewport by stable identity, independent of lazy rows
        // and of temporary background lists during navigation/search.
        let container = app.descendants(matching: .any).matching(identifier: viewportID).firstMatch
        try require(container, app: app)
        for attempt in 0..<18 {
            var viewport = container.frame.intersection(app.frame)
            // A scroll view can extend behind the navigation and tab bars.
            // Clip those areas before deciding whether a control is visible.
            if let bar = app.navigationBars.allElementsBoundByIndex.last {
                let frame = bar.frame
                if !frame.isEmpty && frame.intersects(viewport) && frame.minY < viewport.midY {
                    viewport = CGRect(x: viewport.minX, y: frame.maxY, width: viewport.width,
                                      height: max(0, viewport.maxY - frame.maxY))
                }
            }
            // Background tab bars remain in snapshots under full-screen
            // editors and sheets, but must not clip the foreground viewport.
            for bar in app.tabBars.allElementsBoundByIndex where app.navigationBars.count == 0 {
                let frame = bar.frame
                if !frame.isEmpty && frame.intersects(viewport) && frame.minY > viewport.midY {
                    viewport.size.height = max(0, frame.minY - viewport.minY)
                }
            }
            let standaloneSheets = ["editor.map.list", "editor.map.preview.list", "editor.house.batch.list",
                                    "editor.relationships.preview.list"]
            if !standaloneSheets.contains(container.identifier),
               let reviewBar = app.otherElements.matching(identifier: "editor.review.bar").allElementsBoundByIndex.last
                    ?? app.buttons.matching(identifier: "editor.review.open").allElementsBoundByIndex.last {
                let frame = reviewBar.frame.insetBy(dx: 0, dy: -10)
                if !frame.isEmpty && frame.intersects(viewport) && frame.minY > viewport.midY {
                    viewport.size.height = max(0, frame.minY - viewport.minY)
                }
            }
            try check(!viewport.isEmpty && viewport.minY.isFinite && viewport.maxY.isFinite,
                      "Editor scroll viewport must be visible: \(container.frame)", app: app)
            let frame = element.exists ? element.frame : .null
            let hasFrame = !frame.isEmpty && frame.minY.isFinite && frame.maxY.isFinite
            let visibleArea = viewport.insetBy(dx: -0.5, dy: 4)
            // Offscreen SwiftUI List fields may have an infinite, empty AX
            // frame. Never ask XCTest to compute their activation points.
            if hasFrame && visibleArea.contains(frame) { return }
            let moveTowardBottom = hasFrame ? frame.midY > viewport.midY : attempt < 9
            let distance = min(hasFrame ? max(abs(frame.midY - viewport.midY), 44) : 140,
                               viewport.height * 0.35)
            let direction: CGFloat = moveTowardBottom ? 1 : -1
            let origin = app.coordinate(withNormalizedOffset: .zero)
            let start = origin.withOffset(CGVector(dx: viewport.midX - app.frame.minX,
                dy: viewport.midY - app.frame.minY + direction * distance / 2))
            let end = origin.withOffset(CGVector(dx: viewport.midX - app.frame.minX,
                dy: viewport.midY - app.frame.minY - direction * distance / 2))
            start.press(forDuration: 0.05, thenDragTo: end)
        }
        try check(false, "Editor control could not be revealed: \(element)", app: app)
    }

    @MainActor
    private func selectHomeFilter(_ filter: String, app: XCUIApplication) throws {
        let strips = app.scrollViews.containing(.button, identifier: "tracker.filter.overview")
        let strip = strips.element(boundBy: max(0, strips.count - 1))
        for _ in 0..<7 {
            if strip.exists && strip.isHittable { break }
            app.swipeDown()
        }
        try selectChip(filter, prefix: "tracker.filter.", anchor: "overview", app: app)
    }

    @MainActor
    private func selectChip(_ name: String, prefix: String, anchor: String, app: XCUIApplication) throws {
        let target = app.buttons[prefix + name]
        // The last matching scroll view is the inner horizontal strip, rather
        // than the vertically scrolling tracker that also contains its buttons.
        let strips = app.scrollViews.containing(.button, identifier: prefix + anchor)
        let strip = strips.element(boundBy: max(0, strips.count - 1))
        try require(strip, app: app)
        // XCTest may throw while computing an offscreen chip's activation
        // point. Inspect geometry first; only ask for hittability once the
        // entire chip is inside the visible horizontal scroll viewport.
        for _ in 0..<14 {
            if isFullyVisible(target, within: strip, app: app) { break }
            let viewport = strip.frame.intersection(app.frame)
            if target.exists && target.frame.minX < viewport.minX {
                strip.swipeRight()
            } else {
                strip.swipeLeft()
            }
        }
        try check(isFullyVisible(target, within: strip, app: app),
                  "Chip \(prefix + name) must be visible within its 0.5pt border outset before tapping; "
                    + "button=\(target.frame), strip=\(strip.frame), app=\(app.frame)", app: app)
        try tap(target, app: app)
        try wait(target, predicate: NSPredicate(format: "selected == true"), app: app)
    }

    @MainActor
    private func isFullyVisible(_ element: XCUIElement, within scrollView: XCUIElement,
                                app: XCUIApplication) -> Bool {
        guard element.exists && scrollView.exists else { return false }
        let elementFrame = element.frame
        let viewport = scrollView.frame.intersection(app.frame)
        // The chips' centered 1pt capsule stroke extends their accessibility
        // frames by 0.5pt. Native failure attachments show the first/last chip
        // at x=15.5 / maxX=359.5 in a strip spanning x=16...359, even at rest.
        // Permit only that border outset, not a partially hidden chip. Keep
        // the center inside the real viewport and verify hittability afterward.
        let borderOutset: CGFloat = 0.5
        let center = CGPoint(x: elementFrame.midX, y: elementFrame.midY)
        return !elementFrame.isEmpty && !viewport.isEmpty
            && viewport.contains(center)
            && viewport.insetBy(dx: -borderOutset, dy: -borderOutset).contains(elementFrame)
    }

    @MainActor
    private func revealVertically(_ element: XCUIElement, app: XCUIApplication) throws {
        for _ in 0..<7 {
            if element.exists && element.isHittable { return }
            app.swipeUp()
        }
        try wait(element, predicate: NSPredicate(format: "exists == true AND hittable == true"), app: app)
    }

    @MainActor
    private func tap(_ element: XCUIElement, app: XCUIApplication) throws {
        try wait(element, predicate: NSPredicate(format: "exists == true AND hittable == true"), app: app)
        element.tap()
    }

    @MainActor
    private func require(_ element: XCUIElement, app: XCUIApplication, timeout: TimeInterval = 12) throws {
        try check(element.waitForExistence(timeout: timeout), "Missing element: \(element)", app: app)
    }

    @MainActor
    private func wait(_ element: XCUIElement, predicate: NSPredicate, app: XCUIApplication) throws {
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        let result = XCTWaiter.wait(for: [expectation], timeout: 12)
        try check(result == .completed, "Element did not satisfy \(predicate): \(element)", app: app)
    }

    @MainActor
    private func attachScreenshot(_ name: String, app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    private func check(_ passed: Bool, _ message: String, app: XCUIApplication,
                       file: StaticString = #filePath, line: UInt = #line) throws {
        guard passed else {
            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = "Tracker smoke failure"
            screenshot.lifetime = .keepAlways
            add(screenshot)
            let hierarchy = XCTAttachment(string: app.debugDescription)
            hierarchy.name = "Accessibility hierarchy"
            hierarchy.lifetime = .keepAlways
            add(hierarchy)
            XCTFail(message, file: file, line: line)
            throw SmokeFailure.assertion
        }
    }

    private enum SmokeFailure: Error { case assertion }
}
