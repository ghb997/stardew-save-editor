import SwiftUI

struct ProgressEditorView: View {
    @Bindable var session: SaveSession

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 14) {
                        GameAssetIcon(assetName: "GameUIProgress", size: 40)
                            .font(.largeTitle)
                            .foregroundStyle(.blue)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("状态、货币与世界进度")
                                .font(.headline)
                            Text("仅显示这份存档真实存在的可编辑字段")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if hasCurrencyFields {
                    Section("货币与资源") {
                        optionalNumberRow("齐钻", keyPath: \.qiGems, assetName: "GameUIDiamond")
                        optionalNumberRow("齐币", keyPath: \.clubCoins, assetName: "GameUIGoldBar")
                        optionalNumberRow("累计收入", keyPath: \.totalMoneyEarned, assetName: "GameUIGoldBar")
                        optionalNumberRow("金色核桃", keyPath: \.goldenWalnuts, assetName: "GameUIGoldenWalnut")
                        optionalNumberRow("干草", keyPath: \.piecesOfHay)
                    }
                }

                if session.draft.progress.deepestMineLevel != nil
                    || session.draft.progress.mineLowestLevelReached != nil {
                    Section {
                        optionalNumberRow("个人到达最深层", keyPath: \.deepestMineLevel, assetName: "GameUIStone")
                        optionalNumberRow("世界矿井解锁层", keyPath: \.mineLowestLevelReached, assetName: "GameUIStone")
                    } header: {
                        Text("矿洞进度")
                    } footer: {
                        Text("普通矿井为 1…120 层；更高值可能属于骷髅洞穴。应用保留存档中原有的特殊层数。")
                    }
                }

                Section("天气与任务（只读）") {
                    LabeledContent("明日天气", value: weatherName(session.draft.progress.insights.weatherForTomorrow))
                    LabeledContent(
                        "每日运气",
                        value: session.draft.progress.insights.dailyLuck.map {
                            $0.formatted(.number.precision(.fractionLength(0...3)))
                        } ?? "未提供"
                    )
                    LabeledContent("进行中任务", value: "\(session.draft.progress.insights.activeQuestCount)")
                    LabeledContent("已完成成就", value: "\(session.draft.progress.insights.achievementCount)")
                }

                Section("收藏进度（只读）") {
                    insightRow("已出货种类", value: session.draft.progress.insights.shippedItemKinds, assetName: "GameUIReview")
                    insightRow("已捕获鱼类", value: session.draft.progress.insights.caughtFishKinds, assetName: "GameUIFish")
                    insightRow("已发现矿物", value: session.draft.progress.insights.mineralKinds, assetName: "GameUIDiamond")
                    insightRow("已发现古物", value: session.draft.progress.insights.artifactKinds, assetName: "GameUIArtifact")
                    insightRow("秘密纸条", value: session.draft.progress.insights.secretNoteCount, assetName: "GameUIDwarfGuide")
                    insightRow("已观看事件", value: session.draft.progress.insights.eventCount, assetName: "GameUITrophy")
                }

                if progressHasChanges {
                    Section("进度草稿") {
                        Button("撤销财富与矿洞修改", systemImage: "arrow.uturn.backward") {
                            let original = session.originalDraft.progress
                            session.draft.progress.qiGems = original.qiGems
                            session.draft.progress.clubCoins = original.clubCoins
                            session.draft.progress.totalMoneyEarned = original.totalMoneyEarned
                            session.draft.progress.goldenWalnuts = original.goldenWalnuts
                            session.draft.progress.piecesOfHay = original.piecesOfHay
                            session.draft.progress.deepestMineLevel = original.deepestMineLevel
                            session.draft.progress.mineLowestLevelReached = original.mineLowestLevelReached
                        }
                    }
                }
            }
            .navigationTitle("财富与进度")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    @ViewBuilder
    private func optionalNumberRow(
        _ title: String,
        keyPath: WritableKeyPath<ProgressDraft, Int?>,
        assetName: String? = nil
    ) -> some View {
        if session.draft.progress[keyPath: keyPath] != nil {
            LabeledContent {
                TextField("0", value: optionalIntBinding(keyPath), format: .number)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
            } label: {
                if let assetName {
                    GameAssetLabel(title, assetName: assetName, iconSize: 24)
                } else {
                    Text(title)
                }
            }
        }
    }

    private func optionalIntBinding(_ keyPath: WritableKeyPath<ProgressDraft, Int?>) -> Binding<Int> {
        Binding(
            get: { session.draft.progress[keyPath: keyPath] ?? 0 },
            set: { session.draft.progress[keyPath: keyPath] = $0 }
        )
    }

    private func insightRow(_ title: String, value: Int, assetName: String) -> some View {
        HStack {
            GameAssetLabel(title, assetName: assetName, iconSize: 24)
            Spacer()
            Text(value.formatted())
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }

    private var hasCurrencyFields: Bool {
        let progress = session.draft.progress
        return progress.qiGems != nil || progress.clubCoins != nil
            || progress.totalMoneyEarned != nil || progress.goldenWalnuts != nil
            || progress.piecesOfHay != nil
    }

    private var progressHasChanges: Bool {
        let draft = session.draft.progress
        let original = session.originalDraft.progress
        return draft.qiGems != original.qiGems
            || draft.clubCoins != original.clubCoins
            || draft.totalMoneyEarned != original.totalMoneyEarned
            || draft.goldenWalnuts != original.goldenWalnuts
            || draft.piecesOfHay != original.piecesOfHay
            || draft.deepestMineLevel != original.deepestMineLevel
            || draft.mineLowestLevelReached != original.mineLowestLevelReached
    }

    private func weatherName(_ raw: String?) -> String {
        guard let raw, !raw.isEmpty else { return "未提供" }
        return switch raw.lowercased() {
        case "sun": "晴天"
        case "rain": "雨天"
        case "storm": "雷雨"
        case "snow": "下雪"
        case "wind", "debris": "大风"
        case "greenrain": "绿雨"
        default: raw
        }
    }
}
