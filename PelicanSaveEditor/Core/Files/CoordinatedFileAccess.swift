import Foundation

enum CoordinatedFileError: LocalizedError {
    case read(URL, String)
    case write(URL, String)

    var errorDescription: String? {
        switch self {
        case let .read(url, message):
            "无法读取 \(url.lastPathComponent)：\(message)"
        case let .write(url, message):
            "无法写入 \(url.lastPathComponent)：\(message)"
        }
    }
}

enum CoordinatedFileAccess {
    static func withCoordinatedRead<T>(
        of url: URL,
        options: NSFileCoordinator.ReadingOptions = [],
        _ operation: (URL) throws -> T
    ) throws -> T {
        var coordinationError: NSError?
        var operationError: Error?
        var result: T?
        NSFileCoordinator().coordinate(
            readingItemAt: url,
            options: options,
            error: &coordinationError
        ) { coordinatedURL in
            do {
                result = try operation(coordinatedURL)
            } catch {
                operationError = error
            }
        }
        if let error = operationError ?? coordinationError {
            throw CoordinatedFileError.read(url, error.localizedDescription)
        }
        guard let result else {
            throw CoordinatedFileError.read(url, "文件提供器没有返回数据")
        }
        return result
    }

    static func read(_ url: URL) throws -> Data {
        try withCoordinatedRead(of: url) { coordinatedURL in
            // Callers may retain these bytes as the original state for an in-place
            // transaction, so never retain a memory map of the writable source.
            try Data(contentsOf: coordinatedURL)
        }
    }

    static func write(_ data: Data, to url: URL) throws {
        try withCoordinatedWritePair(mainURL: url, infoURL: nil) { mainURL, _ in
            try writeCoordinatedData(data, to: mainURL)
        }
    }

    /// Keep the hash check, backup, both writes, verification and rollback inside
    /// one coordinated access. Do not nest another coordinator in the operation.
    static func withCoordinatedWritePair<T>(
        mainURL: URL,
        infoURL: URL?,
        _ operation: @escaping (URL, URL?) throws -> T
    ) throws -> T {
        var coordinationError: NSError?
        var operationError: Error?
        var result: T?
        let accessor: (URL, URL?) -> Void = { main, info in
            do {
                result = try operation(main, info)
            } catch {
                operationError = error
            }
        }
        let coordinator = NSFileCoordinator()
        if let infoURL {
            coordinator.coordinate(
                writingItemAt: mainURL, options: [],
                writingItemAt: infoURL, options: [],
                error: &coordinationError
            ) { main, info in accessor(main, info) }
        } else {
            coordinator.coordinate(
                writingItemAt: mainURL, options: [], error: &coordinationError
            ) { main in accessor(main, nil) }
        }
        // Preserve typed transaction errors for the caller's conflict UI.
        if let operationError { throw operationError }
        if let coordinationError {
            throw CoordinatedFileError.write(mainURL, coordinationError.localizedDescription)
        }
        guard let result else {
            throw CoordinatedFileError.write(mainURL, "文件提供器没有完成协调操作")
        }
        return result
    }

    /// Only call while holding a coordinator for this URL.
    static func writeCoordinatedData(_ data: Data, to url: URL) throws {
        // A file grant may not allow creating or renaming a sibling temporary file.
        let handle = try FileHandle(forWritingTo: url)
        var closed = false
        defer { if !closed { try? handle.close() } }
        try handle.seek(toOffset: 0)
        try handle.truncate(atOffset: 0)
        try handle.write(contentsOf: data)
        try handle.synchronize()
        try handle.close()
        closed = true
    }
}
