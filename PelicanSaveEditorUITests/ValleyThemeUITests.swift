import XCTest

final class ValleyThemeUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    @MainActor
    func testMainTabsInDayAndNight() throws {
        for appearance in ["light", "dark"] {
            let app = XCUIApplication()
            app.launchArguments = ["--ui-demo", "--ui-demo-edits", "-appearanceMode", appearance,
                                   "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
            app.launch()
            defer { app.terminate() }
            XCTAssertTrue(app.staticTexts["今日概览"].waitForExistence(timeout: 30))
            capture("build18-home-\(appearance)", app)
            for (title, slug) in [("追踪", "tracker"), ("工具", "tools"), ("设置", "settings")] {
                let tab = app.tabBars.buttons[title]
                XCTAssertTrue(tab.waitForExistence(timeout: 10))
                XCTAssertTrue(tab.isHittable)
                tab.tap()
                XCTAssertTrue(tab.isSelected)
                capture("build18-\(slug)-\(appearance)", app)
            }
        }
    }

    @MainActor
    func testEmptyFarmAndImportPanel() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-appearanceMode", "light", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()
        defer { app.terminate() }
        XCTAssertTrue(app.staticTexts["尚未加载农场"].waitForExistence(timeout: 30))
        capture("build18-home-empty", app)
        app.tabBars.buttons["工具"].tap()
        let load = app.buttons["farm.load.open"]
        XCTAssertTrue(load.waitForExistence(timeout: 10))
        load.tap()
        let copy = app.buttons["farm.load.copy"]
        XCTAssertTrue(copy.waitForExistence(timeout: 10))
        XCTAssertTrue(copy.isHittable)
        capture("build18-import", app)
        app.buttons["farm.load.cancel"].tap()
        XCTAssertTrue(load.waitForExistence(timeout: 10))
    }

    @MainActor
    private func capture(_ name: String, _ app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
