import SwiftUI

struct SkillsEditorView: View {
    @Bindable var session: SaveSession

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 14) {
                        GameIcon(systemName: "star.circle.fill", size: 40)
                            .font(.largeTitle)
                            .foregroundStyle(.purple)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("等级、经验与职业")
                                .font(.headline)
                            Text("五项技能会作为同一份草稿安全写回")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                } footer: {
                    Text("选择 10 级职业时会自动保留其对应的 5 级职业，避免产生无父职业的异常组合。")
                }

                ForEach(session.draft.skills.indices, id: \.self) { index in
                    let skill = session.draft.skills[index]
                    Section {
                        Stepper(
                            "等级：\(skill.level)",
                            value: levelBinding(index),
                            in: 0...10
                        )

                        LabeledContent("经验值") {
                            TextField("0", value: experienceBinding(index), format: .number)
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing)
                        }

                        ProgressView(value: Double(skill.targetExperience), total: 15_000)
                            .tint(skillColor(skill.key))

                        Picker("5 级职业", selection: primaryProfessionBinding(skill.key)) {
                            Text("未选择").tag(Int?.none)
                            ForEach(primaryProfessions(for: skill.key)) { option in
                                Text(option.name).tag(Optional(option.id))
                            }
                        }
                        .disabled(skill.level < 5)

                        Picker("10 级职业", selection: secondaryProfessionBinding(skill.key)) {
                            Text("未选择").tag(Int?.none)
                            ForEach(availableSecondaryProfessions(for: skill.key)) { option in
                                Text(option.name).tag(Optional(option.id))
                            }
                        }
                        .disabled(skill.level < 10 || selectedPrimary(for: skill.key) == nil)
                    } header: {
                        GameLabel(skill.key.displayName, systemImage: skillIcon(skill.key))
                    } footer: {
                        if skill.level < 5 {
                            Text("达到 5 级后可选择职业。")
                        } else if skill.level < 10 {
                            Text("达到 10 级后可选择分支职业。")
                        }
                    }
                }

                if session.draft.skills != session.originalDraft.skills
                    || session.draft.progress.professionIDs != session.originalDraft.progress.professionIDs {
                    Section("技能草稿") {
                        Button("撤销全部技能与职业修改", systemImage: "arrow.uturn.backward") {
                            session.draft.skills = session.originalDraft.skills
                            session.draft.progress.professionIDs = session.originalDraft.progress.professionIDs
                        }
                    }
                }
            }
            .navigationTitle("技能与职业")
        }
    }

    private func levelBinding(_ index: Int) -> Binding<Int> {
        Binding(
            get: { session.draft.skills[index].level },
            set: { value in
                let key = session.draft.skills[index].key
                session.draft.setSkillLevel(value, for: key)
            }
        )
    }

    private func experienceBinding(_ index: Int) -> Binding<Int> {
        Binding(
            get: { session.draft.skills[index].targetExperience },
            set: { value in
                let key = session.draft.skills[index].key
                session.draft.setSkillExperience(value, for: key)
            }
        )
    }

    private func primaryProfessions(for skill: SkillKey) -> [ProfessionOption] {
        ProfessionCatalog.options(for: skill).filter { $0.tier == 5 }
    }

    private func selectedPrimary(for skill: SkillKey) -> Int? {
        primaryProfessions(for: skill).first { session.draft.progress.professionIDs.contains($0.id) }?.id
    }

    private func availableSecondaryProfessions(for skill: SkillKey) -> [ProfessionOption] {
        guard let primary = selectedPrimary(for: skill) else { return [] }
        return ProfessionCatalog.options(for: skill).filter { $0.parentID == primary }
    }

    private func selectedSecondary(for skill: SkillKey) -> Int? {
        availableSecondaryProfessions(for: skill)
            .first { session.draft.progress.professionIDs.contains($0.id) }?.id
    }

    private func primaryProfessionBinding(_ skill: SkillKey) -> Binding<Int?> {
        Binding(
            get: { selectedPrimary(for: skill) },
            set: { session.draft.setPrimaryProfession($0, for: skill) }
        )
    }

    private func secondaryProfessionBinding(_ skill: SkillKey) -> Binding<Int?> {
        Binding(
            get: { selectedSecondary(for: skill) },
            set: { session.draft.setSecondaryProfession($0, for: skill) }
        )
    }

    private func skillIcon(_ skill: SkillKey) -> String {
        switch skill {
        case .farming: "carrot.fill"
        case .fishing: "fish.fill"
        case .foraging: "tree.fill"
        case .mining: "hammer.fill"
        case .combat: "shield.lefthalf.filled"
        }
    }

    private func skillColor(_ skill: SkillKey) -> Color {
        switch skill {
        case .farming: .green
        case .fishing: .blue
        case .foraging: .mint
        case .mining: .gray
        case .combat: .red
        }
    }
}
