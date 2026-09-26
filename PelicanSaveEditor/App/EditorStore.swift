import Foundation
import Observation
import UIKit

@Observable @MainActor
final class SaveSession {
    let source: SaveSource
    private(set) var parsed: ParsedSaveDocument
    private(set) var originalDraft: SaveDraft
    private var editableDraft: SaveDraft
    @ObservationIgnored var didChangeDraft: ((SaveDraft) -> Void)?
    private(set) var isEditingLocked = false
    var draft: SaveDraft {
        get { editableDraft }
        set {
            guard !isEditingLocked else { return }
            editableDraft = newValue
            didChangeDraft?(newValue)
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
        didChangeDraft?(editableDraft)
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
    private let worker: SaveWorkService
    private var loadFollowUpTask: Task<Void, Never>?
    private(set) var lastLoadTimings: SaveLoadTimings?
    var localCopies: [LocalCopyRecord] = []
    var libraryWarning: String?
    var draftStorageMessage: String?
    var draftRecoveryMessage: String?
    private var recoveredDraft: SaveDraft?
    var canRecoverDraft: Bool { recoveredDraft != nil }
    private var draftWriteTask: Task<Void, Never>?
    private var draftRevision = 0
    private var draftWriteError: String?
    var exportRecoveryDirectory: URL?

    init(worker: SaveWorkService? = nil) {
#if DEBUG
        self.worker = worker ?? DebugPersistenceFixture.worker ?? SaveWorkService()
#else
        self.worker = worker ?? SaveWorkService()
#endif
        perform("正在载入离线目录…") {
            let catalogs = await self.worker.initialize()
            self.itemCatalog = catalogs.items; self.recipeCatalog = catalogs.recipes
            self.cropCatalog = catalogs.crops; self.catalogWarnings = catalogs.warnings
            await self.updateBackups()
            await self.updateLocalCopies()
#if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--ui-library-seed"), self.localCopies.isEmpty {
                let source = try await self.worker.resolveFiles(DebugPersistenceFixture.seedURLs(), copying: true)
                try await self.load(source: source, remember: false, imported: true)
                self.clearMessages()
            }
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
            await self.flushDraft()
            let source = try await self.worker.resolveFiles(urls, copying: copying)
            do { try await self.load(source: source, remember: true, imported: copying) }
            catch {
                if copying { try? await self.worker.discardFailedImport(source) }
                throw error
            }
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
        perform("正在重新读取存档…") {
            await self.flushDraft()
            try await self.worker.discardDraft(source: source)
            try await self.load(source: source, remember: false, preservingDraft: false)
        }
    }
    func closeSession(discardingChanges: Bool = false) {
        guard !isBusy, let session else { return }
        perform("正在关闭副本…") {
            if discardingChanges { await self.flushDraft() }
            else { try await self.preserveCurrentDraft() }
            if discardingChanges { try await self.worker.discardDraft(source: session.source) }
            self.session = nil
            self.draftRecoveryMessage = nil; self.recoveredDraft = nil; self.draftStorageMessage = nil
            await self.updateBackups(); await self.updateLocalCopies()
        }
    }

    func save(showSuccess: Bool = true, completion: (@MainActor (Bool) -> Void)? = nil) {
        guard !isBusy else { completion?(false); return }
        guard let session else { completion?(false); return }
        guard session.hasChanges else { completion?(true); return }
        let draft = session.draft
        let originalDraft = session.originalDraft
        let original = session.pair
        perform("正在检查更改…", completion: completion) {
            await self.flushDraft()
            let target = try await self.worker.render(original: original, originalDraft: originalDraft, draft: draft, items: self.itemCatalog, recipes: self.recipeCatalog)
            guard self.session === session else {
                throw SaveValidationError.invalid("当前农场已切换，本次写回已取消。")
            }
            self.busyMessage = "正在备份、写入并校验存档…"
            let written = try await self.worker.write(source: session.source, expected: original, target: target,
                reason: "保存前自动备份", items: self.itemCatalog, recipes: self.recipeCatalog, crops: self.cropCatalog)
            session.replaceParsed(written.parsed, pair: written.pair, snapshot: written.snapshot)
            self.libraryWarning = written.storageWarning
            self.draftStorageMessage = nil
            self.draftWriteError = nil
            if showSuccess {
                self.successMessage = session.source.mode == .importedCopy
                    ? "副本已保存并校验。请导出两份文件到游戏农场目录。"
                    : "保存成功，原始状态已自动备份并完成写后校验。"
            }
            await self.updateBackups()
            await self.updateLocalCopies()
        }
    }
    func restore(_ backup: BackupManifest) {
        guard let session else { return }
        perform("正在校验备份…") {
            await self.flushDraft()
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
            self.libraryWarning = result.storageWarning
            self.draftStorageMessage = nil
            self.verifiedBackupIDs.insert(backup.id)
            self.successMessage = session.source.mode == .importedCopy
                ? "备份已恢复到应用副本；如需用于游戏，请导出两份文件。"
                : "备份已恢复；恢复前的状态也已另行备份。"
            await self.updateBackups()
            await self.updateLocalCopies()
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

    private func load(source: SaveSource, remember: Bool, imported: Bool = false, preservingDraft: Bool = true) async throws {
        if preservingDraft { try await preserveCurrentDraft() }
        else { await flushDraft() }
        loadFollowUpTask?.cancel()
        let result: LoadedSaveWork
        do {
            result = try await worker.load(source: source, items: itemCatalog, recipes: recipeCatalog,
                                          crops: cropCatalog, imported: imported) { [weak self] stage in
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
        draftStorageMessage = nil
        draftWriteError = nil
        recoveredDraft = nil; draftRecoveryMessage = nil
        do {
            recoveredDraft = try await worker.recoveredDraft(source: source, pair: result.pair, original: result.parsed.draft)
            if recoveredDraft != nil { draftRecoveryMessage = "找到这份副本的未保存草稿。已核对原文件，是否继续上次修改？" }
        } catch { draftRecoveryMessage = error.localizedDescription }
        loadedSession.didChangeDraft = { [weak self, weak loadedSession] draft in
            guard let self, let loadedSession else { return }
            self.scheduleDraft(draft, session: loadedSession)
        }
        recoverySource = nil
        recoveryConflictMessage = nil
        switch result.recovery {
        case .completedSaveConfirmed: successMessage = "上次保存的两份文件已完整写入并通过校验。"
        case .originalFilesConfirmed: successMessage = "原始文件完整，上次未开始的写回事务已清理。"
        case .restoredFromBackup: successMessage = "上次写入中断，已恢复两份原始文件。"
        case .none:
            if source.mode == .importedCopy {
                successMessage = imported ? "已复制导入。保存后可导出副本用于游戏。" : "已打开本地副本，可继续编辑或导出。"
            }
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
            await self.updateLocalCopies()
        }
    }

    private func scheduleDraft(_ draft: SaveDraft, session: SaveSession) {
        guard session.source.mode == .importedCopy else { return }
        draftRevision += 1
        let revision = draftRevision
        let previous = draftWriteTask
        let source = session.source, pair = session.pair, original = session.originalDraft
        draftStorageMessage = "正在暂存草稿…"
        draftWriteTask = Task { [weak self] in
            await previous?.value
            guard let self else { return }
            do {
                try await self.worker.persistDraft(source: source, pair: pair, original: original, draft: draft)
                if self.draftRevision == revision, self.session === session {
                    self.draftWriteError = nil
                    self.draftStorageMessage = SaveDiffBuilder.build(original: original, draft: draft).isEmpty ? nil : "草稿已暂存，可在重启后恢复"
                }
            } catch {
                if self.draftRevision == revision, self.session === session {
                    self.draftWriteError = error.localizedDescription
                    self.draftStorageMessage = "草稿暂存失败：\(error.localizedDescription)"
                }
            }
        }
    }
    func flushDraft() async { await draftWriteTask?.value }
    private func preserveCurrentDraft() async throws {
        await flushDraft()
        if session?.source.mode == .importedCopy, session?.hasChanges == true, let draftWriteError {
            throw SaveValidationError.invalid("草稿尚未安全暂存，已保留当前编辑。请先保存或明确放弃草稿，再关闭或切换副本。\(draftWriteError)")
        }
    }
    func flushDraftWhenBackgrounding() {
        let token = UIApplication.shared.beginBackgroundTask(withName: "Persist edit draft")
        Task {
            await flushDraft()
            if token != .invalid { UIApplication.shared.endBackgroundTask(token) }
        }
    }
    func restoreRecoveredDraft() {
        guard let recoveredDraft, let session else { return }
        draftRecoveryMessage = nil; self.recoveredDraft = nil
        session.setEditingLocked(false)
        session.draft = recoveredDraft
        successMessage = "已恢复上次草稿，可继续修改或检查保存。"
    }
    func discardRecoveredDraft() {
        guard let source = session?.source else { return }
        perform("正在放弃恢复草稿…") {
            try await self.worker.discardDraft(source: source)
            self.draftRecoveryMessage = nil; self.recoveredDraft = nil
            await self.updateLocalCopies()
        }
    }
    func closeUnresolvedDraft() {
        draftRecoveryMessage = nil; recoveredDraft = nil
        session = nil; clearMessages()
    }
    func openLocalCopy(_ record: LocalCopyRecord) {
        perform("正在打开本地副本…") {
            let source = try await self.worker.localSource(record)
            try await self.load(source: source, remember: true)
        }
    }
    func refreshLocalCopies() {
        perform("正在读取本地副本…") { await self.updateLocalCopies() }
    }
    private func updateLocalCopies() async {
        do { localCopies = try await worker.localCopies() }
        catch { libraryWarning = "无法读取本地副本：\(error.localizedDescription)" }
    }
    func deleteLocalCopy(_ record: LocalCopyRecord) {
        let current = session?.source.identity
        perform("正在删除本地副本…") {
            await self.flushDraft()
            try await self.worker.deleteLocalCopy(record, currentIdentity: current)
            await self.updateLocalCopies()
        }
    }
    func finishBackupExport() {
        Task {
            do { try await worker.finishBackupExport() }
            catch { libraryWarning = "临时导出文件清理失败：\(error.localizedDescription)" }
        }
    }
    func cleanExportCache() {
        perform("正在清理导出缓存…") {
            try await self.worker.cleanExportCache()
            self.successMessage = "已清理可重新生成的导出缓存。"
        }
    }
    func setBackupProtection(_ manifest: BackupManifest, protected: Bool) {
        perform("正在更新备份保护…") {
            try await self.worker.setBackupProtection(manifest, protected: protected)
            await self.updateBackups()
        }
    }
    func deleteBackup(_ manifest: BackupManifest) {
        perform("正在删除备份…") {
            try await self.worker.deleteBackup(manifest)
            self.verifiedBackupIDs.remove(manifest.id)
            await self.updateBackups()
        }
    }
    func prepareExport(directory: URL, completion: @escaping @MainActor (VerifiedExportReview?) -> Void) {
        guard let session, !session.hasChanges else { completion(nil); return }
        var review: VerifiedExportReview?
        exportRecoveryDirectory = nil
        perform("正在核对游戏目标…", completion: { success in completion(success ? review : nil) }) {
            do { review = try await self.worker.prepareExport(source: session.source, expected: session.pair, directory: directory) }
            catch SaveTransactionError.recoveryConflict(let message) {
                self.exportRecoveryDirectory = directory
                throw SaveTransactionError.recoveryConflict(message)
            }
            await self.updateBackups()
        }
    }
    func keepExportTarget(completion: @escaping @MainActor (VerifiedExportReview?) -> Void) {
        guard let directory = exportRecoveryDirectory else { completion(nil); return }
        perform("正在保留目标当前文件…", completion: { success in
            if success { self.prepareExport(directory: directory, completion: completion) } else { completion(nil) }
        }) { try await self.worker.keepExportTarget(directory) }
    }
    func commitExport(_ review: VerifiedExportReview, completion: @escaping @MainActor (Bool) -> Void) {
        guard let session, !session.hasChanges else { completion(false); return }
        perform("正在备份游戏目标、写入并校验…", completion: completion) {
            self.libraryWarning = try await self.worker.commitExport(source: session.source, review: review)
            await self.updateBackups(); await self.updateLocalCopies()
        }
    }
    func recordFileExport() {
        guard let session else { return }
        perform("正在记录导出状态…") {
            try await self.worker.markFileExport(source: session.source, pair: session.pair)
            await self.updateLocalCopies()
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
            session?.setEditingLocked(draftRecoveryMessage != nil)
            isBusy = false
            // Callbacks can dismiss the editor, open another source, or start a
            // second operation only after the snapshot has been installed.
            completion?(succeeded)
        }
    }
}
