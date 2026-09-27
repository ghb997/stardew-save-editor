import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct VerifiedExportView: View {
    @Environment(EditorStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let session: SaveSession
    @State private var review: VerifiedExportReview?
    @State private var showingDirectory = false
    @State private var directoryFlow = CopyImportPresentationFlow()
    @State private var showingFileExport = false
    @State private var didExportFiles = false
    @State private var gameExited = false
    @State private var acknowledgeConflict = false
    @State private var showingRecoveryConfirmation = false
    @State private var notice: String?

    var body: some View {
        NavigationStack {
            GameList {
                Section("已保存的应用副本") {
                    Text("\(session.originalDraft.farmName) · \(session.originalDraft.playerName)").font(.headline)
                    Text("请选择游戏中这个农场的文件夹，应用会核对两份文件并在覆盖前备份目标。")
                    Button("选择游戏农场目录", systemImage: "folder") {
                        directoryFlow.begin(); showingDirectory = true
                    }
                    .accessibilityIdentifier("export.choose.directory")
                }
                if let review {
                    Section("核对即将替换的内容") {
                        LabeledContent("应用副本") { Text(review.localDescription).multilineTextAlignment(.trailing) }
                        LabeledContent("游戏目标") { Text(review.targetDescription).multilineTextAlignment(.trailing) }
                        Text(review.target.mainURL.deletingLastPathComponent().path)
                            .font(.caption).textSelection(.enabled)
                        if review.targetChanged {
                            Text("目标与导入时不同，可能包含更新的游戏进度。覆盖会把目标替换为上面的应用副本。")
                                .foregroundStyle(AppTheme.trackerWarning)
                        }
                        if review.identityWarning {
                            Text("存档缺少可比对的稳定身份标识，请仔细核对农场、人物和日期。")
                                .foregroundStyle(AppTheme.trackerWarning)
                        }
                        if review.targetChanged || review.identityWarning {
                            Toggle("我已核对，确认替换这个目标", isOn: $acknowledgeConflict)
                        }
                        Toggle("游戏已完全退出", isOn: $gameExited)
                        Button("备份目标并写入两份文件", systemImage: "externaldrive.badge.checkmark") {
                            store.commitExport(review) { success in
                                if success {
                                    notice = "两份游戏文件已写入并通过哈希校验。替换前的目标已保留为保护备份。"
                                } else {
                                    notice = "本次写入未完成，请重新选择目录并核对目标。错误信息中的恢复状态为准。"
                                }
                                self.review = nil; gameExited = false; acknowledgeConflict = false
                            }
                        }
                        .disabled(!gameExited || ((review.targetChanged || review.identityWarning) && !acknowledgeConflict))
                        .accessibilityIdentifier("export.commit")
                    }
                }
                if store.exportRecoveryDirectory != nil {
                    Section("目标有未完成的旧事务") {
                        Text("当前目标已保留，未继续覆盖。可保留当前文件并结束旧事务，然后重新核对；旧备份仍可从备份管理导出。")
                        Button("保留目标并结束旧事务") { showingRecoveryConfirmation = true }
                    }
                }
                if let notice { Section { Text(notice).accessibilityIdentifier("export.result") } }
                if let warning = store.libraryWarning { Section { Text(warning).foregroundStyle(AppTheme.trackerWarning) } }
                Section {
                    Button("导出文件到其他位置", systemImage: "square.and.arrow.up") {
                        didExportFiles = false; showingFileExport = true
                    }
                    Text("系统导出只确认文件已交给所选位置，无法校验游戏目标或为目标建立备份。副本列表会单独标记此状态。")
                        .font(.caption).foregroundStyle(AppTheme.secondary)
                }
            }
            .navigationTitle("导出已保存副本")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        }
        .sheet(isPresented: $showingDirectory, onDismiss: { prepare(directoryFlow.dismissed()) }) {
            GameDirectoryPicker(onPick: { urls in
                prepare(directoryFlow.selected(urls)); showingDirectory = false
            }, onCancel: { directoryFlow.cancelled(); showingDirectory = false })
        }
        .sheet(isPresented: $showingFileExport, onDismiss: {
            if didExportFiles {
                store.recordFileExport()
                notice = "文件已导出，游戏目标未校验。请确认两份文件位于正确的农场目录。"
            } else { notice = "导出已取消，已保存副本仍在本机。" }
        }) {
            SavePairExportPicker(urls: [session.source.mainURL] + [session.source.infoURL].compactMap { $0 },
                onExport: { didExportFiles = true; showingFileExport = false },
                onCancel: { showingFileExport = false })
        }
        .alert("保留当前目标并结束旧事务？", isPresented: $showingRecoveryConfirmation) {
            Button("保留并重新核对") { store.keepExportTarget { review = $0 } }
            Button("取消", role: .cancel) {}
        } message: { Text("会另存当前目标为保护备份，结束旧事务，不会在这一步替换游戏文件。") }
        .allowsHitTesting(!store.isBusy).interactiveDismissDisabled(store.isBusy)
        .operationFeedback()
    }

    private func prepare(_ urls: [URL]?) {
        guard let directory = urls?.first else { return }
        review = nil; notice = nil; gameExited = false; acknowledgeConflict = false
        store.prepareExport(directory: directory) { review = $0 }
    }
}

struct GameDirectoryPicker: UIViewControllerRepresentable {
    let onPick: @MainActor ([URL]) -> Void
    let onCancel: @MainActor () -> Void
    func makeCoordinator() -> CopyImportTwoFilePicker.Coordinator {
        CopyImportTwoFilePicker.Coordinator(onPick: onPick, onCancel: onCancel)
    }
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let controller = UIDocumentPickerViewController(forOpeningContentTypes: [.folder], asCopy: false)
        controller.delegate = context.coordinator
        controller.allowsMultipleSelection = false
        return controller
    }
    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}
}
