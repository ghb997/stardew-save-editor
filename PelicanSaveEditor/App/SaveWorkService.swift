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

    init(backupRootURL: URL? = nil, transactionDirectoryURL: URL? = nil) {
        self.backupRootURL = backupRootURL
        self.transactionDirectoryURL = transactionDirectoryURL
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
        return result
    }

    func discover(_ url: URL) throws -> [SaveSource] { try SaveSourceResolver.discoverDirectories(in: url) }
    func resolveFiles(_ urls: [URL], copying: Bool) throws -> SaveSource {
        if copying { return try SaveSourceResolver.copiedFiles(urls) }
        return try SaveSourceResolver.files(urls)
    }
    func recent() throws -> SaveSource { try RecentSaveSourceStore.load() }
    func remember(_ source: SaveSource) throws { try RecentSaveSourceStore.save(source) }

    func load(source: SaveSource, items: [CatalogItem], recipes: [RecipeKind: [String]],
              crops: [CropDefinition] = [],
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
        _ = try SaveParser.parse(mainData: rendered.mainData, infoData: rendered.infoData, catalog: items, recipeCatalog: recipes)
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
        return LoadedSaveWork(source: source, parsed: parsed, pair: result.written, recovery: .none,
                              snapshot: snapshot, loadTimings: nil)
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
    func exportBackup(_ manifest: BackupManifest) throws -> [URL] { try backupsService().export(manifest) }
    func keepCurrentFiles(source: SaveSource) throws { try transactionsService().archiveRecoveryConflict(source: source) }
}
