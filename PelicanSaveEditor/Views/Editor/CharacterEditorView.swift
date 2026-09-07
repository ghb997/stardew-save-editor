import SwiftUI

struct CharacterEditorView: View {
    @Bindable var session: SaveSession

    var body: some View {
        NavigationStack {
            Form {
                if !session.metadata.warnings.isEmpty {
                    Section("注意") {
                        ForEach(session.metadata.warnings, id: \.self) { warning in
                            GameLabel(warning, systemImage: "exclamationmark.triangle.fill")
                                .font(.footnote)
                                .foregroundStyle(.orange)
                        }
                    }
                }

                Section {
                    LabeledContent(
                        "存档角色",
                        value: session.originalDraft.playerName.isEmpty ? "未命名农夫" : session.originalDraft.playerName
                    )
                    LabeledContent(
                        "存档农场",
                        value: session.originalDraft.farmName.isEmpty
                            ? session.source.farmIdentifier
                            : session.originalDraft.farmName
                    )
                    LabeledContent("游戏版本", value: session.metadata.gameVersion)
                } header: {
                    Text("当前游戏存档")
                } footer: {
                    Text("先修改草稿，检查全部变化后再保存到存档。")
                }

                Section("身份") {
                    TextField("玩家名称", text: $session.draft.playerName)
                        .submitLabel(.done)
                        .onSubmit { KeyboardReturnAction.dismiss() }
                    TextField("农场名称", text: $session.draft.farmName)
                        .submitLabel(.done)
                        .onSubmit { KeyboardReturnAction.dismiss() }
                    TextField("最喜欢的东西", text: $session.draft.favoriteThing)
                        .submitLabel(.done)
                        .onSubmit { KeyboardReturnAction.dismiss() }
                }

                Section {
                    LabeledContent("金钱") {
                        TextField("0", value: $session.draft.money, format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                    }
                    LabeledContent("最大生命") {
                        TextField("100", value: $session.draft.maxHealth, format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                    }
                    LabeledContent("最大体力") {
                        TextField("270", value: $session.draft.maxStamina, format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                    }
                } header: {
                    Text("数值")
                } footer: {
                    Text("安全范围：金钱 0…2147483647，生命 1…999，体力 1…9999。")
                }

                Section {
                    Stepper("第 \(session.draft.year) 年", value: $session.draft.year, in: 1...99)
                    Picker("季节", selection: $session.draft.season) {
                        ForEach(Season.allCases) { season in
                            Text(season.displayName).tag(season)
                        }
                    }
                    Stepper("第 \(session.draft.day) 日", value: $session.draft.day, in: 1...28)
                } header: {
                    Text("游戏日期")
                } footer: {
                    Text("只修改日期字段，不自动结算作物、任务或剧情。进游戏后建议立即睡觉保存一次。")
                }

            }
            .navigationTitle("角色与农场")
        }
    }
}
