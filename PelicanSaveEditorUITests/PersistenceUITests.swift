import XCTest

final class PersistenceUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    @MainActor
    func testSystemExportPickersCanCancelAndReopenWithoutLosingSavedCopy() throws {
        let app = XCUIApplication()
        // Deliberately omit --ui-export-fixture: both real UIKit pickers must
        // present and send their cancellation and dismissal callbacks.
        app.launchArguments = ["--ui-library", UUID().uuidString, "--ui-library-seed",
            "--ui-tab", "tools", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()
        defer { app.terminate() }
        let value = try editAndBeginExport("P", app)
        for attempt in 1...2 {
            let choose = app.buttons["export.choose.directory"]
            XCTAssertTrue(choose.waitForExistence(timeout: 10)); choose.tap()
            try cancelSystemExportPicker(app, returningTo: choose,
                                         screenshot: "build22-system-directory-picker-\(attempt)")
            let notice = app.staticTexts["export.notice"]
            XCTAssertTrue(notice.waitForExistence(timeout: 10))
            XCTAssertTrue(notice.label.contains("选择已取消"))
            XCTAssertFalse(app.buttons["export.commit"].exists)
            XCTAssertFalse(app.buttons["export.done"].exists)
        }
        let files = app.buttons["export.files"]
        let other = app.buttons["export.other"]
        try revealInEditor(other, app); other.tap()
        for attempt in 1...2 {
            try revealInEditor(files, app); files.tap()
            try cancelSystemExportPicker(app, returningTo: files,
                                         screenshot: "build22-system-file-export-picker-\(attempt)")
            let cancelled = XCTNSPredicateExpectation(
                predicate: NSPredicate(format: "exists == true AND label CONTAINS %@", "导出已取消"),
                object: app.staticTexts["export.notice"])
            XCTAssertEqual(XCTWaiter.wait(for: [cancelled], timeout: 15), .completed,
                           "The item-driven file sheet must consume its cancellation after dismissal")
            XCTAssertFalse(app.buttons["export.done"].exists,
                           "Cancelling file export must never advance to export completion")
        }
        capture("build22-system-export-cancelled", app)
        app.buttons["export.later"].tap()
        XCTAssertTrue(app.staticTexts["review.saved.notice"].waitForExistence(timeout: 10))
        try returnFromReview(app)
        let favorite = app.textFields["character.favorite"]
        try revealInEditor(favorite, app)
        XCTAssertEqual(favorite.value as? String, value)
        app.buttons["editor.shell.close"].tap()
        try assertLibraryStatus("已保存，待导出", app)
    }

    @MainActor
    private func cancelSystemExportPicker(_ app: XCUIApplication, returningTo control: XCUIElement,
                                         screenshot: String) throws {
        // Same system Cancel lookup used by the existing AdaptiveLayout picker
        // integration; accept English too if the simulator's Files UI uses it.
        let cancel = app.buttons.matching(NSPredicate(format: "label IN %@", ["取消", "Cancel"])).firstMatch
        let visible = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == true AND enabled == true AND hittable == true"),
            object: cancel)
        XCTAssertEqual(XCTWaiter.wait(for: [visible], timeout: 30), .completed,
                       "The real system picker must finish presenting before cancellation")
        capture(screenshot, app)
        cancel.tap()
        let dismissed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: cancel)
        let resumed = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == true AND enabled == true"), object: control)
        XCTAssertEqual(XCTWaiter.wait(for: [dismissed, resumed], timeout: 30), .completed,
                       "Cancelling the system picker must return to a usable export stage")
        XCTAssertTrue(app.navigationBars["保存并导出"].exists)
        XCTAssertFalse(app.alerts.firstMatch.exists)
    }

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
        try saveLocalCopy(app)
        app.terminate(); app.launchArguments = args; app.launch()
        let resume = app.buttons["library.continue"]
        XCTAssertTrue(resume.waitForExistence(timeout: 30)); resume.tap()
        dismissNotice(app)
        XCTAssertFalse(app.alerts["恢复未保存草稿"].exists)
        let library = app.buttons["tools.library"]
        try revealDirectoryControl(library, in: app); library.tap()
        XCTAssertTrue(app.staticTexts["已保存，待导出"].waitForExistence(timeout: 15))
        let libraryScreenshot = XCTAttachment(screenshot: app.screenshot())
        libraryScreenshot.name = "build22-local-library"; libraryScreenshot.lifetime = .keepAlways; add(libraryScreenshot)
        app.buttons["完成"].tap()
        XCTAssertEqual(try openCharacter(app).value as? String, value)
        app.buttons["editor.review.open"].tap()
        let export = app.buttons["review.primary"]
        XCTAssertEqual(export.label, "继续导出")
        XCTAssertTrue(export.isHittable); export.tap()
        XCTAssertTrue(app.buttons["export.choose.directory"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["export.commit"].exists, "No write can be offered before selecting and inspecting the target")
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "build22-verified-export"; attachment.lifetime = .keepAlways; add(attachment)
    }

    @MainActor
    func testSaveAndExportRunsContinuouslyThenReturnsToSameEditor() throws {
        let app = XCUIApplication()
        let args = persistenceArguments(exportMode: "success")
        app.launchArguments = args + ["--ui-library-seed"]; app.launch()
        defer { app.terminate() }
        let value = try editAndBeginExport("E", app)
        try selectExportTarget(app)
        let commit = app.buttons["export.commit"]
        XCTAssertFalse(commit.isEnabled, "Writing requires confirmation that the game is closed")
        capture("build22-export-target-review", app)
        try confirmGameExited(app)
        try finishVerifiedExport(app)
        let favorite = app.textFields["character.favorite"]
        try revealInEditor(favorite, app)
        XCTAssertEqual(favorite.value as? String, value, "Completion returns to the editor and retains the saved values")
        app.buttons["editor.shell.close"].tap()
        try assertLibraryStatus("已校验写入游戏目录", app)
        app.terminate(); app.launchArguments = args; app.launch()
        try resumeCopy(app)
        XCTAssertFalse(app.alerts["恢复未保存草稿"].exists)
        try assertLibraryStatus("已校验写入游戏目录", app)
        XCTAssertEqual(try openCharacter(app).value as? String, value)
    }

    @MainActor
    func testCancelledExportCanResumeAfterRelaunchWithoutSavingAgain() throws {
        let app = XCUIApplication()
        let args = persistenceArguments(exportMode: "cancel-once")
        app.launchArguments = args + ["--ui-library-seed"]; app.launch()
        defer { app.terminate() }
        let value = try editAndBeginExport("C", app)
        let choose = app.buttons["export.choose.directory"]
        choose.tap()
        XCTAssertTrue(choose.isEnabled)
        XCTAssertFalse(app.buttons["export.commit"].exists, "Cancelling directory selection must not start a write")
        let later = app.buttons["export.later"]
        XCTAssertTrue(later.isHittable); later.tap()
        XCTAssertTrue(app.staticTexts["review.saved.notice"].waitForExistence(timeout: 10))
        capture("build22-export-later", app)
        try returnFromReview(app)
        app.buttons["editor.shell.close"].tap()
        app.terminate(); app.launchArguments = args; app.launch()
        try resumeCopy(app)
        XCTAssertFalse(app.alerts["恢复未保存草稿"].exists)
        try assertLibraryStatus("已保存，待导出", app)
        XCTAssertEqual(try openCharacter(app).value as? String, value)
        app.buttons["editor.review.open"].tap()
        let continueExport = app.buttons["review.primary"]
        XCTAssertEqual(continueExport.label, "继续导出")
        XCTAssertTrue(continueExport.isHittable); continueExport.tap()
        XCTAssertTrue(choose.waitForExistence(timeout: 10))
        XCTAssertFalse(app.alerts.firstMatch.exists, "A previously saved copy must continue without a second save confirmation")
        try selectExportTarget(app)
        try confirmGameExited(app)
        try finishVerifiedExport(app)
    }

    @MainActor
    func testWrongFarmIsRejectedAndCorrectTargetCanBeSelectedAgain() throws {
        let app = XCUIApplication()
        app.launchArguments = persistenceArguments(exportMode: "wrong-farm-once") + ["--ui-library-seed"]
        app.launch()
        defer { app.terminate() }
        _ = try editAndBeginExport("W", app)
        app.buttons["export.choose.directory"].tap()
        try assertExportFailure(contains: "另一份农场", app)
        XCTAssertFalse(app.buttons["export.commit"].exists, "A different stable player identity must never offer a write")
        capture("build22-export-wrong-farm-retry", app)
        try selectExportTarget(app)
        XCTAssertFalse(app.switches["export.confirm.target"].exists)
        try confirmGameExited(app)
        try finishVerifiedExport(app)
    }

    @MainActor
    func testChangedTargetIsPreservedUntilReinspectionAndExplicitConfirmation() throws {
        let app = XCUIApplication()
        app.launchArguments = persistenceArguments(exportMode: "stale-once") + ["--ui-library-seed"]
        app.launch()
        defer { app.terminate() }
        _ = try editAndBeginExport("S", app)
        try selectExportTarget(app)
        try confirmGameExited(app)
        app.buttons["export.commit"].tap()
        try assertExportFailure(contains: "修改", app)
        XCTAssertFalse(app.buttons["export.done"].exists, "A stale target cannot be reported as successfully exported")
        try selectExportTarget(app)
        let changedTarget = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "101 金币")).firstMatch
        XCTAssertTrue(changedTarget.waitForExistence(timeout: 10), "Failed writing must preserve the newer target bytes")
        let acknowledge = app.switches["export.confirm.target"]
        try revealInEditor(acknowledge, app)
        XCTAssertTrue(acknowledge.exists)
        try confirmGameExited(app, mayWrite: false)
        XCTAssertFalse(app.buttons["export.commit"].isEnabled, "Game exit alone must not authorize replacing a changed target")
        try revealInEditor(acknowledge, app); acknowledge.tap()
        XCTAssertTrue(app.buttons["export.commit"].isEnabled)
        capture("build22-export-changed-target-confirmed", app)
        try finishVerifiedExport(app)
    }

    @MainActor
    func testAnimalRenameSaveKeepsSameAnimalAfterListReorders() throws {
        let app = XCUIApplication()
        let args = ["--ui-library", UUID().uuidString, "--ui-tab", "tools", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launchArguments = args + ["--ui-library-seed"]; app.launch()
        defer { app.terminate() }
        XCTAssertTrue(app.buttons["farm.load.switch"].waitForExistence(timeout: 30))
        try openAnimal("1", app)
        let name = app.textFields["editor.animal.name"]
        try revealInEditor(name, app)
        XCTAssertEqual(name.value as? String, "Alpha")
        name.tap()
        name.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 5) + "Zulu\n")
        let renamed = try XCTUnwrap(name.value as? String)
        XCTAssertTrue(renamed.hasPrefix("Zulu"), "Renaming must move this animal after Beta in the saved list")
        app.buttons["editor.review.open"].tap()
        try saveLocalCopy(app)
        try returnFromReview(app)
        try revealInEditor(name, app)
        XCTAssertEqual(name.value as? String, renamed, "Returning after saving must stay on animal ID 1")
        capture("build22-animal-after-reordered-save", app)
        name.tap(); name.typeText("X\n")
        let editedAgain = try XCTUnwrap(name.value as? String)
        app.buttons["editor.review.open"].tap()
        try saveLocalCopy(app)
        app.terminate(); app.launchArguments = args; app.launch()
        let resume = app.buttons["library.continue"]
        XCTAssertTrue(resume.waitForExistence(timeout: 30)); resume.tap()
        dismissNotice(app)
        try openAnimal("1", app)
        try revealInEditor(name, app)
        XCTAssertEqual(name.value as? String, editedAgain)
        let back = app.navigationBars.firstMatch.buttons.element(boundBy: 0)
        back.tap()
        let otherAnimal = app.buttons["editor.animal.2"]
        try revealInEditor(otherAnimal, app); otherAnimal.tap()
        try revealInEditor(name, app)
        XCTAssertEqual(name.value as? String, "Beta", "The other animal must not receive edits after saving")
    }

    @MainActor
    private func openAnimal(_ id: String, _ app: XCUIApplication) throws {
        try selectToolCategory(for: "animals", in: app)
        let entry = app.buttons["editor.tool.animals"]
        try revealDirectoryControl(entry, in: app); entry.tap()
        let animal = app.buttons["editor.animal.\(id)"]
        try revealInEditor(animal, app); animal.tap()
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
        capture("build22-second-save-reopened", app)
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
        let more = app.buttons["review.more"]
        try revealInEditor(more, app); more.tap()
        let reload = app.buttons["重新载入文件"]
        try revealInEditor(reload, app); reload.tap()
        let confirm = app.alerts.buttons["放弃草稿并重新载入"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 10)); confirm.tap()
        let done = app.alerts.buttons["好"]
        try acknowledgeCompletion(done, app)
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
        capture("build22-reload-edit-save-reopened", app)
    }

    @MainActor
    private func revealInEditor(_ element: XCUIElement, _ app: XCUIApplication) throws {
        for _ in 0..<12 where !element.isHittable { app.swipeUp() }
        XCTAssertTrue(element.isHittable)
    }

    @MainActor
    private func saveLocalCopy(_ app: XCUIApplication) throws {
        let save = app.buttons["review.save.later"]
        XCTAssertTrue(save.waitForExistence(timeout: 10))
        XCTAssertTrue(save.isHittable, "Save actions stay visible without scrolling past every change")
        XCTAssertTrue(save.isEnabled)
        save.tap()
        XCTAssertTrue(app.staticTexts["review.saved.notice"].waitForExistence(timeout: 30))
        XCTAssertFalse(app.alerts.firstMatch.exists, "Saving for later gives inline feedback without a redundant completion alert")
        XCTAssertFalse(save.exists && save.isEnabled, "Successful saving must clear pending changes")
        XCTAssertEqual(app.buttons["review.primary"].label, "继续导出")
        capture("build22-saved-for-later", app)
    }

    @MainActor
    private func persistenceArguments(exportMode: String) -> [String] {
        ["--ui-library", UUID().uuidString, "--ui-export-fixture", exportMode,
         "--ui-tab", "tools", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
    }

    @MainActor
    private func editAndBeginExport(_ suffix: String, _ app: XCUIApplication) throws -> String {
        let favorite = try openCharacter(app)
        favorite.tap(); favorite.typeText(suffix + "\n")
        let value = try XCTUnwrap(favorite.value as? String)
        XCTAssertTrue(value.contains(suffix))
        app.buttons["editor.review.open"].tap()
        let save = app.buttons["review.primary"]
        XCTAssertTrue(save.waitForExistence(timeout: 10))
        XCTAssertTrue(save.isHittable, "The main action is visible immediately on entering review")
        XCTAssertEqual(save.label, "保存并导出")
        capture("build22-review-primary", app)
        save.tap()
        let choose = app.buttons["export.choose.directory"]
        XCTAssertTrue(choose.waitForExistence(timeout: 30), "Saving proceeds directly to the export stage")
        XCTAssertTrue(app.navigationBars["保存并导出"].exists)
        XCTAssertFalse(app.alerts.firstMatch.exists)
        XCTAssertFalse(app.buttons["export.commit"].exists)
        capture("build22-export-select-directory", app)
        return value
    }

    @MainActor
    private func selectExportTarget(_ app: XCUIApplication) throws {
        let choose = app.buttons["export.choose.directory"]
        XCTAssertTrue(choose.waitForExistence(timeout: 10))
        try revealInEditor(choose, app); choose.tap()
        XCTAssertTrue(app.buttons["export.commit"].waitForExistence(timeout: 30))
        XCTAssertFalse(app.buttons["export.commit"].isEnabled, "Every target inspection starts with fresh confirmations")
    }

    @MainActor
    private func confirmGameExited(_ app: XCUIApplication, mayWrite: Bool = true) throws {
        let exited = app.switches["export.game.exited"]
        try revealInEditor(exited, app); exited.tap()
        XCTAssertEqual(app.buttons["export.commit"].isEnabled, mayWrite)
    }

    @MainActor
    private func finishVerifiedExport(_ app: XCUIApplication) throws {
        let commit = app.buttons["export.commit"]
        try revealInEditor(commit, app)
        XCTAssertTrue(commit.isEnabled); commit.tap()
        let done = app.buttons["export.done"]
        XCTAssertTrue(done.waitForExistence(timeout: 30))
        XCTAssertTrue(done.isEnabled)
        XCTAssertTrue(app.staticTexts["export.result"].exists)
        XCTAssertFalse(app.alerts.firstMatch.exists)
        capture("build22-export-complete", app)
        done.tap()
        XCTAssertTrue(app.buttons["editor.review.open"].waitForExistence(timeout: 10))
    }

    @MainActor
    private func assertExportFailure(contains message: String, _ app: XCUIApplication) throws {
        let failure = app.alerts["操作失败"]
        XCTAssertTrue(failure.waitForExistence(timeout: 30))
        XCTAssertTrue(failure.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", message)).firstMatch.exists)
        capture("build22-export-failure", app)
        try acknowledgeCompletion(failure.buttons["好"], app)
    }

    @MainActor
    private func resumeCopy(_ app: XCUIApplication) throws {
        let resume = app.buttons["library.continue"]
        XCTAssertTrue(resume.waitForExistence(timeout: 30)); resume.tap()
        dismissNotice(app)
    }

    @MainActor
    private func assertLibraryStatus(_ status: String, _ app: XCUIApplication) throws {
        let library = app.buttons["tools.library"]
        try revealDirectoryControl(library, in: app); library.tap()
        XCTAssertTrue(app.staticTexts[status].waitForExistence(timeout: 15))
        capture("build22-library-export-state", app)
        app.buttons["完成"].tap()
    }

    @MainActor
    private func acknowledgeCompletion(_ button: XCUIElement, _ app: XCUIApplication) throws {
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == true AND enabled == true AND hittable == true"), object: button)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 30), .completed,
                       "The completion action must become enabled after writing finishes")
        capture("build22-completion-enabled", app)
        button.tap()
        let dismissed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: app.alerts.firstMatch)
        XCTAssertEqual(XCTWaiter.wait(for: [dismissed], timeout: 10), .completed,
                       "Acknowledging completion must dismiss the alert so returning is possible")
    }

    @MainActor
    private func returnFromReview(_ app: XCUIApplication) throws {
        let back = app.navigationBars["检查更改"].buttons["editor.shell.close"]
        XCTAssertTrue(back.waitForExistence(timeout: 10))
        XCTAssertEqual(back.label, "返回编辑")
        capture("build22-review-after-operation", app)
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
