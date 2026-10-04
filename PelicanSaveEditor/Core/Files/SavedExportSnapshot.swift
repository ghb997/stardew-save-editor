import Foundation

/// Identifies the saved bytes handed to a particular export presentation.
/// Completion must never substitute whichever farm or revision is currently open.
struct SavedExportSnapshot: Identifiable, Sendable {
    let id = UUID()
    let source: SaveSource
    let pair: SavePairData

    var urls: [URL] { [source.mainURL] + [source.infoURL].compactMap { $0 } }
}

enum FileExportPresentationResult: Sendable {
    case exported(SavedExportSnapshot)
    case cancelled
}

/// UIKit's result and SwiftUI's dismissal may arrive in either order.
/// A presentation token also rejects callbacks from a previously closed picker.
struct FileExportPresentationFlow {
    private var snapshot: SavedExportSnapshot?
    private var presentationID: UUID?
    private var result: FileExportPresentationResult?
    private var didDismiss = false

    mutating func begin(snapshot: SavedExportSnapshot) -> UUID {
        let id = UUID()
        self.snapshot = snapshot
        presentationID = id
        result = nil
        didDismiss = false
        return id
    }

    mutating func exported(presentationID: UUID) -> FileExportPresentationResult? {
        guard let snapshot, self.presentationID == presentationID, result == nil else { return nil }
        result = .exported(snapshot)
        return consumeIfReady()
    }

    mutating func cancelled(presentationID: UUID) -> FileExportPresentationResult? {
        guard self.presentationID == presentationID, result == nil else { return nil }
        result = .cancelled
        return consumeIfReady()
    }

    mutating func dismissed(presentationID: UUID) -> FileExportPresentationResult? {
        guard self.presentationID == presentationID else { return nil }
        didDismiss = true
        return consumeIfReady()
    }

    private mutating func consumeIfReady() -> FileExportPresentationResult? {
        guard didDismiss, let result else { return nil }
        snapshot = nil
        presentationID = nil
        self.result = nil
        didDismiss = false
        return result
    }
}
