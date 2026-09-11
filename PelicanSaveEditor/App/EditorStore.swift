import Foundation
import Observation

@Observable @MainActor
final class SaveSession {
    let source: SaveSource
    private(set) var parsed: ParsedSaveDocument
    private(set) var originalDraft: SaveDraft
    private var editableDraft: SaveDraft
    private(set) var isEditingLocked = false
    var draft: SaveDraft {
        get { editableDraft }
        set {
            guard !isEditingLocked else { return }
            editableDraft = newValue
        }
    }
    private(set) var pair: SavePairData
    private(set) var farmSnapshot: FarmSnapshot
    var mainHash: String { pair.mainHash }
    var infoHash: String? { pair.infoHash }

    init(source: SaveSource, parsed: ParsedSaveDocument, pair: SavePairData, snapshot: FarmSnapshot) {
        self.source = source; self.parsed = parsed; self.pair = pair
        farmSnapshot = snapshot
        originalDraft = parsed.draft; editableDraft = parsed.draft
    }
    var metadata: LoadedSaveMetadata {
        LoadedSaveMetadata(farmIdentifier: source.farmIdentifier, gameVersion: parsed.gameVersion,
            playTimeMilliseconds: parsed.playTimeMilliseconds, farmType: parsed.farmType,
            mainEncoding: parsed.mainPayload.encoding, infoEncoding: parsed.infoPayload?.encoding, warnings: parsed.warnings)
    }
    var diffs: [SaveDiff] { SaveDiffBuilder.build(original: originalDraft, draft: draft) }
    var hasChanges: Bool { !diffs.isEmpty }
    func discardChanges() { draft = originalDraft }
    func revert(diff: SaveDiff) {
        guard !isEditingLocked else { return }
        SaveDiffBuilder.undo(diff, original: originalDraft, draft: &editableDraft)
    }
    func setEditingLocked(_ locked: Bool) { isEditingLocked = locked }
    func replaceParsed(_ newParsed: ParsedSaveDocument, pair: SavePairData, snapshot: FarmSnapshot) {
        parsed = newParsed; originalDraft = newParsed.draft; editableDraft = newParsed.draft; self.pair = pair
        farmSnapshot = snapshot
    }
}

@Observable @MainActor
final class EditorStore {
    private(set) var session: SaveSession?
    private(set) var isBusy = false
    var busyMessage = "正在处理存档…"
    var errorMessage: String?
    var successMessage: String?
    var backups: [BackupManifest] = []
    var verifiedBackupIDs: Set<UUID> = []
    var discoveredSaveSources: [SaveSource] = []
    var itemCatalog: [CatalogItem] = []
    var recipeCatalog: [RecipeKind: [String]] = [:]
    var cropCatalog: [CropDefinition] = []
    var catalogWarnings: [String] = []
    var backupWarning: String?
    var recoveryConflictMessage: String?
    private var recoverySource: SaveSource?
    private let worker = SaveWorkService()
    private var loadFollowUpTask: Task<Void, Never>?
    private(set) var lastLoadTimings: SaveLoadTimings?

    init() {
        perform("正在载入离线目录…") {
            let catalogs = await self.worker.initialize()
            self.itemCatalog = catalogs.items; self.recipeCatalog = catalogs.recipes
            self.cropCatalog = catalogs.crops; self.catalogWarnings = catalogs.warnings
            await self.updateBackups()
#if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--ui-demo") {
                let demo = try DebugDemoSave.makeSession(itemCatalog: self.itemCatalog, recipeCatalog: self.recipeCatalog)
                if ProcessInfo.processInfo.arguments.contains("--ui-demo-edits") {
                    demo.draft.farmActions.waterAllCrops = true
                    demo.draft.farmActions.clearStones = true
                    demo.draft.farmhouse.upgradeLevel = 3
                }
                self.session = demo
            }
#endif
        }
    }

    var hasRecentSource: Bool { RecentSaveSourceStore.hasRecentSource }
    func openDirectory(_ url: URL) {
        perform("正在查找农场…") {
            let sources = try await self.worker.discover(url)
            if sources.count == 1, let source = sources.first { try await self.load(source: source, remember: true) }
            else { self.discoveredSaveSources = sources }
        }
    }
    func openDiscoveredSave(_ source: SaveSource) {
        guard !isBusy, discoveredSaveSources.contains(where: { $0.mainURL == source.mainURL }) else { return }
        discoveredSaveSources = []
        perform("正在读取存档…") { try await self.load(source: source, remember: true) }
    }
    func dismissDiscoveredSaves() { if !isBusy { discoveredSaveSources = [] } }
    func openFiles(_ urls: [URL]) { openFiles(urls, copying: false) }
    func openCopiedFiles(_ urls: [URL]) { openFiles(urls, copying: true) }
    private func openFiles(_ urls: [URL], copying: Bool) {
        perform(copying ? "正在复制导入存档…" : "正在读取存档…") {
            let source = try await self.worker.resolveFiles(urls, copying: copying)
            try await self.load(source: source, remember: true)
        }
    }
    func openRecent() {
        perform("正在打开上次农场…") {
            let source = try await self.worker.recent()
            try await self.load(source: source, remember: false)
        }
    }
    func reload() {
        guard let source = session?.source else { return }
        perform("正在重新读取存档…") { try await self.load(source: source, remember: false) }
    }
    func closeSession(discardingChanges: Bool = false) {
        guard !isBusy, session?.hasChanges != true || discardingChanges else { return }
        session = nil; refreshBackups()
    }

    func save(showSuccess: Bool = true, completion: (@MainActor (Bool) -> Void)? = nil) {
        guard !isBusy else { completion?(false); return }
        guard let session else { completion?(false); return }
        guard session.hasChanges else { completion?(true); return }
        let draft = session.draft
        let originalDraft = session.originalDraft
        let original = session.pair
        perform("正在检查更改…", completion: completion) {
            let target = try await self.worker.render(original: original, originalDraft: originalDraft, draft: draft, items: self.itemCatalog, recipes: self.recipeCatalog)
            guard self.session === session else {
                throw SaveValidationError.invalid("当前农场已切换，本次写回已取消。")
            }
            self.busyMessage = "正在备份、写入并校验存档…"
            let written = try await self.worker.write(source: session.source, expected: original, target: target,
                reason: "保存前自动备份", items: self.itemCatalog, recipes: self.recipeCatalog, crops: self.cropCatalog)
            session.replaceParsed(written.parsed, pair: written.pair, snapshot: written.snapshot)
            if showSuccess {
                self.successMessage = session.source.mode == .importedCopy
                    ? "副本已保存并校验。请导出两份文件到游戏农场目录。"
                    : "保存成功，原始状态已自动备份并完成写后校验。"
            }
            await self.updateBackups()
        }
    }
    func restore(_ backup: BackupManifest) {
        guard let session else { return }
        perform("正在校验备份…") {
            guard backup.farmIdentifier == session.source.farmIdentifier else {
                throw SaveValidationError.invalid("该备份属于另一个农场，请使用导出备份功能。")
            }
            let pair = try await self.worker.backupPair(backup)
            guard self.session === session else {
                throw SaveValidationError.invalid("当前农场已切换，本次恢复已取消。")
            }
            self.busyMessage = "正在备份当前文件并恢复…"
            let result = try await self.worker.write(source: session.source, expected: session.pair, target: pair,
                reason: "恢复备份前的当前状态", items: self.itemCatalog, recipes: self.recipeCatalog, crops: self.cropCatalog)
            session.replaceParsed(result.parsed, pair: result.pair, snapshot: result.snapshot)
            self.verifiedBackupIDs.insert(backup.id)
            self.successMessage = session.source.mode == .importedCopy
                ? "备份已恢复到应用副本；如需用于游戏，请导出两份文件。"
                : "备份已恢复；恢复前的状态也已另行备份。"
            await self.updateBackups()
        }
    }
    func createManualBackup() {
        guard let source = session?.source else { return }
        perform("正在创建保护备份…") {
            _ = try await self.worker.createManualBackup(source: source)
            self.successMessage = "已备份磁盘存档并设为保护备份。未保存的草稿不包含在内。"
            await self.updateBackups()
        }
    }
    func verifyBackup(_ backup: BackupManifest, completion: (@MainActor (Bool, String) -> Void)? = nil) {
        perform("正在校验备份…", completion: { success in
            completion?(success, success ? "备份完整且可以解析" : self.errorMessage ?? "校验失败")
        }) {
            try await self.worker.verifyBackup(backup)
            self.verifiedBackupIDs.insert(backup.id)
            if completion == nil { self.successMessage = "备份完整性及存档结构校验通过。" }
        }
    }
    func exportBackup(_ backup: BackupManifest, completion: @escaping @MainActor ([URL]?) -> Void) {
        var urls: [URL]?
        perform("正在校验并准备导出备份…", completion: { success in completion(success ? urls : nil) }) {
            urls = try await self.worker.exportBackup(backup)
            self.verifiedBackupIDs.insert(backup.id)
        }
    }
    func keepCurrentFilesAfterConflict() {
        guard !isBusy, let source = recoverySource else { return }
        recoveryConflictMessage = nil
        perform("正在保留当前文件并结束旧事务…") {
            try await self.worker.keepCurrentFiles(source: source)
            try await self.load(source: source, remember: true)
        }
    }
    func dismissRecoveryConflict() { recoveryConflictMessage = nil; recoverySource = nil }
    func clearMessages() { errorMessage = nil; successMessage = nil }

    private func load(source: SaveSource, remember: Bool) async throws {
        loadFollowUpTask?.cancel()
        let result: LoadedSaveWork
        do {
            result = try await worker.load(source: source, items: itemCatalog, recipes: recipeCatalog,
                                          crops: cropCatalog) { [weak self] stage in
                self?.busyMessage = stage
            }
        }
        catch SaveTransactionError.recoveryConflict(let message) {
            recoverySource = source; recoveryConflictMessage = message
            await updateBackups(); return
        }
        // Failed or cancelled selections leave the current session and draft intact.
        let loadedSession = SaveSession(source: source, parsed: result.parsed, pair: result.pair, snapshot: result.snapshot)
        lastLoadTimings = result.loadTimings
        loadedSession.setEditingLocked(isBusy)
        session = loadedSession
        recoverySource = nil
        recoveryConflictMessage = nil
        switch result.recovery {
        case .completedSaveConfirmed: successMessage = "上次保存的两份文件已完整写入并通过校验。"
        case .originalFilesConfirmed: successMessage = "原始文件完整，上次未开始的写回事务已清理。"
        case .restoredFromBackup: successMessage = "上次写入中断，已恢复两份原始文件。"
        case .none:
            if source.mode == .importedCopy { successMessage = "已复制导入。保存后可导出副本用于游戏。" }
        }
        // The farm is usable now. File-provider bookmarks and the backup index
        // are housekeeping, and must not extend the modal loading lock.
        loadFollowUpTask = Task { @MainActor [weak self, weak loadedSession] in
            guard let self, let loadedSession, !Task.isCancelled,
                  self.session === loadedSession else { return }
            if remember {
                do { try await self.worker.remember(source) }
                catch {
                    if !Task.isCancelled, self.session === loadedSession, !self.isBusy {
                        self.successMessage = "存档已打开，本次文件授权无法保存为最近访问。"
                    }
                }
            }
            guard !Task.isCancelled, self.session === loadedSession else { return }
            await self.updateBackups()
        }
    }
    func refreshBackups() {
        perform("正在读取备份列表…") { await self.updateBackups(reportFailure: true) }
    }
    private func updateBackups(reportFailure: Bool = false) async {
        do {
            backups = try await worker.listBackups()
            backupWarning = nil
        } catch {
            let message = "无法读取备份列表：\(error.localizedDescription)"
            backupWarning = message
            // A background list refresh cannot turn an already committed save
            // into an apparent save failure or interfere with an export sheet.
            if reportFailure { errorMessage = message }
        }
    }
    private func perform(_ message: String, completion: (@MainActor (Bool) -> Void)? = nil,
                         operation: @escaping @MainActor () async throws -> Void) {
        guard !isBusy else { completion?(false); return }
        isBusy = true; busyMessage = message; clearMessages()
        let initialSession = session
        initialSession?.setEditingLocked(true)
        Task { @MainActor in
            let succeeded: Bool
            do { try await operation(); succeeded = true }
            catch { errorMessage = error.localizedDescription; succeeded = false }
            initialSession?.setEditingLocked(false)
            session?.setEditingLocked(false)
            isBusy = false
            // Callbacks can dismiss the editor, open another source, or start a
            // second operation only after the snapshot has been installed.
            completion?(succeeded)
        }
    }
}
