import SwiftUI

struct AppearanceEditorView: View {
    @Bindable var session: SaveSession
    @State private var appearanceCategory: AppearanceCategory = .hair

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 12) {
                        AppearanceDataSnapshot(
                            title: "原始",
                            gender: session.originalDraft.gender,
                            hair: session.originalDraft.hair,
                            skin: session.originalDraft.skin,
                            accessory: session.originalDraft.accessory,
                            isCurrent: false
                        )

                        GameIcon(systemName: "arrow.right", size: 20)
                            .font(.headline)
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)

                        AppearanceDataSnapshot(
                            title: "当前草稿",
                            gender: session.draft.gender,
                            hair: session.draft.hair,
                            skin: session.draft.skin,
                            accessory: session.draft.accessory,
                            isCurrent: true
                        )
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                } header: {
                    Text("原始与草稿")
                } footer: {
                    Text("数值直接对应存档中的 Gender、hair、skin 与 accessory 字段。")
                }

                Section("人物基础") {
                    Picker("性别", selection: $session.draft.gender) {
                        ForEach(FarmerGender.allCases) { gender in
                            Text(gender.displayName).tag(gender)
                        }
                    }
                }

                Section {
                    Picker("类别", selection: $appearanceCategory) {
                        ForEach(AppearanceCategory.allCases) { category in
                            Text(category.title).tag(category)
                        }
                    }
                    .pickerStyle(.segmented)

                    appearanceChoiceGrid

                    Stepper(
                        "精确编号：\(selectedAppearanceValue)",
                        value: selectedAppearanceBinding,
                        in: appearanceCategory.range
                    )
                } header: {
                    Text("发型、肤色与饰品")
                } footer: {
                    Text("可以点选标准编号，也可以用步进器精确调整。")
                }

                if hasAppearanceChanges {
                    Section("外观草稿") {
                        Button("恢复原始外观", systemImage: "arrow.uturn.backward") {
                            session.draft.gender = session.originalDraft.gender
                            session.draft.hair = session.originalDraft.hair
                            session.draft.skin = session.originalDraft.skin
                            session.draft.accessory = session.originalDraft.accessory
                        }
                    }
                }
            }
            .navigationTitle("人物外观")
        }
    }

    private var appearanceValues: [Int] {
        Array(appearanceCategory.range)
    }

    private var selectedAppearanceValue: Int {
        switch appearanceCategory {
        case .hair: session.draft.hair
        case .skin: session.draft.skin
        case .accessory: session.draft.accessory
        }
    }

    private var selectedAppearanceBinding: Binding<Int> {
        Binding(
            get: { selectedAppearanceValue },
            set: { setAppearanceValue($0) }
        )
    }

    private var appearanceChoiceGrid: some View {
        let rows = Array(repeating: GridItem(.fixed(74), spacing: 8), count: 3)
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                GameLabel(appearanceCategory.helpText, systemImage: appearanceCategory.icon)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(appearanceValues.count) 项")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            if appearanceCategory == .skin,
               GameArtwork.appearanceImage(category: "skin", index: selectedAppearanceValue) == nil {
                Text("缺少原版肤色色板，暂无颜色预览。这里按存档编号选择肤色。")
                    .font(.caption).foregroundStyle(.secondary)
            }

            ScrollView(.horizontal) {
                LazyHGrid(rows: rows, spacing: 8) {
                    ForEach(appearanceValues, id: \.self) { value in
                        Button {
                            setAppearanceValue(value)
                        } label: {
                            AppearanceChoiceButton(
                                value: value,
                                category: appearanceCategory,
                                isSelected: selectedAppearanceValue == value
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(appearanceCategory.title)编号 \(value)")
                        .accessibilityAddTraits(selectedAppearanceValue == value ? .isSelected : [])
                    }
                }
                .padding(.vertical, 3)
            }
            .scrollIndicators(.visible)
            .frame(height: 250)
        }
    }

    private var hasAppearanceChanges: Bool {
        session.draft.gender != session.originalDraft.gender
            || session.draft.hair != session.originalDraft.hair
            || session.draft.skin != session.originalDraft.skin
            || session.draft.accessory != session.originalDraft.accessory
    }

    private func setAppearanceValue(_ value: Int) {
        switch appearanceCategory {
        case .hair: session.draft.hair = value
        case .skin: session.draft.skin = value
        case .accessory: session.draft.accessory = value
        }
    }
}

private enum AppearanceCategory: String, CaseIterable, Identifiable {
    case hair
    case skin
    case accessory

    var id: String { rawValue }

    var title: String {
        switch self {
        case .hair: "发型"
        case .skin: "肤色"
        case .accessory: "饰品"
        }
    }

    var helpText: String {
        switch self {
        case .hair: "选择 0…73 的游戏发型编号"
        case .skin: "选择 0…23 的游戏肤色编号"
        case .accessory: "-1 表示不佩戴饰品"
        }
    }

    var icon: String {
        switch self {
        case .hair: "person.crop.circle"
        case .skin: "paintpalette.fill"
        case .accessory: "eyeglasses"
        }
    }

    var range: ClosedRange<Int> {
        switch self {
        case .hair: 0...73
        case .skin: 0...23
        case .accessory: -1...29
        }
    }
}

private struct AppearanceDataSnapshot: View {
    let title: String
    let gender: FarmerGender
    let hair: Int
    let skin: Int
    let accessory: Int
    let isCurrent: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.bold())
                .foregroundStyle(isCurrent ? Color.accentColor : Color.secondary)
            Divider()
            HStack(spacing: 8) {
                if let sprite = GameArtwork.appearanceImage(category: "hair", index: hair) {
                    Image(uiImage: sprite).resizable().interpolation(.none).scaledToFit()
                        .frame(width: 36, height: 36)
                        .accessibilityLabel("发型 \(hair) 原版贴图")
                } else {
                    Text("发型无预览").font(.caption2).foregroundStyle(.secondary)
                }
                if let sprite = GameArtwork.appearanceImage(category: "accessory", index: accessory) {
                    Image(uiImage: sprite).resizable().interpolation(.none).scaledToFit()
                        .frame(width: 36, height: 36)
                        .accessibilityLabel("饰品 \(accessory) 原版贴图")
                } else if accessory >= 0 {
                    Text("饰品无预览").font(.caption2).foregroundStyle(.secondary)
                }
            }
            appearanceValue("性别", gender.displayName)
            appearanceValue("发型", hair.formatted())
            appearanceValue("肤色", skin.formatted())
            if GameArtwork.appearanceImage(category: "skin", index: skin) == nil {
                Text("肤色暂无原版色板预览").font(.caption2).foregroundStyle(.secondary)
            }
            appearanceValue("饰品", accessory < 0 ? "无（-1）" : accessory.formatted())
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            isCurrent ? Color.accentColor.opacity(0.10) : Color.secondary.opacity(0.07),
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(
                    isCurrent ? Color.accentColor.opacity(0.65) : Color.secondary.opacity(0.18),
                    lineWidth: isCurrent ? 2 : 1
                )
        }
    }

    private func appearanceValue(_ label: String, _ value: String) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer(minLength: 4)
            Text(value)
                .fontWeight(.semibold)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .font(.caption)
    }
}

private struct AppearanceChoiceButton: View {
    let value: Int
    let category: AppearanceCategory
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 2) {
            if let sprite = GameArtwork.appearanceImage(category: category.rawValue, index: value) {
                Image(uiImage: sprite)
                    .resizable()
                    .interpolation(.none)
                    .scaledToFit()
                    .frame(width: 40, height: 40)
            } else if value < 0 {
                Text("无").font(.headline).frame(height: 40)
            } else {
                Text("无预览")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(height: 40)
            }
            Text(value.formatted())
                .font(.caption.bold())
                .monospacedDigit()
        }
        .frame(width: 62, height: 70)
        .background(isSelected ? Color.accentColor.opacity(0.16) : Color.secondary.opacity(0.06))
        .overlay {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
        }
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
    }
}
