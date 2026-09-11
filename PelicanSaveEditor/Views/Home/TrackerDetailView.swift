import SwiftUI

struct TrackerDetailView: View {
    let session: SaveSession
    @State private var section: SaveEditorSection
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var searchText = ""
    @State private var recipeKind: RecipeKind = .cooking
    @State private var recipeStatus: TrackerRecipeStatus = .all

    init(session: SaveSession, section: SaveEditorSection) {
        self.session = session
        _section = State(initialValue: section)
    }

    var body: some View {
        NavigationStack {
            detailContent
                .readablePageWidth(AppLayout.editorWidth)
                .scrollContentBackground(.hidden)
                .background(AppTheme.canvas.ignoresSafeArea())
                .listStyle(.insetGrouped)
                .labeledContentStyle(TrackerLabeledContentStyle())
                .safeAreaInset(edge: .top, spacing: 0) {
                    detailFilterStrip
                }
                .navigationTitle(section.trackerTitle)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .principal) {
                        HStack(spacing: 8) {
                            TrackerSectionArtwork(section: section, size: 26)
                            Text(section.trackerTitle)
                                .font(.headline)
                                .foregroundStyle(AppTheme.trackerTitle)
                        }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("关闭", systemImage: "xmark") { dismiss() }
                            .labelStyle(.iconOnly)
                            .frame(minWidth: 44, minHeight: 44)
                            .accessibilityIdentifier("tracker.detail.close")
                    }
                }
                .toolbarBackground(AppTheme.trackerHeader, for: .navigationBar)
                .toolbarBackground(.visible, for: .navigationBar)
        }
        .tint(AppTheme.trackerAccent)
    }

    private var detailFilterStrip: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 9) {
                    ForEach(SaveEditorSection.allCases) { candidate in
                        Button {
                            section = candidate
                            searchText = ""
                        } label: {
                            Text(candidate.trackerTitle)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(section == candidate ? AppTheme.trackerTitle : Color.primary)
                                .padding(.horizontal, 14)
                                .frame(minHeight: 44)
                                .background(
                                    section == candidate ? AppTheme.trackerSelection : Color(.tertiarySystemFill),
                                    in: Capsule()
                                )
                                .overlay {
                                    Capsule().stroke(Color(.separator).opacity(0.25), lineWidth: 1)
                                }
                        }
                        .buttonStyle(.plain)
                        .id(candidate)
                        .accessibilityAddTraits(section == candidate ? .isSelected : [])
                        .accessibilityIdentifier("tracker.detail.filter.\(candidate.rawValue)")
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }
            .onAppear { proxy.scrollTo(section, anchor: .center) }
            .onChange(of: section) { _, value in
                withAnimation(.easeInOut(duration: 0.2)) {
                    proxy.scrollTo(value, anchor: .center)
                }
            }
        }
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
    }

    @ViewBuilder
    private var detailContent: some View {
        switch section {
        case .character:
            characterList
        case .appearance:
            appearanceList
        case .farmhouse:
            farmhouseList
        case .inventory:
            inventoryList
        case .progress:
            progressList
        case .relationships:
            relationshipsList
        case .skills:
            skillsList
        case .wallet:
            walletList
        case .animals:
            animalsList
        case .recipes:
            recipesList
        case .review:
            statusList
        }
    }

    private var characterList: some View {
        List {
            draftNotice

            Section("基本信息") {
                LabeledContent("农民名称", value: session.draft.playerName.isEmpty ? "—" : session.draft.playerName)
                LabeledContent("农场名字", value: session.draft.farmName.isEmpty ? "—" : session.draft.farmName)
                LabeledContent("农场类型", value: farmTypeName(session.metadata.farmType))
                LabeledContent("游戏版本", value: session.metadata.gameVersion)
            }

            Section("游戏数据") {
                LabeledContent("游玩时间", value: formattedPlayTime(session.metadata.playTimeMilliseconds))
                LabeledContent("游戏日期", value: "第 \(session.draft.year) 年 · \(session.draft.season.displayName)季 \(session.draft.day) 日")
                artworkTrackerValue("金钱", value: session.draft.money.formatted(), assetName: "GameUIGoldBar")
                artworkTrackerValue("最大生命", value: "\(session.draft.maxHealth)", assetName: "GameUIProgress")
                artworkTrackerValue("最大体力", value: "\(session.draft.maxStamina)", assetName: "GameUIProgress")
            }

        }
    }

    private var appearanceList: some View {
        List {
            draftNotice

            Section("存档角色") {
                LabeledContent(
                    "玩家名称",
                    value: session.draft.playerName.isEmpty ? "未命名农夫" : session.draft.playerName
                )
                LabeledContent("原始字段来源", value: "主存档 / player")
            }

            Section {
                LabeledContent("性别", value: session.draft.gender.displayName)
                LabeledContent("发型编号", value: "\(session.draft.hair)")
                LabeledContent("肤色编号", value: "\(session.draft.skin)")
                LabeledContent("饰品编号", value: "\(session.draft.accessory)")
            } header: {
                Text("外观参数")
            } footer: {
                Text("此处展示存档中的实际 Gender、hair、skin 与 accessory 值；修改请前往工具页。")
            }
        }
    }

    private var farmhouseList: some View {
        List {
            draftNotice

            Section {
                Image("GameFarmBackdrop")
                    .resizable()
                    .interpolation(.none)
                    .scaledToFill()
                    .frame(height: 180)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }

            Section("农舍") {
                if let level = session.draft.farmhouse.upgradeLevel {
                    LabeledContent("扩建等级", value: "\(level) 级")
                } else {
                    LabeledContent("扩建等级", value: "存档未提供")
                }
            }

            Section("房间表面") {
                if session.draft.farmhouse.decorations.isEmpty {
                    Text("没有可读取的墙纸或地板条目")
                        .foregroundStyle(AppTheme.trackerSecondary)
                } else {
                    ForEach(session.draft.farmhouse.decorations) { decoration in
                        LabeledContent(
                            "\(decoration.localizedRoomName)·\(decoration.kind.displayName)",
                            value: "样式 \(decoration.styleIndex)"
                        )
                    }
                }
            }
        }
    }

    private var inventoryList: some View {
        List {
            draftNotice

            Section("统计") {
                LabeledContent("可用容量", value: "\(session.draft.usableInventoryCount) 格")
                LabeledContent("已占用", value: "\(session.draft.inventory.prefix(session.draft.usableInventoryCount).filter { $0.item != nil }.count)")
                LabeledContent("空格", value: "\(session.draft.inventory.prefix(session.draft.usableInventoryCount).filter { $0.item == nil }.count)")
                if let capacity = session.draft.backpackCapacity {
                    LabeledContent("存档容量字段", value: "\(capacity)")
                }
            }

            Section("背包槽位") {
                if occupiedInventory.isEmpty {
                    Text("背包为空")
                        .foregroundStyle(AppTheme.trackerSecondary)
                } else {
                    ForEach(occupiedInventory) { slot in
                        if let item = slot.item {
                            HStack(spacing: 12) {
                                ItemArtworkView(item: item, size: 44)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(item.displayName)
                                    Text("槽位 \(slot.id + 1) · 品质 \(item.quality) · \(item.objectType)")
                                        .font(.caption)
                                        .foregroundStyle(AppTheme.trackerSecondary)
                                }
                                Spacer()
                                Text("×\(item.stack)")
                                    .font(.headline.monospacedDigit())
                            }
                        }
                    }
                }
            }
        }
    }

    private var relationshipsList: some View {
        List {
            draftNotice

            Section {
                if filteredFriendships.isEmpty {
                    Text("没有匹配的角色")
                        .foregroundStyle(AppTheme.trackerSecondary)
                } else {
                    ForEach(filteredFriendships) { friend in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                GameNPCPortrait(name: friend.name, size: 48)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(friend.localizedName)
                                        .font(.headline)
                                    if npcChineseNames[friend.name] != nil {
                                        Text(friend.name)
                                            .font(.caption)
                                            .foregroundStyle(AppTheme.trackerSecondary)
                                    }
                                }
                                Spacer()
                                GameLabel("\(friend.hearts)", systemImage: "heart.fill")
                                    .foregroundStyle(.pink)
                            }
                            LabeledContent("好感", value: "\(friend.points) 点")
                            LabeledContent("状态", value: friend.status.displayName)
                                .foregroundStyle(AppTheme.trackerSecondary)
                            if let today = friend.giftsToday { LabeledContent("今日送礼", value: "\(today) 次") }
                            if let week = friend.giftsThisWeek { LabeledContent("本周送礼", value: "\(week) 次") }
                        }
                        .padding(.vertical, 4)
                    }
                }
            } header: {
                Text("人物关系")
            } footer: {
                Text("此页展示好感、关系与存档中已有的送礼次数；修改请前往工具页。")
            }
        }
        .searchable(text: $searchText, prompt: "搜索角色名称")
        .onSubmit(of: .search) { KeyboardReturnAction.dismiss() }
    }

    private var progressList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                if session.hasChanges {
                    Label("正在预览 \(session.diffs.count) 项未保存草稿", systemImage: "eye.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.trackerWarning)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 15))
                }

                collectionOverviewCard

                TrackerDetailCard(title: "财富与资源", artworkName: "GameUIGoldBar") {
                    TrackerDetailDataRow(title: "金币", value: session.draft.money.formatted(), artworkName: "GameUIGoldBar")
                    TrackerDetailDataRow(title: "累计收入", value: formatted(session.draft.progress.totalMoneyEarned), artworkName: "GameUIGoldBar")
                    TrackerDetailDataRow(title: "齐钻", value: formatted(session.draft.progress.qiGems), artworkName: "GameUIDiamond")
                    TrackerDetailDataRow(title: "齐币", value: formatted(session.draft.progress.clubCoins), artworkName: "GameUIGoldBar")
                    TrackerDetailDataRow(title: "持有金色核桃", value: formatted(session.draft.progress.goldenWalnuts), artworkName: "GameUIGoldenWalnut")
                    TrackerDetailDataRow(title: "干草", value: formatted(session.draft.progress.piecesOfHay), systemImage: "leaf.fill")
                }

                TrackerDetailCard(title: "矿洞与世界", artworkName: "GameUIStone") {
                    TrackerDetailDataRow(title: "个人到达最深层", value: formatted(session.draft.progress.deepestMineLevel), artworkName: "GameUIStone")
                    TrackerDetailDataRow(title: "世界矿井解锁层", value: formatted(session.draft.progress.mineLowestLevelReached), artworkName: "GameUIStone")
                    TrackerDetailDataRow(
                        title: "明日天气",
                        value: session.draft.progress.insights.weatherForTomorrow ?? "未提供",
                        systemImage: "cloud.sun.fill"
                    )
                    TrackerDetailDataRow(
                        title: "每日运气",
                        value: session.draft.progress.insights.dailyLuck.map {
                            $0.formatted(.number.precision(.fractionLength(0...3)))
                        } ?? "未提供",
                        artworkName: "GameUITrophy"
                    )
                }

                TrackerDetailCard(title: "收藏统计", artworkName: "GameUIReview") {
                    TrackerDetailDataRow(title: "已出货种类", value: "\(session.draft.progress.insights.shippedItemKinds)", artworkName: "GameUIReview")
                    TrackerDetailDataRow(title: "已捕获鱼类", value: "\(session.draft.progress.insights.caughtFishKinds)", artworkName: "GameUIFish")
                    TrackerDetailDataRow(title: "已发现矿物", value: "\(session.draft.progress.insights.mineralKinds)", artworkName: "GameUIDiamond")
                    TrackerDetailDataRow(title: "已发现古物", value: "\(session.draft.progress.insights.artifactKinds)", artworkName: "GameUIArtifact")
                    TrackerDetailDataRow(title: "秘密纸条", value: "\(session.draft.progress.insights.secretNoteCount)", artworkName: "GameUIDwarfGuide")
                    TrackerDetailDataRow(title: "已观看事件", value: "\(session.draft.progress.insights.eventCount)", artworkName: "GameUITrophy")
                    TrackerDetailDataRow(title: "已完成成就", value: "\(session.draft.progress.insights.achievementCount)", artworkName: "GameUITrophy")
                    TrackerDetailDataRow(title: "进行中任务", value: "\(session.draft.progress.insights.activeQuestCount)", systemImage: "list.bullet.clipboard")
                }

                TrackerDetailCard(title: "累计记录", artworkName: "GameUITrophy") {
                    TrackerDetailDataRow(title: "游玩天数", value: formatted(session.draft.progress.insights.daysPlayed), artworkName: "GameUITrophy")
                    TrackerDetailDataRow(title: "完成任务", value: formatted(session.draft.progress.insights.questsCompleted), systemImage: "checklist")
                    TrackerDetailDataRow(title: "击败怪物", value: formatted(session.draft.progress.insights.monstersKilled), artworkName: "GameUIMonster")
                    TrackerDetailDataRow(title: "出货物品", value: formatted(session.draft.progress.insights.itemsShipped), artworkName: "GameUIReview")
                    TrackerDetailDataRow(title: "捕获鱼数", value: formatted(session.draft.progress.insights.fishCaught), artworkName: "GameUIFish")
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 18)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
        .background(AppTheme.canvas)
    }

    private var collectionOverviewCard: some View {
        let insights = session.draft.progress.insights
        return VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 13) {
                GameAssetIcon(assetName: "GameUITrophy", size: 54)
                    .padding(8)
                    .background(Color(.systemBackground).opacity(0.72), in: RoundedRectangle(cornerRadius: 15))
                VStack(alignment: .leading, spacing: 3) {
                    Text("收藏记录")
                        .font(.title2.bold())
                        .foregroundStyle(AppTheme.trackerTitle)
                    Text("四类记录相加，不代表完美度")
                        .font(.caption)
                        .foregroundStyle(AppTheme.trackerTitle.opacity(0.80))
                }
            }

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible()), count: dynamicTypeSize.isAccessibilitySize ? 1 : 2),
                spacing: 16
            ) {
                TrackerSummaryMetric(value: "\(insights.shippedItemKinds)", label: "出货种类", artworkName: "GameUIReview")
                TrackerSummaryMetric(value: "\(insights.caughtFishKinds)", label: "鱼类", artworkName: "GameUIFish")
                TrackerSummaryMetric(value: "\(insights.mineralKinds)", label: "矿物", artworkName: "GameUIDiamond")
                TrackerSummaryMetric(value: "\(insights.artifactKinds)", label: "古物", artworkName: "GameUIArtifact")
            }
            Text("四类记录合计 \(TrackerMetrics.collectionKindCount(insights)) 项")
                .font(.caption.monospacedDigit())
                .foregroundStyle(AppTheme.trackerTitle.opacity(0.80))
        }
        .padding(20)
        .background(AppTheme.trackerHeaderSoft, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(AppTheme.trackerAccent.opacity(0.14), lineWidth: 1)
        }
    }

    private func formatted(_ value: Int?) -> String {
        value?.formatted() ?? "未提供"
    }

    private var skillsList: some View {
        List {
            draftNotice

            Section("技能") {
                ForEach(session.draft.skills) { skill in
                    VStack(alignment: .leading, spacing: 7) {
                        GameAssetLabel(
                            skill.key.displayName,
                            assetName: GameArtwork.skillAsset(skill.key),
                            iconSize: 26
                        )
                        .font(.headline)
                        Text("Lv. \(skill.level) · \(skill.targetExperience) XP")
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(AppTheme.trackerSecondary)
                        ProgressView(value: TrackerMetrics.fraction(completed: skill.targetExperience, total: 15_000) ?? 0)
                            .tint(AppTheme.progress)
                            .accessibilityLabel("\(skill.key.displayName)经验进度")
                    }
                    .padding(.vertical, 6)
                    .listRowBackground(AppTheme.trackerRow)
                }
            }

            Section("职业") {
                let selected = session.draft.progress.professionIDs
                    .intersection(ProfessionCatalog.knownIDs)
                    .sorted()
                if selected.isEmpty {
                    Text("尚未选择职业")
                        .foregroundStyle(AppTheme.trackerSecondary)
                } else {
                    ForEach(selected, id: \.self) { id in
                        LabeledContent(ProfessionCatalog.name(for: id), value: "编号 \(id)")
                    }
                }
            }
        }
    }

    private var walletList: some View {
        List {
            draftNotice

            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Text("已获得 \(session.draft.progress.walletUnlocks.filter(\.isUnlocked).count) / \(WalletUnlockKey.allCases.count)")
                        .font(.headline.monospacedDigit())
                    ProgressView(value: TrackerMetrics.fraction(
                        completed: session.draft.progress.walletUnlocks.filter(\.isUnlocked).count,
                        total: WalletUnlockKey.allCases.count
                    ) ?? 0)
                    .tint(AppTheme.progress)
                    .accessibilityLabel("钱包能力解锁进度")
                    Text("只读查看特殊物品与能力；不会改变剧情标记。")
                        .font(.caption)
                        .foregroundStyle(AppTheme.trackerSecondary)
                }
                .padding(.vertical, 6)
            }

            Section("钱包能力") {
                ForEach(session.draft.progress.walletUnlocks) { unlock in
                    HStack(spacing: 14) {
                        if let assetName = GameArtwork.walletAsset(unlock.key) {
                            GameAssetIcon(assetName: assetName, size: 36)
                                .opacity(unlock.isUnlocked ? 1 : 0.45)
                        } else {
                            Image(systemName: unlock.key.systemImage)
                                .frame(width: 36)
                                .foregroundStyle(AppTheme.trackerSecondary)
                        }
                        VStack(alignment: .leading, spacing: 5) {
                            Text(unlock.key.displayName)
                                .font(.headline)
                            Label(unlock.isUnlocked ? "已获得" : "未获得",
                                  systemImage: unlock.isUnlocked ? "checkmark.circle.fill" : "lock")
                                .font(.caption)
                                .foregroundStyle(unlock.isUnlocked ? AppTheme.progress : AppTheme.trackerSecondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.vertical, 6)
                    .listRowBackground(unlock.isUnlocked ? AppTheme.trackerRow : AppTheme.card)
                    .accessibilityElement(children: .combine)
                }
            }

            Section("标记统计") {
                LabeledContent("全部邮件/剧情标记", value: "\(session.draft.progress.insights.mailFlagCount)")
            }
        }
    }

    private var animalsList: some View {
        List {
            draftNotice

            Section("动物") {
                if session.draft.animals.isEmpty {
                    Text("没有找到标准存档结构中的动物")
                        .foregroundStyle(AppTheme.trackerSecondary)
                } else {
                    ForEach(session.draft.animals) { animal in
                        VStack(alignment: .leading, spacing: 7) {
                            HStack {
                                GameAnimalPortrait(type: animal.type, size: 42)
                                Text(animal.name)
                                    .font(.headline)
                                Spacer()
                                GameLabel("\(animal.hearts)", systemImage: "heart.fill")
                                    .foregroundStyle(.pink)
                            }
                            Text("\(animal.localizedType) · \(animal.home)")
                                .font(.caption)
                                .foregroundStyle(AppTheme.trackerSecondary)
                            HStack {
                                Text("亲密 \(animal.friendship)")
                                Spacer()
                                Text("心情 \(animal.happiness)")
                                Spacer()
                                Text("饱食 \(animal.fullness)")
                            }
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(AppTheme.trackerSecondary)
                        }
                        .padding(.vertical, 3)
                    }
                }
            }
        }
    }

    private func artworkTrackerValue(_ title: String, value: String, assetName: String) -> some View {
        LabeledContent {
            Text(value)
        } label: {
            GameAssetLabel(title, assetName: assetName, iconSize: 24)
        }
    }

    private var recipesList: some View {
        List {
            draftNotice

            Section {
                Picker("分类", selection: $recipeKind) {
                    ForEach(RecipeKind.allCases) { kind in
                        Text(kind.displayName).tag(kind)
                    }
                }
                .adaptiveSegmentedPicker()

                recipeProgressCard
            }

            Section {
                Picker("解锁状态", selection: $recipeStatus) {
                    ForEach(TrackerRecipeStatus.allCases) { status in
                        Text(status.rawValue).tag(status)
                    }
                }
                .pickerStyle(.menu)
                .accessibilityIdentifier("tracker.recipeStatus")
            }

            Section("\(recipeStatus.rawValue) · \(filteredRecipes.count) 项") {
                if filteredRecipes.isEmpty {
                    Text(searchText.isEmpty ? "当前分类没有符合条件的配方" : "没有匹配的配方，请试试其他名称或筛选")
                        .foregroundStyle(AppTheme.trackerSecondary)
                } else {
                    ForEach(filteredRecipes) { recipe in
                        HStack(spacing: 12) {
                            RecipeArtworkView(key: recipe.key, kind: recipe.kind, size: 40)
                                .opacity(recipe.unlocked ? 1 : 0.50)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(RecipeCatalog.localizedName(for: recipe.key))
                                    .font(.headline)
                                if RecipeCatalog.hasChineseName(for: recipe.key) {
                                    Text(recipe.key)
                                        .font(.caption)
                                        .foregroundStyle(AppTheme.trackerSecondary)
                                }
                                Label(recipe.unlocked ? "已解锁 · 制作 \(recipe.timesMade) 次" : "未解锁",
                                      systemImage: recipe.unlocked ? "checkmark.circle.fill" : "lock")
                                    .font(.caption)
                                    .foregroundStyle(recipe.unlocked ? AppTheme.progress : AppTheme.trackerSecondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(.vertical, 6)
                        .listRowBackground(recipe.unlocked ? AppTheme.trackerRow : AppTheme.card)
                    }
                }
            }
        }
        .searchable(text: $searchText, prompt: "搜索配方名称")
        .onSubmit(of: .search) { KeyboardReturnAction.dismiss() }
    }

    private var statusList: some View {
        List {
            draftNotice

            Section("当前来源") {
                LabeledContent("农场", value: session.source.farmIdentifier)
                LabeledContent("访问模式", value: session.source.mode.displayName)
                LabeledContent("主存档格式", value: session.metadata.mainEncoding.displayName)
                if let infoEncoding = session.metadata.infoEncoding {
                    LabeledContent("SaveGameInfo", value: infoEncoding.displayName)
                }
            }

            Section("兼容性") {
                if session.metadata.warnings.isEmpty {
                    GameLabel("未发现兼容性警告", systemImage: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                } else {
                    ForEach(session.metadata.warnings, id: \.self) { warning in
                        GameLabel(warning, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(AppTheme.trackerWarning)
                    }
                }
            }

            Section {
                if session.diffs.isEmpty {
                    GameLabel("没有待保存的更改", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    ForEach(session.diffs) { diff in
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(diff.section) · \(diff.label)")
                                .font(.headline)
                            Text("\(diff.oldValue) → \(diff.newValue)")
                                .font(.subheadline)
                                .foregroundStyle(AppTheme.trackerSecondary)
                        }
                    }
                }
            } header: {
                Text("待保存草稿")
            } footer: {
                Text("保存、放弃或恢复备份请前往工具页的“检查与保存”。")
            }
        }
    }

    @ViewBuilder
    private var draftNotice: some View {
        if session.hasChanges {
            Section {
                GameLabel("正在预览 \(session.diffs.count) 项未保存草稿", systemImage: "eye.fill")
                    .foregroundStyle(AppTheme.trackerWarning)
            }
        }
    }

    private var occupiedInventory: [InventorySlotDraft] {
        session.draft.inventory.filter { $0.item != nil }
    }

    private var filteredFriendships: [FriendshipDraft] {
        session.draft.friendships.filter { friend in
            searchText.isEmpty
                || friend.name.localizedCaseInsensitiveContains(searchText)
                || npcChineseNames[friend.name]?.localizedCaseInsensitiveContains(searchText) == true
        }
    }

    private var recipesOfSelectedKind: [RecipeDraft] {
        session.draft.recipes.filter { $0.kind == recipeKind }
    }

    private var unlockedRecipes: [RecipeDraft] {
        recipesOfSelectedKind.filter(\.unlocked)
    }

    private var filteredRecipes: [RecipeDraft] {
        recipesOfSelectedKind.filter { recipe in
            recipeStatus.includes(recipe) && (searchText.isEmpty
                || recipe.key.localizedCaseInsensitiveContains(searchText)
                || RecipeCatalog.localizedName(for: recipe.key)
                    .localizedCaseInsensitiveContains(searchText))
        }
    }

    private var recipeProgressCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("已解锁 \(unlockedRecipes.count) / \(recipesOfSelectedKind.count)")
                .font(.headline.monospacedDigit())
            if let progress = TrackerMetrics.fraction(
                completed: unlockedRecipes.count, total: recipesOfSelectedKind.count
            ) {
                ProgressView(value: progress)
                    .tint(AppTheme.progress)
                    .accessibilityLabel("当前分类解锁进度")
            }
            Text("按当前已识别配方统计；解锁不代表已经制作。")
                .font(.caption)
                .foregroundStyle(AppTheme.trackerSecondary)
        }
        .padding(.vertical, 6)
    }
}

private enum TrackerRecipeStatus: String, CaseIterable, Identifiable {
    case all = "全部"
    case unlocked = "已解锁"
    case locked = "未解锁"

    var id: String { rawValue }

    func includes(_ recipe: RecipeDraft) -> Bool {
        switch self {
        case .all: true
        case .unlocked: recipe.unlocked
        case .locked: !recipe.unlocked
        }
    }
}
