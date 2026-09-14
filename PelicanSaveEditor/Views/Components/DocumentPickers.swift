import SwiftUI
import UniformTypeIdentifiers
import UIKit

/// Coordinates the two independent completion signals emitted by a copied-file import.
/// UIKit may report the selected URLs before or after SwiftUI reports that the sheet closed.
struct CopyImportPresentationFlow {
    private var selectedURLs: [URL]?
    private var didDismiss = false
    private var isActive = false

    mutating func begin() {
        selectedURLs = nil
        didDismiss = false
        isActive = true
    }

    mutating func selected(_ urls: [URL]) -> [URL]? {
        guard isActive else { return nil }
        selectedURLs = urls
        return consumeIfReady()
    }

    mutating func dismissed() -> [URL]? {
        guard isActive else { return nil }
        didDismiss = true
        return consumeIfReady()
    }

    mutating func cancelled() {
        reset()
    }

    private mutating func consumeIfReady() -> [URL]? {
        guard didDismiss, let urls = selectedURLs else { return nil }
        reset()
        return urls
    }

    private mutating func reset() {
        selectedURLs = nil
        didDismiss = false
        isActive = false
    }
}

/// Imports the selected pair as local copies for editing and export.
struct CopyImportTwoFilePicker: UIViewControllerRepresentable {
    let onPick: @MainActor ([URL]) -> Void
    let onCancel: @MainActor () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick, onCancel: onCancel)
    }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let controller = UIDocumentPickerViewController(forOpeningContentTypes: [.data, .item], asCopy: true)
        controller.delegate = context.coordinator
        controller.allowsMultipleSelection = true
        controller.shouldShowFileExtensions = true
        return controller
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    @MainActor
    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: @MainActor ([URL]) -> Void
        let onCancel: @MainActor () -> Void

        init(onPick: @escaping @MainActor ([URL]) -> Void, onCancel: @escaping @MainActor () -> Void) {
            self.onPick = onPick
            self.onCancel = onCancel
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            onPick(urls)
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            onCancel()
        }
    }
}
