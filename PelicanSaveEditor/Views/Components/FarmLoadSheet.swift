import SwiftUI

enum FarmLoadMethod: String, Identifiable {
    case copy
    var id: String { rawValue }
}

/// The caller presents the copy picker only after this sheet has dismissed.
struct FarmLoadSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selection: FarmLoadMethod?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Text("导入你的农场").font(.system(.title2, design: .monospaced).bold())
                    Text("先完全退出游戏，再从同一个农场文件夹中同时选择以下两个文件。")
                        .foregroundStyle(AppTheme.secondary)
                    VStack(alignment: .leading, spacing: 16) {
                        fileRow("主存档", detail: "通常为「农场名称_数字」，没有扩展名", symbol: "doc.text")
                        Divider()
                        fileRow("SaveGameInfo", detail: "与主存档位于同一个文件夹", symbol: "doc.text.magnifyingglass")
                    }
                    .padding(18)
                    .appCard()
                    Button {
                        selection = .copy
                        dismiss()
                    } label: {
                        Label("复制导入两个文件", systemImage: "doc.on.doc")
                            .font(.headline)
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(GameButtonStyle(prominent: true))
                    .controlSize(.large)
                    .tint(AppTheme.accent)
                    .accessibilityIdentifier("farm.load.copy")
                    VStack(alignment: .leading, spacing: 8) {
                        Label("修改后如何放回游戏", systemImage: "square.and.arrow.up").font(.headline)
                        Text("编辑的是应用内副本。完成修改后，在「检查与保存」中保存并导出两份文件，放回游戏原农场文件夹，替换同名文件。")
                            .font(.subheadline).foregroundStyle(AppTheme.secondary)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                .padding(20)
                .readablePageWidth(680)
            }
            .accessibilityIdentifier("farm.load.options")
            .background(GamePageBackdrop())
            .navigationTitle("加载农场")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }.accessibilityIdentifier("farm.load.cancel")
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
#if DEBUG
        .modifier(DebugLayoutViewport())
#endif
    }

    private func fileRow(_ title: String, detail: String, symbol: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol).font(.title2).foregroundStyle(AppTheme.accent)
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.headline)
                Text(detail).font(.subheadline).foregroundStyle(AppTheme.secondary)
            }
        }
    }
}

#Preview("Copy import") {
    FarmLoadSheet(selection: .constant(nil))
}

#Preview("Copy import · large text") {
    FarmLoadSheet(selection: .constant(nil)).environment(\.dynamicTypeSize, .accessibility3)
}
