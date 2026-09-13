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
        capture("build16-tools-common", app)
        for tool in ["character", "appearance", "skills", "relationships", "inventory", "equipment",
                     "storage", "recipes", "collections", "farmhouse", "animals", "weather",
                     "machines", "map", "progress", "wallet", "bundles"] {
            try selectToolCategory(for: tool, in: app)
            let entry = app.buttons["editor.tool.\(tool)"]
            try revealDirectoryControl(entry, in: app)
            if ["collections", "machines", "bundles"].contains(tool) {
                capture("build16-category-\(tool)", app)
            }
            XCTAssertTrue(review.isHittable, "Review stays available while browsing")
            entry.tap()
            let close = tool == "map" ? app.buttons["完成"].firstMatch
                : app.buttons[["equipment", "storage", "collections", "weather", "machines", "bundles"].contains(tool)
                    ? "expanded.close" : "editor.shell.close"]
            XCTAssertTrue(close.waitForExistence(timeout: 20), "Opened \(tool)")
            close.tap()
            XCTAssertTrue(review.waitForExistence(timeout: 20))
            XCTAssertEqual(review.label, draftLabel, "Browsing \(tool) must retain draft changes")
        }
        review.tap()
        XCTAssertTrue(app.buttons["editor.shell.close"].waitForExistence(timeout: 20))
        capture("build16-review", app)
    }

    @MainActor
    func testSearchAcrossCategoriesAndEmptyState() throws {
        let app = launch("tools", demo: true)
        defer { app.terminate() }
        let search = app.textFields["tools.search"]
        try revealDirectoryControl(search, in: app, towardTop: true)
        search.tap()
        search.typeText("天气\n")
        XCTAssertTrue(app.buttons["editor.tool.weather"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["editor.tool.inventory"].exists)
        capture("build16-search-weather", app)
        app.buttons["editor.tool.weather"].tap()
        XCTAssertTrue(app.buttons["expanded.close"].waitForExistence(timeout: 15))
        app.buttons["expanded.close"].tap()
        try revealDirectoryControl(app.buttons["tools.search.clear"], in: app, towardTop: true)
        app.buttons["tools.search.clear"].tap()
        search.tap()
        search.typeText("zznomatch123\n")
        XCTAssertTrue(app.staticTexts["没有找到相关功能"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["editor.tool.review"].isHittable)
        capture("build16-search-empty", app)
        app.buttons["tools.search.clear"].tap()
        XCTAssertTrue(app.buttons["tools.category.common"].exists)
        XCTAssertTrue(app.buttons["editor.tool.character"].exists)
    }

    @MainActor
    func testBrandGroupCopyAndQRCode() throws {
        let app = launch("settings", demo: false)
        defer { app.terminate() }
        XCTAssertTrue(app.staticTexts["鹈鹕修改器"].waitForExistence(timeout: 30))
        capture("build16-settings", app)
        try tapByScrolling(app.buttons["settings.qq.copy"], app)
        XCTAssertTrue(app.staticTexts["settings.qq.copied"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.buttons["settings.qq.copy"].value as? String, "已复制群号")
        try tapByScrolling(app.buttons["settings.qq.qrcode"], app)
        XCTAssertTrue(app.buttons["settings.qq.close"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.images["settings.qq.fullImage"].exists)
        capture("build16-qq-full", app)
        try tapByScrolling(app.buttons["settings.qq.share"], app)
        let covered = NSPredicate(format: "hittable == false")
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: covered,
            object: app.buttons["settings.qq.close"])], timeout: 10), .completed)
        capture("build16-qq-share", app)
    }

    @MainActor
    func testToolsAndSettingsAtLargeTextInNarrowWindow() throws {
        let extra = ["--ui-layout-width", "375",
                     "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL",
                     "-appearanceMode", "dark"]
        let app = launch("tools", demo: true, extra: extra)
        defer { XCUIDevice.shared.orientation = .portrait; app.terminate() }
        let category = app.buttons["tools.category.items"]
        try revealDirectoryControl(category, in: app, towardTop: true)
        category.tap()
        let entry = app.buttons["editor.tool.inventory"]
        try revealDirectoryControl(entry, in: app)
        XCTAssertLessThanOrEqual(entry.frame.width, 375)
        XCTAssertTrue(app.buttons["editor.tool.review"].isHittable)
        capture("build16-tools-accessibility-dark", app)
        app.terminate()
        _ = launch("settings", demo: false, extra: extra)
        try tapByScrolling(app.buttons["settings.qq.copy"], app)
        XCTAssertTrue(app.staticTexts["settings.qq.copied"].waitForExistence(timeout: 10))
        capture("build16-settings-accessibility-dark", app)
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
