import XCTest

final class PersistenceUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    @MainActor
    func testDraftSurvivesTerminationAndCanBeRecoveredThenDiscarded() throws {
        let app = XCUIApplication()
        let args = ["--ui-library", UUID().uuidString, "--ui-tab", "tools", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launchArguments = args + ["--ui-library-seed"]
        app.launch()
        defer { app.terminate() }
        let favorite = try openCharacter(app)
        favorite.tap(); favorite.typeText("X\n")
        let value = try XCTUnwrap(favorite.value as? String)
        XCTAssertTrue(value.contains("X"))
        app.buttons["editor.shell.close"].tap()
        let persisted = app.staticTexts["draft.storage.status"]
        XCTAssertTrue(persisted.waitForExistence(timeout: 15))
        let predicate = NSPredicate(format: "label CONTAINS %@", "草稿已暂存")
        let persistence = XCTNSPredicateExpectation(predicate: predicate, object: persisted)
        XCTAssertEqual(XCTWaiter.wait(for: [persistence], timeout: 15), .completed)
        app.terminate()
        app.launchArguments = args; app.launch()
        let resume = app.buttons["library.continue"]
        XCTAssertTrue(resume.waitForExistence(timeout: 30)); resume.tap()
        let recover = app.alerts.buttons["恢复草稿"]
        XCTAssertTrue(recover.waitForExistence(timeout: 30)); recover.tap()
        dismissNotice(app)
        let restored = try openCharacter(app)
        XCTAssertEqual(restored.value as? String, value)
        app.buttons["editor.shell.close"].tap()
        app.terminate(); app.launch()
        XCTAssertTrue(resume.waitForExistence(timeout: 30)); resume.tap()
        let discard = app.alerts.buttons["放弃这份草稿"]
        XCTAssertTrue(discard.waitForExistence(timeout: 30)); discard.tap()
        dismissNotice(app)
        XCTAssertEqual(try openCharacter(app).value as? String, "Tea")
    }

    @MainActor
    func testSavedCopySurvivesTerminationAndOpensVerifiedExportScreen() throws {
        let app = XCUIApplication()
        let args = ["--ui-library", UUID().uuidString, "--ui-tab", "tools", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launchArguments = args + ["--ui-library-seed"]; app.launch()
        defer { app.terminate() }
        let favorite = try openCharacter(app)
        favorite.tap(); favorite.typeText("Y\n")
        let value = favorite.value as? String
        app.buttons["editor.review.open"].tap()
        let save = app.buttons["保存副本并导出"]
        for _ in 0..<12 where !save.isHittable { app.swipeUp() }
        XCTAssertTrue(save.isHittable); save.tap()
        app.alerts.buttons["仅保存到应用副本"].tap()
        let done = app.alerts.buttons["好"]
        XCTAssertTrue(done.waitForExistence(timeout: 30)); done.tap()
        app.terminate(); app.launchArguments = args; app.launch()
        let resume = app.buttons["library.continue"]
        XCTAssertTrue(resume.waitForExistence(timeout: 30)); resume.tap()
        dismissNotice(app)
        XCTAssertFalse(app.alerts["恢复未保存草稿"].exists)
        let library = app.buttons["tools.library"]
        try revealDirectoryControl(library, in: app); library.tap()
        XCTAssertTrue(app.staticTexts["已保存，待导出"].waitForExistence(timeout: 15))
        let libraryScreenshot = XCTAttachment(screenshot: app.screenshot())
        libraryScreenshot.name = "build20-local-library"; libraryScreenshot.lifetime = .keepAlways; add(libraryScreenshot)
        app.buttons["完成"].tap()
        XCTAssertEqual(try openCharacter(app).value as? String, value)
        app.buttons["editor.review.open"].tap()
        let export = app.buttons["再次导出已保存副本"]
        for _ in 0..<12 where !export.isHittable { app.swipeUp() }
        XCTAssertTrue(export.isHittable); export.tap()
        XCTAssertTrue(app.buttons["export.choose.directory"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["export.commit"].exists, "No write can be offered before selecting and inspecting the target")
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "build20-verified-export"; attachment.lifetime = .keepAlways; add(attachment)
    }

    @MainActor
    func testSaveReturnAndContinueEditingPersistsBothChanges() throws {
        let app = XCUIApplication()
        let args = ["--ui-library", UUID().uuidString, "--ui-tab", "tools", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launchArguments = args + ["--ui-library-seed"]; app.launch()
        defer { app.terminate() }
        var favorite = try openCharacter(app)
        favorite.tap(); favorite.typeText("A\n")
        let firstValue = try XCTUnwrap(favorite.value as? String)
        app.buttons["editor.review.open"].tap()
        try saveLocalCopy(app)
        try returnFromReview(app)
        favorite = app.textFields["character.favorite"]
        try revealInEditor(favorite, app)
        XCTAssertEqual(favorite.value as? String, firstValue)
        favorite.tap(); favorite.typeText("B\n")
        let secondValue = try XCTUnwrap(favorite.value as? String)
        XCTAssertTrue(secondValue.contains("A") && secondValue.contains("B"))
        app.buttons["editor.review.open"].tap()
        try saveLocalCopy(app)
        try returnFromReview(app)
        app.buttons["editor.shell.close"].tap()
        app.terminate(); app.launchArguments = args; app.launch()
        let resume = app.buttons["library.continue"]
        XCTAssertTrue(resume.waitForExistence(timeout: 30)); resume.tap()
        dismissNotice(app)
        XCTAssertFalse(app.alerts["恢复未保存草稿"].exists)
        XCTAssertEqual(try openCharacter(app).value as? String, secondValue)
        capture("build21-second-save-reopened", app)
    }

    @MainActor
    func testReloadFromReviewThenEditAndSaveUsesCurrentSession() throws {
        let app = XCUIApplication()
        let args = ["--ui-library", UUID().uuidString, "--ui-tab", "tools", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launchArguments = args + ["--ui-library-seed"]; app.launch()
        defer { app.terminate() }
        var favorite = try openCharacter(app)
        favorite.tap(); favorite.typeText("DiscardMe\n")
        app.buttons["editor.review.open"].tap()
        let reload = app.buttons["重新载入文件"]
        try revealInEditor(reload, app); reload.tap()
        let confirm = app.alerts.buttons["放弃草稿并重新载入"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 10)); confirm.tap()
        let done = app.alerts.buttons["好"]
        XCTAssertTrue(done.waitForExistence(timeout: 30)); done.tap()
        try returnFromReview(app)
        favorite = app.textFields["character.favorite"]
        try revealInEditor(favorite, app)
        XCTAssertEqual(favorite.value as? String, "Tea", "Reload must update the already open editor")
        favorite.tap(); favorite.typeText("R\n")
        let value = try XCTUnwrap(favorite.value as? String)
        app.buttons["editor.review.open"].tap()
        try saveLocalCopy(app)
        try returnFromReview(app)
        app.buttons["editor.shell.close"].tap()
        app.terminate(); app.launchArguments = args; app.launch()
        let resume = app.buttons["library.continue"]
        XCTAssertTrue(resume.waitForExistence(timeout: 30)); resume.tap()
        dismissNotice(app)
        XCTAssertEqual(try openCharacter(app).value as? String, value,
                       "Edits after reload must save to the active session and survive relaunch")
        capture("build21-reload-edit-save-reopened", app)
    }

    @MainActor
    private func revealInEditor(_ element: XCUIElement, _ app: XCUIApplication) throws {
        for _ in 0..<12 where !element.isHittable { app.swipeUp() }
        XCTAssertTrue(element.isHittable)
    }

    @MainActor
    private func saveLocalCopy(_ app: XCUIApplication) throws {
        let save = app.buttons["保存副本并导出"]
        try revealInEditor(save, app)
        XCTAssertTrue(save.isEnabled)
        save.tap()
        let confirm = app.alerts.buttons["仅保存到应用副本"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 10)); confirm.tap()
        let done = app.alerts.buttons["好"]
        XCTAssertTrue(done.waitForExistence(timeout: 30)); done.tap()
        XCTAssertFalse(save.isEnabled, "Successful saving must clear pending changes")
    }

    @MainActor
    private func returnFromReview(_ app: XCUIApplication) throws {
        let back = app.buttons["editor.shell.close"]
        XCTAssertTrue(back.waitForExistence(timeout: 10))
        XCTAssertEqual(back.label, "返回编辑")
        capture("build21-review-after-operation", app)
        back.tap()
        XCTAssertTrue(app.buttons["editor.review.open"].waitForExistence(timeout: 10))
    }

    @MainActor
    private func capture(_ name: String, _ app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }

    @MainActor
    private func openCharacter(_ app: XCUIApplication) throws -> XCUIElement {
        XCTAssertTrue(app.buttons["farm.load.switch"].waitForExistence(timeout: 30))
        try selectToolCategory(for: "character", in: app)
        let entry = app.buttons["editor.tool.character"]
        try revealDirectoryControl(entry, in: app); entry.tap()
        let field = app.textFields["character.favorite"]
        for _ in 0..<10 where !field.isHittable { app.swipeUp() }
        XCTAssertTrue(field.isHittable)
        return field
    }
    @MainActor
    private func dismissNotice(_ app: XCUIApplication) {
        let okay = app.alerts.buttons["好"]
        if okay.waitForExistence(timeout: 5) { okay.tap() }
    }
}
