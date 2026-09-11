import XCTest
import UIKit

final class AdaptiveLayoutUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testImportOptionsSurviveRotation() throws {
        defer { XCUIDevice.shared.orientation = .portrait; XCUIApplication().terminate() }
        let app = launch(demo: false)
        try tap(app.buttons["farm.load.open"], app: app)
        for orientation: UIDeviceOrientation in [.landscapeLeft, .portrait] {
            XCUIDevice.shared.orientation = orientation
            try verifyImportOptions(app)
            capture("import-options-\(orientation.rawValue)", app)
        }
        try tap(app.buttons["farm.load.cancel"], app: app)
        try visible(app.buttons["farm.load.open"], app: app)
    }

    @MainActor
    func testEachDocumentPickerCanOpenCancelAndReopen() throws {
        defer { XCUIDevice.shared.orientation = .portrait; XCUIApplication().terminate() }
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = launch(demo: false)
        for method in ["files", "directory", "copy"] {
            try tap(app.buttons["farm.load.open"], app: app)
            let option = app.buttons["farm.load.\(method)"]
            try reveal(option, in: "farm.load.options", app: app)
            try tap(option, app: app)
            let cancel = app.buttons["取消"].firstMatch
            try visible(cancel, app: app)
            XCTAssertFalse(app.buttons["farm.load.cancel"].exists,
                           "The source sheet must finish dismissing before the document picker opens")
            capture("import-picker-\(method)", app)
            try tap(cancel, app: app)
            try visible(app.buttons["farm.load.open"], app: app)
        }
        try tap(app.buttons["farm.load.open"], app: app)
        try verifyImportOptions(app)
    }

    @MainActor
    func testAllEditorsInLandscape() throws {
        defer { XCUIDevice.shared.orientation = .portrait; XCUIApplication().terminate() }
        XCUIDevice.shared.orientation = .landscapeLeft
        try verifyEditors(launch(), label: "landscape")
    }

    @MainActor
    func testAllEditorsInPortrait() throws {
        defer { XCUIDevice.shared.orientation = .portrait; XCUIApplication().terminate() }
        XCUIDevice.shared.orientation = .portrait
        try verifyEditors(launch(), label: "portrait")
    }

    @MainActor
    func testMainPagesAndUtilitySheets() throws {
        defer { XCUIDevice.shared.orientation = .portrait; XCUIApplication().terminate() }
        XCUIDevice.shared.orientation = .landscapeLeft
        for tab in ["home", "tracker", "tools", "settings"] {
            let app = launch(tab: tab)
            let scrollView = app.scrollViews.firstMatch
            try visible(scrollView, app: app)
            capture("main-\(tab)", app)
            if tab == "tools" {
                for entry in ["tools.backups", "tools.calculator"] {
                    let button = app.buttons[entry]
                    try reveal(button, in: "editor.tools.list", app: app)
                    try tap(button, app: app)
                    let done = app.buttons["完成"].firstMatch
                    try visible(done, app: app)
                    capture(entry, app)
                    try tap(done, app: app)
                }
            }
            app.terminate()
        }
    }

    @MainActor
    func testNarrowWindowAndAccessibilityText() throws {
        defer { XCUIDevice.shared.orientation = .portrait; XCUIApplication().terminate() }
        XCUIDevice.shared.orientation = .landscapeLeft
        XCUIDevice.shared.orientation = UIDevice.current.userInterfaceIdiom == .pad ? .landscapeLeft : .portrait
        let app = launch(extra: ["--ui-layout-width", "375",
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        let list = element("editor.tools.list", app)
        XCTAssertTrue(list.waitForExistence(timeout: 30))
        XCTAssertLessThanOrEqual(list.frame.width, 375.5)
        let character = app.buttons["editor.tool.character"]
        try reveal(character, in: "editor.tools.list", app: app)
        capture("narrow-accessibility-tools", app)
        try tap(character, app: app)
        try visible(app.buttons["editor.shell.close"], app: app)
        try visible(app.buttons["editor.review.open"], app: app)
        XCTAssertLessThanOrEqual(app.navigationBars.firstMatch.frame.width, 375.5)
        capture("narrow-accessibility-editor", app)
        try tap(app.buttons["editor.shell.close"], app: app)
        let switchFarm = app.buttons["farm.load.switch"]
        try reveal(switchFarm, in: "editor.tools.list", app: app, upward: false)
        try tap(switchFarm, app: app)
        try verifyImportOptions(app)
        capture("accessibility-import-options", app)
    }

    @MainActor
    func testExpandedMapFitsViewportAtDefaultZoomAfterRotation() throws {
        defer { XCUIDevice.shared.orientation = .portrait; XCUIApplication().terminate() }
        let app = launch(extra: ["--ui-screen", "expanded-map"])
        let viewport = element("map.expanded.viewport", app)
        let canvas = element("map.expanded.canvas", app)
        for orientation: UIDeviceOrientation in [.landscapeLeft, .portrait] {
            XCUIDevice.shared.orientation = orientation
            try tap(app.buttons["map.expanded.reset"], app: app)
            XCTAssertTrue(canvas.waitForExistence(timeout: 10))
            XCTAssertTrue(viewport.exists && !canvas.frame.isEmpty
                && viewport.frame.insetBy(dx: -1, dy: -1).contains(canvas.frame),
                "At 1x, the entire map must fit the current window in both orientations")
            capture("map-fit-\(orientation.rawValue)", app)
        }
    }

    @MainActor
    private func launch(tab: String = "tools", demo: Bool = true, extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-tab", tab, "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
            + (demo ? ["--ui-demo"] : []) + extra
        app.launch()
        let ready: XCUIElement
        if extra.contains("expanded-map") {
            ready = app.buttons["map.expanded.reset"]
        } else if tab == "tools" {
            ready = app.buttons[demo ? "editor.tool.character" : "farm.load.open"]
        } else if tab == "tracker" {
            ready = app.buttons["tracker.filter.overview"]
        } else if tab == "home" {
            ready = app.buttons["前往工具页"]
        } else {
            ready = app.buttons["在工具页管理农场"]
        }
        XCTAssertTrue(ready.waitForExistence(timeout: 30))
        return app
    }

    @MainActor
    private func verifyImportOptions(_ app: XCUIApplication) throws {
        try visible(app.buttons["farm.load.cancel"], app: app)
        for method in ["files", "directory", "copy"] {
            let button = app.buttons["farm.load.\(method)"]
            try reveal(button, in: "farm.load.options", app: app)
            try visible(button, app: app)
        }
    }

    @MainActor
    private func verifyEditors(_ app: XCUIApplication, label: String) throws {
        for section in ["character", "appearance", "farmhouse", "inventory", "progress", "relationships",
                        "skills", "wallet", "animals", "recipes", "review"] {
            let entry = app.buttons["editor.tool.\(section)"]
            try reveal(entry, in: "editor.tools.list", app: app)
            try tap(entry, app: app)
            let close = app.buttons["editor.shell.close"]
            try visible(close, app: app)
            if section != "review" {
                let review = app.buttons["editor.review.open"]
                try visible(review, app: app)
                XCTAssertFalse(close.frame.intersects(review.frame))
            }
            capture("editor-\(section)-\(label)", app)
            try tap(close, app: app)
        }
    }

    @MainActor
    private func element(_ identifier: String, _ app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    @MainActor
    private func reveal(_ target: XCUIElement, in identifier: String, app: XCUIApplication,
                        upward: Bool = true) throws {
        let viewport = element(identifier, app)
        guard viewport.waitForExistence(timeout: 30) else {
            try fail("Missing viewport: \(identifier)", app: app)
            return
        }
        for _ in 0..<24 {
            let frame = target.exists ? target.frame : .null
            var bounds = viewport.frame.intersection(app.frame)
            if let bar = app.navigationBars.allElementsBoundByIndex.last,
               bar.frame.intersects(bounds), bar.frame.midY < bounds.midY {
                let bottom = bounds.maxY
                bounds.origin.y = max(bounds.minY, bar.frame.maxY)
                bounds.size.height = max(0, bottom - bounds.minY)
            }
            for bar in app.tabBars.allElementsBoundByIndex where app.navigationBars.count == 0 {
                if bar.frame.intersects(bounds), bar.frame.midY > bounds.midY {
                    bounds.size.height = max(0, bar.frame.minY - bounds.minY)
                }
            }
            bounds = bounds.insetBy(dx: -1, dy: 6)
            if !frame.isEmpty && frame.minY.isFinite && bounds.contains(frame) {
                try visible(target, app: app)
                return
            }
            let hasFrame = frame.minY.isFinite && !frame.isEmpty
            let moveUp = hasFrame ? frame.midY > bounds.midY : upward
            // Reduce travel as the row approaches the viewport. A fixed half-
            // screen swipe can keep jumping over a row in a short window.
            let distance = min(hasFrame ? max(abs(frame.midY - bounds.midY), 24) : 140,
                               max(1, bounds.height * 0.35))
            let direction: CGFloat = moveUp ? 1 : -1
            let origin = app.coordinate(withNormalizedOffset: .zero)
            let start = origin.withOffset(CGVector(dx: bounds.midX - app.frame.minX,
                dy: bounds.midY - app.frame.minY + direction * distance / 2))
            let end = origin.withOffset(CGVector(dx: bounds.midX - app.frame.minX,
                dy: bounds.midY - app.frame.minY - direction * distance / 2))
            start.press(forDuration: 0.05, thenDragTo: end)
        }
        try fail("Control was clipped or unreachable: \(target); control=\(target.frame), "
                 + "viewport=\(viewport.frame), window=\(app.frame)", app: app)
    }

    @MainActor
    private func visible(_ target: XCUIElement, app: XCUIApplication) throws {
        let predicate = NSPredicate(format: "exists == true AND hittable == true")
        guard XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: target)],
                            timeout: 30) == .completed,
              !target.frame.isEmpty, app.frame.insetBy(dx: -1, dy: -1).contains(target.frame) else {
            try fail("Control must be fully visible and usable: \(target)", app: app)
            return
        }
    }

    @MainActor
    private func tap(_ target: XCUIElement, app: XCUIApplication) throws {
        try visible(target, app: app)
        target.tap()
    }

    @MainActor
    private func capture(_ name: String, _ app: XCUIApplication) {
        let image = XCTAttachment(screenshot: app.screenshot())
        image.name = name
        image.lifetime = .keepAlways
        add(image)
    }

    @MainActor
    private func fail(_ message: String, app: XCUIApplication) throws {
        capture("layout-failure", app)
        let hierarchy = XCTAttachment(string: app.debugDescription)
        hierarchy.name = "Accessibility hierarchy"
        hierarchy.lifetime = .keepAlways
        add(hierarchy)
        XCTFail(message)
        throw LayoutFailure.unreachable
    }

    private enum LayoutFailure: Error { case unreachable }
}
