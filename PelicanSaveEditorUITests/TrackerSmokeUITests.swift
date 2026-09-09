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
        for _ in 0..<7 {
            if target.exists && target.isHittable { break }
            strip.swipeLeft()
        }
        if !target.isHittable {
            for _ in 0..<7 {
                if target.exists && target.isHittable { break }
                strip.swipeRight()
            }
        }
        try tap(target, app: app)
        try wait(target, predicate: NSPredicate(format: "selected == true"), app: app)
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
