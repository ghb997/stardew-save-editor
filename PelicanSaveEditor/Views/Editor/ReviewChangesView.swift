import SwiftUI
import UIKit

struct ReviewChangesView: View {
    @Environment(EditorStore.self) private var store
    @Bindable var session: SaveSession
    @State private var showingSaveConfirmation = false
    @State private var showingDiscardConfirmation = false
    @State private var showingReloadConfirmation = false
    @State private var showingBackups = false
    @State private var showingExportPicker = false
    @State private var exportNotice: String?
    private var farmSnapshot: FarmSnapshot? { session.farmSnapshot }

    private var groupedDiffs: [SaveDiffGroup] {
        SaveDiffBuilder.grouped(session.diffs)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent("农场", value: session.source.farmIdentifier)
                    LabeledContent("游戏版本", value: session.metadata.gameVersion)
                    LabeledContent("主存档", value: session.metadata.mainEncoding.displayName)
                    if let infoEncoding = session.metadata.infoEncoding {
                        LabeledContent("SaveGameInfo", value: infoEncoding.displayName)
                    }
                    LabeledContent("访问模式", value: session.source.mode.displayName)
                    if session.source.mode == .importedCopy {
                        GameLabel("这是应用内副本，不会直接覆盖游戏存档", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                } header: {
                    GameAssetLabel("当前来源", assetName: "GameUIBackpack", iconSize: 24)
                }

                Section {
                    Text(session.source.mode.saveExplanation)
                        .font(.subheadline)
                    if session.metadata.warnings.isEmpty {
                        GameLabel("未发现兼容性警告", systemImage: "checkmark.shield.fill")
                    } else {
                        ForEach(session.metadata.warnings, id: \.self) { warning in
                            GameLabel(warning, systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                        }
                    }
                    ForEach(store.catalogWarnings, id: \.self) { warning in
                        GameLabel(warning, systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    }
                } header: {
                    GameAssetLabel("兼容性与写入范围", assetName: "GameUIReview", iconSize: 24)
                }

                if let exportNotice {
                    Section("导出状态") {
                        Text(exportNotice)
                    }
                }
                if let message = session.draftValidationMessage {
                    Section("请先修正草稿") {
                        Text(message).foregroundStyle(.red)
                    }
                }

                if groupedDiffs.isEmpty {
                    Section {
                        GameLabel("没有待保存的更改", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                } else {
                    ForEach(groupedDiffs) { group in
                        Section(group.section) {
                            if group.section == "农场", let farmActionImpactSummary {
                                GameLabel(farmActionImpactSummary, systemImage: "wand.and.stars")
                                    .font(.subheadline)
                                    .foregroundStyle(.orange)
                                DisclosureGroup("核对全部处理对象（\(affectedFarmEntities.count)）") {
                                    ForEach(affectedFarmEntities) { entity in
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(entity.label)
                                            Text(entity.coordinateDescription)
                                                .font(.caption.monospacedDigit())
                                                .foregroundStyle(.secondary)
                                        }
                                        .accessibilityElement(children: .combine)
                                    }
                                }
                            }

                            ForEach(group.diffs) { diff in
                                VStack(alignment: .leading, spacing: 5) {
                                    HStack {
                                        Text(diff.label).font(.headline)
                                        Spacer()
                                        if diff.affectsSaveGameInfo {
                                            Text("同步摘要")
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    HStack(alignment: .firstTextBaseline) {
                                        Text(diff.oldValue)
                                            .foregroundStyle(.secondary)
                                        GameIcon(systemName: "arrow.right", size: 14)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        Text(diff.newValue)
                                            .foregroundStyle(.primary)
                                    }
                                    .font(.subheadline)
                                    Button("撤销这项更改", systemImage: "arrow.uturn.backward") {
                                        session.revert(diff: diff)
                                    }
                                    .font(.caption)
                                    .buttonStyle(.borderless)
                                }
                                .padding(.vertical, 3)
                            }
                        }
                    }
                }

                Section {
                    Button {
                        showingSaveConfirmation = true
                    } label: {
                        GameLabel(
                            session.source.mode == .importedCopy ? "保存副本并导出" : "自动备份并保存",
                            systemImage: session.source.mode == .importedCopy
                                ? "square.and.arrow.up.fill"
                                : "externaldrive.badge.checkmark"
                        )
                    }
                    .disabled(!session.hasChanges || session.draftValidationMessage != nil)

                    if session.source.mode == .importedCopy {
                        Button("再次导出已保存副本", systemImage: "square.and.arrow.up") {
                            exportNotice = nil
                            showingExportPicker = true
                        }
                        .disabled(session.hasChanges)
                    }

                    Button("放弃全部更改", systemImage: "arrow.uturn.backward", role: .destructive) {
                        showingDiscardConfirmation = true
                    }
                    .disabled(!session.hasChanges)

                    Button("备份与恢复", systemImage: "clock.arrow.circlepath") {
                        showingBackups = true
                    }

                    Button("重新载入文件", systemImage: "arrow.clockwise") {
                        if session.hasChanges {
                            showingReloadConfirmation = true
                        } else {
                            store.reload()
                        }
                    }
                } header: {
                    GameAssetLabel("操作", assetName: "GameUIReview", iconSize: 24)
                } footer: {
                    Text(
                        session.source.mode == .importedCopy
                            ? "应用先自动备份并保存，再打开系统文件界面。请选择游戏原农场目录，并确认替换主存档与 SaveGameInfo。"
                            : "保存前会创建私有备份，并确认两份文件在编辑期间没有被其他应用修改。"
                    )
                }
            }
            .navigationTitle("检查更改")
            .navigationBarTitleDisplayMode(.inline)
        }
        .alert(
            session.source.mode == .importedCopy ? "保存副本并导出？" : "确认写回存档？",
            isPresented: $showingSaveConfirmation
        ) {
            if session.source.mode == .importedCopy {
                Button("保存并选择原存档目录") {
                    saveAndPresentExporter()
                }
                Button("仅保存到应用副本") {
                    store.save()
                }
            } else {
                Button("自动备份并保存") {
                    store.save()
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text(saveConfirmationMessage)
        }
        .alert("放弃全部更改？", isPresented: $showingDiscardConfirmation) {
            Button("放弃", role: .destructive) { session.discardChanges() }
            Button("取消", role: .cancel) {}
        }
        .alert("重新载入存档？", isPresented: $showingReloadConfirmation) {
            Button("放弃草稿并重新载入", role: .destructive) { store.reload() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("当前未保存的更改会被放弃，并从磁盘重新读取两份存档文件。")
        }
        .sheet(isPresented: $showingBackups) {
            BackupListView()
        }
        .sheet(isPresented: $showingExportPicker, onDismiss: {
            if exportNotice == nil {
                exportNotice = "应用内副本已保存，导出尚未完成。可再次导出继续。"
            }
        }) {
            SavePairExportPicker(
                urls: exportURLs,
                onExport: {
                    showingExportPicker = false
                    exportNotice = "已完成导出。请确认目标目录中的同名文件已替换，再启动游戏。"
                },
                onCancel: {
                    showingExportPicker = false
                    exportNotice = "已保存应用内副本，尚未完成导出。可点“再次导出已保存副本”继续。"
                }
            )
        }
        .disabled(store.isBusy)
        .interactiveDismissDisabled(store.isBusy)
    }

    private var exportURLs: [URL] {
        [session.source.mainURL] + [session.source.infoURL].compactMap { $0 }
    }

    private func saveAndPresentExporter() {
        exportNotice = nil
        store.save(showSuccess: false) { success in
            guard success else { return }
            showingExportPicker = true
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

    private var saveConfirmationMessage: String {
        let base = session.source.mode == .importedCopy
            ? "应用会先备份、保存并校验导入副本，然后打开系统文件界面。请选择游戏原农场目录并确认替换两个同名文件。"
            : "应用会先备份两份原文件，再写入并重新读取校验。操作时请确保游戏已完全退出。"
        guard let farmActionImpactSummary else { return base }
        return "\(farmActionImpactSummary)。\n\n\(base)"
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
