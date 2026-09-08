import SwiftUI

struct RelationshipsEditorView: View {
    @Bindable var session: SaveSession
    @State private var searchText = ""

    private var filteredIndices: [Int] {
        session.draft.friendships.indices.filter { index in
            let friend = session.draft.friendships[index]
            return searchText.isEmpty
                || friend.name.localizedCaseInsensitiveContains(searchText)
                || npcChineseNames[friend.name]?.localizedCaseInsensitiveContains(searchText) == true
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
                            ForEach(filteredIndices, id: \.self) { index in
                                RelationshipRow(session: session, index: index)
                            }
                        } header: {
                            GameAssetLabel("人物关系", assetName: "GameUIRelationships", iconSize: 24)
                        } footer: {
                            Text("订婚、婚姻和离婚涉及配偶、日期、住宅及剧情字段，因此状态保持只读；好感点数仍可调整。")
                        }
                    }
                    .searchable(text: $searchText, prompt: "搜索角色名称")
                    .onSubmit(of: .search) { KeyboardReturnAction.dismiss() }
                }
            }
            .navigationTitle("人物关系")
        }
    }
}

private struct RelationshipRow: View {
    @Bindable var session: SaveSession
    let index: Int

    private var friend: FriendshipDraft { session.draft.friendships[index] }
    private var isDateable: Bool { dateableCharacters.contains(friend.name) }
    private var maximumPoints: Int {
        if friend.status == .married { return 3_749 }
        if isDateable, friend.status == .friendly { return 2_249 }
        return 2_749
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

            Stepper(
                "好感：\(friend.points) 点",
                value: pointsBinding,
                in: 0...maximumPoints,
                step: 10
            )

            HStack {
                Button("0") { session.draft.friendships[index].points = 0 }
                Button("8 心") { session.draft.friendships[index].points = min(2_000, maximumPoints) }
                Button("满心") { session.draft.friendships[index].points = maximumPoints }
            }
            .buttonStyle(.bordered)
            .font(.caption)

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
        }
        .padding(.vertical, 5)
    }

    private var pointsBinding: Binding<Int> {
        Binding(
            get: { session.draft.friendships[index].points },
            set: { session.draft.friendships[index].points = min($0, maximumPoints) }
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

private let dateableCharacters: Set<String> = [
    "Abigail", "Alex", "Elliott", "Emily", "Haley", "Harvey",
    "Leah", "Maru", "Penny", "Sam", "Sebastian", "Shane"
]

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
