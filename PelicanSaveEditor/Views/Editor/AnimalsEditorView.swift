import SwiftUI

struct AnimalsEditorView: View {
    @Bindable var session: SaveSession
    @State private var showingMaxConfirmation = false

    var body: some View {
        Group {
            Group {
                if session.draft.animals.isEmpty {
                    GameEmptyState(
                        title: "没有找到可编辑动物",
                        systemImage: "pawprint",
                        message: "动物仍可能存在于模组自定义结构中；应用不会猜测未知节点。"
                    )
                } else {
                    GameList {
                        Section {
                            Button("全部恢复最佳状态", systemImage: "sparkles") {
                                showingMaxConfirmation = true
                            }
                            .foregroundStyle(AppTheme.trackerWarning)
                        } header: {
                            GameAssetLabel("动物批量状态", assetName: "GameAnimalWhiteChicken", iconSize: 26)
                        } footer: {
                            Text("会将亲密度设为 1000，心情与饱食度设为 255；名称和饲养天数保持不变。动物图用于识别物种和颜色，不表示当前年龄、朝向或动作；三种鸡使用游戏内幼年示意图。")
                        }

                        ForEach(session.draft.animals) { animal in
                            NavigationLink {
                                AnimalDetailEditorView(session: session, animalID: animal.id)
                            } label: {
                                HStack(spacing: 14) {
                                    AnimalPreview(type: animal.type, size: 48)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(animal.name)
                                            .font(.headline)
                                        Text("\(animal.localizedType) · \(animal.home)")
                                            .font(.caption)
                                            .foregroundStyle(AppTheme.secondary)
                                        if GameArtwork.animalImage(type: animal.type) == nil {
                                            Text("缺少该动物的原版贴图，无预览")
                                                .font(.caption2).foregroundStyle(AppTheme.secondary)
                                        }
                                    }
                                    Spacer()
                                    GameLabel("\(animal.hearts)", systemImage: "heart.fill")
                                        .font(.caption.bold())
                                        .foregroundStyle(.pink)
                                }
                            }
                            .accessibilityIdentifier("editor.animal.\(animal.id)")
                        }

                        if session.draft.animals != session.originalDraft.animals {
                            Section("动物草稿") {
                                Button("撤销全部动物修改", systemImage: "arrow.uturn.backward") {
                                    session.draft.animals = session.originalDraft.animals
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("农场动物")
            .navigationBarTitleDisplayMode(.inline)
            .alert("将全部动物恢复最佳状态？", isPresented: $showingMaxConfirmation) {
                Button("恢复最佳状态") {
                    for index in session.draft.animals.indices {
                        session.draft.animals[index].friendship = 1_000
                        session.draft.animals[index].happiness = 255
                        session.draft.animals[index].fullness = 255
                    }
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("更改只会加入草稿，仍需在“检查与保存”中确认。")
            }
        }
    }


}

private struct AnimalDetailEditorView: View {
    @Bindable var session: SaveSession
    let animalID: String

    private var animal: FarmAnimalDraft? { session.draft.animals.first { $0.id == animalID } }

    var body: some View {
        GameForm {
            if let animal {
            Section {
                HStack(spacing: 16) {
                    AnimalPreview(type: animal.type, size: 56)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(animal.localizedType)
                            .font(.headline)
                        Text(animal.home)
                            .font(.caption)
                            .foregroundStyle(AppTheme.secondary)
                        if GameArtwork.animalImage(type: animal.type) == nil {
                            Text("缺少原版动物贴图；下方为存档实际数据。")
                                .font(.caption).foregroundStyle(AppTheme.secondary)
                        }
                    }
                }
            }

            Section("身份") {
                TextField("动物名称", text: nameBinding)
                    .accessibilityIdentifier("editor.animal.name")
                    .submitLabel(.done)
                    .onSubmit { KeyboardReturnAction.dismiss() }
                Stepper(
                    "饲养 \(animal.daysOwned) 天",
                    value: daysBinding,
                    in: 0...Int(Int32.max)
                )
            }

            Section("状态") {
                animalValueRow(
                    "亲密度",
                    value: friendshipBinding,
                    range: 0...1_000,
                    step: 50,
                    color: .pink
                )
                animalValueRow(
                    "心情",
                    value: happinessBinding,
                    range: 0...255,
                    step: 5,
                    color: .orange
                )
                animalValueRow(
                    "饱食度",
                    value: fullnessBinding,
                    range: 0...255,
                    step: 5,
                    color: .green
                )
            }

            Section {
                Button("恢复这只动物的原始值", systemImage: "arrow.uturn.backward") {
                    guard let index = session.draft.animals.firstIndex(where: { $0.id == animalID }),
                          let original = session.originalDraft.animals.first(where: { $0.id == animalID }) else { return }
                    session.draft.animals[index] = original
                }
            }
            } else {
                ContentUnavailableView("动物列表已更新", systemImage: "arrow.clockwise",
                    description: Text("这只动物已不在当前存档中，请返回动物列表重新选择。"))
            }
        }
        .navigationTitle(animal?.name ?? "农场动物")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func animalValueRow(
        _ title: String,
        value: Binding<Int>,
        range: ClosedRange<Int>,
        step: Int,
        color: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Stepper("\(title)：\(value.wrappedValue)", value: value, in: range, step: step)
            ProgressView(
                value: Double(value.wrappedValue - range.lowerBound),
                total: Double(range.upperBound - range.lowerBound)
            )
            .tint(color)
        }
        .padding(.vertical, 3)
    }

    private var nameBinding: Binding<String> {
        animalBinding(\.name, fallback: "")
    }

    private var daysBinding: Binding<Int> {
        animalBinding(\.daysOwned, fallback: 0)
    }

    private var friendshipBinding: Binding<Int> {
        animalBinding(\.friendship, fallback: 0)
    }

    private var happinessBinding: Binding<Int> {
        animalBinding(\.happiness, fallback: 0)
    }

    private var fullnessBinding: Binding<Int> {
        animalBinding(\.fullness, fallback: 0)
    }

    // Saving reparses and sorts animals by name. Resolve identity for every
    // read and write so the open detail never follows another animal's index.
    private func animalBinding<Value>(_ keyPath: WritableKeyPath<FarmAnimalDraft, Value>, fallback: Value) -> Binding<Value> {
        Binding(get: { animal?[keyPath: keyPath] ?? fallback }, set: { value in
            guard let index = session.draft.animals.firstIndex(where: { $0.id == animalID }) else { return }
            session.draft.animals[index][keyPath: keyPath] = value
        })
    }
}

/// An animal is shown only when its own verified game preview is available.
private struct AnimalPreview: View {
    let type: String
    let size: CGFloat

    var body: some View {
        Group {
            if let sprite = GameArtwork.animalImage(type: type) {
                Image(uiImage: sprite).resizable().interpolation(.none).scaledToFit()
            } else {
                Text("无预览")
                    .font(.caption2)
                    .foregroundStyle(AppTheme.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(width: size, height: size)
        .gameInset(AppTheme.inset)
        .accessibilityLabel(GameArtwork.animalImage(type: type) == nil
                            ? "\(type)，缺少原版动物贴图，无预览" : "\(type)，游戏原版贴图")
    }
}
