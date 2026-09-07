import SwiftUI

struct AnimalsEditorView: View {
    @Bindable var session: SaveSession
    @State private var showingMaxConfirmation = false

    var body: some View {
        NavigationStack {
            Group {
                if session.draft.animals.isEmpty {
                    ContentUnavailableView(
                        "没有找到可编辑动物",
                        systemImage: "pawprint",
                        description: Text("动物仍可能存在于模组自定义结构中；应用不会猜测未知节点。")
                    )
                } else {
                    List {
                        Section {
                            Button("全部恢复最佳状态", systemImage: "sparkles") {
                                showingMaxConfirmation = true
                            }
                            .foregroundStyle(.orange)
                        } footer: {
                            Text("会将亲密度设为 1000，心情与饱食度设为 255；名称和饲养天数保持不变。")
                        }

                        ForEach(session.draft.animals.indices, id: \.self) { index in
                            NavigationLink {
                                AnimalDetailEditorView(session: session, index: index)
                            } label: {
                                HStack(spacing: 14) {
                                    AnimalPreview(type: session.draft.animals[index].type, size: 48)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(session.draft.animals[index].name)
                                            .font(.headline)
                                        Text("\(session.draft.animals[index].localizedType) · \(session.draft.animals[index].home)")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        if GameArtwork.animalImage(type: session.draft.animals[index].type) == nil {
                                            Text("缺少该动物的原版贴图，无预览")
                                                .font(.caption2).foregroundStyle(.secondary)
                                        }
                                    }
                                    Spacer()
                                    GameLabel("\(session.draft.animals[index].hearts)", systemImage: "heart.fill")
                                        .font(.caption.bold())
                                        .foregroundStyle(.pink)
                                }
                            }
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
            .confirmationDialog("将全部动物恢复最佳状态？", isPresented: $showingMaxConfirmation) {
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
    let index: Int

    var body: some View {
        Form {
            Section {
                HStack(spacing: 16) {
                    AnimalPreview(type: session.draft.animals[index].type, size: 56)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(session.draft.animals[index].localizedType)
                            .font(.headline)
                        Text(session.draft.animals[index].home)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if GameArtwork.animalImage(type: session.draft.animals[index].type) == nil {
                            Text("缺少原版动物贴图；下方为存档实际数据。")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section("身份") {
                TextField("动物名称", text: nameBinding)
                    .submitLabel(.done)
                    .onSubmit { KeyboardReturnAction.dismiss() }
                Stepper(
                    "饲养 \(session.draft.animals[index].daysOwned) 天",
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
                    guard let original = session.originalDraft.animals.first(where: {
                        $0.id == session.draft.animals[index].id
                    }) else { return }
                    session.draft.animals[index] = original
                }
            }
        }
        .navigationTitle(session.draft.animals[index].name)
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
        Binding(
            get: { session.draft.animals[index].name },
            set: { session.draft.animals[index].name = $0 }
        )
    }

    private var daysBinding: Binding<Int> {
        Binding(
            get: { session.draft.animals[index].daysOwned },
            set: { session.draft.animals[index].daysOwned = $0 }
        )
    }

    private var friendshipBinding: Binding<Int> {
        Binding(
            get: { session.draft.animals[index].friendship },
            set: { session.draft.animals[index].friendship = $0 }
        )
    }

    private var happinessBinding: Binding<Int> {
        Binding(
            get: { session.draft.animals[index].happiness },
            set: { session.draft.animals[index].happiness = $0 }
        )
    }

    private var fullnessBinding: Binding<Int> {
        Binding(
            get: { session.draft.animals[index].fullness },
            set: { session.draft.animals[index].fullness = $0 }
        )
    }
}

/// An animal is shown only when its own game texture is available.
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
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(width: size, height: size)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
        .accessibilityLabel(GameArtwork.animalImage(type: type) == nil
                            ? "\(type)，缺少原版动物贴图，无预览" : "\(type)，游戏原版贴图")
    }
}
