import SwiftUI

struct HomeView: View {
    @Environment(EditorStore.self) private var store
    @Environment(\.dynamicTypeSize) private var typeSize
    @Binding var selectedTab: MainTab
    @State private var showingMagicMap = false

    var body: some View {
        VStack(spacing: 0) {
            FarmDateHeader(session: store.session)

            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    Text("今日概览")
                        .font(.title2.bold())

                    if let session = store.session {
                        loadedFarmCard(session)
                        FarmerPortraitCard(session: session)
                        FarmMapCard(session: session, cropCatalog: store.cropCatalog) {
                            showingMagicMap = true
                        }
                        quickActions
                    } else {
                        emptyFarmCard
                    }

                    safetyCard
                }
                .padding(.horizontal, 20)
                .padding(.top, 22)
                .padding(.bottom, 34)
                .readablePageWidth()
            }
            .background(AppTheme.canvas)
        }
        .fullScreenCover(isPresented: $showingMagicMap) {
            if let session = store.session {
                FarmMapAnalysisView(session: session, cropCatalog: store.cropCatalog)
            } else {
                GameEmptyState(title: "请先加载农场", systemImage: "externaldrive.badge.plus")
            }
        }
    }

    private func loadedFarmCard(_ session: SaveSession) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(session.draft.playerName.isEmpty ? "未命名农夫" : session.draft.playerName)
                        .font(.title2.bold())
                    Text("农场：\(session.draft.farmName.isEmpty ? session.source.farmIdentifier : session.draft.farmName)")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("v\(session.metadata.gameVersion)")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            LazyVGrid(
                columns: AppLayout.pairedColumns(for: typeSize),
                spacing: 16
            ) {
                MetricView(
                    value: session.draft.money.formatted(),
                    label: "金币",
                    artworkName: "GameUIGoldBar"
                )
                MetricView(
                    value: "\(session.draft.maxHealth)",
                    label: "生命",
                    artworkName: "GameUIProgress"
                )
                MetricView(
                    value: "\(session.draft.inventory.filter { $0.item != nil }.count)",
                    label: "背包物品",
                    artworkName: "GameUIBackpack"
                )
                MetricView(
                    value: formattedPlayTime(session.metadata.playTimeMilliseconds),
                    label: "游玩时间",
                    artworkName: "GameUITrophy"
                )
            }

            Button {
                selectedTab = .tools
            } label: {
                GameLabel("前往工具页", systemImage: "hammer.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(AppTheme.accent)
        }
        .padding(22)
        .background(AppTheme.headerSoft, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private var quickActions: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("快捷入口")
                .font(.title2.bold())

            LazyVGrid(columns: AppLayout.pairedColumns(for: typeSize), spacing: 14) {
                HomeShortcut(
                    title: "数据追踪",
                    subtitle: "查看农场概览",
                    systemImage: "trophy.fill"
                ) {
                    selectedTab = .tracker
                }

                HomeShortcut(
                    title: "存档工具",
                    subtitle: "编辑与备份",
                    systemImage: "gamecontroller.fill"
                ) {
                    selectedTab = .tools
                }
            }
        }
    }

    private var emptyFarmCard: some View {
        VStack(spacing: 18) {
            GameIcon(systemName: "externaldrive.badge.plus", size: 50)
                .font(.system(size: 50, weight: .light))
                .foregroundStyle(AppTheme.accent)
            Text("尚未加载农场")
                .font(.title3.bold())
            Text("在工具页加载《星露谷物语》1.6.x 存档后，这里会显示日期、农场和角色概览。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("前往工具页加载") {
                selectedTab = .tools
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(AppTheme.accent)
        }
        .padding(26)
        .frame(maxWidth: .infinity)
        .appCard()
    }

    private var safetyCard: some View {
        HStack(alignment: .top, spacing: 14) {
            GameIcon(systemName: "lock.shield.fill", size: 28)
                .font(.title2)
                .foregroundStyle(.green)
            VStack(alignment: .leading, spacing: 5) {
                Text("本地、安全地处理存档")
                    .font(.headline)
                Text("不会上传文件；每次写回前自动创建成对备份。编辑前请完全退出游戏。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .appCard()
    }
}

private struct FarmerPortraitCard: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    let session: SaveSession

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("外观存档参数")
                        .font(.title2.bold())
                    Text(session.draft.playerName.isEmpty ? "未命名农夫" : session.draft.playerName)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                GameLabel(
                    session.hasChanges ? "当前草稿" : "存档读取值",
                    systemImage: "doc.text.magnifyingglass"
                )
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.accent)
            }

            LazyVGrid(
                columns: AppLayout.pairedColumns(for: typeSize),
                spacing: 12
            ) {
                AppearanceMetric(
                    title: "性别",
                    value: session.draft.gender.displayName,
                    systemImage: "person.fill"
                )
                AppearanceMetric(
                    title: "发型编号",
                    value: session.draft.hair.formatted(),
                    systemImage: "scissors"
                )
                AppearanceMetric(
                    title: "肤色编号",
                    value: session.draft.skin.formatted(),
                    systemImage: "paintpalette.fill"
                )
                AppearanceMetric(
                    title: "饰品编号",
                    value: session.draft.accessory < 0 ? "无" : session.draft.accessory.formatted(),
                    systemImage: "eyeglasses"
                )
            }

            Text(
                session.hasChanges
                    ? "以上内容包含尚未保存的草稿；可在工具页检查每个参数的变化。"
                    : "以上内容直接读取自主存档。"
            )
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(20)
        .appCard()
    }
}

private struct AppearanceMetric: View {
    let title: String
    let value: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 12) {
            GameIcon(systemName: systemImage)
                .foregroundStyle(AppTheme.accent)
                .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.headline.monospacedDigit())
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 14))
    }
}

private struct FarmMapCard: View {
    let session: SaveSession
    let snapshot: FarmSnapshot
    let onOpen: () -> Void

    init(session: SaveSession, cropCatalog: [CropDefinition], onOpen: @escaping () -> Void) {
        self.session = session
        self.onOpen = onOpen
        snapshot = FarmSnapshotExtractor.extract(
            from: session.parsed.mainRoot,
            cropCatalog: cropCatalog
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("农场实体坐标")
                        .font(.title2.bold())
                    Text(session.draft.farmName.isEmpty ? session.source.farmIdentifier : session.draft.farmName)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(farmTypeName(session.metadata.farmType))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.accent)
            }

            ZStack(alignment: .bottomLeading) {
                Image("GameFarmBackdrop")
                    .resizable()
                    .interpolation(.none)
                    .scaledToFill()
                    .frame(height: 184)
                    .clipped()

                LinearGradient(
                    colors: [.clear, .black.opacity(0.62)],
                    startPoint: .center,
                    endPoint: .bottom
                )

                HStack(spacing: 12) {
                    GameLabel("\(snapshot.count(for: .crop)) 作物", systemImage: "leaf.fill")
                    GameLabel("\(snapshot.count(for: .building)) 建筑", systemImage: "house.fill")
                    GameLabel("\(snapshot.stoneCount) 石块", systemImage: "circle.fill")
                }
                .font(.caption.bold())
                .foregroundStyle(.white)
                .padding(14)
            }
            .frame(height: 184)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

            GameLabel(
                "从 Farm 节点读取 \(snapshot.entities.count) 个实体，其中 \(snapshot.positionedEntities.count) 个包含真实坐标",
                systemImage: "scope"
            )
                .font(.caption)
                .foregroundStyle(.secondary)

            Button(action: onOpen) {
                GameLabel("打开魔法地图", systemImage: "wand.and.stars")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)

            if let warning = snapshot.warnings.first {
                GameLabel(warning, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .padding(20)
        .appCard()
    }
}

func formattedPlayTime(_ milliseconds: Int64?) -> String {
    guard let milliseconds, milliseconds >= 0 else { return "—" }
    let totalMinutes = milliseconds / 60_000
    return "\(totalMinutes / 60)h \(totalMinutes % 60)m"
}

func farmTypeName(_ farmType: Int?) -> String {
    switch farmType {
    case 0: "标准农场"
    case 1: "河边农场"
    case 2: "森林农场"
    case 3: "山顶农场"
    case 4: "荒野农场"
    case 5: "四角农场"
    case 6: "沙滩农场"
    case 7: "草原农场"
    case let value?: "农场类型 \(value)"
    case nil: "类型未知"
    }
}

private struct FarmDateHeader: View {
    let session: SaveSession?

    var body: some View {
        VStack(spacing: 5) {
            if let session {
                Text("\(session.draft.season.displayName)季第 \(session.draft.day) 天")
                    .font(.largeTitle.weight(.bold))
                Text("第 \(session.draft.year) 年 · \(weekday(for: session.draft))")
                    .font(.title3)
                    .foregroundStyle(AppTheme.title.opacity(0.72))
            } else {
                Text("穗光琥珀存档匣")
                    .font(.largeTitle.weight(.bold))
                Text("农场助手")
                    .font(.title3)
                    .foregroundStyle(AppTheme.title.opacity(0.72))
            }
        }
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, 20)
        .padding(.vertical, 24)
        .foregroundStyle(AppTheme.title)
        .frame(maxWidth: .infinity)
        .frame(minHeight: 130)
        .background(AppTheme.header.ignoresSafeArea(edges: .top))
    }

    private func weekday(for draft: SaveDraft) -> String {
        let totalDays = max(0, draft.year - 1) * 112
            + draft.season.saveIndex * 28
            + max(0, draft.day - 1)
        return ["周一", "周二", "周三", "周四", "周五", "周六", "周日"][totalDays % 7]
    }
}

private struct MetricView: View {
    let value: String
    let label: String
    var artworkName: String? = nil

    var body: some View {
        VStack(spacing: 6) {
            if let artworkName {
                GameAssetIcon(assetName: artworkName, size: 30)
            }
            Text(value)
                .font(.title2.bold())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct HomeShortcut: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 10) {
                GameIcon(systemName: systemImage, size: 34)
                    .font(.system(size: 34, weight: .medium))
                Text(title)
                    .font(.headline)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .foregroundStyle(.primary)
            .padding(.vertical, 20)
            .frame(maxWidth: .infinity)
            .appCard()
        }
        .buttonStyle(.plain)
    }
}
