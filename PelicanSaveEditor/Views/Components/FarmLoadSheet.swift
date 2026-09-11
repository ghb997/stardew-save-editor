import SwiftUI

enum FarmLoadMethod: String, Identifiable {
    case recent, directory, files, copy
    var id: String { rawValue }
}

/// A scrollable sheet avoids anchoring an iPad action popover to the whole
/// Tools tab. The caller opens the selected picker only after this sheet ends.
struct FarmLoadSheet: View {
    @Environment(\.dismiss) private var dismiss
    let hasRecentSource: Bool
    @Binding var selection: FarmLoadMethod?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("选择存档打开方式")
                        .font(.title2.bold())
                    Text("自签安装建议直接选择主存档与 SaveGameInfo；编辑完成后可写回原文件。")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    if hasRecentSource {
                        option(.recent, title: "打开上次农场",
                               subtitle: "继续使用上次授权的存档位置", icon: "clock.arrow.circlepath")
                    }
                    option(.files, title: "选择主存档与 SaveGameInfo",
                           subtitle: "自签推荐 · 同时选择这两个文件，保存时写回原位置。",
                           icon: "doc.badge.plus")
                    option(.directory, title: "选择 Stardew Valley 或存档文件夹",
                           subtitle: "授权文件夹后，自动查找其中的农场存档。",
                           icon: "folder")
                    option(.copy, title: "复制导入两个文件",
                           subtitle: "备用方式 · 无法获得写入授权时使用；保存后需要导出并替换游戏文件。",
                           icon: "doc.on.doc")
                }
                .padding(20)
                .readablePageWidth(680)
            }
            .accessibilityIdentifier("farm.load.options")
            .background(AppTheme.canvas)
            .navigationTitle("加载农场")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                        .accessibilityIdentifier("farm.load.cancel")
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private func option(_ method: FarmLoadMethod, title: String,
                        subtitle: String, icon: String) -> some View {
        Button {
            selection = method
            dismiss()
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                Label(title, systemImage: icon)
                    .font(.headline)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .padding(18)
            .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 18))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("farm.load.\(method.rawValue)")
    }
}

#Preview("Import options") {
    FarmLoadSheet(hasRecentSource: false, selection: .constant(nil))
}

#Preview("Recent farm · large text") {
    FarmLoadSheet(hasRecentSource: true, selection: .constant(nil))
        .environment(\.dynamicTypeSize, .accessibility3)
}
