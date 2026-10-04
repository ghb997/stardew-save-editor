import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct VerifiedExportView: View {
    @Environment(EditorStore.self) private var store
    let session: SaveSession
    var returnTitle = "返回编辑"
    let onLater: () -> Void
    let onFinish: () -> Void
    @State private var review: VerifiedExportReview?
    @State private var showingDirectory = false
    @State private var directoryFlow = CopyImportPresentationFlow()
    @State private var directorySnapshot: SavedExportSnapshot?
    @State private var filePresentation: FilePresentation?
    @State private var fileFlow = FileExportPresentationFlow()
    @State private var fileDismissalID: UUID?
    @State private var gameExited = false
    @State private var acknowledgeConflict = false
    @State private var showingRecoveryConfirmation = false
    @State private var notice: String?
    @State private var completion: Completion?

    private struct FilePresentation: Identifiable {
        let id: UUID
        let snapshot: SavedExportSnapshot
    }
    private enum Completion {
        case verified, files(recorded: Bool)
        var title: String {
            switch self {
            case .verified: "已写入游戏目录"
            case .files: "文件已导出"
            }
        }
        var message: String {
            switch self {
            case .verified: "两份游戏文件已写入并通过校验。现在可以重新打开游戏，载入这个农场。"
            case .files(true): "文件已导出，游戏目标未校验。请确认主存档和 SaveGameInfo 都已放入正确的游戏农场目录。"
            case .files(false): "文件已交给所选位置，但本地导出记录未更新。游戏目标未校验，副本仍保留在本机。"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            GameList {
                Section {
                    SaveFlowProgress(step: completion == nil ? 2 : 3)
                    GameAssetLabel(completion?.title ?? (review == nil ? "副本已保存，选择导出位置" : "核对游戏里的这个农场"),
                                   assetName: completion == nil ? "GameUIBackpack" : "GameUIReview", iconSize: 28)
                        .font(.headline)
                    Text("\(session.originalDraft.farmName) · \(session.originalDraft.playerName)")
                        .font(.subheadline).foregroundStyle(AppTheme.secondary)
                    if let completion {
                        Text(completion.message).accessibilityIdentifier("export.result")
                        if case .verified = completion {
                            GameLabel("替换前的游戏文件已保留为保护备份", systemImage: "checkmark.shield.fill")
                                .font(.subheadline).foregroundStyle(AppTheme.progress)
                        }
                    } else {
                        Text(review == nil ? "选择游戏中这个农场的文件夹。应用会先核对目标，再让你确认写入。"
                             : "确认下方内容后，应用会备份目标、写入两份文件并重新读取校验。")
                            .font(.subheadline)
                    }
                }
                if completion == nil {
                    if let review {
                        Section("即将写入") {
                            LabeledContent("已保存副本") { Text(review.localDescription).multilineTextAlignment(.trailing) }
                            LabeledContent("游戏当前内容") { Text(review.targetDescription).multilineTextAlignment(.trailing) }
                            DisclosureGroup("目标文件夹") {
                                Text(review.target.mainURL.deletingLastPathComponent().path)
                                    .font(.caption).textSelection(.enabled)
                            }
                            Button("重新选择目录", systemImage: "folder") { chooseDirectory() }
                                .accessibilityIdentifier("export.choose.directory")
                        }
                        Section("写入前确认") {
                            if review.targetChanged {
                                Text("游戏目标与导入时不同，可能有更新的进度。继续会用上面的副本替换它。")
                                    .foregroundStyle(AppTheme.trackerWarning)
                            }
                            if review.identityWarning {
                                Text("存档缺少可比对的稳定身份标识，请核对农场、人物和日期。")
                                    .foregroundStyle(AppTheme.trackerWarning)
                            }
                            if review.targetChanged || review.identityWarning {
                                Toggle("我已核对，确认替换这个目标", isOn: $acknowledgeConflict)
                                    .accessibilityIdentifier("export.confirm.target")
                            }
                            Toggle("游戏已完全退出", isOn: $gameExited)
                                .accessibilityIdentifier("export.game.exited")
                        }
                    }
                    if store.exportRecoveryDirectory != nil {
                        Section("目标有未完成的旧事务") {
                            Text("目标已保留，未继续覆盖。可以保留当前文件并结束旧事务，然后重新核对。旧备份仍可从备份管理导出。")
                            Button("保留目标并结束旧事务") { showingRecoveryConfirmation = true }
                        }
                    }
                    if let notice {
                        Section { Text(notice).foregroundStyle(AppTheme.trackerWarning).accessibilityIdentifier("export.notice") }
                    }
                    Section {
                        DisclosureGroup("其他导出方式") {
                            Button("导出文件到其他位置", systemImage: "square.and.arrow.up") { exportFiles() }
                                .accessibilityIdentifier("export.files")
                            Text("使用系统文件导出。不会核对或备份游戏目标，需要自行确认文件的位置。")
                                .font(.caption).foregroundStyle(AppTheme.secondary)
                        }.accessibilityIdentifier("export.other")
                    }
                }
                if let warning = store.libraryWarning {
                    Section { Text(warning).foregroundStyle(AppTheme.trackerWarning) }
                }
            }
            SaveFlowActionBar {
                if completion != nil {
                    Button { onFinish() } label: {
                        Text("完成，\(returnTitle)").frame(maxWidth: .infinity)
                    }
                        .buttonStyle(GameButtonStyle(prominent: true))
                        .accessibilityIdentifier("export.done")
                } else {
                    if let review {
                        Button { commit(review) } label: {
                            Text("备份并写入游戏目录").frame(maxWidth: .infinity)
                        }
                            .buttonStyle(GameButtonStyle(prominent: true))
                            .disabled(!gameExited || ((review.targetChanged || review.identityWarning) && !acknowledgeConflict))
                            .accessibilityIdentifier("export.commit")
                    } else {
                        Button { chooseDirectory() } label: {
                            Label("选择游戏农场目录", systemImage: "folder").frame(maxWidth: .infinity)
                        }
                            .buttonStyle(GameButtonStyle(prominent: true))
                            .accessibilityIdentifier("export.choose.directory")
                    }
                    Button("稍后导出") { onLater() }
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .accessibilityIdentifier("export.later")
                }
            }
        }
        .navigationTitle(completion == nil ? "保存并导出" : "导出完成")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingDirectory, onDismiss: { prepare(directoryFlow.dismissed()) }) {
            GameDirectoryPicker(onPick: { urls in
                prepare(directoryFlow.selected(urls)); showingDirectory = false
            }, onCancel: {
                directoryFlow.cancelled(); showingDirectory = false
                notice = "选择已取消。副本已经保存，可以重新选择目录或稍后导出。"
            })
        }
        .sheet(item: $filePresentation, onDismiss: {
            if let id = fileDismissalID { consume(fileFlow.dismissed(presentationID: id)) }
        }) { presentation in
            SavePairExportPicker(urls: presentation.snapshot.urls, onExport: {
                consume(fileFlow.exported(presentationID: presentation.id))
                if filePresentation?.id == presentation.id { filePresentation = nil }
            }, onCancel: {
                consume(fileFlow.cancelled(presentationID: presentation.id))
                if filePresentation?.id == presentation.id { filePresentation = nil }
            })
            .interactiveDismissDisabled()
        }
        .alert("保留当前目标并结束旧事务？", isPresented: $showingRecoveryConfirmation) {
            Button("保留并重新核对") { store.keepExportTarget { review = $0 } }
            Button("取消", role: .cancel) {}
        } message: { Text("会另存当前目标为保护备份，结束旧事务，不会在这一步替换游戏文件。") }
        .allowsHitTesting(!store.isBusy)
        .interactiveDismissDisabled(store.isBusy)
    }

    private func chooseDirectory() {
        guard let snapshot = store.exportSnapshot(for: session) else {
            notice = "副本状态已变化，请返回检查更改后重新导出。"; return
        }
        directorySnapshot = snapshot
        review = nil; notice = nil; gameExited = false; acknowledgeConflict = false
#if DEBUG
        do {
            switch try DebugPersistenceFixture.exportDirectorySelection() {
            case .systemPicker: break
            case .cancelled:
                notice = "选择已取消。副本已经保存，可以重新选择目录或稍后导出。"; return
            case .selected(let directory): prepare([directory]); return
            }
        } catch { store.errorMessage = error.localizedDescription; return }
#endif
        directoryFlow.begin(); showingDirectory = true
    }

    private func prepare(_ urls: [URL]?) {
        guard let directory = urls?.first, let snapshot = directorySnapshot else { return }
        store.prepareExport(snapshot: snapshot, directory: directory) { result in
            review = result
            if result == nil { notice = "尚未导出这份副本。副本已保存，请按错误提示处理后重新选择目录。" }
        }
    }

    private func commit(_ reviewed: VerifiedExportReview) {
#if DEBUG
        do { try DebugPersistenceFixture.beforeExportCommit() }
        catch { store.errorMessage = error.localizedDescription; return }
#endif
        store.commitExport(reviewed) { success in
            if success { completion = .verified }
            else { notice = "本次写入未完成，副本仍保存在本机。请根据错误提示处理，再重新选择目录核对。" }
            review = nil; gameExited = false; acknowledgeConflict = false
        }
    }

    private func exportFiles() {
        guard let snapshot = store.exportSnapshot(for: session) else {
            notice = "副本状态已变化，请返回检查更改后重新导出。"; return
        }
        let id = fileFlow.begin(snapshot: snapshot)
        fileDismissalID = id
        filePresentation = FilePresentation(id: id, snapshot: snapshot)
    }

    private func consume(_ result: FileExportPresentationResult?) {
        guard let result else { return }
        switch result {
        case .cancelled:
            notice = "导出已取消，副本已保存在本机。可以重试或稍后导出。"
        case .exported(let snapshot):
            store.recordFileExport(snapshot: snapshot) { recorded in completion = .files(recorded: recorded) }
        }
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
