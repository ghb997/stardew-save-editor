import SwiftUI
import UIKit

@main
struct PelicanSaveEditorApp: App {
    @State private var store: EditorStore

    init() {
        GlobalKeyboardReturnInstaller.shared.start()
        _store = State(initialValue: EditorStore())
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .tint(Color(red: 0.20, green: 0.56, blue: 0.31))
#if DEBUG
                .modifier(DebugLayoutViewport())
#endif
        }
    }
}

/// Installs the same native input accessory on every UIKit-backed text input.
/// SwiftUI TextField, SecureField and searchable use UITextField subclasses;
/// TextEditor uses UITextView. The concrete responder is covered regardless of
/// sheet, full-screen cover, navigation stack, form or left/right field layout.
@MainActor
final class GlobalKeyboardReturnInstaller: NSObject {
    static let shared = GlobalKeyboardReturnInstaller()
    static let toolbarIdentifier = "global.keyboardReturn.toolbar"
    static let buttonIdentifier = "global.keyboardReturn.button"
    private var isObserving = false
    private weak var activeResponder: UIResponder?

    func start() {
        guard !isObserving else { return }
        isObserving = true

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(textFieldDidBeginEditing(_:)),
            name: UITextField.textDidBeginEditingNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(textViewDidBeginEditing(_:)),
            name: UITextView.textDidBeginEditingNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardDidShow(_:)),
            name: UIResponder.keyboardDidShowNotification,
            object: nil
        )
    }

    @objc private func textFieldDidBeginEditing(_ notification: Notification) {
        guard let textField = notification.object as? UITextField else { return }
        activeResponder = textField
        install(on: textField)
    }

    @objc private func textViewDidBeginEditing(_ notification: Notification) {
        guard let textView = notification.object as? UITextView else { return }
        activeResponder = textView
        install(on: textView)
    }

    @objc private func keyboardDidShow(_ notification: Notification) {
        if let textField = activeResponder as? UITextField, textField.isFirstResponder {
            install(on: textField)
        } else if let textView = activeResponder as? UITextView, textView.isFirstResponder {
            install(on: textView)
        }
    }

    private func install(on textField: UITextField) {
        guard textField.inputAccessoryView?.accessibilityIdentifier != Self.toolbarIdentifier else { return }
        textField.inputAccessoryView = makeToolbar()
        if textField.isFirstResponder {
            textField.reloadInputViews()
        }
    }

    private func install(on textView: UITextView) {
        guard textView.inputAccessoryView?.accessibilityIdentifier != Self.toolbarIdentifier else { return }
        textView.inputAccessoryView = makeToolbar()
        if textView.isFirstResponder {
            textView.reloadInputViews()
        }
    }

    private func makeToolbar() -> UIToolbar {
        let toolbar = UIToolbar()
        toolbar.autoresizingMask = [.flexibleWidth]
        toolbar.accessibilityIdentifier = Self.toolbarIdentifier

        let spacer = UIBarButtonItem(systemItem: .flexibleSpace)
        let returnButton = UIBarButtonItem(
            title: "返回",
            style: .done,
            target: self,
            action: #selector(dismissKeyboard)
        )
        returnButton.accessibilityIdentifier = Self.buttonIdentifier
        toolbar.items = [spacer, returnButton]
        toolbar.sizeToFit()
        return toolbar
    }

    @objc func dismissKeyboard() {
        if activeResponder?.resignFirstResponder() != true {
            KeyboardReturnAction.dismiss()
        }
    }
}

@MainActor
enum KeyboardReturnAction {
    static func dismiss() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
    }
}
