import SwiftUI

struct TrackerView: View {
    @Environment(EditorStore.self) private var store
    @Binding var selectedTab: MainTab
    @State private var selectedSection: SaveEditorSection?

    var body: some View {
        VStack(spacing: 0) {
            LargePageHeader(title: "追踪")

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let session = store.session {
                        trackerFarmCard(session)

                        Text("查看板块")
                            .font(.headline)
                            .foregroundStyle(.secondary)

                        ForEach(SaveEditorSection.allCases) { section in
                            ToolRowButton(
                                title: section.trackerTitle,
                                subtitle: trackerSubtitle(for: section, session: session),
                                systemImage: section.systemImage,
                                iconColor: section.tint,
                                artworkName: section.artworkName
                            ) {
                                selectedSection = section
                            }
                        }
                    } else {
                        unloadedTracker
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 24)
                .padding(.bottom, 20)
                .frame(maxWidth: 720)
                .frame(maxWidth: .infinity)
            }
            .background(AppTheme.canvas)
        }
        .fullScreenCover(item: $selectedSection) { section in
            if let session = store.session {
                TrackerDetailView(session: session, section: section)
            } else {
                ContentUnavailableView("农场已卸载", systemImage: "externaldrive.badge.xmark")
            }
        }
    }

    private func trackerFarmCard(_ session: SaveSession) -> some View {
        HStack(spacing: 14) {
            GameIcon(systemName: "eye.fill", size: 28)
                .font(.title2)
                .foregroundStyle(AppTheme.accent)
            VStack(alignment: .leading, spacing: 3) {
                Text(session.draft.farmName.isEmpty ? session.source.farmIdentifier : session.draft.farmName)
                    .font(.headline)
                Text("主玩家 · 只读查看")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if session.hasChanges {
                Text("预览 \(session.diffs.count) 项草稿")
                    .font(.caption.bold())
                    .foregroundStyle(.orange)
            }
        }
        .padding(18)
        .background(AppTheme.headerSoft, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
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
            let totalLevel = session.draft.skills.reduce(0) { $0 + $1.level }
            let professions = session.draft.progress.professionIDs.intersection(ProfessionCatalog.knownIDs).count
            return "技能总等级 \(totalLevel) · 已选 \(professions) 个职业"
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
        VStack(spacing: 18) {
            GameIcon(systemName: "trophy", size: 48)
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(AppTheme.muted)
            Text("加载农场后查看追踪数据")
                .font(.title3.bold())
            Button("前往工具页") {
                selectedTab = .tools
            }
            .buttonStyle(.borderedProminent)
            .tint(AppTheme.accent)
        }
        .padding(30)
        .frame(maxWidth: .infinity)
        .appCard()
    }

}

private struct TrackerDetailView: View {
    let session: SaveSession
    let section: SaveEditorSection
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var recipeKind: RecipeKind = .cooking

    var body: some View {
        NavigationStack {
            detailContent
                .navigationTitle(section.trackerTitle)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("关闭", systemImage: "xmark") { dismiss() }
                            .labelStyle(.iconOnly)
                    }
                }
        }
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
                LabeledContent("金钱", value: session.draft.money.formatted())
                LabeledContent("最大生命", value: "\(session.draft.maxHealth)")
                LabeledContent("最大体力", value: "\(session.draft.maxStamina)")
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
                        .foregroundStyle(.secondary)
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
                LabeledContent("总格数", value: "\(session.draft.inventory.count)")
                LabeledContent("已占用", value: "\(occupiedInventory.count)")
                LabeledContent("空格", value: "\(session.draft.inventory.count - occupiedInventory.count)")
            }

            Section("背包槽位") {
                if occupiedInventory.isEmpty {
                    Text("背包为空")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(occupiedInventory) { slot in
                        if let item = slot.item {
                            HStack(spacing: 12) {
                                ItemArtworkView(item: item, size: 44)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(item.displayName)
                                    Text("槽位 \(slot.id + 1) · 品质 \(item.quality) · \(item.objectType)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
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
                        .foregroundStyle(.secondary)
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
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                GameLabel("\(friend.hearts)", systemImage: "heart.fill")
                                    .foregroundStyle(.pink)
                            }
                            LabeledContent("好感", value: "\(friend.points) 点")
                            LabeledContent("状态", value: friend.status.displayName)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                }
            } header: {
                Text("人物关系")
            } footer: {
                Text("此页仅展示好感与关系状态；修改请前往工具页。")
            }
        }
        .searchable(text: $searchText, prompt: "搜索角色名称")
        .onSubmit(of: .search) { KeyboardReturnAction.dismiss() }
    }

    private var progressList: some View {
        List {
            draftNotice

            Section("财富与资源") {
                LabeledContent("金币", value: session.draft.money.formatted())
                optionalTrackerValue("累计收入", session.draft.progress.totalMoneyEarned)
                optionalTrackerValue("齐钻", session.draft.progress.qiGems)
                optionalTrackerValue("齐币", session.draft.progress.clubCoins)
                optionalTrackerValue("金色核桃", session.draft.progress.goldenWalnuts)
                optionalTrackerValue("干草", session.draft.progress.piecesOfHay)
            }

            Section("矿洞与世界") {
                optionalTrackerValue("个人到达最深层", session.draft.progress.deepestMineLevel)
                optionalTrackerValue("世界矿井解锁层", session.draft.progress.mineLowestLevelReached)
                LabeledContent("明日天气", value: session.draft.progress.insights.weatherForTomorrow ?? "未提供")
                LabeledContent(
                    "每日运气",
                    value: session.draft.progress.insights.dailyLuck.map {
                        $0.formatted(.number.precision(.fractionLength(0...3)))
                    } ?? "未提供"
                )
            }

            Section("收藏统计") {
                LabeledContent("已出货种类", value: "\(session.draft.progress.insights.shippedItemKinds)")
                LabeledContent("已捕获鱼类", value: "\(session.draft.progress.insights.caughtFishKinds)")
                LabeledContent("已发现矿物", value: "\(session.draft.progress.insights.mineralKinds)")
                LabeledContent("已发现古物", value: "\(session.draft.progress.insights.artifactKinds)")
                LabeledContent("秘密纸条", value: "\(session.draft.progress.insights.secretNoteCount)")
                LabeledContent("已观看事件", value: "\(session.draft.progress.insights.eventCount)")
                LabeledContent("已完成成就", value: "\(session.draft.progress.insights.achievementCount)")
                LabeledContent("进行中任务", value: "\(session.draft.progress.insights.activeQuestCount)")
            }

            Section("累计记录") {
                optionalTrackerValue("游玩天数", session.draft.progress.insights.daysPlayed)
                optionalTrackerValue("完成任务", session.draft.progress.insights.questsCompleted)
                optionalTrackerValue("击败怪物", session.draft.progress.insights.monstersKilled)
                optionalTrackerValue("出货物品", session.draft.progress.insights.itemsShipped)
                optionalTrackerValue("捕获鱼数", session.draft.progress.insights.fishCaught)
            }
        }
    }

    private var skillsList: some View {
        List {
            draftNotice

            Section("技能") {
                ForEach(session.draft.skills) { skill in
                    VStack(alignment: .leading, spacing: 7) {
                        HStack {
                            Text(skill.key.displayName)
                            Spacer()
                            Text("Lv. \(skill.level) · \(skill.targetExperience) XP")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        ProgressView(value: Double(skill.targetExperience), total: 15_000)
                            .tint(AppTheme.accent)
                    }
                }
            }

            Section("职业") {
                let selected = session.draft.progress.professionIDs
                    .intersection(ProfessionCatalog.knownIDs)
                    .sorted()
                if selected.isEmpty {
                    Text("尚未选择职业")
                        .foregroundStyle(.secondary)
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

            Section("钱包能力") {
                ForEach(session.draft.progress.walletUnlocks) { unlock in
                    Label {
                        HStack {
                            Text(unlock.key.displayName)
                            Spacer()
                            Text(unlock.isUnlocked ? "已获得" : "未获得")
                                .foregroundStyle(unlock.isUnlocked ? .green : .secondary)
                        }
                    } icon: {
                        GameIcon(systemName: unlock.key.systemImage)
                            .foregroundStyle(unlock.isUnlocked ? .teal : .secondary)
                    }
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
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(session.draft.animals) { animal in
                        VStack(alignment: .leading, spacing: 7) {
                            HStack {
                                Text(animal.name)
                                    .font(.headline)
                                Spacer()
                                GameLabel("\(animal.hearts)", systemImage: "heart.fill")
                                    .foregroundStyle(.pink)
                            }
                            Text("\(animal.localizedType) · \(animal.home)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            HStack {
                                Text("亲密 \(animal.friendship)")
                                Spacer()
                                Text("心情 \(animal.happiness)")
                                Spacer()
                                Text("饱食 \(animal.fullness)")
                            }
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 3)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func optionalTrackerValue(_ title: String, _ value: Int?) -> some View {
        if let value {
            LabeledContent(title, value: value.formatted())
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
                .pickerStyle(.segmented)

                LabeledContent("已解锁", value: "\(unlockedRecipes.count) / \(recipesOfSelectedKind.count)")
            }

            Section("已解锁配方") {
                if filteredRecipes.isEmpty {
                    Text("没有匹配的已解锁配方")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(filteredRecipes) { recipe in
                        HStack(spacing: 12) {
                            RecipeArtworkView(key: recipe.key, kind: recipe.kind, size: 40)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(RecipeCatalog.localizedName(for: recipe.key))
                                if RecipeCatalog.hasChineseName(for: recipe.key) {
                                    Text(recipe.key)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Text("制作 \(recipe.timesMade) 次")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .searchable(text: $searchText, prompt: "搜索已解锁配方")
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
                            .foregroundStyle(.orange)
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
                                .foregroundStyle(.secondary)
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
                    .foregroundStyle(.orange)
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
        unlockedRecipes.filter { recipe in
            searchText.isEmpty
                || recipe.key.localizedCaseInsensitiveContains(searchText)
                || RecipeCatalog.localizedName(for: recipe.key)
                    .localizedCaseInsensitiveContains(searchText)
        }
    }
}
