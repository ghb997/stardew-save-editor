import SwiftUI
import UniformTypeIdentifiers
import UIKit

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
