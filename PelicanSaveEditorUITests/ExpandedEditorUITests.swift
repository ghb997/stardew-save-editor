import XCTest

final class ExpandedEditorUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    @MainActor
    func testChestQuantityDraftAndReview() throws {
        let app = try launch("storage")
        defer { app.terminate() }
        let chest = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "storage.container.")).firstMatch
        // NavigationLink may be exposed as a cell's button depending on iOS.
        let target = chest.exists ? chest : app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "storage.container.")).firstMatch
        try tap(target, app)
        try tap(app.buttons["storage.slot.0"], app)
        let quantity = app.textFields["storage.quantity"]
        try tap(app.buttons["storage.quantity.clear"], app)
        try tap(quantity, app)
        quantity.typeText("25")
        try tap(app.buttons["storage.apply"], app)
        XCTAssertTrue(app.buttons["storage.slot.0"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["storage.slot.0"].label.contains("25"), app.debugDescription)
        screenshot("build14-storage-quantity", app)
        try tap(app.buttons["editor.review.open"], app)
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "箱子与冰箱")).firstMatch.waitForExistence(timeout: 10))
        screenshot("build14-storage-review", app)
    }

    @MainActor
    func testWeatherLuckPresetRestoreAndWeatherReview() throws {
        let app = try launch("weather")
        defer { app.terminate() }
        try tap(app.buttons["weather.luck.best"], app)
        let currentLuck = app.staticTexts["weather.luck.current"]
        XCTAssertTrue(currentLuck.waitForExistence(timeout: 10))
        XCTAssertTrue(currentLuck.label.contains("0.1000"))
        screenshot("build14-weather-luck", app)
        try tap(app.buttons["weather.luck.restore"], app)
        XCTAssertTrue(app.staticTexts["weather.luck.current"].label.contains("0.0250"))
        try tap(app.buttons["weather.region.Default"], app, downFirst: true)
        try tap(app.buttons["雷雨"], app)
        XCTAssertTrue(app.staticTexts["原始：雨天 → 草稿：雷雨"].waitForExistence(timeout: 10))
        try tap(app.buttons["editor.review.open"], app)
        XCTAssertTrue(app.staticTexts["山谷明日天气"].waitForExistence(timeout: 10))
        screenshot("build14-weather-review", app)
    }

    @MainActor
    func testMachineSelectionPreviewApplyAndUndo() throws {
        let app = try launch("machines")
        defer { app.terminate() }
        try tap(app.buttons["machines.selectVisible"], app)
        try tap(app.buttons["machines.preview"], app)
        XCTAssertTrue(app.navigationBars["完成加工预览"].waitForExistence(timeout: 10))
        screenshot("build14-machines-preview", app)
        try tap(app.buttons["machines.apply"], app)
        XCTAssertTrue(app.staticTexts["待保存：完成加工"].waitForExistence(timeout: 10))
        screenshot("build14-machines-applied", app)
        let undo = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "machines.undo.")).firstMatch
        try tap(undo, app)
        XCTAssertFalse(app.staticTexts["待保存：完成加工"].exists)
        XCTAssertTrue(app.switches.matching(NSPredicate(format: "label CONTAINS %@", "选择完成")).firstMatch.exists)
    }

    @MainActor
    func testBundleSupplyPreviewAddsInventoryDiffWithoutCompletingBundle() throws {
        let app = try launch("bundles")
        defer { app.terminate() }
        try tap(app.buttons["bundles.select.0:0"], app)
        try tap(app.buttons["bundles.preview"], app, downFirst: true)
        XCTAssertTrue(app.navigationBars["材料补给预览"].waitForExistence(timeout: 10))
        screenshot("build14-bundle-supply-preview", app)
        try tap(app.buttons["bundles.apply"], app)
        XCTAssertTrue(app.staticTexts["0 / 2 个收集包已完成"].waitForExistence(timeout: 10))
        try tap(app.buttons["editor.review.open"], app)
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "防风草")).firstMatch.waitForExistence(timeout: 10))
        screenshot("build14-bundle-inventory-draft", app)
    }

    @MainActor
    private func launch(_ tool: String) throws -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-tab", "tools", "--ui-demo", "--ui-expanded", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["工具"].waitForExistence(timeout: 40))
        try tap(app.buttons["editor.tool.\(tool)"], app, attempts: 24)
        return app
    }

    @MainActor
    private func tap(_ element: XCUIElement, _ app: XCUIApplication, attempts: Int = 10, downFirst: Bool = false) throws {
        for _ in 0..<attempts {
            if element.exists && element.isHittable { element.tap(); return }
            if downFirst { app.swipeDown() } else { app.swipeUp() }
        }
        screenshot("build14-missing-control", app)
        XCTFail("Missing or obstructed control: \(element)\n\(app.debugDescription)")
        throw NSError(domain: "ExpandedEditorUITests", code: 1)
    }

    @MainActor
    private func screenshot(_ name: String, _ app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
