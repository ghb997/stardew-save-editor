import Foundation

/// Trees are created in this actor and transferred once to the UI with `sending`.
/// Saving takes value snapshots, never the mutable XML tree owned by the UI.
struct LoadedSaveWork {
    let source: SaveSource
    let parsed: ParsedSaveDocument
    let pair: SavePairData
    let recovery: SaveTransactionRecovery
    let snapshot: FarmSnapshot
    let loadTimings: SaveLoadTimings?
    var storageWarning: String? = nil
}

/// Durations and sizes only; no farm names, paths or save contents are logged.
struct SaveLoadTimings: Sendable {
    let recovery: TimeInterval
    let read: TimeInterval
    let parse: TimeInterval
    let snapshot: TimeInterval
    let byteCount: Int

    var total: TimeInterval { recovery + read + parse + snapshot }
}

struct CatalogLoadResult: Sendable {
    var items: [CatalogItem] = []
    var recipes: [RecipeKind: [String]] = [:]
    var crops: [CropDefinition] = []
    var warnings: [String] = []
}

actor SaveWorkService {
    private var backupStore: BackupStore?
    private var transactionService: SaveTransactionService?
    private let backupRootURL: URL?
    private let transactionDirectoryURL: URL?
    private let localRootURL: URL?
    private var library: LocalSaveLibrary?
    private var exportCacheInUse = false

    init(backupRootURL: URL? = nil, transactionDirectoryURL: URL? = nil, localRootURL: URL? = nil) {
        self.backupRootURL = backupRootURL
        self.transactionDirectoryURL = transactionDirectoryURL
        self.localRootURL = localRootURL
    }

    private func localLibrary() throws -> LocalSaveLibrary {
        if let library { return library }
        let value = try LocalSaveLibrary(root: localRootURL)
        library = value
        return value
    }

    private func backupsService() throws -> BackupStore {
        if let backupStore { return backupStore }
        let created = try BackupStore(rootURL: backupRootURL)
        backupStore = created
        return created
    }

    private func transactionsService() throws -> SaveTransactionService {
        if let transactionService { return transactionService }
        let created = try SaveTransactionService(backupStore: backupsService(), journalDirectoryURL: transactionDirectoryURL)
        transactionService = created
        return created
    }

    func initialize() -> CatalogLoadResult {
        // A failed writable directory must not hide working offline catalogs or
        // prevent exporting existing backups. Initialize each capability alone.
        var result = CatalogLoadResult()
        do { result.items = try ItemCatalog.load() }
        catch { result.warnings.append("物品目录：\(error.localizedDescription)") }
        do { result.recipes = try RecipeCatalog.load() }
        catch { result.warnings.append("配方目录：\(error.localizedDescription)") }
        do { result.crops = try CropCatalog.load() }
        catch { result.warnings.append("作物目录：\(error.localizedDescription)") }
        do { _ = try backupsService() }
        catch { result.warnings.append("本地备份暂不可用：\(error.localizedDescription)") }
        do { _ = try transactionsService() }
        catch { result.warnings.append("安全写回与中断恢复暂不可用：\(error.localizedDescription)") }
        do { _ = try localLibrary(); try backupsService().cleanExportCache() }
        catch { result.warnings.append("本地副本管理：\(error.localizedDescription)") }
        return result
    }

    func discover(_ url: URL) throws -> [SaveSource] { try SaveSourceResolver.discoverDirectories(in: url) }
    func resolveFiles(_ urls: [URL], copying: Bool) throws -> SaveSource {
        if copying { return try SaveSourceResolver.copiedFiles(urls, importRootURL: localLibrary().root) }
        return try SaveSourceResolver.files(urls)
    }
    func recent() throws -> SaveSource { try RecentSaveSourceStore.load() }
    func remember(_ source: SaveSource) throws { try RecentSaveSourceStore.save(source) }

    func load(source: SaveSource, items: [CatalogItem], recipes: [RecipeKind: [String]],
              crops: [CropDefinition] = [], imported: Bool = false,
              onStage: @MainActor @Sendable (String) -> Void = { _ in }) async throws -> sending LoadedSaveWork {
        await onStage("正在检查上次保存状态…")
        let started = ProcessInfo.processInfo.systemUptime
        let transactions = try transactionsService()
        let recovery = try transactions.recoverInterruptedTransactionIfNeeded(source: source)
        let recovered = ProcessInfo.processInfo.systemUptime
        await onStage("正在读取存档文件…")
        let pair = try transactions.read(source: source)
        let read = ProcessInfo.processInfo.systemUptime
        await onStage("正在解析人物与存档数据…")
        let parsed = try SaveParser.parse(mainData: pair.main, infoData: pair.info, catalog: items, recipeCatalog: recipes)
        let parsedAt = ProcessInfo.processInfo.systemUptime
        await onStage("正在整理农场概览…")
        let snapshot = FarmSnapshotExtractor.extract(from: parsed.mainRoot, cropCatalog: crops)
        let finished = ProcessInfo.processInfo.systemUptime
        if source.mode == .importedCopy {
            _ = try localLibrary().register(source, draft: parsed.draft, pair: pair, imported: imported)
        }
        let timings = SaveLoadTimings(recovery: recovered - started, read: read - recovered,
            parse: parsedAt - read, snapshot: finished - parsedAt, byteCount: pair.main.count + (pair.info?.count ?? 0))
        return LoadedSaveWork(source: source, parsed: parsed, pair: pair, recovery: recovery,
                              snapshot: snapshot, loadTimings: timings)
    }

    func render(original: SavePairData, originalDraft: SaveDraft, draft: SaveDraft,
                items: [CatalogItem], recipes: [RecipeKind: [String]]) throws -> SavePairData {
        let fresh = try SaveParser.parse(mainData: original.main, infoData: original.info, catalog: items, recipeCatalog: recipes)
        // Inventory UUIDs identify draft instances and are regenerated by parsing.
        // Compare against the matching session's immutable value baseline so an
        // unrelated edit does not look like every inventory item was replaced.
        // Only XML trees created within this actor are used for rendering.
        let parsed = ParsedSaveDocument(mainRoot: fresh.mainRoot, infoRoot: fresh.infoRoot,
            mainPayload: fresh.mainPayload, infoPayload: fresh.infoPayload, draft: originalDraft,
            gameVersion: fresh.gameVersion, playTimeMilliseconds: fresh.playTimeMilliseconds,
            farmType: fresh.farmType, warnings: fresh.warnings)
        let rendered = try SaveMutator.render(parsed: parsed, draft: draft)
        let reloaded = try SaveParser.parse(mainData: rendered.mainData, infoData: rendered.infoData, catalog: items, recipeCatalog: recipes)
        try SaveIntentVerifier.verify(original: originalDraft, intended: draft, reloaded: reloaded, originalRoot: fresh.mainRoot)
        return SavePairData(main: rendered.mainData, info: rendered.infoData)
    }

    func write(source: SaveSource, expected: SavePairData, target: SavePairData, reason: String,
               items: [CatalogItem], recipes: [RecipeKind: [String]], crops: [CropDefinition] = []) throws -> sending LoadedSaveWork {
        // Finish every throwing parse before committing. The transaction verifies
        // the written bytes against target hashes; this fresh, unshared tree is
        // therefore the tree for the committed pair and can be transferred once.
        let parsed = try SaveParser.parse(mainData: target.main, infoData: target.info, catalog: items, recipeCatalog: recipes)
        let snapshot = FarmSnapshotExtractor.extract(from: parsed.mainRoot, cropCatalog: crops)
        let transactions = try transactionsService()
        let result = try transactions.replace(source: source, expectedMainHash: expected.mainHash,
            expectedInfoHash: expected.infoHash, newData: target, reason: reason)
        var warning: String?
        if source.mode == .importedCopy {
            do {
                _ = try localLibrary().register(source, draft: parsed.draft, pair: result.written, saved: true)
                try localLibrary().discardCheckpoint(for: source)
            } catch { warning = "文件已保存，副本索引或草稿清理失败：\(error.localizedDescription)" }
        }
        return LoadedSaveWork(source: source, parsed: parsed, pair: result.written, recovery: .none,
                              snapshot: snapshot, loadTimings: nil, storageWarning: warning)
    }

    func backupPair(_ manifest: BackupManifest) throws -> SavePairData {
        let backups = try backupsService()
        try backups.validate(manifest)
        let data = try backups.data(for: manifest)
        return SavePairData(main: data.main, info: data.info)
    }
    func listBackups() throws -> [BackupManifest] { try backupsService().list() }
    func createManualBackup(source: SaveSource) throws -> BackupManifest {
        let backups = try backupsService()
        let transactions = try transactionsService()
        let pair = try transactions.read(source: source)
        return try backups.create(source: source, mainData: pair.main, infoData: pair.info, reason: "手动保护备份", isProtected: true)
    }
    func verifyBackup(_ manifest: BackupManifest) throws { try backupsService().validate(manifest) }
    func exportBackup(_ manifest: BackupManifest) throws -> [URL] {
        guard !exportCacheInUse else { throw SaveValidationError.invalid("请先完成或取消上一次导出。") }
        try backupsService().cleanExportCache()
        let urls = try backupsService().export(manifest)
        exportCacheInUse = true
        return urls
    }
    func keepCurrentFiles(source: SaveSource) throws { try transactionsService().archiveRecoveryConflict(source: source) }

    func finishBackupExport() throws {
        exportCacheInUse = false
        try backupsService().cleanExportCache()
    }
    func cleanExportCache() throws {
        guard !exportCacheInUse else { throw SaveValidationError.invalid("导出窗口仍在使用临时文件，请先关闭。") }
        try backupsService().cleanExportCache()
    }
    func setBackupProtection(_ manifest: BackupManifest, protected: Bool) throws {
        if !protected { try transactionsService().ensureBackupIsNotRequired(manifest) }
        guard let current = try backupsService().list().first(where: { $0.id == manifest.id }) else { throw BackupStoreError.missingBackup }
        _ = try backupsService().setProtected(current, isProtected: protected)
    }
    func deleteBackup(_ manifest: BackupManifest) throws {
        try transactionsService().ensureBackupIsNotRequired(manifest)
        guard let current = try backupsService().list().first(where: { $0.id == manifest.id }) else { throw BackupStoreError.missingBackup }
        try backupsService().delete(current)
    }
    func localCopies() throws -> [LocalCopyRecord] { try localLibrary().list() }
    func localSource(_ record: LocalCopyRecord) throws -> SaveSource { try localLibrary().source(for: record) }
    func discardFailedImport(_ source: SaveSource) throws { try localLibrary().removeFailedImport(source) }
    func deleteLocalCopy(_ record: LocalCopyRecord, currentIdentity: String?) throws {
        let library = try localLibrary()
        let source: SaveSource
        if record.isFailedImport {
            try SaveSourceResolver.validateFarmIdentifier(record.farmIdentifier)
            let folder = try library.directory(record.id)
            source = SaveSource(mode: .importedCopy, farmIdentifier: record.farmIdentifier,
                mainURL: folder.appendingPathComponent(record.farmIdentifier), infoURL: folder.appendingPathComponent("SaveGameInfo"), accessURLs: [])
        } else { source = try library.source(for: record) }
        guard source.identity != currentIdentity, try !transactionsService().hasPendingTransaction(for: source) else {
            throw SaveValidationError.invalid("当前打开或用于未完成事务的副本不能删除。")
        }
        if record.isFailedImport { try library.removeFailedImport(source) }
        else { try library.remove(record) }
    }
    func persistDraft(source: SaveSource, pair: SavePairData, original: SaveDraft, draft: SaveDraft) throws {
        let library = try localLibrary()
        guard library.owns(source) else { return }
        if SaveDiffBuilder.build(original: original, draft: draft).isEmpty { try library.discardCheckpoint(for: source); return }
        try library.checkpoint(DraftCheckpoint(copyID: library.id(for: source), savedAt: Date(),
            mainHash: pair.mainHash, infoHash: pair.infoHash, original: original, draft: draft))
    }
    func recoveredDraft(source: SaveSource, pair: SavePairData, original: SaveDraft) throws -> SaveDraft? {
        let library = try localLibrary()
        guard library.owns(source), let checkpoint = try library.checkpoint(for: source) else { return nil }
        return try checkpoint.rebased(on: original, pair: pair, copyID: library.id(for: source))
    }
    func discardDraft(source: SaveSource) throws {
        let library = try localLibrary()
        if library.owns(source) { try library.discardCheckpoint(for: source) }
    }
    func markFileExport(source: SaveSource, pair: SavePairData) throws {
        let current = try transactionsService().read(source: source)
        guard current.mainHash == pair.mainHash, current.infoHash == pair.infoHash else {
            throw SaveValidationError.invalid("导出期间副本已变化，仍保留待导出状态。")
        }
        try localLibrary().markExported(source, mainHash: pair.mainHash, infoHash: pair.infoHash, verified: false)
    }
    func prepareExport(source: SaveSource, expected: SavePairData, directory: URL) throws -> VerifiedExportReview {
        let transactions = try transactionsService()
        let pair = try transactions.read(source: source)
        guard pair.mainHash == expected.mainHash, pair.infoHash == expected.infoHash else { throw SaveTransactionError.changedExternally }
        let target = try SaveSourceResolver.directory(directory)
        _ = try transactions.recoverInterruptedTransactionIfNeeded(source: target)
        return try VerifiedExportRules.review(local: source, pair: pair, origin: localLibrary().record(for: source),
            target: target, targetPair: transactions.read(source: target))
    }
    func commitExport(source: SaveSource, review: VerifiedExportReview) throws -> String? {
        guard source.identity == review.localSourceIdentity else {
            throw SaveValidationError.invalid("当前副本与核对时不同，请重新选择导出目标。")
        }
        let transactions = try transactionsService()
        let pair = try transactions.read(source: source)
        guard pair.mainHash == review.localMainHash, pair.infoHash == review.localInfoHash else { throw SaveTransactionError.changedExternally }
        _ = try transactions.replace(source: review.target, expectedMainHash: review.targetMainHash,
            expectedInfoHash: review.targetInfoHash, newData: pair, reason: "导出前的游戏目标存档", keepBackupProtected: true)
        do { try localLibrary().markExported(source, mainHash: pair.mainHash, infoHash: pair.infoHash, verified: true) }
        catch { return "游戏文件已校验写入，但本地导出状态更新失败：\(error.localizedDescription)" }
        return nil
    }
    func keepExportTarget(_ directory: URL) throws {
        try transactionsService().archiveRecoveryConflict(source: SaveSourceResolver.directory(directory))
    }
}
