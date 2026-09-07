import XCTest
@testable import PelicanSaveEditor

final class TransactionRegressionTests: XCTestCase {
    private enum InjectedFailure: Error { case write }

    private struct Harness {
        let root: URL
        let backupRoot: URL
        let journalRoot: URL
        let backups: BackupStore
        let service: SaveTransactionService
        let source: SaveSource
    }

    private func pair(money: Int) -> SavePairData {
        let player = """
        <name>Farmer</name><farmName>Farm</farmName><favoriteThing>Tea</favoriteThing>
        <uniqueMultiplayerID>42</uniqueMultiplayerID><money>\(money)</money>
        <maxHealth>100</maxHealth><maxStamina>270</maxStamina>
        <yearForSaveGame>1</yearForSaveGame><seasonForSaveGame>0</seasonForSaveGame>
        <dayOfMonthForSaveGame>1</dayOfMonthForSaveGame><items/>
        """
        return SavePairData(
            main: Data("<SaveGame><gameVersion>1.6.15</gameVersion><player>\(player)</player><year>1</year><currentSeason>spring</currentSeason><dayOfMonth>1</dayOfMonth><locations/></SaveGame>".utf8),
            info: Data("<Farmer>\(player)</Farmer>".utf8)
        )
    }

    private func makeSource(under root: URL, folder: String, pair: SavePairData) throws -> SaveSource {
        let farm = root.appendingPathComponent(folder, isDirectory: true)
            .appendingPathComponent("Farmer_123", isDirectory: true)
        try FileManager.default.createDirectory(at: farm, withIntermediateDirectories: true)
        try pair.main.write(to: farm.appendingPathComponent("Farmer_123"))
        try pair.info?.write(to: farm.appendingPathComponent("SaveGameInfo"))
        return try SaveSourceResolver.directory(farm)
    }

    private func makeHarness(writeData: @escaping (Data, URL) throws -> Void = CoordinatedFileAccess.writeCoordinatedData) throws -> Harness {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("TransactionRegression-\(UUID().uuidString)")
        let backupRoot = root.appendingPathComponent("Backups")
        let journalRoot = root.appendingPathComponent("Transactions")
        let backups = try BackupStore(rootURL: backupRoot)
        let service = try SaveTransactionService(backupStore: backups, journalDirectoryURL: journalRoot, writeData: writeData)
        let source = try makeSource(under: root, folder: "Game", pair: pair(money: 100))
        return Harness(root: root, backupRoot: backupRoot, journalRoot: journalRoot, backups: backups, service: service, source: source)
    }

    @discardableResult
    private func prepareJournal(_ harness: Harness, target: SavePairData, legacy: Bool = false, unboundBackup: Bool = false) throws -> BackupManifest {
        let original = try harness.service.read(source: harness.source)
        var backup = try harness.backups.create(source: harness.source, mainData: original.main, infoData: original.info,
                                               reason: "pending transaction", isProtected: true)
        if unboundBackup {
            backup.sourceIdentity = nil
            backup.sourceMode = nil
            backup.sourceLocation = nil
            let manifestURL = harness.backupRoot.appendingPathComponent(backup.farmIdentifier)
                .appendingPathComponent(backup.id.uuidString).appendingPathComponent("manifest.json")
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(backup).write(to: manifestURL, options: .atomic)
        }
        let journal = SaveTransactionJournal(
            id: UUID(), farmIdentifier: harness.source.farmIdentifier, backupID: backup.id, startedAt: Date(),
            originalMainHash: original.mainHash, originalInfoHash: original.infoHash,
            targetMainHash: target.mainHash, targetInfoHash: target.infoHash, phase: .mainWritten,
            sourceIdentity: legacy ? nil : harness.source.identity
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let url = legacy ? harness.service.journalURL(for: harness.source.farmIdentifier) : harness.service.journalURL(for: harness.source)
        try encoder.encode(journal).write(to: url, options: .atomic)
        return backup
    }

    func testSameFarmNameAtDifferentSourcesDoesNotShareJournal() throws {
        let harness = try makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.root) }
        let target = pair(money: 200)
        try prepareJournal(harness, target: target)
        let other = try makeSource(under: harness.root, folder: "ImportedCopy", pair: pair(money: 900))
        XCTAssertNotEqual(harness.source.identity, other.identity)
        XCTAssertNotEqual(harness.service.journalURL(for: harness.source), harness.service.journalURL(for: other))
        XCTAssertEqual(try harness.service.recoverInterruptedTransactionIfNeeded(source: other), .none)
        XCTAssertEqual(try harness.service.read(source: other).mainHash, pair(money: 900).mainHash)
        XCTAssertTrue(FileManager.default.fileExists(atPath: harness.service.journalURL(for: harness.source).path))
        let fileSelection = try SaveSourceResolver.files([harness.source.mainURL, try XCTUnwrap(harness.source.infoURL)])
        XCTAssertEqual(harness.source.identity, fileSelection.identity, "Changing picker mode must not lose a pending transaction")
    }

    func testUnknownNewProgressIsPreservedAndNeedsExplicitChoice() throws {
        let harness = try makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.root) }
        let originalBackup = try prepareJournal(harness, target: pair(money: 200))
        let newer = pair(money: 900)
        try newer.main.write(to: harness.source.mainURL)
        try newer.info?.write(to: try XCTUnwrap(harness.source.infoURL))
        for _ in 0..<2 {
            XCTAssertThrowsError(try harness.service.recoverInterruptedTransactionIfNeeded(source: harness.source)) { error in
                guard case SaveTransactionError.recoveryConflict = error else { return XCTFail("Expected recovery conflict: \(error)") }
            }
            let current = try harness.service.read(source: harness.source)
            XCTAssertEqual(current.mainHash, newer.mainHash)
            XCTAssertEqual(current.infoHash, newer.infoHash)
        }
        let backups = try harness.backups.list()
        XCTAssertEqual(backups.count, 2, "Repeated attempts must reuse an unchanged rescue snapshot")
        XCTAssertTrue(backups.allSatisfy { $0.isProtected == true })
        XCTAssertTrue(backups.contains { $0.id == originalBackup.id })
        let rescue = try XCTUnwrap(backups.first { $0.mainHash == newer.mainHash })
        XCTAssertEqual(try harness.backups.data(for: rescue).main, newer.main)
        try harness.service.archiveRecoveryConflict(source: harness.source)
        XCTAssertEqual(try harness.service.recoverInterruptedTransactionIfNeeded(source: harness.source), .none)
        XCTAssertEqual(try harness.service.read(source: harness.source).mainHash, newer.mainHash)
        let archived = try FileManager.default.contentsOfDirectory(at: harness.journalRoot.appendingPathComponent("Conflicts"), includingPropertiesForKeys: nil)
        XCTAssertEqual(archived.count, 1)
    }

    func testUnboundLegacyJournalNeverGuessesSourceFromFarmName() throws {
        let harness = try makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.root) }
        let target = pair(money: 200)
        try prepareJournal(harness, target: target, legacy: true, unboundBackup: true)
        try target.main.write(to: harness.source.mainURL)
        XCTAssertThrowsError(try harness.service.recoverInterruptedTransactionIfNeeded(source: harness.source)) { error in
            guard case SaveTransactionError.recoveryConflict = error else { return XCTFail("Expected legacy conflict: \(error)") }
        }
        XCTAssertEqual(try Data(contentsOf: harness.source.mainURL), target.main)
        XCTAssertTrue(FileManager.default.fileExists(atPath: harness.service.journalURL(for: harness.source.farmIdentifier).path))
    }

    func testBoundKnownMixedPairRestoresOriginal() throws {
        let harness = try makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.root) }
        let target = pair(money: 200)
        let backup = try prepareJournal(harness, target: target)
        try target.main.write(to: harness.source.mainURL)
        guard case let .restoredFromBackup(restoredBackup) = try harness.service.recoverInterruptedTransactionIfNeeded(source: harness.source) else {
            return XCTFail("Expected known mixed pair recovery")
        }
        XCTAssertEqual(restoredBackup.id, backup.id)
        XCTAssertEqual(try harness.service.read(source: harness.source).mainHash, pair(money: 100).mainHash)
        XCTAssertFalse(FileManager.default.fileExists(atPath: harness.service.journalURL(for: harness.source).path))
    }

    func testFailureDuringSecondWriteRestoresBothOriginalFiles() throws {
        var writes = 0
        let harness = try makeHarness { data, url in
            writes += 1
            if writes == 2 {
                try CoordinatedFileAccess.writeCoordinatedData(Data(), to: url)
                throw InjectedFailure.write
            }
            try CoordinatedFileAccess.writeCoordinatedData(data, to: url)
        }
        defer { try? FileManager.default.removeItem(at: harness.root) }
        let original = pair(money: 100)
        XCTAssertThrowsError(try harness.service.replace(source: harness.source, expectedMainHash: original.mainHash,
                                                       expectedInfoHash: original.infoHash, newData: pair(money: 200), reason: "failure test")) { error in
            guard case SaveTransactionError.writeRolledBack = error else { return XCTFail("Expected verified rollback: \(error)") }
        }
        let current = try harness.service.read(source: harness.source)
        XCTAssertEqual(current.mainHash, original.mainHash)
        XCTAssertEqual(current.infoHash, original.infoHash)
        XCTAssertFalse(FileManager.default.fileExists(atPath: harness.service.journalURL(for: harness.source).path))
        XCTAssertEqual(try harness.backups.list().first?.isProtected, true)
    }

    func testRollbackFailureRetainsJournalAndExportableProtectedBackup() throws {
        var writes = 0
        let harness = try makeHarness { data, url in
            writes += 1
            if writes >= 2 { throw InjectedFailure.write }
            try CoordinatedFileAccess.writeCoordinatedData(data, to: url)
        }
        defer { try? FileManager.default.removeItem(at: harness.root) }
        let original = pair(money: 100)
        XCTAssertThrowsError(try harness.service.replace(source: harness.source, expectedMainHash: original.mainHash,
                                                       expectedInfoHash: original.infoHash, newData: pair(money: 200), reason: "rollback failure")) { error in
            guard case SaveTransactionError.rollbackUncertain = error else { return XCTFail("Expected uncertain rollback: \(error)") }
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: harness.service.journalURL(for: harness.source).path))
        let backup = try XCTUnwrap(harness.backups.list().first)
        XCTAssertEqual(backup.isProtected, true)
        let urls = try harness.backups.export(backup)
        XCTAssertEqual(try Data(contentsOf: urls[0]), original.main)
        XCTAssertEqual(try Data(contentsOf: urls[1]), original.info)
    }

    func testBackupExportsWithoutOriginalFilesOrEditingSession() throws {
        let harness = try makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.root) }
        let original = pair(money: 100)
        let backup = try harness.backups.create(source: harness.source, mainData: original.main, infoData: original.info,
                                               reason: "manual recovery point", isProtected: true)
        try Data("broken XML".utf8).write(to: harness.source.mainURL)
        try FileManager.default.removeItem(at: try XCTUnwrap(harness.source.infoURL))
        try harness.backups.validate(backup)
        let urls = try harness.backups.export(backup)
        XCTAssertEqual(urls.map(\.lastPathComponent), ["Farmer_123", "SaveGameInfo"])
        XCTAssertEqual(try Data(contentsOf: urls[0]), original.main)
        XCTAssertEqual(try Data(contentsOf: urls[1]), original.info)
        XCTAssertEqual(try Data(contentsOf: harness.source.mainURL), Data("broken XML".utf8))
        XCTAssertFalse(FileManager.default.fileExists(atPath: try XCTUnwrap(harness.source.infoURL).path))
    }

    func testProtectedRecoveryPointSurvivesAutomaticRetention() throws {
        let harness = try makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.root) }
        let original = pair(money: 100)
        let protected = try harness.backups.create(source: harness.source, mainData: original.main, infoData: original.info,
                                                  reason: "manual", isProtected: true)
        var last: BackupManifest?
        for value in 0..<12 {
            let current = pair(money: value)
            last = try harness.backups.create(source: harness.source, mainData: current.main, infoData: current.info, reason: "automatic")
        }
        let retained = try harness.backups.list()
        XCTAssertEqual(retained.filter { $0.isProtected != true }.count, 10)
        XCTAssertTrue(retained.contains { $0.id == protected.id })
        XCTAssertTrue(retained.contains { $0.id == last?.id }, "The newest backup survives same-second timestamp ties")
        XCTAssertEqual(try harness.backups.data(for: protected).main, original.main)
    }

    func testInvalidRenderedInfoIsRejectedBeforeSourceWrites() throws {
        let harness = try makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.root) }
        let original = pair(money: 100)
        XCTAssertThrowsError(try harness.service.replace(source: harness.source, expectedMainHash: original.mainHash,
                                                       expectedInfoHash: original.infoHash,
                                                       newData: SavePairData(main: pair(money: 200).main, info: Data("<Wrong/>".utf8)), reason: "invalid pair"))
        XCTAssertEqual(try harness.service.read(source: harness.source).mainHash, original.mainHash)
        XCTAssertTrue(try harness.backups.list().isEmpty)
    }
}
