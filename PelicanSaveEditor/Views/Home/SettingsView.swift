import SwiftUI

struct SettingsView: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(EditorStore.self) private var store
    @Binding var selectedTab: MainTab
    @AppStorage("appearanceMode") private var appearanceMode = "system"

    var body: some View {
        VStack(spacing: 0) {
            LargePageHeader(title: "设置", systemImage: "gearshape.fill")

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if let session = store.session {
                        Text("农场")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                        farmCard(session)
                    }

                    Text("通用设置")
                        .font(.headline)
                        .foregroundStyle(.secondary)

                    VStack(spacing: 0) {
                        SettingsRow(title: "语言", value: "简体中文", systemImage: "character.bubble")
                        Divider().padding(.leading, 54)
                        HStack(spacing: 14) {
                            GameAssetIcon(assetName: "GameUIProgress", size: 26)
                                .frame(width: 30)
                            Text("外观")
                            Spacer()
                            Picker("外观", selection: $appearanceMode) {
                                Text("跟随系统").tag("system")
                                Text("浅色").tag("light")
                                Text("深色").tag("dark")
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                        }
                        .padding(18)
                    }
                    .appCard()

                    Text("关于")
                        .font(.headline)
                        .foregroundStyle(.secondary)

                    VStack(spacing: 0) {
                        SettingsRow(
                            title: "版本",
                            value: appVersion,
                            systemImage: "info.circle",
                            artworkName: "GameUITrophy"
                        )
                        Divider().padding(.leading, 54)
                        SettingsRow(
                            title: "存档处理",
                            value: "仅在设备本地",
                            systemImage: "lock.shield",
                            artworkName: "GameUIBackup"
                        )
                    }
                    .appCard()

                    Text("非官方个人工具；界面使用游戏内像素素材。修改存档前请完全退出游戏，并保留额外副本。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 24)
                .padding(.bottom, 20)
                .readablePageWidth()
            }
            .background(AppTheme.canvas)
        }
    }

    private func farmCard(_ session: SaveSession) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            farmHeaderLayout {
                GameIcon(systemName: "person.crop.circle.fill", size: 44)
                VStack(alignment: .leading, spacing: 5) {
                    Text(session.draft.playerName.isEmpty ? "未命名农夫" : session.draft.playerName)
                        .font(.title3.bold())
                    Text("农场信息：\(session.draft.farmName.isEmpty ? session.source.farmIdentifier : session.draft.farmName)")
                    Text("第 \(session.draft.year) 年 · \(session.draft.season.displayName)季 \(session.draft.day) 日")
                }
                VStack(alignment: .trailing, spacing: 5) {
                    Text("游戏版本：\(session.metadata.gameVersion)")
                    Text("\(session.diffs.count) 项待保存")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Button {
                selectedTab = .tools
            } label: {
                GameLabel("在工具页管理农场", systemImage: "arrow.left.arrow.right")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .tint(AppTheme.accent)
        }
        .padding(20)
        .background(AppTheme.headerSoft, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var appVersion: String {
        let version = (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "0.5.2"
        let build = (Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String) ?? "13"
        return "\(version) (\(build))"
    }

    private var farmHeaderLayout: AnyLayout {
        typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
            : AnyLayout(HStackLayout(spacing: 12))
    }
}

private struct SettingsRow: View {
    let title: String
    let value: String
    let systemImage: String
    var artworkName: String? = nil

    var body: some View {
        LabeledContent {
            Text(value).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        } label: {
            HStack(spacing: 14) {
            Group {
                if let artworkName {
                    GameAssetIcon(assetName: artworkName, size: 26)
                } else {
                    GameIcon(systemName: systemImage)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 30)
            Text(title)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(18)
    }
}
