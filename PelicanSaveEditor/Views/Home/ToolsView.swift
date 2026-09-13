import SwiftUI

private enum ToolsPresentation: Identifiable {
    case entry(EditorToolEntry)
    case calculator
    var id: String {
        switch self {
        case .entry(let entry): entry.id
        case .calculator: "calculator"
        }
    }
}

struct ToolsView: View {
    @Environment(EditorStore.self) private var store
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var showingSourceOptions = false
    @State private var sourceMethod: FarmLoadMethod?
    @State private var copiedURLs: [URL]?
    @State private var showingCopyImportPicker = false
    @State private var showingBackups = false
    @State private var showingSwitchConfirmation = false
    @State private var showingReloadConfirmation = false
    @State private var presentation: ToolsPresentation?
    @State private var category: EditorToolCategory = .common
    @State private var searchText = ""
    @FocusState private var searchFocused: Bool

    private var isSearching: Bool { !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    private var visibleEntries: [EditorToolEntry] { EditorToolEntry.visible(in: category, query: searchText) }
    private var toolColumns: [GridItem] {
        typeSize.isAccessibilitySize ? [GridItem(.flexible())] : [GridItem(.adaptive(minimum: 320), alignment: .top)]
    }

    var body: some View {
        VStack(spacing: 0) {
            LargePageHeader(title: "工具", artworkName: "GameUISkillMining", verticalPadding: 10, minimumHeight: 66)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let session = store.session {
                        connectedFarmCard(session)
                        toolDirectory
                    } else {
                        ToolRowButton(title: "加载农场",
                                      subtitle: "复制导入主存档与 SaveGameInfo 两个文件",
                                      systemImage: "doc.on.doc", iconColor: .green,
                                      artworkName: "GameUIBackpack") { showingSourceOptions = true }
                            .accessibilityIdentifier("farm.load.open")
                    }
                    if !isSearching {
                        managementTools
                        sectionTitle("辅助工具")
                        ToolRowButton(title: "农作物计算器", subtitle: "计算成熟日、收获次数与基础收益",
                                      systemImage: "calendar", iconColor: .purple,
                                      artworkName: "GameUICropPlanner") { presentation = .calculator }
                            .accessibilityIdentifier("tools.calculator")
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
                .readablePageWidth()
            }
            .scrollDismissesKeyboard(.interactively)
            .accessibilityIdentifier("editor.tools.list")
            .background(AppTheme.canvas)
            if let session = store.session {
                reviewFooter(session)
            }
        }
        .sheet(isPresented: $showingSourceOptions, onDismiss: openSelectedSourceMethod) {
            FarmLoadSheet(selection: $sourceMethod)
        }
        .sheet(isPresented: $showingCopyImportPicker, onDismiss: openCopiedSource) {
            CopyImportTwoFilePicker(
                onPick: { urls in
                    copiedURLs = urls
                    showingCopyImportPicker = false
                },
                onCancel: { copiedURLs = nil; showingCopyImportPicker = false }
            )
            .presentationDetents([.large])
        }
        .sheet(isPresented: $showingBackups) { BackupListView() }
        .alert("切换农场？", isPresented: $showingSwitchConfirmation) {
            Button("导入新农场", role: .destructive) { showingSourceOptions = true }
            Button("取消", role: .cancel) {}
        } message: {
            Text("成功导入新农场后才会替换当前会话。取消选择或导入失败会保留当前草稿。")
        }
        .alert("重新读取副本？", isPresented: $showingReloadConfirmation) {
            Button("放弃草稿并重新读取", role: .destructive) { store.reload() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("未保存的更改会被放弃，并重新读取应用内已保存的两份副本。如需读取游戏中的最新存档，请切换农场并重新导入。")
        }
        .fullScreenCover(item: $presentation) { destination in
            switch destination {
            case .calculator:
                CropCalculatorView(catalog: store.cropCatalog, session: store.session)
            case .entry(let entry):
                if let session = store.session {
                    editor(entry, session: session)
                } else {
                    GameEmptyState(title: "请先加载农场", systemImage: "externaldrive.badge.plus")
                }
            }
        }
    }

    private var toolDirectory: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("搜索修改功能，如金币、天气、工具", text: $searchText)
                    .font(.subheadline).focused($searchFocused)
                    .submitLabel(.search).onSubmit { searchFocused = false }
                    .accessibilityIdentifier("tools.search")
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                        searchFocused = false
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary).frame(minWidth: 44, minHeight: 44)
                    }
                    .accessibilityLabel("清除搜索").accessibilityIdentifier("tools.search.clear")
                }
            }
            .padding(.horizontal, 14).frame(minHeight: 52)
            .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 16))

            if !isSearching {
                LazyVGrid(columns: typeSize.isAccessibilitySize ? [GridItem(.flexible())]
                          : [GridItem(.adaptive(minimum: 96))], spacing: 8) {
                    ForEach(EditorToolCategory.allCases) { item in
                        Button {
                            category = item
                            searchFocused = false
                        } label: {
                            Text(item.title)
                                .font(.subheadline.weight(category == item ? .bold : .medium))
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, minHeight: 44)
                                .padding(.horizontal, 8)
                                .foregroundStyle(category == item ? AppTheme.title : .primary)
                                .background(category == item ? AppTheme.headerSoft : AppTheme.card,
                                            in: RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(category == item ? .isSelected : [])
                        .accessibilityIdentifier("tools.category.\(item.rawValue)")
                    }
                }
            }
            HStack {
                sectionTitle(isSearching ? "搜索结果" : category.title)
                Spacer()
                Text("\(visibleEntries.count) 项").font(.caption).foregroundStyle(.secondary)
            }
            if visibleEntries.isEmpty {
                ContentUnavailableView("没有找到相关功能", systemImage: "magnifyingglass",
                                       description: Text("试试「金币」「背包」「天气」等关键词。"))
                    .accessibilityIdentifier("tools.search.empty")
            } else {
                LazyVGrid(columns: toolColumns, alignment: .leading, spacing: 10) {
                    ForEach(visibleEntries) { entry in
                        ToolRowButton(title: entry.title, subtitle: entry.subtitle,
                                      systemImage: entry.symbol, iconColor: entry.tint,
                                      artworkName: entry.artworkName) {
                            searchFocused = false
                            presentation = .entry(entry)
                        }
                        .accessibilityIdentifier("editor.tool.\(entry.id)")
                    }
                }
            }
        }
    }

    private var managementTools: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("存档管理")
            ToolRowButton(title: "备份管理", subtitle: "创建备份、校验、导出与恢复",
                          systemImage: "book.closed.fill", iconColor: .brown,
                          artworkName: "GameUIBackup") { showingBackups = true }
                .accessibilityIdentifier("tools.backups")
            ToolRowButton(title: "重新读取与校验",
                          subtitle: store.session == nil ? "加载农场后可用" : "重新读取应用内副本；游戏新进度需重新导入",
                          systemImage: "checkmark.shield.fill", iconColor: .blue,
                          artworkName: "GameUIReview", disabled: store.session == nil) {
                if store.session?.hasChanges == true { showingReloadConfirmation = true }
                else { store.reload() }
            }
            .accessibilityIdentifier("tools.reload")
        }
    }

    private func connectedFarmCard(_ session: SaveSession) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 10) {
                GameAssetIcon(assetName: "AppLogo", size: 32)
                VStack(alignment: .leading, spacing: 4) {
                    Text(session.draft.farmName.isEmpty ? session.source.farmIdentifier : session.draft.farmName)
                        .font(.headline)
                    Text("\(session.draft.playerName) · 游戏 \(session.metadata.gameVersion)")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                if !typeSize.isAccessibilitySize { switchFarmButton(session) }
            }
            Text("导入副本 · 保存后导出两份文件并替换游戏存档")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if typeSize.isAccessibilitySize { switchFarmButton(session) }
        }
        .padding(12).appCard()
    }

    private func switchFarmButton(_ session: SaveSession) -> some View {
        Button(typeSize.isAccessibilitySize ? "切换农场" : "切换", systemImage: "arrow.left.arrow.right") {
            searchFocused = false
            if session.hasChanges { showingSwitchConfirmation = true }
            else { showingSourceOptions = true }
        }
        .font(.subheadline.weight(.semibold)).frame(minHeight: 44)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityLabel("切换农场")
        .accessibilityIdentifier("farm.load.switch")
    }

    private func reviewFooter(_ session: SaveSession) -> some View {
        Button {
            searchFocused = false
            presentation = .entry(.editor(.review))
        } label: {
            VStack(spacing: 4) {
                if typeSize.isAccessibilitySize {
                    Text("检查与保存").font(.headline)
                } else {
                    Label("检查与保存", systemImage: "checkmark.circle.fill").font(.headline)
                    Text(session.hasChanges ? "\(session.diffs.count) 项待保存 · 草稿在各分类间保留" : "查看存档、备份与导出")
                        .font(.caption)
                }
            }
            .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.borderedProminent).tint(AppTheme.accent)
        .accessibilityValue(typeSize.isAccessibilitySize
            ? "\(session.diffs.count) 项待保存，草稿在各分类间保留" : "")
        .accessibilityIdentifier("editor.tool.review")
        .padding(.horizontal, 20).padding(.vertical, 10)
        .readablePageWidth().background(.bar)
    }

    @ViewBuilder private func editor(_ entry: EditorToolEntry, session: SaveSession) -> some View {
        switch entry {
        case .editor(let section): EditorShellView(session: session, section: section)
        case .expanded(let tool): ExpandedEditorShell(session: session, tool: tool)
        case .map: FarmMapAnalysisView(session: session, cropCatalog: store.cropCatalog)
        }
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title).font(.headline).foregroundStyle(.secondary)
    }

    private func openSelectedSourceMethod() {
        let method = sourceMethod
        sourceMethod = nil
        // Preserve the established iPad dismissal ordering.
        if method == .copy { showingCopyImportPicker = true }
    }

    private func openCopiedSource() {
        let urls = copiedURLs
        copiedURLs = nil
        if let urls { store.openCopiedFiles(urls) }
    }
}
