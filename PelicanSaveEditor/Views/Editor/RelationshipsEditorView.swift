import SwiftUI

struct RelationshipsEditorView: View {
    @Bindable var session: SaveSession
    @State private var searchText = ""
    @State private var filter: RelationshipFilter = .all
    @State private var batchRequest: RelationshipBatchRequest?

    private var filteredIndices: [Int] {
        session.draft.friendships.indices.filter { index in
            let friend = session.draft.friendships[index]
            let original = session.originalDraft.friendships.first { $0.name == friend.name }
            guard filter.includes(friend, original: original) else { return false }
            let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            return query.isEmpty || friend.name.localizedCaseInsensitiveContains(query)
                || friend.localizedName.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if session.draft.friendships.isEmpty {
                    GameEmptyState(title: "没有关系数据", systemImage: "heart.slash")
                } else {
                    List {
                        Section {
                            Picker("人物筛选", selection: $filter) {
                                ForEach(RelationshipFilter.allCases) { value in
                                    Text(value.title).tag(value)
                                }
                            }
                            .accessibilityIdentifier("editor.relationships.filter")
                            LabeledContent("当前结果", value: "\(filteredIndices.count) / \(session.draft.friendships.count) 人")
                            ForEach(RelationshipBatchAction.allCases) { action in
                                let candidates = filteredIndices.map { session.draft.friendships[$0] }.filter(action.willChange)
                                Button("\(action.title) · \(candidates.count) 人", systemImage: action == .fillHearts ? "heart.fill" : "gift") {
                                    batchRequest = RelationshipBatchRequest(action: action, friends: candidates)
                                }
                                .disabled(candidates.isEmpty)
                                .accessibilityIdentifier("editor.relationships.batch.\(action.rawValue)")
                            }
                        } header: {
                            Text("筛选与批量操作")
                        } footer: {
                            Text("批量操作只包含当前搜索与筛选结果，先预览，再加入待保存草稿。")
                        }
                        Section {
                            if filteredIndices.isEmpty {
                                ContentUnavailableView("没有匹配角色", systemImage: "person.crop.circle.badge.questionmark",
                                    description: Text("试试其他名字，或切换人物筛选。"))
                            }
                            ForEach(filteredIndices, id: \.self) { index in
                                RelationshipRow(session: session, index: index)
                            }
                        } header: {
                            GameAssetLabel("人物关系", assetName: "GameUIRelationships", iconSize: 24)
                        } footer: {
                            Text("订婚、婚姻和离婚涉及配偶、日期、住宅及剧情字段，因此状态保持只读；好感点数仍可调整。")
                        }
                    }
                    .accessibilityIdentifier("editor.relationships.list")
                    .searchable(text: $searchText, prompt: "搜索角色名称")
                    .onSubmit(of: .search) { KeyboardReturnAction.dismiss() }
                }
            }
            .navigationTitle("人物关系")
        }
        .sheet(item: $batchRequest) { request in
            RelationshipBatchPreview(session: session, request: request)
        }
    }
}

private struct RelationshipBatchRequest: Identifiable {
    let id = UUID()
    let action: RelationshipBatchAction
    let friends: [FriendshipDraft]
}

private struct RelationshipBatchPreview: View {
    @Bindable var session: SaveSession
    let request: RelationshipBatchRequest
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("将修改 \(request.friends.count) 位角色")
                        .font(.headline)
                    Text(request.action == .fillHearts
                        ? "按当前关系补到 8、10 或 14 心。已有更高好感会保留；关系状态不会改变。"
                        : "将已有的今日、本周送礼次数清零。好感、婚姻和上次送礼日期会保留。")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                Section("本次范围") {
                    ForEach(request.friends) { friend in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(friend.localizedName).font(.headline)
                            if request.action == .fillHearts, let target = FriendshipRules.fullHeartPoints(for: friend) {
                                Text("\(friend.points) → \(target) 点")
                            } else {
                                if let count = friend.giftsToday { Text("今日：\(count) → 0 次") }
                                if let count = friend.giftsThisWeek { Text("本周：\(count) → 0 次") }
                            }
                        }
                    }
                }
                Section {
                    Button("加入草稿", systemImage: "checkmark") {
                        session.draft.applyRelationshipBatch(request.action, names: Set(request.friends.map(\.name)))
                        dismiss()
                    }
                    .accessibilityIdentifier("editor.relationships.batch.apply")
                    .disabled(session.isEditingLocked)
                } footer: {
                    Text("可在“检查与保存”中逐项撤销；最终保存时才会写入存档。")
                }
            }
            .accessibilityIdentifier("editor.relationships.preview.list")
            .navigationTitle(request.action.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
        }
    }
}

private struct RelationshipRow: View {
    @Bindable var session: SaveSession
    let index: Int

    private var friend: FriendshipDraft { session.draft.friendships[index] }
    private var isDateable: Bool { FriendshipRules.dateableCharacters.contains(friend.name) }
    private var maximumPoints: Int {
        FriendshipRules.maximumEditablePoints(for: friend)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                GameNPCPortrait(name: friend.name, size: 52)
                VStack(alignment: .leading, spacing: 2) {
                    Text(friend.localizedName)
                        .font(.headline)
                    if npcChineseNames[friend.name] != nil {
                        Text(friend.name).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                GameLabel("\(friend.hearts)", systemImage: "heart.fill")
                    .foregroundStyle(.pink)
            }

            LabeledContent("直接输入好感") {
                TextField("好感点数", value: pointsBinding, format: .number)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .accessibilityLabel("\(friend.localizedName) 好感点数")
                    .accessibilityIdentifier("editor.relationship.\(friend.name).points")
                    .disabled(!friend.hasEditablePoints)
            }
            Stepper(
                "好感：\(friend.points) 点",
                value: pointsBinding,
                in: 0...maximumPoints,
                step: 10
            )
            .disabled(!friend.hasEditablePoints)

            HStack {
                Button("0") { session.draft.friendships[index].points = 0 }
                Button("8 心") { session.draft.friendships[index].points = min(2_000, maximumPoints) }
                if let target = FriendshipRules.fullHeartPoints(for: friend) {
                    Button("满心") { session.draft.friendships[index].points = max(friend.points, target) }
                }
            }
            .buttonStyle(.bordered)
            .font(.caption)
            .disabled(!friend.hasEditablePoints)

            if friend.canEditStatus, isDateable {
                Picker("关系状态", selection: statusBinding) {
                    Text(RelationshipStatus.friendly.displayName).tag(RelationshipStatus.friendly)
                    Text(RelationshipStatus.dating.displayName).tag(RelationshipStatus.dating)
                }
                .pickerStyle(.segmented)
            } else {
                LabeledContent("状态", value: friend.status.displayName)
                    .foregroundStyle(.secondary)
            }
            if friend.giftsToday != nil || friend.giftsThisWeek != nil {
                VStack(alignment: .leading, spacing: 5) {
                    if let today = friend.giftsToday { LabeledContent("今日送礼", value: "\(today) 次") }
                    if let week = friend.giftsThisWeek { LabeledContent("本周送礼", value: "\(week) 次") }
                    Button("重置送礼次数", systemImage: "gift") {
                        session.draft.applyRelationshipBatch(.resetGifts, names: [friend.name])
                    }
                    .disabled(!RelationshipBatchAction.resetGifts.willChange(friend))
                    .accessibilityIdentifier("editor.relationship.\(friend.name).resetGifts")
                }
                .font(.subheadline)
            }
        }
        .padding(.vertical, 5)
    }

    private var pointsBinding: Binding<Int> {
        Binding(
            get: { session.draft.friendships[index].points },
            set: { session.draft.friendships[index].points = max(0, min($0, maximumPoints)) }
        )
    }

    private var statusBinding: Binding<RelationshipStatus> {
        Binding(
            get: { session.draft.friendships[index].status },
            set: {
                guard $0 == .friendly || $0 == .dating else { return }
                session.draft.friendships[index].status = $0
                session.draft.friendships[index].points = min(
                    session.draft.friendships[index].points,
                    $0 == .friendly ? 2_249 : 2_749
                )
            }
        )
    }
}

let npcChineseNames: [String: String] = [
    "Abigail": "阿比盖尔", "Alex": "亚历克斯", "Caroline": "卡洛琳",
    "Clint": "克林特", "Dwarf": "矮人", "Elliott": "艾利欧特",
    "Emily": "艾米丽", "Evelyn": "艾芙琳", "George": "乔治",
    "Gus": "格斯", "Haley": "海莉", "Harvey": "哈维", "Jas": "贾斯",
    "Jodi": "乔迪", "Kent": "肯特", "Krobus": "科罗布斯", "Leah": "莉亚",
    "Leo": "雷欧", "Lewis": "刘易斯", "Linus": "莱纳斯", "Marnie": "玛妮",
    "Maru": "玛鲁", "Pam": "潘姆", "Penny": "潘妮", "Pierre": "皮埃尔",
    "Robin": "罗宾", "Sam": "山姆", "Sandy": "桑迪", "Sebastian": "塞巴斯蒂安",
    "Shane": "谢恩", "Vincent": "文森特", "Willy": "威利", "Wizard": "法师",
    "Demetrius": "德米特里厄斯", "Birdie": "贝乔", "Bouncer": "保镖",
    "Gil": "吉尔", "Governor": "州长", "Gunther": "古瑟", "Henchman": "哥布林守卫",
    "Marlon": "马隆", "Morris": "莫里斯", "Mr. Qi": "齐先生", "Professor Snail": "蜗牛教授",
    "Trash Bear": "垃圾熊", "Bear": "熊", "Fizz": "菲兹", "Bookseller": "书商"
]
