import SwiftUI
import Observation

/// The last visible modal owns ordinary operation feedback. A nested sheet
/// suspends its parent host until dismissal, without consuming its messages.
@Observable
@MainActor
final class OperationFeedbackRegistry {
    static let shared = OperationFeedbackRegistry()
    private var hosts: [UUID] = []

    var hasModalHost: Bool { !hosts.isEmpty }
    func isCurrent(_ id: UUID) -> Bool { hosts.last == id }

    func register(_ id: UUID) {
        hosts.removeAll { $0 == id }
        hosts.append(id)
    }

    func unregister(_ id: UUID) {
        hosts.removeAll { $0 == id }
    }
}

@MainActor
private struct OperationFeedbackModifier: ViewModifier {
    @Environment(EditorStore.self) private var store
    @State private var hostID = UUID()
    private let registry = OperationFeedbackRegistry.shared

    func body(content: Content) -> some View {
        let isCurrentHost = registry.isCurrent(hostID)
        return content
            .overlay {
                if isCurrentHost && store.isBusy {
                    ZStack {
                        Color.black.opacity(0.18).ignoresSafeArea()
                        ProgressView(store.busyMessage)
                            .padding(24)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
                    }
                }
            }
            .alert(
                store.errorMessage != nil ? "操作失败" : "完成",
                isPresented: Binding(
                    get: {
                        registry.isCurrent(hostID) && !store.isBusy && store.recoveryConflictMessage == nil
                            && (store.errorMessage != nil || store.successMessage != nil)
                    },
                    set: { presented in
                        // Losing ownership is not a user acknowledgement.
                        if !presented && !store.isBusy && registry.isCurrent(hostID) { store.clearMessages() }
                    }
                )
            ) {
                Button("好") { store.clearMessages() }
            } message: {
                Text(store.errorMessage ?? store.successMessage ?? "")
            }
            .onAppear { registry.register(hostID) }
            .onDisappear { registry.unregister(hostID) }
    }
}

extension View {
    @MainActor
    func operationFeedback() -> some View {
        modifier(OperationFeedbackModifier())
    }
}
