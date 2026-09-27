import SwiftUI

enum MainTab: Hashable {
    case home
    case tracker
    case tools
    case settings
}

struct RootView: View {
    @Environment(EditorStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("appearanceMode") private var appearanceMode = "system"
    @State private var selectedTab: MainTab = Self.debugInitialTab
    @State private var showingRescueBackups = false

    private struct Notice {
        let title: String
        let message: String
        let isRecovery: Bool
        var isDraft = false
    }
    private var notice: Notice? {
        guard !store.isBusy else { return nil }
        if let message = store.draftRecoveryMessage {
            return Notice(title: "恢复未保存草稿", message: message, isRecovery: false, isDraft: true)
        }
        if let message = store.recoveryConflictMessage {
            return Notice(title: "发现未完成事务", message: message, isRecovery: true)
        }
        guard !OperationFeedbackRegistry.shared.hasModalHost else { return nil }
        if let message = store.errorMessage { return Notice(title: "操作失败", message: message, isRecovery: false) }
        if let message = store.successMessage { return Notice(title: "完成", message: message, isRecovery: false) }
        return nil
    }

    var body: some View {
        ZStack {
            primaryContent

            if store.isBusy && !OperationFeedbackRegistry.shared.hasModalHost {
                Color.black.opacity(0.18).ignoresSafeArea()
                ProgressView(store.busyMessage)
                    .padding(24)
                    .background(GamePanel())
            }
        }
        .background(GamePageBackdrop())
        .disabled(store.isBusy)
        .preferredColorScheme(preferredColorScheme)
        .alert(
            notice?.title ?? "提示",
            isPresented: Binding(
                get: { notice != nil },
                set: {
                    if !$0 && !store.isBusy {
                        store.recoveryConflictMessage = nil
                        if !OperationFeedbackRegistry.shared.hasModalHost { store.clearMessages() }
                    }
                }
            ),
            presenting: notice,
            actions: { displayed in
                if displayed.isDraft {
                    if store.canRecoverDraft {
                        Button("恢复草稿") { store.restoreRecoveredDraft() }
                    }
                    Button("放弃这份草稿", role: .destructive) { store.discardRecoveredDraft() }
                    Button("关闭副本，保留草稿", role: .cancel) { store.closeUnresolvedDraft() }
                } else if displayed.isRecovery {
                    Button("保留当前文件并继续") { store.keepCurrentFilesAfterConflict() }
                    Button("查看与导出备份") {
                        store.dismissRecoveryConflict()
                        showingRescueBackups = true
                    }
                    Button("取消", role: .cancel) { store.dismissRecoveryConflict() }
                } else {
                    Button("好") { store.clearMessages() }
                }
            },
            message: { displayed in
                Text(displayed.message)
            }
        )
        .sheet(isPresented: $showingRescueBackups) { BackupListView() }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { store.flushDraftWhenBackgrounding() }
        }
    }

    @ViewBuilder
    private var primaryContent: some View {
#if DEBUG
        if let debugScreen, let session = store.session {
            switch debugScreen {
            case "magic-map":
                FarmMapAnalysisView(session: session, cropCatalog: store.cropCatalog)
            case "expanded-map":
                ExpandedFarmMapView(
                    snapshot: session.farmSnapshot,
                    actions: session.draft.farmActions
                )
            case "house":
                FarmhouseEditorView(session: session)
            case "character":
                CharacterEditorView(session: session)
            case "appearance":
                AppearanceEditorView(session: session)
            case "inventory":
                InventoryEditorView(session: session, catalog: store.itemCatalog)
            case "progress":
                ProgressEditorView(session: session)
            case "relationships":
                RelationshipsEditorView(session: session)
            case "skills":
                SkillsEditorView(session: session)
            case "wallet":
                WalletEditorView(session: session)
            case "animals":
                AnimalsEditorView(session: session)
            case "recipes":
                RecipesEditorView(session: session)
            case "review":
                ReviewChangesView(session: session)
            default:
                tabContent
            }
        } else {
            tabContent
        }
#else
        tabContent
#endif
    }

    private var tabContent: some View {
        TabView(selection: $selectedTab) {
            HomeView(selectedTab: $selectedTab)
                .tag(MainTab.home)
                .tabItem {
                    Label("主页", systemImage: "house")
                }

            TrackerView(selectedTab: $selectedTab)
                .tag(MainTab.tracker)
                .tabItem {
                    Label("追踪", systemImage: "leaf")
                }

            ToolsView()
                .tag(MainTab.tools)
                .tabItem {
                    Label("工具", systemImage: "wrench.and.screwdriver")
                }

            SettingsView(selectedTab: $selectedTab)
                .tag(MainTab.settings)
                .tabItem {
                    Label("设置", systemImage: "gearshape")
                }
        }
        // System symbols keep the navigation quiet; game artwork stays in the content.
        .tint(AppTheme.accent)
        .toolbarBackground(.visible, for: .tabBar)
        .toolbarBackground(AppTheme.canvas, for: .tabBar)
    }

    private var preferredColorScheme: ColorScheme? {
        switch appearanceMode {
        case "light": .light
        case "dark": .dark
        default: nil
        }
    }

    private static var debugInitialTab: MainTab {
#if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if let flagIndex = arguments.firstIndex(of: "--ui-tab"),
           arguments.indices.contains(flagIndex + 1) {
            switch arguments[flagIndex + 1] {
            case "tracker": return .tracker
            case "tools": return .tools
            case "settings": return .settings
            default: break
            }
        }
#endif
        return .home
    }

#if DEBUG
    private var debugScreen: String? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let flagIndex = arguments.firstIndex(of: "--ui-screen"),
              arguments.indices.contains(flagIndex + 1) else {
            return nil
        }
        return arguments[flagIndex + 1]
    }
#endif
}
