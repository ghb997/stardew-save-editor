import SwiftUI
import UIKit

struct ReviewChangesView: View {
    @Environment(EditorStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Bindable var session: SaveSession
    var returnTitle = "返回编辑"
    @State private var showingExport = false
    @State private var showingSaveConfirmation = false
    @State private var showingDiscardConfirmation = false
    @State private var showingReloadConfirmation = false
    @State private var showingBackups = false
    @State private var savedNotice: String?
    private var farmSnapshot: FarmSnapshot? { session.farmSnapshot }
    private var isCopy: Bool { session.source.mode == .importedCopy }
    private var groupedDiffs: [SaveDiffGroup] { SaveDiffBuilder.grouped(session.diffs) }

    var body: some View {
        Group {
            if showingExport {
                VerifiedExportView(session: session, returnTitle: returnTitle, onLater: {
                    savedNotice = "已保存，待导出。可以继续编辑，也可以稍后从这里继续导出。"
                    showingExport = false
                }, onFinish: { dismiss() })
            } else {
                reviewContent
            }
        }
        .alert("确认写回存档？", isPresented: $showingSaveConfirmation) {
            Button("游戏已退出，备份并保存") { save(exportAfterwards: false) }
            Button("取消", role: .cancel) {}
        } message: {
            Text("保存前会备份原文件，再写入并重新读取校验。请先完全退出游戏。")
        }
        .alert("放弃全部更改？", isPresented: $showingDiscardConfirmation) {
            Button("放弃", role: .destructive) { session.discardChanges() }
            Button("取消", role: .cancel) {}
        }
        .alert("重新载入存档？", isPresented: $showingReloadConfirmation) {
            Button("放弃草稿并重新载入", role: .destructive) { store.reload() }
            Button("取消", role: .cancel) {}
        } message: {
            Text(isCopy ? "未保存的更改会被放弃，并重新读取应用内已保存的两份副本。游戏中的新进度需要重新复制导入。"
                        : "当前未保存的更改会被放弃，并从磁盘重新读取两份存档文件。")
        }
        .sheet(isPresented: $showingBackups) { BackupListView() }
        .allowsHitTesting(!store.isBusy)
        .interactiveDismissDisabled(store.isBusy)
    }

    private var reviewContent: some View {
        VStack(spacing: 0) {
            GameList {
                Section {
                    if isCopy { SaveFlowProgress(step: 1) }
                    GameAssetLabel(session.hasChanges ? "确认这 \(session.diffs.count) 项更改" : "当前更改已保存",
                                   assetName: "GameUIReview", iconSize: 28)
                        .font(.headline)
                    Text("\(session.draft.farmName) · \(session.draft.playerName)")
                        .font(.subheadline).foregroundStyle(AppTheme.secondary)
                    Text(isCopy ? "确认后会先备份并保存副本，再带你选择游戏目录。" : session.source.mode.saveExplanation)
                        .font(.subheadline)
                    if !session.hasChanges, let savedNotice {
                        Text(savedNotice).foregroundStyle(AppTheme.progress)
                            .accessibilityIdentifier("review.saved.notice")
                    } else if !session.hasChanges && isCopy {
                        Text("副本保存在本机，可直接继续导出。")
                            .foregroundStyle(AppTheme.secondary)
                            .accessibilityIdentifier("review.saved.notice")
                    }
                }
                if let message = session.draftValidationMessage {
                    Section("请先修正草稿") { Text(message).foregroundStyle(AppTheme.danger) }
                }
                if !session.metadata.warnings.isEmpty || !store.catalogWarnings.isEmpty {
                    Section("需要留意") {
                        ForEach(session.metadata.warnings + store.catalogWarnings, id: \.self) { warning in
                            GameLabel(warning, systemImage: "exclamationmark.triangle.fill")
                                .font(.subheadline).foregroundStyle(AppTheme.trackerWarning)
                        }
                    }
                }
                ForEach(groupedDiffs) { group in
                    Section(group.section) {
                        if group.section == "农场", let farmActionImpactSummary {
                            Text(farmActionImpactSummary).foregroundStyle(AppTheme.trackerWarning)
                            DisclosureGroup("核对全部处理对象（\(affectedFarmEntities.count)）") {
                                ForEach(affectedFarmEntities) { entity in
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(entity.label)
                                        Text(entity.coordinateDescription).font(.caption).foregroundStyle(AppTheme.secondary)
                                    }.accessibilityElement(children: .combine)
                                }
                            }
                        }
                        ForEach(group.diffs) { diff in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text(diff.label).font(.headline)
                                    Spacer()
                                    if diff.affectsSaveGameInfo {
                                        Text("同步摘要").font(.caption2).foregroundStyle(AppTheme.secondary)
                                    }
                                }
                                HStack(alignment: .firstTextBaseline) {
                                    Text(diff.oldValue).foregroundStyle(AppTheme.secondary)
                                    Image(systemName: "arrow.right").font(.caption).accessibilityHidden(true)
                                    Text(diff.newValue).foregroundStyle(AppTheme.ink)
                                }.font(.subheadline)
                                Button("撤销这项更改", systemImage: "arrow.uturn.backward") { session.revert(diff: diff) }
                                    .font(.caption).buttonStyle(.borderless)
                            }.padding(.vertical, 3)
                        }
                    }
                }
                Section {
                    DisclosureGroup("存档信息") {
                        LabeledContent("来源", value: session.source.farmIdentifier)
                        LabeledContent("游戏版本", value: session.metadata.gameVersion)
                        LabeledContent("访问模式", value: session.source.mode.displayName)
                        LabeledContent("主存档", value: session.metadata.mainEncoding.displayName)
                        if let encoding = session.metadata.infoEncoding {
                            LabeledContent("SaveGameInfo", value: encoding.displayName)
                        }
                    }
                    DisclosureGroup("备份与更多操作") {
                        Button("备份与恢复", systemImage: "clock.arrow.circlepath") { showingBackups = true }
                        Button("重新载入文件", systemImage: "arrow.clockwise") {
                            if session.hasChanges { showingReloadConfirmation = true } else { store.reload() }
                        }
                        Button("放弃全部更改", systemImage: "arrow.uturn.backward", role: .destructive) {
                            showingDiscardConfirmation = true
                        }.disabled(!session.hasChanges)
                    }.accessibilityIdentifier("review.more")
                }
            }
            SaveFlowActionBar {
                Button {
                    if isCopy {
                        if session.hasChanges { save(exportAfterwards: true) } else { showingExport = true }
                    } else { showingSaveConfirmation = true }
                } label: {
                    Text(isCopy ? (session.hasChanges ? "保存并导出" : "继续导出") : "备份并保存")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(GameButtonStyle(prominent: true))
                .disabled(session.draftValidationMessage != nil || (!isCopy && !session.hasChanges))
                .accessibilityIdentifier("review.primary")
                if isCopy && session.hasChanges {
                    Button("仅保存，稍后导出") { save(exportAfterwards: false) }
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .disabled(session.draftValidationMessage != nil)
                        .accessibilityIdentifier("review.save.later")
                }
            }
        }
        .navigationTitle("检查更改")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func save(exportAfterwards: Bool) {
        KeyboardReturnAction.dismiss()
        store.save(showSuccess: false) { success in
            guard success else { return }
            savedNotice = isCopy ? "已保存，待导出。稍后可从这里继续，退出应用也不会丢失。" : "已备份并保存，两份文件已通过校验。"
            if exportAfterwards { showingExport = true }
        }
    }

    private var affectedFarmEntities: [FarmEntity] {
        farmSnapshot?.affectedEntities(by: session.draft.farmActions) ?? []
    }

    private var farmActionImpactSummary: String? {
        let actions = session.draft.farmActions
        guard actions.hasChanges else { return nil }
        let entities = affectedFarmEntities
        let watered = entities.filter { $0.kind == .crop && $0.state == .dry }.count
        let removed = entities.count - watered
        return "预计浇水 \(watered) 格，清理 \(removed) 个对象（重叠选择已合并）"
    }

}

struct SavePairExportPicker: UIViewControllerRepresentable {
    let urls: [URL]
    let onExport: @MainActor () -> Void
    let onCancel: @MainActor () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onExport: onExport, onCancel: onCancel)
    }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let controller = UIDocumentPickerViewController(forExporting: urls, asCopy: true)
        controller.delegate = context.coordinator
        controller.shouldShowFileExtensions = true
        return controller
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    @MainActor
    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onExport: @MainActor () -> Void
        let onCancel: @MainActor () -> Void

        init(onExport: @escaping @MainActor () -> Void, onCancel: @escaping @MainActor () -> Void) {
            self.onExport = onExport
            self.onCancel = onCancel
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            onExport()
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            onCancel()
        }
    }
}
