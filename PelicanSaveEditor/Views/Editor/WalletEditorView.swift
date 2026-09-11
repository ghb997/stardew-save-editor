import SwiftUI

struct WalletEditorView: View {
    @Bindable var session: SaveSession

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Image("GameUIWalletStrip")
                            .resizable()
                            .interpolation(.none)
                            .scaledToFit()
                            .frame(maxWidth: 380, maxHeight: 84)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .accessibilityHidden(true)
                        Text("钱包特殊物品与能力")
                            .font(.headline)
                        Text("兼容星露谷物语 1.6 的存档标记")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } footer: {
                    Text("未知邮件与剧情标记会原样保留；这里只处理下列已知钱包能力。")
                }

                Section("特殊物品与能力") {
                    ForEach(session.draft.progress.walletUnlocks.indices, id: \.self) { index in
                        Toggle(isOn: walletBinding(index)) {
                            walletLabel(session.draft.progress.walletUnlocks[index].key)
                        }
                    }
                }

                Section("状态") {
                    LabeledContent("已获得", value: "\(session.draft.progress.walletUnlocks.filter(\.isUnlocked).count) / \(WalletUnlockKey.allCases.count)")
                    LabeledContent("存档全部邮件标记", value: "\(session.draft.progress.insights.mailFlagCount)")
                }

                if session.draft.progress.walletUnlocks != session.originalDraft.progress.walletUnlocks {
                    Section("能力草稿") {
                        Button("撤销全部特殊能力修改", systemImage: "arrow.uturn.backward") {
                            session.draft.progress.walletUnlocks = session.originalDraft.progress.walletUnlocks
                        }
                    }
                }
            }
            .navigationTitle("特殊物品与能力")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func walletBinding(_ index: Int) -> Binding<Bool> {
        Binding(
            get: { session.draft.progress.walletUnlocks[index].isUnlocked },
            set: { session.draft.progress.walletUnlocks[index].isUnlocked = $0 }
        )
    }

    @ViewBuilder
    private func walletLabel(_ key: WalletUnlockKey) -> some View {
        if let assetName = GameArtwork.walletAsset(key) {
            GameAssetLabel(key.displayName, assetName: assetName, iconSize: 24)
        } else {
            GameLabel(key.displayName, systemImage: key.systemImage)
        }
    }
}
