import XCTest
import UIKit

final class PelicanBrandUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    @MainActor
    func testAllToolCategoriesOpenAndKeepDraft() throws {
        let app = launch("tools", demo: true, extra: ["--ui-demo-edits", "--ui-expanded", "--ui-repair"])
        defer { app.terminate() }
        let review = app.buttons["editor.tool.review"]
        XCTAssertTrue(review.waitForExistence(timeout: 30))
        let draftLabel = review.label
        XCTAssertTrue(draftLabel.contains("项待保存"))
        let firstTool = app.buttons["editor.tool.character"]
        XCTAssertTrue(firstTool.isHittable)
        XCTAssertTrue(app.scrollViews["editor.tools.list"].frame.contains(firstTool.frame),
                      "The first common editor should be visible without scrolling")
        capture("build20-tools-common", app)
        for tool in ["character", "appearance", "skills", "relationships", "inventory", "equipment",
                     "storage", "recipes", "collections", "farmhouse", "animals", "weather",
                     "machines", "map", "progress", "wallet", "bundles"] {
            try selectToolCategory(for: tool, in: app)
            let entry = app.buttons["editor.tool.\(tool)"]
            try revealDirectoryControl(entry, in: app)
            if ["collections", "machines", "bundles"].contains(tool) {
                capture("build20-category-\(tool)", app)
            }
            XCTAssertTrue(review.isHittable, "Review stays available while browsing")
            entry.tap()
            let close = tool == "map" ? app.buttons["editor.map.close"]
                : app.buttons[["equipment", "storage", "collections", "weather", "machines", "bundles"].contains(tool)
                    ? "expanded.close" : "editor.shell.close"]
            XCTAssertTrue(close.waitForExistence(timeout: 20), "Opened \(tool)")
            capture("build21-editor-\(tool)", app)
            XCTAssertEqual(close.label, "返回工具", "Every editor must show a visible destination instead of an icon-only close control")
            XCTAssertGreaterThan(close.frame.width, 80, "The visible return control must fit its arrow and four-character destination")
            close.tap()
            XCTAssertTrue(review.waitForExistence(timeout: 20))
            XCTAssertEqual(review.label, draftLabel, "Browsing \(tool) must retain draft changes")
        }
        let more = app.buttons["tools.management.more"]
        try revealDirectoryControl(more, in: app)
        more.tap()
        XCTAssertTrue(app.buttons["关闭当前副本（保留草稿）"].waitForExistence(timeout: 10))
        app.buttons["重新读取与校验"].tap()
        XCTAssertTrue(app.alerts["重新读取副本？"].waitForExistence(timeout: 10))
        app.alerts.buttons["取消"].tap()
        XCTAssertEqual(review.label, draftLabel, "Cancelling reload must retain the draft")
        review.tap()
        XCTAssertTrue(app.buttons["editor.shell.close"].waitForExistence(timeout: 20))
        capture("build20-review", app)
    }

    @MainActor
    func testSearchAcrossCategoriesAndEmptyState() throws {
        let app = launch("tools", demo: true)
        defer { app.terminate() }
        let openSearch = app.buttons["tools.search.open"]
        XCTAssertTrue(openSearch.waitForExistence(timeout: 10))
        openSearch.tap()
        let search = app.textFields["tools.search"]
        XCTAssertTrue(search.waitForExistence(timeout: 10), "The header search control must expand the directory")
        try revealDirectoryControl(search, in: app, towardTop: true)
        search.tap()
        search.typeText("天气\n")
        XCTAssertTrue(app.buttons["editor.tool.weather"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["editor.tool.inventory"].exists)
        capture("build20-search-weather", app)
        app.buttons["editor.tool.weather"].tap()
        XCTAssertTrue(app.buttons["expanded.close"].waitForExistence(timeout: 15))
        app.buttons["expanded.close"].tap()
        try revealDirectoryControl(app.buttons["tools.search.clear"], in: app, towardTop: true)
        app.buttons["tools.search.clear"].tap()
        search.tap()
        search.typeText("zznomatch123\n")
        XCTAssertTrue(app.staticTexts["没有找到相关功能"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["editor.tool.review"].isHittable)
        capture("build20-search-empty", app)
        app.buttons["tools.search.clear"].tap()
        XCTAssertTrue(app.buttons["tools.category.common"].exists)
        XCTAssertTrue(app.buttons["editor.tool.character"].exists)
    }

    @MainActor
    func testBrandGroupCopyAndQRCode() throws {
        let app = launch("settings", demo: false)
        defer { app.terminate() }
        XCTAssertTrue(app.staticTexts["鹈鹕修改器"].waitForExistence(timeout: 30))
        capture("build20-settings", app)
        try tapByScrolling(app.buttons["settings.qq.copy"], app)
        XCTAssertTrue(app.staticTexts["settings.qq.copied"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.buttons["settings.qq.copy"].value as? String, "已复制群号")
        try tapByScrolling(app.buttons["settings.qq.qrcode"], app)
        XCTAssertTrue(app.buttons["settings.qq.close"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.images["settings.qq.fullImage"].exists)
        capture("build20-qq-full", app)
        try tapByScrolling(app.buttons["settings.qq.share"], app)
        // Assert the presented system action itself, rather than whether its
        // asynchronously loaded sheet currently covers the underlying toolbar.
        let shareSheet = app.otherElements["ActivityListView"]
        // iOS 26 exposes these actions as collection cells; older versions
        // expose buttons. Scope to the system sheet and accept either type.
        let copyImage = shareSheet.descendants(matching: .any)
            .matching(NSPredicate(format: "label IN %@", ["拷贝", "Copy"])).firstMatch
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == true AND hittable == true"), object: copyImage)
        let result = XCTWaiter.wait(for: [ready], timeout: 30)
        capture("build21-qq-share", app)
        if result != .completed {
            let hierarchy = XCTAttachment(string: app.debugDescription)
            hierarchy.name = "build21-qq-share-hierarchy"
            hierarchy.lifetime = .keepAlways
            add(hierarchy)
        }
        XCTAssertEqual(result, .completed, "Sharing must present the system image-copy action")
    }

    @MainActor
    func testToolsAndSettingsAtLargeTextInNarrowWindow() throws {
        let extra = ["--ui-layout-width", "375",
                     "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL",
                     "-appearanceMode", "dark"]
        let app = launch("tools", demo: true, extra: extra)
        defer { XCUIDevice.shared.orientation = .portrait; app.terminate() }
        try openToolDirectory(in: app)
        let category = app.buttons["tools.category.items"]
        try revealDirectoryControl(category, in: app, towardTop: true)
        category.tap()
        let entry = app.buttons["editor.tool.inventory"]
        try revealDirectoryControl(entry, in: app)
        XCTAssertLessThanOrEqual(entry.frame.width, 375)
        XCTAssertTrue(app.buttons["editor.tool.review"].isHittable)
        capture("build20-tools-accessibility-dark", app)
        app.terminate()
        _ = launch("settings", demo: false, extra: extra)
        let appearance = app.descendants(matching: .any).matching(identifier: "settings.appearance").firstMatch
        try tapByScrolling(appearance, app)
        let dark = app.buttons["深色"].firstMatch
        XCTAssertTrue(dark.waitForExistence(timeout: 10))
        capture("build20-settings-appearance-accessibility-menu", app)
        dark.tap()
        XCTAssertTrue(appearance.isHittable)
        XCTAssertTrue(app.frame.contains(appearance.frame))
        capture("build20-settings-appearance-accessibility-dark", app)
        try tapByScrolling(app.buttons["settings.qq.copy"], app)
        XCTAssertTrue(app.staticTexts["settings.qq.copied"].waitForExistence(timeout: 10))
        capture("build20-settings-accessibility-dark", app)
    }

    @MainActor
    func testNumericInputCanReturnReviewAndUndoWithoutLosingDraft() throws {
        let app = launch("tools", demo: true)
        defer { app.terminate() }
        try tapByScrolling(app.buttons["editor.tool.character"], app)
        let money = app.textFields["character.money"]
        try tapByScrolling(money, app)
        let original = try XCTUnwrap(money.value as? String).filter(\.isNumber)
        money.typeText("7")
        let edited = try XCTUnwrap(money.value as? String).filter(\.isNumber)
        XCTAssertNotEqual(edited, original)
        let finishInput = app.buttons["global.keyboardReturn.button"]
        XCTAssertTrue(finishInput.waitForExistence(timeout: 10))
        XCTAssertEqual(finishInput.label, "完成输入")
        let close = app.buttons["editor.shell.close"]
        XCTAssertTrue(close.isHittable, "Page return must remain available with the number keyboard open")
        capture("build21-number-keyboard-return", app)
        close.tap()
        XCTAssertTrue(app.buttons["editor.tool.review"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.keyboards.firstMatch.exists)
        try tapByScrolling(app.buttons["editor.tool.character"], app)
        try tapByScrolling(money, app)
        XCTAssertEqual((money.value as? String)?.filter(\.isNumber), edited)
        app.buttons["editor.review.open"].tap()
        let reviewClose = app.navigationBars["检查更改"].buttons["editor.shell.close"]
        XCTAssertTrue(reviewClose.waitForExistence(timeout: 10))
        XCTAssertEqual(reviewClose.label, "返回编辑")
        XCTAssertGreaterThan(reviewClose.frame.width, 80)
        try tapByScrolling(app.buttons["撤销这项更改"].firstMatch, app)
        reviewClose.tap()
        try tapByScrolling(money, app)
        XCTAssertEqual((money.value as? String)?.filter(\.isNumber), original)
        app.buttons["global.keyboardReturn.button"].tap()
        let keyboardDismissed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: app.keyboards.firstMatch)
        XCTAssertEqual(XCTWaiter.wait(for: [keyboardDismissed], timeout: 10), .completed)
        capture("build21-input-finished", app)
        XCTAssertTrue(close.isHittable, "Finishing input must keep the editor open")
        close.tap()
        XCTAssertTrue(app.buttons["editor.tool.review"].waitForExistence(timeout: 10))
    }

    @MainActor
    func testChildEditorAndMapReviewReturnToTheirSource() throws {
        let app = launch("tools", demo: true, extra: ["--ui-repair"])
        defer { app.terminate() }
        try selectToolCategory(for: "appearance", in: app)
        try revealDirectoryControl(app.buttons["editor.tool.appearance"], in: app)
        app.buttons["editor.tool.appearance"].tap()
        try tapByScrolling(app.buttons["editor.appearance.colors"], app)
        let childBar = app.navigationBars["外观颜色"]
        XCTAssertTrue(childBar.waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["editor.review.open"].isHittable)
        capture("build21-child-editor", app)
        app.buttons["editor.review.open"].tap()
        let reviewClose = app.navigationBars["检查更改"].buttons["editor.shell.close"]
        XCTAssertTrue(reviewClose.waitForExistence(timeout: 10))
        XCTAssertEqual(reviewClose.label, "返回编辑")
        reviewClose.tap()
        XCTAssertTrue(childBar.waitForExistence(timeout: 10), "Review must return to the same child editor")
        let back = childBar.buttons.element(boundBy: 0)
        XCTAssertNotEqual(back.identifier, "editor.shell.close", "Child back must preserve the one-level navigation hierarchy")
        back.tap()
        XCTAssertTrue(app.navigationBars["人物外观"].waitForExistence(timeout: 10))
        let close = app.navigationBars["人物外观"].buttons["editor.shell.close"]
        XCTAssertEqual(close.label, "返回工具")
        close.tap()
        try selectToolCategory(for: "map", in: app)
        try revealDirectoryControl(app.buttons["editor.tool.map"], in: app)
        app.buttons["editor.tool.map"].tap()
        XCTAssertTrue(app.buttons["editor.map.close"].waitForExistence(timeout: 15))
        app.buttons["editor.review.open"].tap()
        XCTAssertTrue(reviewClose.waitForExistence(timeout: 10))
        XCTAssertEqual(reviewClose.label, "返回地图")
        capture("build21-map-review-return", app)
        reviewClose.tap()
        XCTAssertTrue(app.buttons["editor.map.close"].waitForExistence(timeout: 10))
        app.buttons["editor.map.close"].tap()
        XCTAssertTrue(app.buttons["editor.tool.review"].waitForExistence(timeout: 10))
    }

    @MainActor
    private func launch(_ tab: String, demo: Bool, extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-tab", tab, "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
            + (demo ? ["--ui-demo"] : []) + extra
        app.launch()
        XCTAssertTrue(app.scrollViews.firstMatch.waitForExistence(timeout: 30))
        return app
    }

    @MainActor
    private func tapByScrolling(_ target: XCUIElement, _ app: XCUIApplication) throws {
        for _ in 0..<18 {
            if target.exists && target.isHittable { target.tap(); return }
            app.swipeUp()
        }
        XCTFail("Control missing: \(target)\n\(app.debugDescription)")
        throw NSError(domain: "PelicanBrandUITests", code: 1)
    }

    @MainActor
    private func capture(_ name: String, _ app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
