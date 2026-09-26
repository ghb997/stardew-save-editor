import XCTest
@testable import PelicanSaveEditor

@MainActor
final class ReliabilityRegressionTests: XCTestCase {
    private func pair(money: Int = 100, identity: String = "42", extra: String = "", objects: String = "") -> SavePairData {
        let player = """
        <name>Farmer</name><farmName>Farm</farmName><favoriteThing>Tea</favoriteThing>
        <uniqueMultiplayerID>\(identity)</uniqueMultiplayerID><money>\(money)</money>
        <maxHealth>100</maxHealth><maxStamina>270</maxStamina>
        <yearForSaveGame>1</yearForSaveGame><seasonForSaveGame>0</seasonForSaveGame><dayOfMonthForSaveGame>1</dayOfMonthForSaveGame>
        <items><Item xsi:type="Object"><name>Wood</name><itemId>388</itemId><stack>10</stack><quality>0</quality><bigCraftable>false</bigCraftable></Item></items>
        """
        let namespace = "xmlns:xsi=\"http://www.w3.org/2001/XMLSchema-instance\""
        return SavePairData(main: Data("<SaveGame \(namespace)><gameVersion>1.6.15</gameVersion><player>\(player)</player><year>1</year><currentSeason>spring</currentSeason><dayOfMonth>1</dayOfMonth>\(extra)<locations><GameLocation xsi:type=\"Farm\"><name>Farm</name><objects>\(objects)</objects></GameLocation></locations></SaveGame>".utf8),
            info: Data("<Farmer \(namespace)>\(player)</Farmer>".utf8))
    }
    private func parse(_ pair: SavePairData) throws -> ParsedSaveDocument {
        try SaveParser.parse(mainData: pair.main, infoData: pair.info, catalog: [], recipeCatalog: [:])
    }
    private func root() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Reliability-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try FileManager.default.removeItem(at: root) }
        return root
    }
    private func game(_ root: URL, pair: SavePairData) throws -> SaveSource {
        let directory = root.appendingPathComponent("Game/Farmer_123", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try pair.main.write(to: directory.appendingPathComponent("Farmer_123"))
        try pair.info?.write(to: directory.appendingPathComponent("SaveGameInfo"))
        return try SaveSourceResolver.directory(directory)
    }
    private func imported(_ root: URL, pair: SavePairData) throws -> SaveSource {
        let original = try game(root, pair: pair)
        let library = try LocalSaveLibrary(root: root.appendingPathComponent("ImportedSaves", isDirectory: true))
        let source = try SaveSourceResolver.copiedFiles([original.mainURL, try XCTUnwrap(original.infoURL)], importRootURL: library.root)
        _ = try library.register(source, draft: parse(pair).draft, pair: pair, imported: true)
        return source
    }
    private func worker(_ root: URL) -> SaveWorkService {
        SaveWorkService(backupRootURL: root.appendingPathComponent("Backups"),
                        transactionDirectoryURL: root.appendingPathComponent("Transactions"),
                        localRootURL: root.appendingPathComponent("ImportedSaves", isDirectory: true))
    }

    func testMixedXMLTextCDATAWhitespaceAndCarriageReturnsSurviveMoneyEdit() throws {
        let extra = "<extension a=\"x&#13;&#10;&#9;y\">before<value>kept</value><![CDATA[after<&>]]></extension><preserved xml:space=\"preserve\"> <a/>\n <b/> </preserved><line>first&#13;second</line>"
        let original = try parse(pair(extra: extra))
        var draft = original.draft; draft.money = 4321
        let rendered = try SaveMutator.render(parsed: original, draft: draft)
        let reread = try parse(SavePairData(main: rendered.mainData, info: rendered.infoData))
        XCTAssertEqual(reread.draft.money, 4321)
        for key in ["extension", "preserved", "line"] {
            let before = try XCTUnwrap(original.mainRoot.child(named: key))
            let after = try XCTUnwrap(reread.mainRoot.child(named: key))
            XCTAssertTrue(before.semanticallyEquals(after), key)
        }
        XCTAssertEqual(reread.mainRoot.value(named: "line"), "first\rsecond")
        XCTAssertTrue(String(decoding: rendered.mainData, as: UTF8.self).contains("before<value>kept</value>after&lt;&amp;&gt;"))
    }

    func testUnsupportedMixedContainerMutationIsRejected() throws {
        let root = try XMLTreeParser().parse(Data("<a>before<b/>after</a>".utf8))
        XCTAssertTrue(root.canSerializeLosslessly)
        root.children.removeAll()
        XCTAssertFalse(root.canSerializeLosslessly)
        let original = try parse(pair(objects: "text" + debris(flag: "false", x: 1) + "tail"))
        var draft = original.draft; draft.farmActions.clearWeeds = true
        XCTAssertThrowsError(try SaveMutator.render(parsed: original, draft: draft))
    }

    private func debris(flag: String?, x: Int, extra: String = "") -> String {
        let flagXML = flag.map { "<bigCraftable>\($0)</bigCraftable>" } ?? ""
        return "<item><key><Vector2><X>\(x)</X><Y>1</Y></Vector2></key><value><Object><name>Object</name><itemId>0</itemId>\(flagXML)\(extra)</Object></value></item>"
    }
    func testDebrisRequiresUnambiguousFalseAndPreservesWhitespaceTruePlants() throws {
        let flags: [String?] = [" true ", "\nTrUe\t", " 1 ", nil, "unknown", " false ", "\n0 "]
        let objects = flags.enumerated().map { debris(flag: $0.element, x: $0.offset) }.joined()
            + debris(flag: "false", x: 20, extra: "<bigCraftable>true</bigCraftable>")
            + debris(flag: "false", x: 21, extra: "<itemId>0</itemId>")
        let original = try parse(pair(objects: objects))
        let snapshot = FarmSnapshotExtractor.extract(from: original.mainRoot, cropCatalog: [])
        XCTAssertEqual(snapshot.weedCount, 2)
        var draft = original.draft; draft.farmActions.clearWeeds = true
        let rendered = try SaveMutator.render(parsed: original, draft: draft)
        let reloaded = try parse(SavePairData(main: rendered.mainData, info: rendered.infoData))
        let remaining = try XCTUnwrap(reloaded.mainRoot.child(named: "locations")?.children.first?.child(named: "objects"))
        XCTAssertEqual(remaining.children.count, 7)
        XCTAssertEqual(remaining.children.compactMap { $0.child(named: "key")?.child(named: "Vector2")?.value(named: "X") }, ["0", "1", "2", "3", "4", "20", "21"])
    }

    func testSavedCopyIsDiscoverableAfterNewWorkerAndReopensExactBytes() async throws {
        let root = try root(), original = pair(), saved = pair(money: 500)
        let source = try imported(root, pair: original)
        let first = worker(root)
        _ = try await first.write(source: source, expected: original, target: saved, reason: "test", items: [], recipes: [:])
        let restarted = worker(root)
        let copies = try await restarted.localCopies()
        let copy = try XCTUnwrap(copies.first)
        XCTAssertTrue(copy.needsExport)
        let reopened = try await restarted.localSource(copy)
        let loaded = try await restarted.load(source: reopened, items: [], recipes: [:])
        XCTAssertEqual(loaded.pair.main, saved.main); XCTAssertEqual(loaded.pair.info, saved.info)
        XCTAssertEqual(loaded.parsed.draft.money, 500)
        XCTAssertGreaterThan(copy.byteCount, Int64(saved.main.count + (saved.info?.count ?? 0)))
    }

    func testLegacyCopyMigratesWithoutInventingOriginHashes() throws {
        let root = try root(), original = pair()
        let source = try imported(root, pair: original)
        try FileManager.default.removeItem(at: source.mainURL.deletingLastPathComponent().appendingPathComponent("copy.json"))
        let library = try LocalSaveLibrary(root: root.appendingPathComponent("ImportedSaves", isDirectory: true))
        let record = try XCTUnwrap(library.list().first)
        XCTAssertNil(record.originMainHash); XCTAssertTrue(record.needsExport)
        XCTAssertEqual(try Data(contentsOf: library.source(for: record).mainURL), original.main)
    }

    func testDraftReopensAndRebindsInventoryUUIDs() async throws {
        let root = try root(), pair = pair()
        let source = try imported(root, pair: pair), original = try parse(pair).draft
        var draft = original; draft.money = 999; draft.inventory[0].item?.stack = 25
        let first = worker(root)
        try await first.persistDraft(source: source, pair: pair, original: original, draft: draft)
        let restarted = worker(root), fresh = try parse(pair).draft
        XCTAssertNotEqual(original.inventory[0].item?.id, fresh.inventory[0].item?.id)
        let recovered = try await restarted.recoveredDraft(source: source, pair: pair, original: fresh)
        XCTAssertEqual(recovered?.money, 999); XCTAssertEqual(recovered?.inventory[0].item?.stack, 25)
        XCTAssertEqual(recovered?.inventory[0].item?.id, fresh.inventory[0].item?.id)
        let copies = try await restarted.localCopies()
        XCTAssertEqual(copies.first?.hasDraft, true)
    }

    func testDraftRejectsChangedPairAndPreservesCheckpoint() async throws {
        let root = try root(), original = pair()
        let source = try imported(root, pair: original), base = try parse(original).draft
        var draft = base; draft.money = 888
        let service = worker(root)
        try await service.persistDraft(source: source, pair: original, original: base, draft: draft)
        do {
            _ = try await service.recoveredDraft(source: source, pair: pair(money: 200), original: base)
            XCTFail("Must refuse stale checkpoint")
        } catch {}
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.mainURL.deletingLastPathComponent().appendingPathComponent("draft.json").path))
        try await service.discardDraft(source: source)
        let cleared = try await service.recoveredDraft(source: source, pair: original, original: base)
        XCTAssertNil(cleared)
    }

    func testUnknownDraftSchemaAndCorruptDraftAreRetained() async throws {
        let root = try root(), pair = pair(), source = try imported(root, pair: pair)
        let library = try LocalSaveLibrary(root: root.appendingPathComponent("ImportedSaves", isDirectory: true))
        let original = try parse(pair).draft
        var checkpoint = DraftCheckpoint(copyID: try library.id(for: source), savedAt: Date(), mainHash: pair.mainHash,
                                         infoHash: pair.infoHash, original: original, draft: original)
        checkpoint.schemaVersion = 500
        try library.checkpoint(checkpoint)
        XCTAssertThrowsError(try checkpoint.rebased(on: original, pair: pair, copyID: checkpoint.copyID))
        let url = source.mainURL.deletingLastPathComponent().appendingPathComponent("draft.json")
        try Data("broken".utf8).write(to: url)
        do { _ = try await worker(root).recoveredDraft(source: source, pair: pair, original: original); XCTFail("Corrupt draft") } catch {}
        XCTAssertEqual(try Data(contentsOf: url), Data("broken".utf8))
    }

    func testSaveClearsDraftAndProtectsPendingExportFromDeletion() async throws {
        let root = try root(), original = pair(), source = try imported(root, pair: original)
        let service = worker(root), base = try parse(original).draft
        var draft = base; draft.money = 999
        try await service.persistDraft(source: source, pair: original, original: base, draft: draft)
        _ = try await service.write(source: source, expected: original, target: pair(money: 999), reason: "save", items: [], recipes: [:])
        let records = try await service.localCopies(), record = try XCTUnwrap(records.first)
        XCTAssertFalse(record.hasDraft); XCTAssertTrue(record.needsExport)
        do { try await service.deleteLocalCopy(record, currentIdentity: nil); XCTFail("Pending export protected") } catch {}
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.mainURL.path))
    }

    func testCurrentAndDraftCopiesCannotBeDeletedThenExportedCopyCan() async throws {
        let root = try root(), pair = pair(), source = try imported(root, pair: pair), service = worker(root)
        let copies = try await service.localCopies(), copy = try XCTUnwrap(copies.first)
        do { try await service.deleteLocalCopy(copy, currentIdentity: source.identity); XCTFail("Current copy protected") } catch {}
        let original = try parse(pair).draft
        var draft = original; draft.money = 888
        try await service.persistDraft(source: source, pair: pair, original: original, draft: draft)
        do { try await service.deleteLocalCopy(copy, currentIdentity: nil); XCTFail("Draft protected") } catch {}
        try await service.discardDraft(source: source)
        try await service.markFileExport(source: source, pair: pair)
        try await service.deleteLocalCopy(copy, currentIdentity: nil)
        XCTAssertFalse(FileManager.default.fileExists(atPath: source.mainURL.path))
    }

    func testFailedUnindexedImportCanBeRemovedWithoutTouchingOriginal() async throws {
        let root = try root(), original = pair(), game = try game(root, pair: original), service = worker(root)
        try Data("broken".utf8).write(to: game.mainURL)
        let copy = try await service.resolveFiles([game.mainURL, try XCTUnwrap(game.infoURL)], copying: true)
        do { _ = try await service.load(source: copy, items: [], recipes: [:], imported: true); XCTFail("Invalid import") } catch {}
        try await service.discardFailedImport(copy)
        XCTAssertFalse(FileManager.default.fileExists(atPath: copy.mainURL.deletingLastPathComponent().path))
        XCTAssertEqual(try Data(contentsOf: game.mainURL), Data("broken".utf8))
    }

    func testExportRejectsWrongPlayerAndShowsChangedTarget() async throws {
        let root = try root(), original = pair(), source = try imported(root, pair: original), service = worker(root)
        let wrong = try game(root, pair: pair(identity: "99"))
        do { _ = try await service.prepareExport(source: source, expected: original, directory: wrong.mainURL.deletingLastPathComponent()); XCTFail("Wrong identity") } catch {}
        let target = try game(root, pair: pair(money: 800))
        let review = try await service.prepareExport(source: source, expected: original, directory: target.mainURL.deletingLastPathComponent())
        XCTAssertTrue(review.targetChanged); XCTAssertFalse(review.identityWarning)
        XCTAssertTrue(review.targetDescription.contains("800"))
    }

    func testChangedTargetAfterReviewAbortsWithoutWriting() async throws {
        let root = try root(), original = pair(), source = try imported(root, pair: original), service = worker(root)
        let target = try game(root, pair: original)
        let review = try await service.prepareExport(source: source, expected: original, directory: target.mainURL.deletingLastPathComponent())
        XCTAssertFalse(review.targetChanged)
        let newer = pair(money: 700)
        try newer.main.write(to: target.mainURL); try newer.info?.write(to: try XCTUnwrap(target.infoURL))
        do { _ = try await service.commitExport(source: source, review: review); XCTFail("Target changed") } catch {}
        XCTAssertEqual(try Data(contentsOf: target.mainURL), newer.main)
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(target.infoURL)), newer.info)
    }

    func testVerifiedExportBacksUpTargetAndRecordsExactWrittenPair() async throws {
        let root = try root(), original = pair(), saved = pair(money: 900)
        let source = try imported(root, pair: original), service = worker(root)
        _ = try await service.write(source: source, expected: original, target: saved, reason: "save", items: [], recipes: [:])
        let target = try game(root, pair: pair(money: 700))
        let beforeMain = try Data(contentsOf: target.mainURL), beforeInfo = try Data(contentsOf: XCTUnwrap(target.infoURL))
        let review = try await service.prepareExport(source: source, expected: saved, directory: target.mainURL.deletingLastPathComponent())
        let warning = try await service.commitExport(source: source, review: review)
        XCTAssertNil(warning)
        XCTAssertEqual(try Data(contentsOf: target.mainURL), saved.main)
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(target.infoURL)), saved.info)
        let backups = try await service.listBackups(), backup = try XCTUnwrap(backups.first { $0.sourceIdentity == target.identity })
        XCTAssertEqual(backup.isProtected, true)
        let backed = try await service.backupPair(backup)
        XCTAssertEqual(backed.main, beforeMain); XCTAssertEqual(backed.info, beforeInfo)
        let copies = try await service.localCopies(), record = try XCTUnwrap(copies.first)
        XCTAssertFalse(record.needsExport); XCTAssertTrue(record.verifiedGameExport)
        XCTAssertEqual(record.originMainHash, saved.mainHash)
    }

    func testBackupExportCacheLeaseAndCleanupAndProtection() async throws {
        let root = try root(), pair = pair(), source = try imported(root, pair: pair), service = worker(root)
        let backup = try await service.createManualBackup(source: source)
        do { try await service.deleteBackup(backup); XCTFail("Protected backup") } catch {}
        let urls = try await service.exportBackup(backup)
        XCTAssertEqual(try Data(contentsOf: urls[0]), pair.main)
        do { try await service.cleanExportCache(); XCTFail("Export lease active") } catch {}
        try await service.finishBackupExport()
        XCTAssertFalse(FileManager.default.fileExists(atPath: urls[0].path))
        try await service.setBackupProtection(backup, protected: false)
        try await service.deleteBackup(backup)
        let backups = try await service.listBackups()
        XCTAssertTrue(backups.isEmpty)
    }

    func testActiveTransactionBlocksBackupUnprotectAndCopyDelete() async throws {
        let root = try root(), original = pair(), source = try imported(root, pair: original), service = worker(root)
        let backup = try await service.createManualBackup(source: source)
        let transactions = try SaveTransactionService(backupStore: BackupStore(rootURL: root.appendingPathComponent("Backups")), journalDirectoryURL: root.appendingPathComponent("Transactions"))
        let journal = SaveTransactionJournal(id: UUID(), farmIdentifier: source.farmIdentifier, backupID: backup.id,
            startedAt: Date(), originalMainHash: original.mainHash, originalInfoHash: original.infoHash,
            targetMainHash: pair(money: 200).mainHash, targetInfoHash: pair(money: 200).infoHash, phase: .prepared, sourceIdentity: source.identity)
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(journal).write(to: transactions.journalURL(for: source))
        do { try await service.setBackupProtection(backup, protected: false); XCTFail("Required backup") } catch {}
        let copies = try await service.localCopies(), copy = try XCTUnwrap(copies.first)
        do { try await service.deleteLocalCopy(copy, currentIdentity: nil); XCTFail("Active journal") } catch {}
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.mainURL.path))
    }
}
