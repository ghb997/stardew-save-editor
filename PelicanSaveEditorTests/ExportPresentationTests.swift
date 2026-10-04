import XCTest
@testable import PelicanSaveEditor

final class ExportPresentationTests: XCTestCase {
    private func snapshot() -> SavedExportSnapshot {
        let folder = URL(fileURLWithPath: "/local/Farmer_123")
        return SavedExportSnapshot(source: SaveSource(mode: .importedCopy, farmIdentifier: "Farmer_123",
            mainURL: folder.appendingPathComponent("Farmer_123"), infoURL: folder.appendingPathComponent("SaveGameInfo"), accessURLs: []),
            pair: SavePairData(main: Data("main".utf8), info: Data("info".utf8)))
    }

    func testFileExportSuccessIsConsumedOnceInEitherCallbackOrder() {
        for dismissalFirst in [false, true] {
            var flow = FileExportPresentationFlow()
            let snapshot = snapshot(), id = flow.begin(snapshot: snapshot)
            let result: FileExportPresentationResult?
            if dismissalFirst {
                XCTAssertNil(flow.dismissed(presentationID: id))
                result = flow.exported(presentationID: id)
            } else {
                XCTAssertNil(flow.exported(presentationID: id))
                result = flow.dismissed(presentationID: id)
            }
            guard case let .exported(actual)? = result else { return XCTFail("Expected captured export") }
            XCTAssertEqual(actual.id, snapshot.id)
            XCTAssertEqual(actual.pair.mainHash, snapshot.pair.mainHash)
            XCTAssertNil(flow.exported(presentationID: id))
            XCTAssertNil(flow.dismissed(presentationID: id))
        }
    }

    func testFileExportCancellationAndLateCallbacksDoNotAffectNextPresentation() {
        for dismissalFirst in [false, true] {
            var flow = FileExportPresentationFlow()
            let snapshot = snapshot(), first = flow.begin(snapshot: snapshot)
            let result: FileExportPresentationResult?
            if dismissalFirst {
                XCTAssertNil(flow.dismissed(presentationID: first))
                result = flow.cancelled(presentationID: first)
            } else {
                XCTAssertNil(flow.cancelled(presentationID: first))
                result = flow.dismissed(presentationID: first)
            }
            guard case .cancelled? = result else { return XCTFail("Expected cancellation") }
            // Even re-exporting the same saved snapshot gets a new presentation token.
            let second = flow.begin(snapshot: snapshot)
            XCTAssertNotEqual(first, second)
            XCTAssertNil(flow.exported(presentationID: first))
            XCTAssertNil(flow.dismissed(presentationID: first))
            XCTAssertNil(flow.cancelled(presentationID: first))
            XCTAssertNil(flow.exported(presentationID: second))
            guard case .exported? = flow.dismissed(presentationID: second) else {
                return XCTFail("The new picker must still complete")
            }
        }
    }
}
