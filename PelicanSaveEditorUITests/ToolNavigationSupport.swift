import XCTest

extension XCTestCase {
    @MainActor
    func selectToolCategory(for tool: String, in app: XCUIApplication) throws {
        if tool == "review" { return }
        let category: String
        switch tool {
        case "character", "inventory", "equipment", "relationships", "weather": category = "common"
        case "appearance", "skills": category = "farmer"
        case "recipes", "storage", "collections": category = "items"
        case "farmhouse", "animals", "machines", "map": category = "farm"
        case "progress", "wallet", "bundles": category = "progress"
        default: throw NSError(domain: "ToolDirectoryTests", code: 1)
        }
        let button = app.buttons["tools.category.\(category)"]
        try revealDirectoryControl(button, in: app)
        button.tap()
    }

    @MainActor
    func revealDirectoryControl(_ element: XCUIElement, in app: XCUIApplication) throws {
        let list = app.scrollViews["editor.tools.list"]
        XCTAssertTrue(list.waitForExistence(timeout: 30))
        let startsAbove = element.identifier.hasPrefix("tools.category.")
            || element.identifier.hasPrefix("tools.search")
        for attempt in 0..<28 {
            let bounds = list.frame.intersection(app.frame).insetBy(dx: 0, dy: 4)
            let frame = element.exists ? element.frame : .null
            let hasFrame = !frame.isEmpty && frame.minY.isFinite
            if hasFrame && bounds.contains(frame) && element.isHittable { return }
            let down = hasFrame ? frame.midY > bounds.midY : (attempt < 14 ? !startsAbove : startsAbove)
            let distance = min(hasFrame ? max(abs(frame.midY - bounds.midY), 40) : 140,
                               bounds.height * 0.35)
            let direction: CGFloat = down ? 1 : -1
            let origin = app.coordinate(withNormalizedOffset: .zero)
            let start = origin.withOffset(CGVector(dx: bounds.midX - app.frame.minX,
                dy: bounds.midY - app.frame.minY + direction * distance / 2))
            let end = origin.withOffset(CGVector(dx: bounds.midX - app.frame.minX,
                dy: bounds.midY - app.frame.minY - direction * distance / 2))
            start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.2)
        }
        XCTFail("Tool directory control unreachable: \(element)\n\(app.debugDescription)")
        throw NSError(domain: "ToolDirectoryTests", code: 2)
    }
}
