import CryptoKit
import Foundation

struct SavePairData: Sendable {
    let main: Data
    let info: Data?

    var mainHash: String { Self.hash(main) }
    var infoHash: String? { info.map(Self.hash) }

    private static func hash(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

struct SaveTransactionJournal: Codable, Sendable {
    enum Phase: String, Codable, Sendable {
        case prepared
        case mainWritten
        case infoWritten
        case verified
    }

    let id: UUID
    let farmIdentifier: String
    let backupID: UUID
    let startedAt: Date
    let originalMainHash: String
    let originalInfoHash: String?
    let targetMainHash: String
    let targetInfoHash: String?
    var phase: Phase
    var sourceIdentity: String? = nil
    var rescueBackupID: UUID? = nil
}

enum SaveTransactionRecovery: Equatable, Sendable {
    case none
    case completedSaveConfirmed
    case originalFilesConfirmed
    case restoredFromBackup(BackupManifest)
}

struct SaveTransactionResult: Sendable {
    let backup: BackupManifest
    let written: SavePairData
}

enum SaveTransactionError: LocalizedError {
    case changedExternally
    case invalidRenderedMain
    case missingRenderedInfo
    case writeRolledBack(String)
    case rollbackUncertain(String)
    case verificationFailed
    case recoveryBackupMissing
    case recoveryBackupCorrupt
    case recoveryConflict(String)

    var errorDescription: String? {
        switch self {
        case .changedExternally:
            "存档在编辑期间被游戏或其他应用修改。为避免覆盖，请重新载入后再试。"
        case .invalidRenderedMain:
            "生成后的主存档校验失败，原文件没有被修改。"
        case .missingRenderedInfo:
            "当前来源包含 SaveGameInfo，但生成结果缺少该文件。"
        case let .writeRolledBack(message):
            "写回失败，原文件已从自动备份恢复：\(message)"
        case let .rollbackUncertain(message):
            "写回失败，而且无法确认回滚结果。请先不要启动游戏，并从应用备份恢复：\(message)"
        case .verificationFailed:
            "写回后的哈希校验失败，已停止后续操作。"
        case .recoveryBackupMissing:
            "检测到未完成的写回事务，但对应的私有备份不存在。请勿启动游戏覆盖该存档。"
        case .recoveryBackupCorrupt:
            "检测到未完成的写回事务，但对应备份的哈希校验失败。原存档未被继续修改。"
        case let .recoveryConflict(message):
            "检测到未完成事务与当前存档冲突，未覆盖当前文件。\(message)可选择保留当前存档并结束旧事务，或在备份中心导出之前的备份。"
        }
    }
}

final class SaveTransactionService {
    private let backupStore: BackupStore
    private let fileManager: FileManager
    private let journalDirectoryURL: URL
    private let writeData: (Data, URL) throws -> Void

    init(
        backupStore: BackupStore,
        fileManager: FileManager = .default,
        journalDirectoryURL customJournalDirectoryURL: URL? = nil,
        writeData: @escaping (Data, URL) throws -> Void = CoordinatedFileAccess.writeCoordinatedData
    ) throws {
        self.backupStore = backupStore
        self.fileManager = fileManager
        self.writeData = writeData
        let transactions: URL
        if let customJournalDirectoryURL {
            transactions = customJournalDirectoryURL
        } else {
            let support = try fileManager.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            transactions = support
                .appendingPathComponent("PelicanSaveEditor", isDirectory: true)
                .appendingPathComponent("Transactions", isDirectory: true)
        }
        try fileManager.createDirectory(at: transactions, withIntermediateDirectories: true)
        journalDirectoryURL = transactions
    }

    func read(source: SaveSource) throws -> SavePairData {
        try source.withSecurityScopedAccess {
            SavePairData(
                main: try CoordinatedFileAccess.read(source.mainURL),
                info: try source.infoURL.map(CoordinatedFileAccess.read)
            )
        }
    }

    /// Only a source-bound, known mixture can be recovered automatically.
    /// Unknown data may be newer game progress and is retained for user review.
    func recoverInterruptedTransactionIfNeeded(source: SaveSource) throws -> SaveTransactionRecovery {
        guard let journalURL = activeJournalURL(for: source) else { return .none }
        var journal = try readJournal(at: journalURL)
        return try source.withSecurityScopedAccess {
            try CoordinatedFileAccess.withCoordinatedWritePair(
                mainURL: source.mainURL, infoURL: source.infoURL
            ) { [self] mainURL, infoURL in
                let current = try readCoordinatedPair(mainURL: mainURL, infoURL: infoURL)
                let backup = try backupStore.list(farmIdentifier: journal.farmIdentifier)
                    .first { $0.id == journal.backupID }
                // Legacy journals can only inherit an identity from a newer backup
                // manifest. An unbound old journal must never guess from a farm name.
                let boundIdentity = journal.sourceIdentity ?? backup?.sourceIdentity
                guard journal.farmIdentifier == source.farmIdentifier, boundIdentity == source.identity else {
                    try preserveConflict(current, source: source, journal: &journal, at: journalURL)
                    throw SaveTransactionError.recoveryConflict("旧事务无法确认属于这个文件来源；当前两份文件已另行保留为保护备份。")
                }
                if matches(current, mainHash: journal.targetMainHash, infoHash: journal.targetInfoHash) {
                    try removeJournal(at: journalURL)
                    if let backup { _ = try? backupStore.setProtected(backup, isProtected: false) }
                    return .completedSaveConfirmed
                }
                if matches(current, mainHash: journal.originalMainHash, infoHash: journal.originalInfoHash) {
                    try removeJournal(at: journalURL)
                    if let backup { _ = try? backupStore.setProtected(backup, isProtected: false) }
                    return .originalFilesConfirmed
                }
                let knownMain = current.mainHash == journal.originalMainHash || current.mainHash == journal.targetMainHash
                let knownInfo = current.infoHash == journal.originalInfoHash || current.infoHash == journal.targetInfoHash
                guard knownMain && knownInfo else {
                    try preserveConflict(current, source: source, journal: &journal, at: journalURL)
                    throw SaveTransactionError.recoveryConflict("当前内容含有旧事务未记录的数据，可能是更新的游戏进度，已另行保留为保护备份。")
                }
                guard let backup else { throw SaveTransactionError.recoveryBackupMissing }
                _ = try backupStore.setProtected(backup, isProtected: true)
                let original = try backupStore.data(for: backup)
                let originalPair = SavePairData(main: original.main, info: original.info)
                guard matches(originalPair, mainHash: journal.originalMainHash, infoHash: journal.originalInfoHash) else {
                    throw SaveTransactionError.recoveryBackupCorrupt
                }
                do {
                    try writePair(originalPair, mainURL: mainURL, infoURL: infoURL)
                    let restored = try readCoordinatedPair(mainURL: mainURL, infoURL: infoURL)
                    guard matches(restored, mainHash: journal.originalMainHash, infoHash: journal.originalInfoHash) else {
                        throw SaveTransactionError.verificationFailed
                    }
                    try removeJournal(at: journalURL)
                    return .restoredFromBackup(backup)
                } catch {
                    throw SaveTransactionError.rollbackUncertain("中断恢复未完成：\(error.localizedDescription)。保护备份仍可在备份中心导出。")
                }
            }
        }
    }

    /// Explicit user choice: preserve the current pair and archive the conflicting
    /// journal. Nothing is written to the selected game files.
    func archiveRecoveryConflict(source: SaveSource) throws {
        guard let journalURL = activeJournalURL(for: source) else { return }
        try source.withSecurityScopedAccess {
            try CoordinatedFileAccess.withCoordinatedWritePair(
                mainURL: source.mainURL, infoURL: source.infoURL
            ) { [self] mainURL, infoURL in
                let current = try readCoordinatedPair(mainURL: mainURL, infoURL: infoURL)
                _ = try backupStore.create(source: source, mainData: current.main, infoData: current.info,
                                           reason: "保留当前存档并结束冲突事务", isProtected: true)
                if let journal = try? readJournal(at: journalURL),
                   let backup = try backupStore.list(farmIdentifier: journal.farmIdentifier).first(where: { $0.id == journal.backupID }) {
                    _ = try backupStore.setProtected(backup, isProtected: true)
                }
                let archiveDirectory = journalDirectoryURL.appendingPathComponent("Conflicts", isDirectory: true)
                try fileManager.createDirectory(at: archiveDirectory, withIntermediateDirectories: true)
                let archivedURL = archiveDirectory.appendingPathComponent("\(UUID().uuidString).json")
                try fileManager.moveItem(at: journalURL, to: archivedURL)
            }
        }
    }

    func replace(
        source: SaveSource,
        expectedMainHash: String,
        expectedInfoHash: String?,
        newData: SavePairData,
        reason: String
    ) throws -> SaveTransactionResult {
        try validate(pair: newData, expectsInfo: source.infoURL != nil)
        return try source.withSecurityScopedAccess {
            try CoordinatedFileAccess.withCoordinatedWritePair(
                mainURL: source.mainURL, infoURL: source.infoURL
            ) { [self] mainURL, infoURL in
                guard activeJournalURL(for: source) == nil else {
                    throw SaveTransactionError.recoveryConflict("请先重新打开这个农场，处理上次未完成的事务。")
                }
                let journalURL = journalURL(for: source)
                let current = try readCoordinatedPair(mainURL: mainURL, infoURL: infoURL)
                guard matches(current, mainHash: expectedMainHash, infoHash: expectedInfoHash) else {
                    throw SaveTransactionError.changedExternally
                }
                let backup = try backupStore.create(
                    source: source, mainData: current.main, infoData: current.info,
                    reason: reason, isProtected: true
                )
                var journal = SaveTransactionJournal(
                    id: UUID(), farmIdentifier: source.farmIdentifier, backupID: backup.id,
                    startedAt: Date(), originalMainHash: current.mainHash, originalInfoHash: current.infoHash,
                    targetMainHash: newData.mainHash, targetInfoHash: newData.infoHash, phase: .prepared,
                    sourceIdentity: source.identity
                )
                try writeJournal(journal, to: journalURL)
                do {
                    try writeData(newData.main, mainURL)
                    journal.phase = .mainWritten
                    try writeJournal(journal, to: journalURL)
                    if let infoURL, let info = newData.info {
                        try writeData(info, infoURL)
                        journal.phase = .infoWritten
                        try writeJournal(journal, to: journalURL)
                    }
                    let verification = try readCoordinatedPair(mainURL: mainURL, infoURL: infoURL)
                    guard matches(verification, mainHash: newData.mainHash, infoHash: newData.infoHash) else {
                        throw SaveTransactionError.verificationFailed
                    }
                    journal.phase = .verified
                    try writeJournal(journal, to: journalURL)
                    try removeJournal(at: journalURL)
                    let completedBackup = (try? backupStore.setProtected(backup, isProtected: false)) ?? backup
                    return SaveTransactionResult(backup: completedBackup, written: verification)
                } catch {
                    let writeFailure = error
                    do {
                        try writePair(current, mainURL: mainURL, infoURL: infoURL)
                        let rolledBack = try readCoordinatedPair(mainURL: mainURL, infoURL: infoURL)
                        guard matches(rolledBack, mainHash: current.mainHash, infoHash: current.infoHash) else {
                            throw SaveTransactionError.verificationFailed
                        }
                        try removeJournal(at: journalURL)
                    } catch {
                        throw SaveTransactionError.rollbackUncertain(
                            "写入：\(writeFailure.localizedDescription)；回滚：\(error.localizedDescription)"
                        )
                    }
                    throw SaveTransactionError.writeRolledBack(writeFailure.localizedDescription)
                }
            }
        }
    }

    private func validate(pair: SavePairData, expectsInfo: Bool) throws {
        if expectsInfo && pair.info == nil { throw SaveTransactionError.missingRenderedInfo }
        _ = try SaveParser.parse(mainData: pair.main, infoData: pair.info, catalog: [], recipeCatalog: [:])
    }

    func journalURL(for source: SaveSource) -> URL {
        journalDirectoryURL.appendingPathComponent("source-\(source.identity).json", isDirectory: false)
    }

    /// Legacy location, retained for migration; new transactions never use it.
    func journalURL(for farmIdentifier: String) -> URL {
        let safeName = farmIdentifier
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")
        return journalDirectoryURL.appendingPathComponent("\(safeName).json", isDirectory: false)
    }

    private func activeJournalURL(for source: SaveSource) -> URL? {
        let current = journalURL(for: source)
        if fileManager.fileExists(atPath: current.path) { return current }
        let legacy = journalURL(for: source.farmIdentifier)
        return fileManager.fileExists(atPath: legacy.path) ? legacy : nil
    }

    private func readJournal(at url: URL) throws -> SaveTransactionJournal {
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(SaveTransactionJournal.self, from: Data(contentsOf: url))
        } catch {
            throw SaveTransactionError.recoveryConflict("事务记录无法解析，已原样保留。")
        }
    }

    private func readCoordinatedPair(mainURL: URL, infoURL: URL?) throws -> SavePairData {
        // Copy the bytes rather than retaining a memory map across an in-place write.
        SavePairData(main: try Data(contentsOf: mainURL), info: try infoURL.map { try Data(contentsOf: $0) })
    }

    private func writePair(_ pair: SavePairData, mainURL: URL, infoURL: URL?) throws {
        try writeData(pair.main, mainURL)
        if let infoURL, let info = pair.info { try writeData(info, infoURL) }
    }

    private func matches(_ pair: SavePairData, mainHash: String, infoHash: String?) -> Bool {
        pair.mainHash == mainHash && pair.infoHash == infoHash
    }

    private func preserveConflict(
        _ pair: SavePairData, source: SaveSource,
        journal: inout SaveTransactionJournal, at journalURL: URL
    ) throws {
        let existing = try backupStore.list(farmIdentifier: source.farmIdentifier)
        if let original = existing.first(where: { $0.id == journal.backupID }) {
            _ = try backupStore.setProtected(original, isProtected: true)
        }
        if let rescueID = journal.rescueBackupID,
           let previous = existing.first(where: { $0.id == rescueID }),
           previous.sourceIdentity == source.identity,
           previous.mainHash == pair.mainHash, previous.infoHash == pair.infoHash {
            _ = try backupStore.data(for: previous)
            return
        }
        let rescue = try backupStore.create(
            source: source, mainData: pair.main, infoData: pair.info,
            reason: "事务冲突：保留当前未知或更新的进度", isProtected: true
        )
        journal.rescueBackupID = rescue.id
        try writeJournal(journal, to: journalURL)
    }

    private func writeJournal(_ journal: SaveTransactionJournal, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(journal).write(to: url, options: .atomic)
    }

    private func removeJournal(at url: URL) throws {
        guard fileManager.fileExists(atPath: url.path) else { return }
        try fileManager.removeItem(at: url)
    }
}
