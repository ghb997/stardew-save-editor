import Foundation

private struct PersistedSaveSource: Codable {
    let mode: SaveAccessMode
    let farmIdentifier: String?
    let bookmarks: [Data]
}

enum RecentSaveSourceStore {
    private static let key = "recentSaveSource.v3"

    static var hasRecentSource: Bool {
        UserDefaults.standard.data(forKey: key) != nil
    }

    static func save(_ source: SaveSource) throws {
        let bookmarks = try source.accessURLs.map { url -> Data in
            let active = url.startAccessingSecurityScopedResource()
            defer { if active { url.stopAccessingSecurityScopedResource() } }
            return try url.bookmarkData(
                options: [.minimalBookmark],
                includingResourceValuesForKeys: [.isDirectoryKey, .isRegularFileKey],
                relativeTo: nil
            )
        }
        let encoded = try JSONEncoder().encode(PersistedSaveSource(
            mode: source.mode,
            farmIdentifier: source.farmIdentifier,
            bookmarks: bookmarks
        ))
        UserDefaults.standard.set(encoded, forKey: key)
    }

    static func load() throws -> SaveSource {
        guard let encoded = UserDefaults.standard.data(forKey: key) else {
            throw SaveSourceError.noRecentSource
        }
        let stored = try JSONDecoder().decode(PersistedSaveSource.self, from: encoded)
        var urls: [URL] = []
        for bookmark in stored.bookmarks {
            var stale = false
            let url = try URL(
                resolvingBookmarkData: bookmark,
                options: [.withoutUI],
                relativeTo: nil,
                bookmarkDataIsStale: &stale
            )
            guard !stale else { throw SaveSourceError.staleBookmark }
            urls.append(url)
        }
        switch stored.mode {
        case .directory:
            guard let directory = urls.first else { throw SaveSourceError.staleBookmark }
            if let farmIdentifier = stored.farmIdentifier {
                return try SaveSourceResolver.directory(
                    directory,
                    farmIdentifier: farmIdentifier
                )
            }
            return try SaveSourceResolver.directory(directory)
        case .twoFiles:
            return try SaveSourceResolver.files(urls)
        case .importedCopy:
            return try SaveSourceResolver.importedFiles(urls)
        }
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}
