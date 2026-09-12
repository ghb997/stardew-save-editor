import SwiftUI

enum ExpandedEditorTool: String, CaseIterable, Identifiable {
    case storage, weather, machines, bundles
    var id: String { rawValue }
    var title: String {
        switch self { case .storage: "箱子与冰箱"; case .weather: "天气与运气"; case .machines: "机器加工"; case .bundles: "社区中心" }
    }
    var symbol: String {
        switch self { case .storage: "shippingbox.fill"; case .weather: "cloud.sun.fill"; case .machines: "gearshape.2.fill"; case .bundles: "leaf.fill" }
    }
    var subtitle: String {
        switch self {
        case .storage: "按地点查找容器，添加物品、修改数量与品质"
        case .weather: "选择明日天气，调整每日运气并对照原值"
        case .machines: "查找正在加工的机器，预览并完成所选设备"
        case .bundles: "查看献祭进度，选择缺失材料并补给到背包"
        }
    }
}

struct ExpandedEditorShell: View {
    @Environment(EditorStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Bindable var session: SaveSession
    let tool: ExpandedEditorTool
    @State private var review = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label(tool.title, systemImage: tool.symbol).font(.headline)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                Button("返回工具", systemImage: "xmark") { dismiss() }
                    .labelStyle(.iconOnly).buttonStyle(.bordered).frame(minWidth: 44, minHeight: 44)
                    .accessibilityIdentifier("expanded.close")
            }
            .padding(.horizontal).padding(.vertical, 10).readablePageWidth(AppLayout.editorWidth).background(.bar)
            content.readablePageWidth(AppLayout.editorWidth)
            DraftReviewBar(session: session) { review = true }
        }
        .background(AppTheme.canvas)
        .fullScreenCover(isPresented: $review) { EditorShellView(session: session, section: .review) }
        .disabled(store.isBusy).interactiveDismissDisabled(store.isBusy).operationFeedback()
#if DEBUG
        .modifier(DebugLayoutViewport())
#endif
    }

    @ViewBuilder private var content: some View {
        switch tool {
        case .storage: StorageEditorView(session: session, catalog: store.itemCatalog)
        case .weather: WeatherEditorView(session: session)
        case .machines: MachinesEditorView(session: session)
        case .bundles: CommunityCenterView(session: session, catalog: store.itemCatalog)
        }
    }
}
