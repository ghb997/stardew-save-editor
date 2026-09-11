import SwiftUI

enum MainTab: Hashable {
    case home
    case tracker
    case tools
    case settings
}

struct RootView: View {
    @Environment(EditorStore.self) private var store
    @AppStorage("appearanceMode") private var appearanceMode = "system"
    @State private var selectedTab: MainTab = Self.debugInitialTab
    @State private var showingRescueBackups = false

    private struct Notice {
        let title: String
        let message: String
        let isRecovery: Bool
    }
    private var notice: Notice? {
        guard !store.isBusy else { return nil }
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
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
            }
        }
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
                if displayed.isRecovery {
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
                    Label("主页", systemImage: "house.fill")
                }

            TrackerView(selectedTab: $selectedTab)
                .tag(MainTab.tracker)
                .tabItem {
                    Label("追踪", systemImage: "trophy.fill")
                }

            ToolsView()
                .tag(MainTab.tools)
                .badge(store.session?.diffs.count ?? 0)
                .tabItem {
                    Label("工具", systemImage: "hammer.fill")
                }

            SettingsView(selectedTab: $selectedTab)
                .tag(MainTab.settings)
                .tabItem {
                    Label("设置", systemImage: "gearshape.fill")
                }
        }
        // UITabBar reads an icon's intrinsic UIImage size and does not honor
        // layout frames inside a custom SwiftUI label. Native tab symbols keep
        // every item inside the system-managed bar on iPhone and iPad.
        .tint(selectedTab == .tracker ? AppTheme.trackerAccent : AppTheme.accent)
        .toolbarBackground(.visible, for: .tabBar)
        .toolbarBackground(Color(.systemBackground), for: .tabBar)
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
