import Foundation

struct LocalCopyRecord: Codable, Identifiable, Sendable {
    let id: String
    let farmIdentifier: String
    var playerName: String
    var farmName: String
    let importedAt: Date
    var lastOpenedAt: Date
    var savedAt: Date
    var gameDate: String
    var savedMainHash: String
    var savedInfoHash: String?
    // Nil on legacy copies: never guess which game revision they came from.
    var originMainHash: String?
    var originInfoHash: String?
    var needsExport: Bool
    var lastExportAt: Date?
    var verifiedGameExport = false
    var byteCount: Int64 = 0
    var hasDraft = false
    var problem: String? = nil
    var isFailedImport = false

    var status: String {
        if problem != nil { return "副本无法读取，请保留并检查" }
        if hasDraft { return "有可恢复草稿" }
        if needsExport { return "已保存，待导出" }
        if lastExportAt != nil { return verifiedGameExport ? "已校验写入游戏目录" : "已导出文件，游戏目标未校验" }
        return "已导入副本"
    }
}

struct DraftCheckpoint: Codable, Sendable {
    var schemaVersion = 1
    let copyID: String
    let savedAt: Date
    let mainHash: String
    let infoHash: String?
    let original: SaveDraft
    let draft: SaveDraft

    func rebased(on current: SaveDraft, pair: SavePairData, copyID: String) throws -> SaveDraft {
        guard schemaVersion == 1, self.copyID == copyID,
              mainHash == pair.mainHash, infoHash == pair.infoHash else {
            throw SaveValidationError.invalid("草稿对应的存档已变化，已保留草稿且没有自动套用。")
        }
        // Parsing gives items fresh UUIDs. Rebind existing identities only when
        // the entire immutable baseline (including opaque templates) still matches.
        var baseline = original
        var recovered = draft
        var identities: [UUID: UUID] = [:]
        func align(_ old: inout [InventorySlotDraft], _ fresh: [InventorySlotDraft]) throws {
            guard old.count == fresh.count else { throw SaveValidationError.invalid("草稿物品范围已变化。") }
            for index in old.indices {
                if let previous = old[index].item, let actual = fresh[index].item {
                    identities[previous.id] = actual.id
                    old[index].item?.id = actual.id
                }
            }
        }
        try align(&baseline.inventory, current.inventory)
        guard baseline.storages.count == current.storages.count else {
            throw SaveValidationError.invalid("草稿容器范围已变化。")
        }
        for index in baseline.storages.indices { try align(&baseline.storages[index].slots, current.storages[index].slots) }
        guard baseline == current else {
            throw SaveValidationError.invalid("草稿版本或目录数据已变化，无法自动恢复；已保留原记录。")
        }
        func rebind(_ slots: inout [InventorySlotDraft]) {
            for index in slots.indices {
                if let id = slots[index].item?.id, let rebound = identities[id] { slots[index].item?.id = rebound }
            }
        }
        rebind(&recovered.inventory)
        for index in recovered.storages.indices { rebind(&recovered.storages[index].slots) }
        return recovered
    }
}

/// All mutation goes through SaveWorkService's serial actor. The directory ID,
/// rather than an absolute sandbox URL, survives application container moves.
final class LocalSaveLibrary {
    let root: URL
    private let manager = FileManager.default

    init(root: URL? = nil) throws {
        self.root = try root ?? FileManager.default.url(for: .applicationSupportDirectory,
            in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("PelicanSaveEditor/ImportedSaves", isDirectory: true)
        try manager.createDirectory(at: self.root, withIntermediateDirectories: true)
    }

    func directory(_ id: String) throws -> URL {
        guard !id.isEmpty, id != ".", id != "..", !id.contains("/"), !id.contains("\\") else {
            throw SaveValidationError.invalid("副本标识无效。")
        }
        let candidate = root.appendingPathComponent(id, isDirectory: true).standardizedFileURL
        guard candidate.deletingLastPathComponent() == root.standardizedFileURL,
              candidate.resolvingSymlinksInPath().deletingLastPathComponent() == root.resolvingSymlinksInPath() else {
            throw SaveValidationError.invalid("副本目录超出应用存储范围。")
        }
        return candidate
    }

    func id(for source: SaveSource) throws -> String {
        let folder = source.mainURL.deletingLastPathComponent()
        let id = folder.lastPathComponent
        guard source.mode == .importedCopy, try directory(id) == folder.standardizedFileURL else {
            throw SaveValidationError.invalid("只能管理应用内副本。")
        }
        return id
    }

    func owns(_ source: SaveSource) -> Bool { (try? id(for: source)) != nil }

    func source(for record: LocalCopyRecord) throws -> SaveSource {
        let folder = try directory(record.id)
        try SaveSourceResolver.validateFarmIdentifier(record.farmIdentifier)
        let urls = [folder.appendingPathComponent(record.farmIdentifier), folder.appendingPathComponent("SaveGameInfo")]
        guard try urls.allSatisfy({ try $0.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true }) else {
            throw SaveValidationError.invalid("副本文件不能是符号链接。")
        }
        return try SaveSourceResolver.importedFiles(urls)
    }

    func record(for source: SaveSource) throws -> LocalCopyRecord {
        try readRecord(id(for: source))
    }

    func register(_ source: SaveSource, draft: SaveDraft, pair: SavePairData,
                  imported: Bool = false, saved: Bool = false) throws -> LocalCopyRecord {
        let id = try id(for: source)
        let now = Date()
        var record = (try? readRecord(id)) ?? LocalCopyRecord(id: id, farmIdentifier: source.farmIdentifier,
            playerName: draft.playerName, farmName: draft.farmName,
            importedAt: now, lastOpenedAt: now, savedAt: now, gameDate: "",
            savedMainHash: pair.mainHash, savedInfoHash: pair.infoHash,
            originMainHash: imported ? pair.mainHash : nil, originInfoHash: imported ? pair.infoHash : nil,
            needsExport: !imported)
        if saved || record.savedMainHash != pair.mainHash || record.savedInfoHash != pair.infoHash {
            record.needsExport = true; record.savedAt = now; record.verifiedGameExport = false
        }
        record.playerName = draft.playerName; record.farmName = draft.farmName
        record.gameDate = "第 \(draft.year) 年 · \(draft.season.displayName)季 \(draft.day) 日"
        record.lastOpenedAt = now
        record.savedMainHash = pair.mainHash; record.savedInfoHash = pair.infoHash
        record.byteCount = Int64(pair.main.count + (pair.info?.count ?? 0))
        try write(record)
        return record
    }

    func list() throws -> [LocalCopyRecord] {
        var records: [LocalCopyRecord] = []
        for folder in try manager.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) {
            guard (try? directory(folder.lastPathComponent)) != nil,
                  (try? folder.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { continue }
            var record = try? readRecord(folder.lastPathComponent)
            if record == nil {
                // Adopt copies made by older releases, including saved-but-not-exported copies.
                let files = (try? manager.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
                if let main = files.first(where: { (try? SaveSourceResolver.validateFarmIdentifier($0.lastPathComponent)) != nil }),
                   let source = try? SaveSourceResolver.importedFiles([main, folder.appendingPathComponent("SaveGameInfo")]),
                   let pair = try? readPair(source),
                   let parsed = try? SaveParser.parse(mainData: pair.main, infoData: pair.info, catalog: [], recipeCatalog: [:]) {
                    record = try register(source, draft: parsed.draft, pair: pair)
                }
            }
            if record == nil {
                let id = folder.lastPathComponent
                // Only folders in the importer's documented naming scheme are managed.
                guard id.count > 37, UUID(uuidString: String(id.suffix(36))) != nil else { continue }
                let farm = String(id.dropLast(37))
                guard (try? SaveSourceResolver.validateFarmIdentifier(farm)) != nil else { continue }
                let created = (try? folder.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date.distantPast
                record = LocalCopyRecord(id: id, farmIdentifier: farm, playerName: "未知人物", farmName: farm,
                    importedAt: created, lastOpenedAt: created, savedAt: created, gameDate: "无法读取日期",
                    savedMainHash: "", savedInfoHash: nil, originMainHash: nil, originInfoHash: nil, needsExport: true)
                record?.problem = "文件缺失或内容无效，未自动清理。"
                record?.isFailedImport = !manager.fileExists(atPath: folder.appendingPathComponent("copy.json").path)
            }
            guard var record else { continue }
            if (try? source(for: record)) == nil { record.problem = "存档文件缺失或无法读取。" }
            record.hasDraft = manager.fileExists(atPath: folder.appendingPathComponent("draft.json").path)
            record.byteCount = try manager.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey])
                .reduce(Int64(0)) { total, url in
                    let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
                    return total + (values.isRegularFile == true ? Int64(values.fileSize ?? 0) : 0)
                }
            records.append(record)
        }
        return records.sorted { $0.lastOpenedAt > $1.lastOpenedAt }
    }

    func checkpoint(_ value: DraftCheckpoint) throws {
        let folder = try directory(value.copyID)
        guard manager.fileExists(atPath: folder.appendingPathComponent("copy.json").path) else {
            throw SaveValidationError.invalid("副本目录不存在，草稿未暂存。")
        }
        let encoder = JSONEncoder()
        encoder.nonConformingFloatEncodingStrategy = .convertToString(positiveInfinity: "+Infinity", negativeInfinity: "-Infinity", nan: "NaN")
        try encoder.encode(value).write(to: folder.appendingPathComponent("draft.json"), options: .atomic)
    }

    func checkpoint(for source: SaveSource) throws -> DraftCheckpoint? {
        let url = try directory(id(for: source)).appendingPathComponent("draft.json")
        guard manager.fileExists(atPath: url.path) else { return nil }
        let decoder = JSONDecoder()
        decoder.nonConformingFloatDecodingStrategy = .convertFromString(positiveInfinity: "+Infinity", negativeInfinity: "-Infinity", nan: "NaN")
        return try decoder.decode(DraftCheckpoint.self, from: Data(contentsOf: url))
    }

    func discardCheckpoint(for source: SaveSource) throws {
        let url = try directory(id(for: source)).appendingPathComponent("draft.json")
        if manager.fileExists(atPath: url.path) { try manager.removeItem(at: url) }
    }

    func markExported(_ source: SaveSource, mainHash: String, infoHash: String?, verified: Bool) throws {
        var record = try record(for: source)
        guard record.savedMainHash == mainHash, record.savedInfoHash == infoHash else {
            throw SaveValidationError.invalid("导出期间副本已变化，仍保留待导出状态。")
        }
        record.needsExport = false; record.lastExportAt = Date(); record.verifiedGameExport = verified
        // The next verified write should compare against what we last put in the game.
        if verified { record.originMainHash = mainHash; record.originInfoHash = infoHash }
        try write(record)
    }

    func remove(_ record: LocalCopyRecord) throws {
        let folder = try directory(record.id)
        let current = try readRecord(record.id)
        guard current.farmIdentifier == record.farmIdentifier, !current.needsExport,
              !manager.fileExists(atPath: folder.appendingPathComponent("draft.json").path) else {
            throw SaveValidationError.invalid("待导出副本或含草稿的副本受保护，请先导出或处理草稿。")
        }
        let pair = try readPair(source(for: current))
        guard pair.mainHash == current.savedMainHash, pair.infoHash == current.savedInfoHash else {
            throw SaveValidationError.invalid("副本文件已变化，请先打开并核对内容，再决定是否删除。")
        }
        try manager.removeItem(at: folder)
    }

    func removeFailedImport(_ source: SaveSource) throws {
        let folder = try directory(id(for: source))
        guard !manager.fileExists(atPath: folder.appendingPathComponent("copy.json").path),
              !manager.fileExists(atPath: folder.appendingPathComponent("draft.json").path) else { return }
        try manager.removeItem(at: folder)
    }

    private func readRecord(_ id: String) throws -> LocalCopyRecord {
        let record = try JSONDecoder().decode(LocalCopyRecord.self, from: Data(contentsOf: directory(id).appendingPathComponent("copy.json")))
        guard record.id == id else { throw SaveValidationError.invalid("副本索引不匹配。") }
        return record
    }
    private func write(_ record: LocalCopyRecord) throws {
        try JSONEncoder().encode(record).write(to: directory(record.id).appendingPathComponent("copy.json"), options: .atomic)
    }
    private func readPair(_ source: SaveSource) throws -> SavePairData {
        SavePairData(main: try Data(contentsOf: source.mainURL), info: try source.infoURL.map { try Data(contentsOf: $0) })
    }
}
