import XCTest
@testable import PelicanSaveEditor

final class ToolDirectoryTests: XCTestCase {
    func testEveryEditorHasOneCategoryAndStableIdentifier() {
        let all = EditorToolEntry.all
        let expected = Set(SaveEditorSection.allCases.filter { $0 != .review }.map(\.rawValue)
            + ExpandedEditorTool.allCases.map(\.rawValue) + ["map"])
        XCTAssertEqual(Set(all.map(\.id)), expected)
        XCTAssertEqual(all.count, expected.count)
        let categorized = EditorToolCategory.allCases.filter { $0 != .common }
            .flatMap { EditorToolEntry.visible(in: $0, query: "") }
        XCTAssertEqual(categorized.count, expected.count)
        XCTAssertEqual(Set(categorized.map(\.id)), expected)
    }

    func testSearchIgnoresCategoryAndAcceptsWhitespaceAndAliases() {
        XCTAssertEqual(EditorToolEntry.visible(in: .items, query: " 天气 ").map(\.id), ["weather"])
        XCTAssertEqual(EditorToolEntry.visible(in: .farm, query: "金钱").map(\.id), ["character"])
        XCTAssertEqual(EditorToolEntry.visible(in: .progress, query: "工具 升级").map(\.id), ["equipment"])
        XCTAssertTrue(EditorToolEntry.visible(in: .common, query: "zznomatch123").isEmpty)
        XCTAssertEqual(EditorToolEntry.visible(in: .common, query: "  \n").count, 5)
    }
}
