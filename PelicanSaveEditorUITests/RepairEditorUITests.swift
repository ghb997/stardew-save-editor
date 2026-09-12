import XCTest

final class RepairEditorUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    @MainActor
    func testToolUpgradeCreatesReviewDiff() throws {
        let app = try launch("equipment")
        defer { app.terminate() }
        try tap(equipment(in: app).element(boundBy: 0), app)
        try tap(app.buttons["equipment.field.upgradeLevel"], app)
        try tap(app.buttons["铱"], app)
        try tap(app.buttons["equipment.apply"], app)
        try tap(app.buttons["editor.review.open"], app)
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "升级等级")).firstMatch.waitForExistence(timeout: 10))
        screenshot("build15-equipment-review", app)
    }

    @MainActor
    func testEquipmentCancelLeavesDraftUnchanged() throws {
        let app = try launch("equipment")
        defer { app.terminate() }
        try tap(equipment(in: app).element(boundBy: 0), app)
        try tap(app.buttons["equipment.field.upgradeLevel"], app)
        try tap(app.buttons["铱"], app)
        try tap(app.buttons["取消"], app)
        try tap(app.buttons["editor.review.open"], app)
        XCTAssertTrue(app.staticTexts["没有待保存的更改"].waitForExistence(timeout: 10))
        screenshot("build15-equipment-cancel", app)
    }

    @MainActor
    func testWeaponInvalidInputAndRestore() throws {
        let app = try launch("equipment")
        defer { app.terminate() }
        try tap(equipment(in: app).element(boundBy: 1), app)
        try tap(app.buttons["equipment.clear.minDamage"], app)
        try tap(app.buttons["equipment.apply"], app)
        let error = app.staticTexts["equipment.error"]
        XCTAssertTrue(error.waitForExistence(timeout: 10))
        XCTAssertTrue(error.label.contains("有效"), app.debugDescription)
        let field = app.textFields["equipment.field.minDamage"]
        try tap(field, app)
        field.typeText("90")
        try tap(app.buttons["equipment.apply"], app)
        XCTAssertTrue(error.label.contains("最低伤害不能大于最高伤害"), app.debugDescription)
        screenshot("build15-equipment-invalid-damage", app)
        try tap(app.buttons["equipment.restore"], app)
        try tap(app.buttons["equipment.apply"], app)
        try tap(app.buttons["editor.review.open"], app)
        XCTAssertTrue(app.staticTexts["没有待保存的更改"].waitForExistence(timeout: 10))
    }

    @MainActor
    func testCollectionSupplyCreatesInventoryDraftWithoutMarkingDonation() throws {
        let app = try launch("collections")
        defer { app.terminate() }
        let search = app.searchFields.firstMatch
        try tap(search, app, downFirst: true)
        search.typeText("97")
        try tap(app.buttons["collection.item.97"], app)
        // LabeledContent exposes its title and value as one accessibility label.
        let record = app.staticTexts["记录、缺少记录"]
        XCTAssertTrue(record.waitForExistence(timeout: 10), app.debugDescription)
        try tap(app.buttons["collection.supply"], app)
        XCTAssertTrue(app.staticTexts["collection.feedback"].label.contains("已加入背包草稿"))
        XCTAssertTrue(record.exists, app.debugDescription)
        screenshot("build15-collection-supply", app)
        try tap(app.buttons["完成"], app)
        try tap(app.buttons["editor.review.open"], app)
        XCTAssertTrue(app.staticTexts["槽位 3"].waitForExistence(timeout: 10))
        screenshot("build15-collection-review", app)
    }

    @MainActor
    private func equipment(in app: XCUIApplication) -> XCUIElementQuery {
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "equipment.item."))
    }

    @MainActor
    private func launch(_ tool: String) throws -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-tab", "tools", "--ui-demo", "--ui-repair", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "editor.tools.list").firstMatch.waitForExistence(timeout: 40))
        try tap(app.buttons["editor.tool.\(tool)"], app, attempts: 24)
        return app
    }

    @MainActor
    private func tap(_ element: XCUIElement, _ app: XCUIApplication, attempts: Int = 12, downFirst: Bool = false) throws {
        for _ in 0..<attempts {
            if element.exists && element.isHittable { element.tap(); return }
            if downFirst { app.swipeDown() } else { app.swipeUp() }
        }
        screenshot("build15-missing-control", app)
        XCTFail("Missing or obstructed control: \(element)\n\(app.debugDescription)")
        throw NSError(domain: "RepairEditorUITests", code: 1)
    }

    @MainActor
    private func screenshot(_ name: String, _ app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
