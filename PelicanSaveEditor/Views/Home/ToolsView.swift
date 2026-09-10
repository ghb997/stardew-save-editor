import SwiftUI

private enum SaveUtilityTool: String, Identifiable {
    case cropCalculator
    case farmMapAnalysis

    var id: String { rawValue }
}

struct ToolsView: View {
    @Environment(EditorStore.self) private var store
    @State private var showingSourceOptions = false
    @State private var showingDirectoryPicker = false
    @State private var showingFilePicker = false
    @State private var showingCopyImportPicker = false
    @State private var selectedEditorSection: SaveEditorSection?
    @State private var showingBackups = false
    @State private var showingSwitchConfirmation = false
    @State private var showingReloadConfirmation = false
    @State private var selectedUtilityTool: SaveUtilityTool?

    var body: some View {
        VStack(spacing: 0) {
            LargePageHeader(title: "工具", artworkName: "GameUISkillMining")

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let session = store.session {
                        connectedFarmCard(session)

                        toolSectionTitle("存档修改")

                        if session.hasChanges {
                            GameLabel(
                                session.source.mode == .importedCopy
                                    ? "草稿会先保存到导入副本，再由系统文件界面导出替换"
                                    : "草稿会在各板块间保留，进入“检查与保存”后统一写回",
                                systemImage: "tray.full.fill"
                            )
                                .font(.footnote)
                                .foregroundStyle(.orange)
                                .padding(.horizontal, 4)
                        }

                        ForEach(SaveEditorSection.allCases) { section in
                            ToolRowButton(
                                title: section.title,
                                subtitle: editorSubtitle(for: section, session: session),
                                systemImage: section.systemImage,
                                iconColor: section.tint,
                                artworkName: section.artworkName
                            ) {
                                selectedEditorSection = section
                            }
                            .accessibilityIdentifier("editor.tool.\(section.rawValue)")
                        }
                    } else {
                        ToolRowButton(
                            title: "加载农场",
                            subtitle: "授权 Stardew Valley 文件夹并自动查找存档",
                            systemImage: "externaldrive.badge.plus",
                            iconColor: .green,
                            artworkName: "GameUIBackpack"
                        ) {
                            showingSourceOptions = true
                        }
                    }

                    toolSectionTitle("存档管理")

                    ToolRowButton(
                        title: "备份管理",
                        subtitle: "手动备份、完整性校验、导出与恢复",
                        systemImage: "book.closed.fill",
                        iconColor: .brown,
                        artworkName: "GameUIBackup"
                    ) {
                        showingBackups = true
                    }

                    ToolRowButton(
                        title: "重新读取与校验",
                        subtitle: store.session == nil ? "加载农场后可用" : "重新读取两份文件并检查兼容性",
                        systemImage: "checkmark.shield.fill",
                        iconColor: .blue,
                        artworkName: "GameUIReview",
                        disabled: store.session == nil
                    ) {
                        if store.session?.hasChanges == true {
                            showingReloadConfirmation = true
                        } else {
                            store.reload()
                        }
                    }

                    toolSectionTitle("扩展工具")

                    ToolRowButton(
                        title: "农作物计算器",
                        subtitle: "按 1.6 作物数据计算成熟日、收获次数、产量与基础收益",
                        systemImage: "calendar",
                        iconColor: .purple,
                        artworkName: "GameUICropPlanner"
                    ) {
                        selectedUtilityTool = .cropCalculator
                    }

                    ToolRowButton(
                        title: "魔法地图",
                        subtitle: store.session == nil
                            ? "加载农场后查看真实坐标并使用批量工具"
                            : "坐标地图、一键浇水、清除石块、杂草与树枝",
                        systemImage: "map.fill",
                        iconColor: .orange,
                        artworkName: "GameUIFarmComputer",
                        disabled: store.session == nil
                    ) {
                        selectedUtilityTool = .farmMapAnalysis
                    }
                    .accessibilityIdentifier("editor.tool.map")
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 24)
                .frame(maxWidth: 720)
                .frame(maxWidth: .infinity)
            }
            .accessibilityIdentifier("editor.tools.list")
            .background(AppTheme.canvas)
        }
        .confirmationDialog("加载农场", isPresented: $showingSourceOptions, titleVisibility: .visible) {
            if store.hasRecentSource {
                Button("打开上次农场") {
                    store.openRecent()
                }
            }
            Button("选择 Stardew Valley 或存档文件夹") {
                showingDirectoryPicker = true
            }
            Button("选择主存档与 SaveGameInfo（自签推荐）") {
                showingFilePicker = true
            }
            Button("复制导入两个文件（备用）") {
                showingCopyImportPicker = true
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("自签环境请优先选择主存档与 SaveGameInfo 原位写回；只有系统无法返回文件写入授权时，才使用复制导入并在保存后导出替换。")
        }
        .confirmationDialog("切换农场？", isPresented: $showingSwitchConfirmation, titleVisibility: .visible) {
            Button("选择新农场", role: .destructive) {
                showingSourceOptions = true
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("选择并成功加载新农场后才会替换当前会话。取消选择或加载失败会保留当前草稿。")
        }
        .confirmationDialog("重新读取存档？", isPresented: $showingReloadConfirmation, titleVisibility: .visible) {
            Button("放弃草稿并重新读取", role: .destructive) {
                store.reload()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("当前未保存的更改会被放弃，并从磁盘重新读取两份存档文件。")
        }
        .sheet(isPresented: $showingDirectoryPicker) {
            DirectoryPicker(
                onPick: { url in
                    showingDirectoryPicker = false
                    store.openDirectory(url)
                },
                onCancel: { showingDirectoryPicker = false }
            )
        }
        .sheet(isPresented: $showingFilePicker) {
            TwoFilePicker(
                onPick: { urls in
                    showingFilePicker = false
                    store.openFiles(urls)
                },
                onCancel: { showingFilePicker = false }
            )
        }
        .sheet(isPresented: $showingCopyImportPicker) {
            CopyImportTwoFilePicker(
                onPick: { urls in
                    showingCopyImportPicker = false
                    store.openCopiedFiles(urls)
                },
                onCancel: { showingCopyImportPicker = false }
            )
        }
        .sheet(
            isPresented: Binding(
                get: { !store.discoveredSaveSources.isEmpty },
                set: { if !$0 { store.dismissDiscoveredSaves() } }
            )
        ) {
            DiscoveredSaveSelectionView(
                sources: store.discoveredSaveSources,
                onSelect: store.openDiscoveredSave,
                onCancel: store.dismissDiscoveredSaves
            )
        }
        .sheet(isPresented: $showingBackups) {
            BackupListView()
        }
        .fullScreenCover(item: $selectedEditorSection) { section in
            if let session = store.session {
                EditorShellView(session: session, section: section)
            } else {
                GameEmptyState(title: "农场已卸载", systemImage: "externaldrive.badge.xmark")
            }
        }
        .fullScreenCover(item: $selectedUtilityTool) { tool in
            switch tool {
            case .cropCalculator:
                CropCalculatorView(catalog: store.cropCatalog, session: store.session)
            case .farmMapAnalysis:
                if let session = store.session {
                    FarmMapAnalysisView(session: session, cropCatalog: store.cropCatalog)
                } else {
                    GameEmptyState(title: "请先加载农场", systemImage: "externaldrive.badge.plus")
                }
            }
        }
    }

    private func connectedFarmCard(_ session: SaveSession) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                GameIcon(systemName: "leaf.circle.fill")
                    .font(.title)
                    .foregroundStyle(.green)
                VStack(alignment: .leading, spacing: 2) {
                    Text(session.draft.farmName.isEmpty ? session.source.farmIdentifier : session.draft.farmName)
                        .font(.headline)
                    Text("\(session.draft.playerName) · 游戏 \(session.metadata.gameVersion)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if session.hasChanges {
                    Text("\(session.diffs.count) 项待保存")
                        .font(.caption.bold())
                        .foregroundStyle(.orange)
                }
            }

            if session.source.mode == .importedCopy {
                GameLabel("复制导入副本 · 保存后需导出替换游戏文件", systemImage: "doc.on.doc.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.orange)
            }

            Button("切换农场", systemImage: "arrow.left.arrow.right") {
                if session.hasChanges {
                    showingSwitchConfirmation = true
                } else {
                    showingSourceOptions = true
                }
            }
            .font(.subheadline.weight(.semibold))
        }
        .padding(18)
        .background(AppTheme.headerSoft, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func editorSubtitle(for section: SaveEditorSection, session: SaveSession) -> String {
        switch section {
        case .character:
            return "名称、金钱、生命、体力与游戏日期"
        case .appearance:
            return "前后对照预览，以及 74 款发型、24 种肤色和 31 个饰品编号"
        case .farmhouse:
            return session.draft.farmhouse.hasEditableContent
                ? "农舍等级与 \(session.draft.farmhouse.decorations.count) 项房间装饰"
                : "检查农舍等级与可编辑的房间字段"
        case .inventory:
            return "\(session.draft.usableInventoryCount) 格背包 · 容量、物品搜索与槽位编辑"
        case .progress:
            return "齐钻、齐币、核桃、干草与矿洞进度"
        case .relationships:
            return "\(session.draft.friendships.count) 位角色 · 批量好感、送礼次数与关系"
        case .skills:
            return "精确经验、等级与 5/10 级职业分支"
        case .wallet:
            let unlocked = session.draft.progress.walletUnlocks.filter(\.isUnlocked).count
            return "管理 \(WalletUnlockKey.allCases.count) 项钱包能力，当前已获得 \(unlocked) 项"
        case .animals:
            return session.draft.animals.isEmpty
                ? "检查标准动物节点；当前存档未发现可编辑动物"
                : "编辑 \(session.draft.animals.count) 只动物的名称与状态"
        case .recipes:
            let unlocked = session.draft.recipes.filter(\.unlocked).count
            return "已解锁 \(unlocked) / \(session.draft.recipes.count) 项配方"
        case .review:
            return session.hasChanges
                ? "查看 \(session.diffs.count) 项草稿，统一备份并保存"
                : "查看来源、备份与保存状态"
        }
    }

    private func toolSectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.headline)
            .foregroundStyle(.secondary)
            .padding(.top, 10)
            .padding(.horizontal, 4)
    }
}

private struct DiscoveredSaveSelectionView: View {
    @Environment(\.dismiss) private var dismiss
    let sources: [SaveSource]
    let onSelect: @MainActor (SaveSource) -> Void
    let onCancel: @MainActor () -> Void

    var body: some View {
        NavigationStack {
            List(sources, id: \.farmIdentifier) { source in
                Button {
                    onSelect(source)
                    dismiss()
                } label: {
                    HStack(spacing: 14) {
                        GameIcon(systemName: "leaf.circle.fill", size: 28)
                            .font(.title2)
                            .foregroundStyle(.green)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(source.farmIdentifier)
                                .font(.headline)
                            Text("包含主存档与 SaveGameInfo")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
            }
            .navigationTitle("选择游戏存档")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        onCancel()
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
