import SwiftUI

struct RecipesEditorView: View {
    @Bindable var session: SaveSession
    @State private var selectedKind: RecipeKind = .cooking
    @State private var searchText = ""
    @State private var showingUnlockAllConfirmation = false

    private var filteredIndices: [Int] {
        session.draft.recipes.indices.filter { index in
            let recipe = session.draft.recipes[index]
            guard recipe.kind == selectedKind else { return false }
            return searchText.isEmpty
                || recipe.key.localizedCaseInsensitiveContains(searchText)
                || RecipeCatalog.localizedName(for: recipe.key)
                    .localizedCaseInsensitiveContains(searchText)
        }
    }

    private var unlockedCount: Int {
        session.draft.recipes.filter { $0.kind == selectedKind && $0.unlocked }.count
    }

    private var selectedRecipes: [RecipeDraft] {
        session.draft.recipes.filter { $0.kind == selectedKind }
    }

    private var localizedCount: Int {
        selectedRecipes.filter { RecipeCatalog.hasChineseName(for: $0.key) }.count
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("分类", selection: $selectedKind) {
                        ForEach(RecipeKind.allCases) { kind in
                            Text(kind.displayName).tag(kind)
                        }
                    }
                    .pickerStyle(.segmented)

                    LabeledContent("已解锁", value: "\(unlockedCount) 项")
                    LabeledContent(
                        "中文名称",
                        value: "\(localizedCount) / \(selectedRecipes.count)"
                    )
                    Button("解锁当前分类", systemImage: "lock.open") {
                        unlock(kind: selectedKind)
                    }
                    Button("解锁全部烹饪与制作配方", systemImage: "books.vertical.fill") {
                        showingUnlockAllConfirmation = true
                    }
                } header: {
                    GameAssetLabel("配方范围", assetName: "GameUIRecipes", iconSize: 24)
                }

                Section {
                    ForEach(filteredIndices, id: \.self) { index in
                        Toggle(isOn: recipeBinding(index)) {
                            HStack(spacing: 12) {
                                RecipeArtworkView(
                                    key: session.draft.recipes[index].key,
                                    kind: session.draft.recipes[index].kind,
                                    size: 42
                                )
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(RecipeCatalog.localizedName(
                                        for: session.draft.recipes[index].key
                                    ))
                                    if RecipeCatalog.hasChineseName(
                                        for: session.draft.recipes[index].key
                                    ) {
                                        Text(session.draft.recipes[index].key)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                        .padding(.vertical, 2)
                    }
                } header: {
                    GameAssetLabel(selectedKind.displayName, assetName: "GameUIRecipes", iconSize: 24)
                } footer: {
                    Text("新解锁的配方会写入制作次数 0；已有配方的次数保持不变。")
                }
            }
            .searchable(text: $searchText, prompt: "搜索中文或英文配方名")
            .onSubmit(of: .search) { KeyboardReturnAction.dismiss() }
            .navigationTitle("配方")
        }
        .confirmationDialog("解锁全部配方？", isPresented: $showingUnlockAllConfirmation) {
            Button("全部解锁") {
                for index in session.draft.recipes.indices {
                    session.draft.recipes[index].unlocked = true
                }
            }
            Button("取消", role: .cancel) {}
        }
    }

    private func recipeBinding(_ index: Int) -> Binding<Bool> {
        Binding(
            get: { session.draft.recipes[index].unlocked },
            set: { session.draft.recipes[index].unlocked = $0 }
        )
    }

    private func unlock(kind: RecipeKind) {
        for index in session.draft.recipes.indices where session.draft.recipes[index].kind == kind {
            session.draft.recipes[index].unlocked = true
        }
    }
}

struct RecipeArtworkView: View {
    let key: String
    let kind: RecipeKind
    var size: CGFloat = 42

    var body: some View {
        Group {
            if let sprite = GameArtwork.recipeImage(key: key, kind: kind) {
                Image(uiImage: sprite)
                    .resizable()
                    .interpolation(.none)
                    .scaledToFit()
                    .padding(4)
            } else {
                GameIcon(systemName: "questionmark", size: size * 0.65)
            }
        }
        .frame(width: size, height: size)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 8))
        .accessibilityHidden(true)
    }
}
