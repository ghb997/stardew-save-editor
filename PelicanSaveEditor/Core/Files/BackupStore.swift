import Foundation

struct BackupManifest: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let farmIdentifier: String
    let savedAt: Date
    let mainOriginalName: String
    let infoOriginalName: String?
    let reason: String
    /// Optional for backward compatibility with backups created before hashes
    /// were added to the manifest.
    let mainHash: String?
    let infoHash: String?
    var sourceIdentity: String? = nil
    var sourceMode: SaveAccessMode? = nil
    var sourceLocation: String? = nil
    var isProtected: Bool? = nil
}

enum BackupStoreError: LocalizedError {
    case missingBackup
    case invalidManifest
    case corruptBackup(String)

    var errorDescription: String? {
        switch self {
        case .missingBackup: "找不到所选备份文件。"
        case .invalidManifest: "备份清单无效。"
        case let .corruptBackup(name): "备份文件 \(name) 的完整性校验失败，已取消恢复。"
        }
    }
}

final class BackupStore {
    private let fileManager: FileManager
    private let rootURL: URL

    init(fileManager: FileManager = .default, rootURL customRootURL: URL? = nil) throws {
        self.fileManager = fileManager
        if let customRootURL {
            rootURL = customRootURL
        } else {
            let applicationSupport = try fileManager.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            rootURL = applicationSupport
                .appendingPathComponent("PelicanSaveEditor", isDirectory: true)
                .appendingPathComponent("Backups", isDirectory: true)
        }
        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
    }

    @discardableResult
    func create(
        source: SaveSource,
        mainData: Data,
        infoData: Data?,
        reason: String,
        isProtected: Bool = false
    ) throws -> BackupManifest {
        let pair = SavePairData(main: mainData, info: infoData)
        let manifest = BackupManifest(
            id: UUID(),
            farmIdentifier: source.farmIdentifier,
            savedAt: Date(),
            mainOriginalName: source.mainURL.lastPathComponent,
            infoOriginalName: source.infoURL?.lastPathComponent,
            reason: reason,
            mainHash: pair.mainHash,
            infoHash: pair.infoHash,
            sourceIdentity: source.identity,
            sourceMode: source.mode,
            sourceLocation: source.mainURL.deletingLastPathComponent().lastPathComponent,
            isProtected: isProtected
        )
        let directory = backupURL(manifest)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        do {
            try mainData.write(to: directory.appendingPathComponent("MainSave"), options: .atomic)
            if let infoData {
                try infoData.write(to: directory.appendingPathComponent("SaveGameInfo"), options: .atomic)
            }
            try writeManifest(manifest)
            // Read every byte back before allowing the caller to modify its source.
            _ = try data(for: manifest)
        } catch {
            try? fileManager.removeItem(at: directory)
            throw error
        }
        try prune(farmIdentifier: source.farmIdentifier, keeping: 10, excluding: manifest.id)
        return manifest
    }

    func list(farmIdentifier: String? = nil) throws -> [BackupManifest] {
        if let farmIdentifier { try SaveSourceResolver.validateFarmIdentifier(farmIdentifier) }
        guard fileManager.fileExists(atPath: rootURL.path) else { return [] }
        let farmDirectories: [URL]
        if let farmIdentifier {
            farmDirectories = [rootURL.appendingPathComponent(safeComponent(farmIdentifier), isDirectory: true)]
        } else {
            farmDirectories = try fileManager.contentsOfDirectory(
                at: rootURL,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
        }

        var manifests: [BackupManifest] = []
        for farmDirectory in farmDirectories where fileManager.fileExists(atPath: farmDirectory.path) {
            let directories = (try? fileManager.contentsOfDirectory(
                at: farmDirectory,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )) ?? []
            for directory in directories {
                let manifestURL = directory.appendingPathComponent("manifest.json")
                guard let data = try? Data(contentsOf: manifestURL),
                      let manifest = try? JSONDecoder.backupDecoder.decode(BackupManifest.self, from: data) else {
                    continue
                }
                guard (try? SaveSourceResolver.validateFarmIdentifier(manifest.farmIdentifier)) != nil,
                      directory.lastPathComponent == manifest.id.uuidString,
                      farmDirectory.lastPathComponent == safeComponent(manifest.farmIdentifier) else { continue }
                manifests.append(manifest)
            }
        }
        return manifests.sorted { $0.savedAt > $1.savedAt }
    }

    func data(for manifest: BackupManifest) throws -> (main: Data, info: Data?) {
        try validateManifest(manifest)
        let directory = backupURL(manifest)
        let mainURL = directory.appendingPathComponent("MainSave")
        guard fileManager.fileExists(atPath: mainURL.path) else { throw BackupStoreError.missingBackup }
        let main = try Data(contentsOf: mainURL)
        let infoURL = directory.appendingPathComponent("SaveGameInfo")
        let info = fileManager.fileExists(atPath: infoURL.path) ? try Data(contentsOf: infoURL) : nil
        if manifest.infoOriginalName != nil, info == nil { throw BackupStoreError.missingBackup }
        let pair = SavePairData(main: main, info: info)
        if let expectedMainHash = manifest.mainHash,
           pair.mainHash != expectedMainHash {
            throw BackupStoreError.corruptBackup(manifest.mainOriginalName)
        }
        if let expectedInfoHash = manifest.infoHash,
           pair.infoHash != expectedInfoHash {
            throw BackupStoreError.corruptBackup(manifest.infoOriginalName ?? "SaveGameInfo")
        }
        return (main, info)
    }

    /// Available without a live or parseable original save. Legacy backups also
    /// undergo semantic validation before they can be exported or restored.
    func validate(_ manifest: BackupManifest) throws {
        let stored = try data(for: manifest)
        guard stored.info != nil else { throw BackupStoreError.missingBackup }
        _ = try SaveParser.parse(
            mainData: stored.main, infoData: stored.info, catalog: [], recipeCatalog: [:]
        )
    }

    /// Creates a complete, verified rescue pair entirely from private backup data.
    /// No source bookmark, source file or editing session is required.
    func export(_ manifest: BackupManifest, exportRootURL: URL? = nil) throws -> [URL] {
        try validate(manifest)
        let stored = try data(for: manifest)
        guard let info = stored.info else { throw BackupStoreError.missingBackup }
        let exportRoot = exportRootURL ?? rootURL.deletingLastPathComponent()
            .appendingPathComponent("BackupExports", isDirectory: true)
        let exportDirectory = exportRoot.appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent(manifest.farmIdentifier, isDirectory: true)
        try fileManager.createDirectory(at: exportDirectory, withIntermediateDirectories: true)
        do {
            let mainURL = exportDirectory.appendingPathComponent(manifest.mainOriginalName)
            let infoURL = exportDirectory.appendingPathComponent("SaveGameInfo")
            try stored.main.write(to: mainURL, options: .atomic)
            try info.write(to: infoURL, options: .atomic)
            let exported = SavePairData(main: try Data(contentsOf: mainURL), info: try Data(contentsOf: infoURL))
            let original = SavePairData(main: stored.main, info: info)
            guard exported.mainHash == original.mainHash, exported.infoHash == original.infoHash else {
                throw BackupStoreError.corruptBackup(manifest.mainOriginalName)
            }
            return [mainURL, infoURL]
        } catch {
            try? fileManager.removeItem(at: exportDirectory)
            throw error
        }
    }

    @discardableResult
    func setProtected(_ manifest: BackupManifest, isProtected: Bool) throws -> BackupManifest {
        try validateManifest(manifest)
        var updated = manifest
        updated.isProtected = isProtected
        try writeManifest(updated)
        if !isProtected { try prune(farmIdentifier: manifest.farmIdentifier, keeping: 10, excluding: manifest.id) }
        return updated
    }

    private func writeManifest(_ manifest: BackupManifest) throws {
        try JSONEncoder.backupEncoder.encode(manifest)
            .write(to: backupURL(manifest).appendingPathComponent("manifest.json"), options: .atomic)
    }

    private func validateManifest(_ manifest: BackupManifest) throws {
        guard (try? SaveSourceResolver.validateFarmIdentifier(manifest.farmIdentifier)) != nil,
              manifest.mainOriginalName == manifest.farmIdentifier,
              manifest.infoOriginalName == nil || manifest.infoOriginalName == "SaveGameInfo" else {
            throw BackupStoreError.invalidManifest
        }
    }

    private func prune(farmIdentifier: String, keeping count: Int, excluding excludedID: UUID? = nil) throws {
        let manifests = try list(farmIdentifier: farmIdentifier).filter { $0.isProtected != true }
        guard manifests.count > count else { return }
        // Always retain the just-created record even when ISO-8601 timestamps tie.
        let candidates = manifests.filter { $0.id != excludedID }
        let otherCount = excludedID.flatMap { id in manifests.contains { $0.id == id } ? count - 1 : nil } ?? count
        for manifest in candidates.dropFirst(max(0, otherCount)) {
            let directory = backupURL(manifest)
            let standardized = directory.standardizedFileURL
            guard standardized.path.hasPrefix(rootURL.standardizedFileURL.path + "/") else { continue }
            try fileManager.removeItem(at: standardized)
        }
    }

    private func backupURL(_ manifest: BackupManifest) -> URL {
        rootURL
            .appendingPathComponent(safeComponent(manifest.farmIdentifier), isDirectory: true)
            .appendingPathComponent(manifest.id.uuidString, isDirectory: true)
    }

    private func safeComponent(_ value: String) -> String {
        value.replacingOccurrences(of: "/", with: "_")
    }
}

private extension JSONEncoder {
    static var backupEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

private extension JSONDecoder {
    static var backupDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
