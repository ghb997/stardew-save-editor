import CryptoKit
import Foundation
import UniformTypeIdentifiers

enum SaveAccessMode: String, Codable, Sendable {
    case directory
    case twoFiles
    case importedCopy
}

struct SaveSource: Sendable {
    let mode: SaveAccessMode
    let farmIdentifier: String
    let mainURL: URL
    let infoURL: URL?
    let accessURLs: [URL]

    /// A farm can be opened through a directory or two file grants. Its physical
    /// pair, rather than its display name or access mode, identifies the source.
    /// App-owned imports have unique directories and therefore unique identities.
    var identity: String {
        let locations = [mainURL, infoURL].compactMap { $0 }
            .map { $0.standardizedFileURL.absoluteString }
        let encoded = (try? JSONEncoder().encode(locations)) ?? Data()
        return SHA256.hash(data: encoded).map { String(format: "%02x", $0) }.joined()
    }

    func withSecurityScopedAccess<T>(_ operation: () throws -> T) rethrows -> T {
        let activeURLs = accessURLs.filter { $0.startAccessingSecurityScopedResource() }
        defer {
            for url in activeURLs.reversed() {
                url.stopAccessingSecurityScopedResource()
            }
        }
        return try operation()
    }
}

enum SaveSourceError: LocalizedError {
    case invalidFarmName(String)
    case missingMain(String)
    case missingInfo
    case wrongFileCount(Int)
    case duplicateInfo
    case differentFolders
    case notRegularFile(String)
    case staleBookmark
    case noRecentSource
    case noFarmDirectories(String)

    var errorDescription: String? {
        switch self {
        case let .invalidFarmName(name):
            "存档目录名称格式不正确：\(name)。应类似 Farmer_123456789。"
        case let .missingMain(name):
            "目录中找不到主存档文件：\(name)"
        case .missingInfo:
            "目录中找不到 SaveGameInfo。"
        case let .wrongFileCount(count):
            "需要同时选择主存档与 SaveGameInfo，当前选择了 \(count) 个文件。"
        case .duplicateInfo:
            "不能同时选择两个 SaveGameInfo 文件。"
        case .differentFolders:
            "两个文件必须来自同一个农场目录。"
        case let .notRegularFile(name):
            "所选项目不是普通文件：\(name)"
        case .staleBookmark:
            "上次存档的文件授权已失效，请重新选择。"
        case .noRecentSource:
            "还没有最近使用的农场。"
        case let .noFarmDirectories(name):
            "在“\(name)”中没有找到有效存档。请选择 Stardew Valley 文件夹，或名称类似 Farmer_123456789 的存档文件夹。"
        }
    }
}

enum SaveSourceResolver {
    private static let farmPattern = try! NSRegularExpression(pattern: #"^.+_[0-9]+$"#)

    private struct FarmDirectoryEntry {
        let farmIdentifier: String
        let hasMain: Bool
        let hasInfo: Bool
    }

    static func directory(_ directoryURL: URL) throws -> SaveSource {
        let access = directoryURL.startAccessingSecurityScopedResource()
        defer { if access { directoryURL.stopAccessingSecurityScopedResource() } }

        return try makeDirectorySource(
            farmDirectoryURL: directoryURL,
            accessURL: directoryURL
        )
    }

    /// Accepts either one farm directory or the parent Stardew Valley directory.
    /// Sources discovered below a parent retain that parent URL as their security scope.
    static func discoverDirectories(in selectedURL: URL) throws -> [SaveSource] {
        let access = selectedURL.startAccessingSecurityScopedResource()
        defer { if access { selectedURL.stopAccessingSecurityScopedResource() } }

        if isValidFarmIdentifier(selectedURL.lastPathComponent) {
            return [try makeDirectorySource(
                farmDirectoryURL: selectedURL,
                accessURL: selectedURL
            )]
        }

        let entries = try CoordinatedFileAccess.withCoordinatedRead(
            of: selectedURL,
            options: .withoutChanges
        ) { coordinatedRoot in
            let children = try FileManager.default.contentsOfDirectory(
                at: coordinatedRoot,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
            return try children.compactMap { child -> FarmDirectoryEntry? in
                let farmIdentifier = child.lastPathComponent
                guard isValidFarmIdentifier(farmIdentifier),
                      try child.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true else {
                    return nil
                }
                return FarmDirectoryEntry(
                    farmIdentifier: farmIdentifier,
                    hasMain: FileManager.default.fileExists(
                        atPath: child.appendingPathComponent(farmIdentifier).path
                    ),
                    hasInfo: FileManager.default.fileExists(
                        atPath: child.appendingPathComponent("SaveGameInfo").path
                    )
                )
            }
        }
        let sources = entries.compactMap { entry -> SaveSource? in
            guard entry.hasMain, entry.hasInfo else { return nil }
            let child = selectedURL.appendingPathComponent(
                entry.farmIdentifier,
                isDirectory: true
            )
            return SaveSource(
                mode: .directory,
                farmIdentifier: entry.farmIdentifier,
                mainURL: child.appendingPathComponent(entry.farmIdentifier),
                infoURL: child.appendingPathComponent("SaveGameInfo"),
                accessURLs: [selectedURL]
            )
        }
        .sorted {
            $0.farmIdentifier.localizedStandardCompare($1.farmIdentifier) == .orderedAscending
        }

        guard !sources.isEmpty else {
            throw SaveSourceError.noFarmDirectories(selectedURL.lastPathComponent)
        }
        return sources
    }

    /// Restores a previously selected farm while retaining access through its bookmarked root.
    static func directory(_ accessURL: URL, farmIdentifier: String) throws -> SaveSource {
        try validateFarmIdentifier(farmIdentifier)
        let access = accessURL.startAccessingSecurityScopedResource()
        defer { if access { accessURL.stopAccessingSecurityScopedResource() } }

        let farmDirectoryURL = accessURL.lastPathComponent == farmIdentifier
            ? accessURL
            : accessURL.appendingPathComponent(farmIdentifier, isDirectory: true)
        return try makeDirectorySource(
            farmDirectoryURL: farmDirectoryURL,
            accessURL: accessURL
        )
    }

    private static func makeDirectorySource(
        farmDirectoryURL: URL,
        accessURL: URL
    ) throws -> SaveSource {
        let farmID = farmDirectoryURL.lastPathComponent
        try validateFarmIdentifier(farmID)

        let mainURL = farmDirectoryURL.appendingPathComponent(farmID, isDirectory: false)
        let infoURL = farmDirectoryURL.appendingPathComponent("SaveGameInfo", isDirectory: false)
        let presence = try CoordinatedFileAccess.withCoordinatedRead(
            of: farmDirectoryURL,
            options: .withoutChanges
        ) { coordinatedFarm in
            (
                main: FileManager.default.fileExists(
                    atPath: coordinatedFarm.appendingPathComponent(farmID).path
                ),
                info: FileManager.default.fileExists(
                    atPath: coordinatedFarm.appendingPathComponent("SaveGameInfo").path
                )
            )
        }
        guard presence.main else {
            throw SaveSourceError.missingMain(farmID)
        }
        guard presence.info else {
            throw SaveSourceError.missingInfo
        }

        return SaveSource(
            mode: .directory,
            farmIdentifier: farmID,
            mainURL: mainURL,
            infoURL: infoURL,
            accessURLs: [accessURL]
        )
    }

    static func files(_ urls: [URL]) throws -> SaveSource {
        try makeFileSource(urls, mode: .twoFiles, requiresSameFolder: true)
    }

    /// Imports picker-provided copies into stable app-owned storage.
    /// The returned source can be edited safely, but never writes back to the game container.
    static func copiedFiles(
        _ urls: [URL],
        fileManager: FileManager = .default,
        importRootURL customImportRootURL: URL? = nil
    ) throws -> SaveSource {
        let pickerSource = try makeFileSource(
            urls,
            mode: .twoFiles,
            requiresSameFolder: false
        )
        let pair = try pickerSource.withSecurityScopedAccess {
            SavePairData(
                main: try CoordinatedFileAccess.read(pickerSource.mainURL),
                info: try pickerSource.infoURL.map(CoordinatedFileAccess.read)
            )
        }
        guard let infoData = pair.info else { throw SaveSourceError.missingInfo }

        let importRootURL: URL
        if let customImportRootURL {
            importRootURL = customImportRootURL
        } else {
            importRootURL = try fileManager.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            .appendingPathComponent("PelicanSaveEditor", isDirectory: true)
            .appendingPathComponent("ImportedSaves", isDirectory: true)
        }
        try fileManager.createDirectory(at: importRootURL, withIntermediateDirectories: true)
        let importedDirectoryURL = importRootURL.appendingPathComponent(
            "\(pickerSource.farmIdentifier)-\(UUID().uuidString)",
            isDirectory: true
        )
        try fileManager.createDirectory(at: importedDirectoryURL, withIntermediateDirectories: false)

        do {
            let mainURL = importedDirectoryURL.appendingPathComponent(pickerSource.farmIdentifier)
            let infoURL = importedDirectoryURL.appendingPathComponent("SaveGameInfo")
            try pair.main.write(to: mainURL, options: .atomic)
            try infoData.write(to: infoURL, options: .atomic)
            return try makeFileSource(
                [mainURL, infoURL],
                mode: .importedCopy,
                requiresSameFolder: true
            )
        } catch {
            try? fileManager.removeItem(at: importedDirectoryURL)
            throw error
        }
    }

    /// Reopens a stable app-owned copy, such as one restored from a recent-source bookmark.
    static func importedFiles(_ urls: [URL]) throws -> SaveSource {
        try makeFileSource(urls, mode: .importedCopy, requiresSameFolder: true)
    }

    private static func makeFileSource(
        _ urls: [URL],
        mode: SaveAccessMode,
        requiresSameFolder: Bool
    ) throws -> SaveSource {
        guard urls.count == 2 else { throw SaveSourceError.wrongFileCount(urls.count) }
        let access = urls.filter { $0.startAccessingSecurityScopedResource() }
        defer { access.forEach { $0.stopAccessingSecurityScopedResource() } }

        for url in urls {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey])
            guard values.isRegularFile == true else {
                throw SaveSourceError.notRegularFile(url.lastPathComponent)
            }
        }

        let infoMatches = urls.filter { $0.lastPathComponent == "SaveGameInfo" }
        guard !infoMatches.isEmpty else { throw SaveSourceError.missingInfo }
        guard infoMatches.count == 1 else { throw SaveSourceError.duplicateInfo }
        guard let infoURL = infoMatches.first,
              let mainURL = urls.first(where: { $0 != infoURL }) else {
            throw SaveSourceError.missingInfo
        }
        guard !requiresSameFolder || mainURL.deletingLastPathComponent().standardizedFileURL
            == infoURL.deletingLastPathComponent().standardizedFileURL else {
            throw SaveSourceError.differentFolders
        }

        let farmID = mainURL.lastPathComponent
        try validateFarmIdentifier(farmID)
        return SaveSource(
            mode: mode,
            farmIdentifier: farmID,
            mainURL: mainURL,
            infoURL: infoURL,
            accessURLs: [mainURL, infoURL]
        )
    }

    static func validateFarmIdentifier(_ value: String) throws {
        guard isValidFarmIdentifier(value) else {
            throw SaveSourceError.invalidFarmName(value)
        }
    }

    private static func isValidFarmIdentifier(_ value: String) -> Bool {
        guard !value.contains("/"), !value.contains(":"), !value.contains("\\") else {
            return false
        }
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        return farmPattern.firstMatch(in: value, range: range) != nil
    }
}
