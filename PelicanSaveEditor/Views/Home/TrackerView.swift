import SwiftUI

struct TrackerView: View {
    @Environment(EditorStore.self) private var store
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Binding var selectedTab: MainTab
    @State private var selectedSection: SaveEditorSection?
    @State private var selectedFilter: TrackerFilter = .overview
    @State private var expandedGroups: Set<TrackerGroup> = Set(TrackerGroup.allCases)

    var body: some View {
        VStack(spacing: 0) {
            LargePageHeader(
                title: "农场追踪", artworkName: "GameUITrophy",
                headerColor: AppTheme.trackerHeader, titleColor: AppTheme.trackerTitle,
                verticalPadding: 12, minimumHeight: 82
            )

            if store.session != nil {
                trackerFilterStrip
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(AppTheme.canvas)
            }

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        if let session = store.session {
                            if selectedFilter == .overview {
                                trackerFarmCard(session)
                            }
                            ForEach(TrackerGroup.allCases.filter { selectedFilter.includes($0) }) { group in
                                trackerGroupPanel(group, session: session)
                            }
                        } else {
                            unloadedTracker
                        }
                    }
                    .id("tracker.top")
                    .padding(.horizontal, 16)
                    .padding(.vertical, 16)
                    .padding(.bottom, 20)
                    .frame(maxWidth: 720)
                    .frame(maxWidth: .infinity)
                }
                .background(AppTheme.canvas)
                .onChange(of: selectedFilter) { _, _ in
                    proxy.scrollTo("tracker.top", anchor: .top)
                }
            }
        }
        .fullScreenCover(item: $selectedSection) { section in
            if let session = store.session {
                TrackerDetailView(session: session, section: section)
            } else {
                GameEmptyState(title: "农场已卸载", systemImage: "externaldrive.badge.xmark")
            }
        }
#if DEBUG
        .onChange(of: store.session != nil, initial: true) { _, loaded in
            let arguments = ProcessInfo.processInfo.arguments
            guard loaded, arguments.contains("--ui-demo"),
                  let index = arguments.firstIndex(of: "--ui-tracker-section"),
                  arguments.indices.contains(index + 1),
                  let section = SaveEditorSection(rawValue: arguments[index + 1]) else { return }
            selectedSection = section
        }
#endif
    }

    private func trackerFarmCard(_ session: SaveSession) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            farmHeaderLayout {
                GameAssetIcon(assetName: "GameUIFarmhouse", size: 42)
                    .padding(5)
                    .background(Color(.tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 16))

                VStack(alignment: .leading, spacing: 4) {
                    Text(session.draft.farmName.isEmpty ? session.source.farmIdentifier : session.draft.farmName)
                        .font(.title2.bold())
                        .fixedSize(horizontal: false, vertical: true)
                    Text(session.draft.playerName.isEmpty ? "未命名农夫" : session.draft.playerName)
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.trackerTitle.opacity(0.80))
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Label("只读", systemImage: "eye.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.trackerAccent)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(Color(.systemBackground).opacity(0.72), in: Capsule())
            }

            Divider()
                .overlay(AppTheme.trackerTitle.opacity(0.16))

            LazyVGrid(columns: summaryColumns, spacing: 16) {
                TrackerSummaryMetric(
                    value: "\(session.draft.season.displayName) \(session.draft.day)日",
                    label: "第 \(session.draft.year) 年",
                    artworkName: "GameUITrophy"
                )
                TrackerSummaryMetric(
                    value: trackerCollectionFootprint(session).formatted(),
                    label: "四类收藏合计",
                    artworkName: "GameUIReview"
                )
                TrackerSummaryMetric(
                    value: "\(session.draft.recipes.filter(\.unlocked).count)/\(session.draft.recipes.count)",
                    label: "配方解锁",
                    artworkName: "GameUIRecipes"
                )
            }

            if session.hasChanges {
                Label("正在预览 \(session.diffs.count) 项未保存草稿", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.trackerWarning)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .foregroundStyle(AppTheme.trackerTitle)
        .padding(16)
        .background(AppTheme.trackerHeaderSoft, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(AppTheme.trackerAccent.opacity(0.14), lineWidth: 1)
        }
        .accessibilityIdentifier("tracker.farmSummary")
    }

    private var farmHeaderLayout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 14))
    }

    private var summaryColumns: [GridItem] {
        Array(repeating: GridItem(.flexible()), count: dynamicTypeSize.isAccessibilitySize ? 1 : 3)
    }

    private var trackerFilterStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(TrackerFilter.allCases) { filter in
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedFilter = filter
                            if let group = filter.group {
                                expandedGroups.insert(group)
                            }
                        }
                    } label: {
                        Text(filter.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(selectedFilter == filter ? AppTheme.trackerTitle : Color.primary)
                            .padding(.horizontal, 17)
                            .frame(minHeight: 44)
                            .background(
                                selectedFilter == filter ? AppTheme.trackerSelection : Color(.tertiarySystemFill),
                                in: Capsule()
                            )
                            .overlay {
                                Capsule()
                                    .stroke(
                                        selectedFilter == filter ? AppTheme.trackerAccent.opacity(0.12) : Color(.separator).opacity(0.42),
                                        lineWidth: 1
                                    )
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selectedFilter == filter ? .isSelected : [])
                    .accessibilityIdentifier("tracker.filter.\(filter.rawValue)")
                }
            }
            .padding(.vertical, 1)
        }
    }

    private func trackerGroupPanel(_ group: TrackerGroup, session: SaveSession) -> some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.22)) {
                    if expandedGroups.contains(group) {
                        expandedGroups.remove(group)
                    } else {
                        expandedGroups.insert(group)
                    }
                }
            } label: {
                HStack(spacing: 12) {
                    GameAssetIcon(assetName: group.artworkName, size: 34)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(group.title)
                            .font(.headline)
                        Text(group.subtitle)
                            .font(.caption)
                            .foregroundStyle(AppTheme.trackerSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    Text("\(group.sections.count)")
                        .font(.caption.monospacedDigit().weight(.semibold))
                        .foregroundStyle(AppTheme.trackerSecondary)
                    Image(systemName: expandedGroups.contains(group) ? "chevron.up" : "chevron.down")
                        .font(.caption.bold())
                        .foregroundStyle(AppTheme.trackerSecondary)
                }
                .foregroundStyle(.primary)
                .padding(.horizontal, 18)
                .padding(.vertical, 16)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(expandedGroups.contains(group) ? "已展开" : "已折叠")
            .accessibilityHint("双击展开或折叠\(group.title)")
            .accessibilityIdentifier("tracker.group.\(group.rawValue)")

            if expandedGroups.contains(group) {
                Divider()

                VStack(spacing: 11) {
                    ForEach(group.sections) { section in
                        trackerSectionRow(section, session: session)
                    }
                }
                .padding(14)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color(.separator).opacity(0.38), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private func trackerSectionRow(_ section: SaveEditorSection, session: SaveSession) -> some View {
        Button {
            selectedSection = section
        } label: {
            HStack(alignment: .top, spacing: 12) {
                TrackerSectionArtwork(section: section, size: 44)
                    .frame(width: 52, height: 52)
                    .background(Color(.systemBackground).opacity(0.78), in: RoundedRectangle(cornerRadius: 13))

                VStack(alignment: .leading, spacing: 7) {
                    Text(section.trackerTitle)
                        .font(.headline)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(trackerSubtitle(for: section, session: session))
                        .font(.caption)
                        .foregroundStyle(AppTheme.trackerSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 10) {
                            trackerRowMetric(section, session: session)
                            trackerRowProgress(section, session: session)
                        }
                        VStack(alignment: .leading, spacing: 6) {
                            trackerRowMetric(section, session: session)
                            trackerRowProgress(section, session: session)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right")
                    .font(.caption.bold())
                    .foregroundStyle(.tertiary)
                    .padding(.top, 18)
            }
            .foregroundStyle(.primary)
            .padding(13)
            .background(AppTheme.trackerRow, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 17, style: .continuous)
                    .stroke(Color(.separator).opacity(0.24), lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint("打开只读详情")
        .accessibilityIdentifier("tracker.section.\(section.rawValue)")
    }

    private func trackerRowMetric(_ section: SaveEditorSection, session: SaveSession) -> some View {
        Text(trackerMetric(for: section, session: session))
            .font(.caption.monospacedDigit().weight(.semibold))
            .foregroundStyle(section == .review && !session.metadata.warnings.isEmpty
                ? AppTheme.trackerWarning : AppTheme.progress)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private func trackerRowProgress(_ section: SaveEditorSection, session: SaveSession) -> some View {
        if let progress = trackerProgress(for: section, session: session) {
            ProgressView(value: progress)
                .progressViewStyle(.linear)
                .tint(AppTheme.progress)
                .frame(width: 72)
                .accessibilityHidden(true)
        }
    }

    private func trackerMetric(for section: SaveEditorSection, session: SaveSession) -> String {
        switch section {
        case .character:
            return "第 \(session.draft.year) 年"
        case .appearance:
            return "4 项"
        case .farmhouse:
            return "\(session.draft.farmhouse.decorations.count) 项"
        case .inventory:
            return "\(session.draft.inventory.filter { $0.item != nil }.count)/\(session.draft.inventory.count)"
        case .progress:
            return "\(trackerCollectionFootprint(session)) 项"
        case .relationships:
            return "\(session.draft.friendships.count) 人"
        case .skills:
            let levels = TrackerMetrics.skillLevelSummary(session.draft.skills)
            return "\(levels.current)/\(levels.total) 级"
        case .wallet:
            return "\(session.draft.progress.walletUnlocks.filter(\.isUnlocked).count)/\(WalletUnlockKey.allCases.count)"
        case .animals:
            return "\(session.draft.animals.count) 只"
        case .recipes:
            return "\(session.draft.recipes.filter(\.unlocked).count)/\(session.draft.recipes.count)"
        case .review:
            return TrackerMetrics.statusText(warnings: session.metadata.warnings, diffCount: session.diffs.count)
        }
    }

    private func trackerProgress(for section: SaveEditorSection, session: SaveSession) -> Double? {
        switch section {
        case .skills:
            let levels = TrackerMetrics.skillLevelSummary(session.draft.skills)
            return TrackerMetrics.fraction(completed: levels.current, total: levels.total)
        case .wallet:
            return TrackerMetrics.fraction(
                completed: session.draft.progress.walletUnlocks.filter(\.isUnlocked).count,
                total: WalletUnlockKey.allCases.count
            )
        case .recipes:
            return TrackerMetrics.fraction(
                completed: session.draft.recipes.filter(\.unlocked).count,
                total: session.draft.recipes.count
            )
        case .review:
            return nil // Compatibility is a status, not game completion.
        default:
            return nil
        }
    }

    private func trackerCollectionFootprint(_ session: SaveSession) -> Int {
        TrackerMetrics.collectionKindCount(session.draft.progress.insights)
    }

    private func trackerSubtitle(for section: SaveEditorSection, session: SaveSession) -> String {
        switch section {
        case .character:
            return "身份、基础数值、游戏日期与游玩时间"
        case .appearance:
            return "性别、发型、肤色与饰品编号"
        case .farmhouse:
            let decorationCount = session.draft.farmhouse.decorations.count
            return "农舍等级与 \(decorationCount) 项房间表面"
        case .inventory:
            return "\(session.draft.inventory.filter { $0.item != nil }.count) 个物品 · 逐格查看"
        case .progress:
            let insights = session.draft.progress.insights
            return "\(insights.shippedItemKinds) 种出货 · \(insights.caughtFishKinds) 种鱼 · 矿洞进度"
        case .relationships:
            return "\(session.draft.friendships.count) 位角色 · 好感与状态"
        case .skills:
            let professions = session.draft.progress.professionIDs.intersection(ProfessionCatalog.knownIDs).count
            return "已选 \(professions) 个职业 · 按已识别技能的 0–10 级统计"
        case .wallet:
            let unlocked = session.draft.progress.walletUnlocks.filter(\.isUnlocked).count
            return "已获得 \(unlocked) / \(WalletUnlockKey.allCases.count) 项钱包能力"
        case .animals:
            return "\(session.draft.animals.count) 只动物 · 亲密度、心情与饱食度"
        case .recipes:
            let unlocked = session.draft.recipes.filter(\.unlocked).count
            return "已解锁 \(unlocked) / \(session.draft.recipes.count) 项"
        case .review:
            return "格式、兼容性警告与 \(session.diffs.count) 项待保存草稿"
        }
    }

    private var unloadedTracker: some View {
        VStack(spacing: 20) {
            GameAssetIcon(assetName: "GameUITrophy", size: 72)
                .padding(16)
                .background(AppTheme.trackerHeaderSoft, in: RoundedRectangle(cornerRadius: 22))
            VStack(spacing: 7) {
                Text("载入农场，开始追踪")
                    .font(.title2.bold())
                Text("集中查看角色、收藏、技能、关系与农场生活进度。")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.trackerSecondary)
                    .multilineTextAlignment(.center)
            }
            Button {
                selectedTab = .tools
            } label: {
                Label("前往工具页加载", systemImage: "folder.badge.plus")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(AppTheme.accent)
            .accessibilityIdentifier("tracker.loadFarm")
        }
        .padding(26)
        .frame(maxWidth: .infinity)
        .appCard()
    }

}
