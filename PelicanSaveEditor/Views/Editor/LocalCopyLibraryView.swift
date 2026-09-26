import SwiftUI

struct LocalCopyLibraryView: View {
    @Environment(EditorStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Binding var selection: LocalCopyRecord?
    @State private var deleting: LocalCopyRecord?

    var body: some View {
        NavigationStack {
            GameList {
                Section {
                    Text("已保存副本和暂存草稿保存在本机，退出应用后可从这里继续。卸载应用会删除这些数据，请及时导出。")
                        .font(.subheadline)
                    LabeledContent("本地占用", value: ByteCountFormatter.string(
                        fromByteCount: store.localCopies.reduce(0) { $0 + $1.byteCount }, countStyle: .file))
                    if let warning = store.libraryWarning {
                        Text(warning).font(.footnote).foregroundStyle(AppTheme.trackerWarning)
                    }
                }
                if store.localCopies.isEmpty {
                    GameEmptyState(title: "尚无本地副本", systemImage: "doc.on.doc")
                }
                ForEach(store.localCopies) { copy in
                    Section {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(copy.farmName.isEmpty ? copy.farmIdentifier : copy.farmName).font(.headline)
                            Text("\(copy.playerName) · \(copy.gameDate)").font(.subheadline)
                        Text(copy.status).font(.caption).foregroundStyle(AppTheme.accent)
                        }
                        if let problem = copy.problem { Text(problem).font(.footnote).foregroundStyle(AppTheme.trackerWarning) }
                        LabeledContent("最近保存", value: copy.savedAt.formatted(date: .abbreviated, time: .shortened))
                        LabeledContent("导入时间", value: copy.importedAt.formatted(date: .abbreviated, time: .shortened))
                        LabeledContent("占用空间", value: ByteCountFormatter.string(fromByteCount: copy.byteCount, countStyle: .file))
                        Button("打开这份副本", systemImage: "folder") {
                            selection = copy; dismiss()
                        }
                        .accessibilityIdentifier("library.open.\(copy.id)")
                        .disabled(copy.problem != nil)
                        Button(copy.isFailedImport ? "删除失败的导入" : "删除副本", systemImage: "trash", role: .destructive) { deleting = copy }
                            .disabled((copy.needsExport && !copy.isFailedImport) || copy.hasDraft || isCurrent(copy))
                        if copy.needsExport || copy.hasDraft || isCurrent(copy) {
                            Text("当前打开、待导出或含草稿的副本受保护。关闭当前副本并完成导出、处理草稿后可删除。")
                                .font(.caption).foregroundStyle(AppTheme.secondary)
                        }
                    }
                }
                Section {
                    Button("清理临时导出缓存", systemImage: "trash.slash") { store.cleanExportCache() }
                    Text("只清理可重新生成的临时文件，保留副本、草稿和备份。导出窗口关闭后也会自动清理。")
                        .font(.caption).foregroundStyle(AppTheme.secondary)
                }
            }
            .navigationTitle("本地副本")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        }
        .onAppear { store.refreshLocalCopies() }
        .alert("删除这份本地副本？", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("删除", role: .destructive) { if let deleting { store.deleteLocalCopy(deleting) }; deleting = nil }
            Button("取消", role: .cancel) { deleting = nil }
        } message: { Text("副本将从本机删除，应用备份和已导出的文件不受影响。") }
        .disabled(store.isBusy).interactiveDismissDisabled(store.isBusy)
        .operationFeedback()
    }

    private func isCurrent(_ copy: LocalCopyRecord) -> Bool {
        store.session?.source.mode == .importedCopy && store.session?.source.mainURL.deletingLastPathComponent().lastPathComponent == copy.id
    }
}
