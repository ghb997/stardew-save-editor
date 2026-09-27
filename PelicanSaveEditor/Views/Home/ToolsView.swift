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
    @State private var copyImportFlow = CopyImportPresentationFlow()
    @State private var showingCopyImportPicker = false
    @State private var showingBackups = false
    @State private var showingLibrary = false
    @State private var selectedCopy: LocalCopyRecord?
    @State private var showingSwitchConfirmation = false
    @State private var showingReloadConfirmation = false
    @State private var presentation: ToolsPresentation?
    @State private var category: EditorToolCategory = .common
    @State private var searchText = ""
    @State private var showingDirectory = false
    @FocusState private var searchFocused: Bool

    private var isSearching: Bool { !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    private var visibleEntries: [EditorToolEntry] { EditorToolEntry.visible(in: category, query: searchText) }
    private var toolColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 0, alignment: .top),
              count: typeSize.isAccessibilitySize ? 1 : 2)
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    journalHeader
                    if let session = store.session {
                        connectedFarmCard(session)
                        toolDirectory
                    } else {
                        ToolRowButton(title: "加载农场",
                                      subtitle: "复制导入主存档与 SaveGameInfo 两个文件",
                                      systemImage: "doc.on.doc", iconColor: .green,
                                      artworkName: "GameUIBackpack") { showingSourceOptions = true }
                            .accessibilityIdentifier("farm.load.open")
                        if let recent = store.localCopies.first {
                            ToolRowButton(title: "继续上次副本", subtitle: "\(recent.farmName) · \(recent.status)",
                                          systemImage: "clock.arrow.circlepath", iconColor: .brown,
                                          artworkName: "GameUIBackup") { store.openLocalCopy(recent) }
                                .accessibilityIdentifier("library.continue")
                        }
                    }
                    if !isSearching {
                        managementTools
                        if showingDirectory || store.session == nil {
                            JournalActionRow(title: "农作物计算器", subtitle: "成熟日、收获次数与收益",
                                             systemImage: "calendar") { presentation = .calculator }
                                .accessibilityIdentifier("tools.calculator")
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 12)
                .readablePageWidth(760)
            }
            .scrollDismissesKeyboard(.interactively)
            .accessibilityIdentifier("editor.tools.list")
            .background(GamePageBackdrop())
            if let session = store.session {
                reviewFooter(session)
            }
        }
        .sheet(isPresented: $showingSourceOptions, onDismiss: openSelectedSourceMethod) {
            FarmLoadSheet(selection: $sourceMethod)
        }
        .sheet(isPresented: $showingCopyImportPicker, onDismiss: finishCopyImportDismissal) {
            CopyImportTwoFilePicker(
                onPick: { urls in
                    openCopiedSource(copyImportFlow.selected(urls))
                    showingCopyImportPicker = false
                },
                onCancel: {
                    copyImportFlow.cancelled()
                    showingCopyImportPicker = false
                }
            )
            .presentationDetents([.large])
        }
        .sheet(isPresented: $showingBackups) { BackupListView() }
        .sheet(isPresented: $showingLibrary, onDismiss: {
            if let selectedCopy { store.openLocalCopy(selectedCopy) }
            selectedCopy = nil
        }) { LocalCopyLibraryView(selection: $selectedCopy) }
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

    private var journalHeader: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .center, spacing: 8) {
                Text("工具").font(.largeTitle.bold())
                if let sprig = GameArtwork.itemImage(id: "251") {
                    Image(uiImage: sprig).resizable().interpolation(.none).scaledToFit()
                        .frame(width: 26, height: 30).accessibilityHidden(true)
                }
                Spacer(minLength: 8)
                if store.session != nil {
                    Button {
                        showingDirectory = true
                        searchFocused = true
                    } label: {
                        Image(systemName: "magnifyingglass")
                            .font(.title2.weight(.regular))
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel("搜索功能")
                    .accessibilityIdentifier("tools.search.open")
                }
            }
            Text("让你的星露谷存档更自由")
                .font(.subheadline).foregroundStyle(AppTheme.secondary)
                .fixedSize(horizontal: false, vertical: true)
            // Keep the whole illustration at its native aspect ratio. Only the
            // generated image's transparent top/bottom padding falls outside.
            Color.clear.aspectRatio(7, contentMode: .fit)
                .overlay {
                    GeometryReader { geometry in
                        Image("JournalFarmBanner")
                            .resizable().interpolation(.none).scaledToFit()
                            .frame(width: geometry.size.width,
                                   height: geometry.size.width * 718 / 2188)
                            .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
                    }
                }
                // Clipping trims pixels, but does not trim SwiftUI hit testing.
                // Transparent illustration padding must never cover nearby controls.
                .clipped().allowsHitTesting(false).accessibilityHidden(true)
                .padding(.horizontal, -20).padding(.top, 6)
        }
    }

    private var toolDirectory: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                sectionTitle(showingDirectory ? "全部功能" : "常用工具")
                Spacer(minLength: 8)
                Button {
                    showingDirectory.toggle()
                    if !showingDirectory {
                        category = .common
                        searchText = ""
                        searchFocused = false
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(showingDirectory ? "收起" : "全部功能")
                        Image(systemName: showingDirectory ? "chevron.up" : "arrow.right")
                    }
                    .font(.subheadline).frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .accessibilityIdentifier("tools.directory.toggle")
                .accessibilityValue(showingDirectory ? "已展开" : "已收起")
            }
            if showingDirectory { directoryFilters }
            if visibleEntries.isEmpty {
                ContentUnavailableView("没有找到相关功能", systemImage: "magnifyingglass",
                                       description: Text("试试「金币」「背包」「天气」等关键词。"))
                    .accessibilityIdentifier("tools.search.empty")
            } else {
                LazyVGrid(columns: toolColumns, alignment: .leading, spacing: 0) {
                    ForEach(Array(visibleEntries.enumerated()), id: \.element.id) { index, entry in
                        JournalToolButton(entry: entry) {
                            searchFocused = false
                            presentation = .entry(entry)
                        }
                        .overlay(alignment: .trailing) {
                            if !typeSize.isAccessibilitySize && index.isMultiple(of: 2) {
                                Rectangle().fill(AppTheme.border).frame(width: 0.5)
                                    .allowsHitTesting(false)
                            }
                        }
                        .overlay(alignment: .bottom) {
                            if index < visibleEntries.count - (typeSize.isAccessibilitySize ? 1 : 2) {
                                Rectangle().fill(AppTheme.border).frame(height: 0.5)
                                    .allowsHitTesting(false)
                            }
                        }
                        .accessibilityIdentifier("editor.tool.\(entry.id)")
                    }
                }
            }
        }
    }


    private var directoryFilters: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(AppTheme.secondary)
                TextField("搜索修改功能，如金币、天气、工具", text: $searchText,
                          prompt: Text("搜索修改功能，如金币、天气、工具").foregroundStyle(AppTheme.secondary))
                    .font(.subheadline).focused($searchFocused)
                    .submitLabel(.search).onSubmit { searchFocused = false }
                    .accessibilityIdentifier("tools.search")
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                        searchFocused = false
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(AppTheme.secondary).frame(minWidth: 44, minHeight: 44)
                    }
                    .accessibilityLabel("清除搜索").accessibilityIdentifier("tools.search.clear")
                }
            }
            .padding(.horizontal, 14).frame(minHeight: 48)
            .gameInset(AppTheme.inset)

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
                                .foregroundStyle(category == item ? AppTheme.title : AppTheme.ink)
                                .background(GameInset(fill: category == item ? AppTheme.selection : AppTheme.card))
                                .overlay(alignment: .bottom) {
                                    if category == item {
                                        Rectangle().fill(AppTheme.accent).frame(height: 3).padding(.horizontal, 8)
                                            .allowsHitTesting(false)
                                    }
                                }
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(category == item ? .isSelected : [])
                        .accessibilityIdentifier("tools.category.\(item.rawValue)")
                    }
                }
            }
            HStack {
                Text(isSearching ? "搜索结果" : category.title)
                    .font(.caption).foregroundStyle(AppTheme.secondary)
                Spacer()
                Text("\(visibleEntries.count) 项").font(.caption).foregroundStyle(AppTheme.secondary)
            }
        }
    }

    private var managementTools: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                sectionTitle("存档管理")
                Spacer()
                if store.session != nil {
                    Menu {
                        Button("重新读取与校验", systemImage: "arrow.clockwise") {
                            if store.session?.hasChanges == true { showingReloadConfirmation = true }
                            else { store.reload() }
                        }
                        .accessibilityIdentifier("tools.reload")
                        Button("关闭当前副本（保留草稿）", systemImage: "xmark.circle") { store.closeSession() }
                            .accessibilityIdentifier("library.close")
                    } label: {
                        Label("更多", systemImage: "ellipsis").font(.subheadline).frame(minHeight: 44)
                    }
                    .accessibilityIdentifier("tools.management.more")
                }
            }
            JournalActionRow(title: "本地副本", subtitle: "导入副本 · 保存后导出两份文件",
                             systemImage: "doc.on.doc") { showingLibrary = true }
                .accessibilityIdentifier("tools.library")
            Divider().overlay(AppTheme.border)
            JournalActionRow(title: "备份管理", subtitle: "管理历史存档 · 恢复与替换",
                             systemImage: "folder") { showingBackups = true }
                .accessibilityIdentifier("tools.backups")
        }
    }

    private func connectedFarmCard(_ session: SaveSession) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(session.draft.farmName.isEmpty ? session.source.farmIdentifier : session.draft.farmName)
                        .font(.title2.bold()).fixedSize(horizontal: false, vertical: true)
                    Text("\(session.draft.playerName) · 第\(session.draft.year)年 \(session.draft.season.displayName)季\(session.draft.day)日")
                        .font(.caption).foregroundStyle(AppTheme.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                if !typeSize.isAccessibilitySize { switchFarmButton(session) }
            }
            if let status = store.draftStorageMessage {
                Text(status).font(.caption).foregroundStyle(AppTheme.secondary)
                    .accessibilityIdentifier("draft.storage.status")
            }
            if typeSize.isAccessibilitySize { switchFarmButton(session) }
        }
        .padding(.bottom, 10)
        .overlay(alignment: .bottom) { Rectangle().fill(AppTheme.accent.opacity(0.6)).frame(height: 1) }
    }

    private func switchFarmButton(_ session: SaveSession) -> some View {
        Button("切换农场", systemImage: "arrow.left.arrow.right") {
            searchFocused = false
            if session.hasChanges { showingSwitchConfirmation = true }
            else { showingSourceOptions = true }
        }
        .font(.caption.weight(.medium)).frame(minHeight: 44)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityLabel("切换农场")
        .accessibilityIdentifier("farm.load.switch")
    }

    private func reviewFooter(_ session: SaveSession) -> some View {
        Button {
            searchFocused = false
            presentation = .entry(.editor(.review))
        } label: {
            Text(typeSize.isAccessibilitySize || !session.hasChanges ? "检查与保存"
                 : "检查与保存 · \(session.diffs.count) 项待保存")
                .font(.headline)
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, minHeight: 32)
        }
        .buttonStyle(GameButtonStyle(prominent: true)).tint(AppTheme.accent)
        .accessibilityValue(typeSize.isAccessibilitySize
            ? "\(session.diffs.count) 项待保存，草稿在各分类间保留" : "")
        .accessibilityIdentifier("editor.tool.review")
        .padding(.horizontal, 20).padding(.vertical, 10)
        .readablePageWidth(760).gameBar()
    }

    @ViewBuilder private func editor(_ entry: EditorToolEntry, session: SaveSession) -> some View {
        switch entry {
        case .editor(let section): EditorShellView(session: session, section: section)
        case .expanded(let tool): ExpandedEditorShell(session: session, tool: tool)
        case .map: FarmMapAnalysisView(session: session, cropCatalog: store.cropCatalog)
        }
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title).font(.title3.bold()).foregroundStyle(AppTheme.ink)
    }

    private func openSelectedSourceMethod() {
        let method = sourceMethod
        sourceMethod = nil
        // Preserve the established iPad dismissal ordering.
        if method == .copy {
            copyImportFlow.begin()
            showingCopyImportPicker = true
        }
    }

    private func finishCopyImportDismissal() {
        openCopiedSource(copyImportFlow.dismissed())
    }

    private func openCopiedSource(_ urls: [URL]?) {
        if let urls { store.openCopiedFiles(urls) }
    }
}
