import SwiftUI

struct BackupListView: View {
    @Environment(EditorStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var selectedBackup: BackupManifest?
    @State private var exportURLs: [URL] = []
    @State private var showingExporter = false
    @State private var exportNotice: String?
    @State private var verificationResults: [UUID: String] = [:]
    @State private var searchText = ""

    private var visibleBackups: [BackupManifest] {
        store.backups.filter {
            searchText.isEmpty || $0.farmIdentifier.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if let session = store.session {
                        LabeledContent("当前农场", value: session.source.farmIdentifier)
                        Button("立即备份当前文件", systemImage: "externaldrive.badge.plus") {
                            store.createManualBackup()
                        }
                        Text("手动备份保存磁盘上的文件，未保存草稿请先到检查页保存。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("无需加载农场即可校验和导出备份。加载对应农场后，还可以直接恢复。")
                            .font(.subheadline)
                    }
                    if let exportNotice { Text(exportNotice).font(.footnote) }
                    if let warning = store.backupWarning {
                        GameLabel(warning, systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote).foregroundStyle(.orange)
                    }
                } header: {
                    GameAssetLabel("备份管理", assetName: "GameUIBackup", iconSize: 26)
                }

                if visibleBackups.isEmpty {
                    GameEmptyState(
                        title: searchText.isEmpty ? "尚无应用备份" : "未找到这个农场的备份",
                        systemImage: "externaldrive"
                    )
                } else {
                    ForEach(visibleBackups) { backup in
                        Section {
                            HStack(alignment: .top, spacing: 12) {
                                GameAssetIcon(assetName: "GameUIBackup", size: 38)
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(backup.farmIdentifier).font(.headline)
                                    Text(backup.savedAt, format: .dateTime.year().month().day().hour().minute().second())
                                        .font(.subheadline)
                                    Text(backup.reason).font(.caption).foregroundStyle(.secondary)
                                    Text(verificationResults[backup.id] ??
                                         (store.verifiedBackupIDs.contains(backup.id) ? "完整性校验通过" : "尚未在本次会话校验"))
                                        .font(.caption)
                                        .foregroundStyle(store.verifiedBackupIDs.contains(backup.id) ? Color.green : Color.secondary)
                                }
                            }
                            .accessibilityElement(children: .combine)
                            if let sourceMode = backup.sourceMode {
                                LabeledContent("备份来源", value: sourceMode.displayName)
                            }
                            if let location = backup.sourceLocation, !location.isEmpty {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("来源位置").font(.caption).foregroundStyle(.secondary)
                                    Text(location).font(.caption).textSelection(.enabled)
                                }
                            }
                            if let isProtected = backup.isProtected {
                                GameLabel(
                                    isProtected ? "保护备份，不参与自动清理" : "自动备份，按保留策略管理",
                                    systemImage: isProtected ? "lock.shield.fill" : "clock.arrow.circlepath"
                                )
                                .font(.caption)
                            }
                            Button("校验备份", systemImage: "checkmark.shield.fill") {
                                store.verifyBackup(backup) { _, message in
                                    verificationResults[backup.id] = message
                                }
                            }
                            Button("导出备份文件", systemImage: "square.and.arrow.up") {
                                store.exportBackup(backup) { urls in
                                    guard let urls else { return }
                                    exportURLs = urls
                                    exportNotice = nil
                                    showingExporter = true
                                }
                            }
                            if store.session?.source.farmIdentifier == backup.farmIdentifier {
                                Button("恢复到当前农场", systemImage: "clock.arrow.circlepath", role: .destructive) {
                                    selectedBackup = backup
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("备份管理")
            .searchable(text: $searchText, prompt: "按农场名称筛选备份")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
        .onAppear { store.refreshBackups() }
        .disabled(store.isBusy)
        .interactiveDismissDisabled(store.isBusy)
        .sheet(isPresented: $showingExporter, onDismiss: {
            if exportNotice == nil { exportNotice = "导出尚未完成，应用内备份仍保留。" }
        }) {
            SavePairExportPicker(urls: exportURLs, onExport: {
                showingExporter = false
                exportNotice = "备份已导出。恢复游戏时请成对替换对应存档文件。"
            }, onCancel: {
                showingExporter = false
                exportNotice = "已取消导出，应用内备份仍保留。"
            })
        }
        .confirmationDialog("恢复这份备份？", isPresented: Binding(
            get: { selectedBackup != nil },
            set: { if !$0 { selectedBackup = nil } }
        )) {
            if let selectedBackup {
                Button("备份当前状态并恢复", role: .destructive) {
                    store.restore(selectedBackup)
                    self.selectedBackup = nil
                }
            }
            Button("取消", role: .cancel) { selectedBackup = nil }
        } message: {
            Text(store.session?.hasChanges == true
                 ? "恢复会放弃未保存草稿；恢复前会先备份磁盘上的当前文件。"
                 : "恢复前会先校验备份并备份磁盘上的当前文件。")
        }
        .operationFeedback()
    }
}
