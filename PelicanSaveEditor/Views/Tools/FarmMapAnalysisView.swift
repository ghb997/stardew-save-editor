import SwiftUI

struct FarmMapAnalysisView: View {
    @Bindable var session: SaveSession
    let snapshot: FarmSnapshot
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var showingExpandedMap = false
    @State private var selectedEntityID: String?
    @State private var visibleKinds = Set(FarmEntityKind.allCases)
    @State private var showingEntityList = false
    @State private var showingReview = false

    init(session: SaveSession, cropCatalog: [CropDefinition]) {
        self.session = session
        snapshot = FarmSnapshotExtractor.extract(
            from: session.parsed.mainRoot,
            cropCatalog: cropCatalog
        )
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { scrollProxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    heroCard
                    magicActionsCard
                    coordinateCard
                        .id("map.coordinate")
                    Button("按坐标查看与选择全部对象", systemImage: "list.bullet.rectangle") {
                        showingEntityList = true
                    }
                    .buttonStyle(.bordered)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    summaryGrid

                    ForEach(FarmEntityKind.allCases) { kind in
                        if snapshot.count(for: kind) > 0 {
                            entityGroup(kind)
                        }
                    }

                    if !snapshot.warnings.isEmpty {
                        warningCard
                    }

                    Text("实体坐标来自当前农场，底图为坐标参考网格。作物以产物图标标识种类，果树和动物使用物种示意图；年龄、生长阶段与动作请看文字。无法确认具体外观的对象显示问号，可在对象列表核对名称与坐标。操作加入草稿后需检查并保存。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)
                }
                .padding(20)
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity)
            }
            .onChange(of: selectedEntityID) { _, selected in
                if selected != nil {
                    withAnimation { scrollProxy.scrollTo("map.coordinate", anchor: .top) }
                }
            }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("魔法地图")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("搜索与范围", systemImage: "magnifyingglass") { showingEntityList = true }
                        .accessibilityIdentifier("editor.map.objects")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
        .fullScreenCover(isPresented: $showingExpandedMap) {
            ExpandedFarmMapView(snapshot: snapshot, actions: $session.draft.farmActions)
        }
        .sheet(isPresented: $showingEntityList) {
            FarmEntityListView(snapshot: snapshot, actions: $session.draft.farmActions) { entity in
                visibleKinds.insert(entity.kind)
                selectedEntityID = entity.id
            }
        }
        .safeAreaInset(edge: .bottom) {
            DraftReviewBar(session: session) { showingReview = true }
        }
        .fullScreenCover(isPresented: $showingReview) {
            EditorShellView(session: session, section: .review)
        }
        .operationFeedback()
    }

    private var heroCard: some View {
        ZStack(alignment: .bottomLeading) {
            Image("GameFarmBackdrop")
                .resizable()
                .interpolation(.none)
                .scaledToFill()
                .frame(height: 210)
                .clipped()

            LinearGradient(
                colors: [.clear, .black.opacity(0.72)],
                startPoint: .center,
                endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: 4) {
                Text(session.draft.farmName.isEmpty ? session.source.farmIdentifier : session.draft.farmName)
                    .font(.title2.bold())
                Text("真实坐标图层 · \(snapshot.positionedEntities.count) 个实体 · 游戏 \(session.metadata.gameVersion)")
                    .font(.caption.weight(.medium))
                    .opacity(0.92)
            }
            .foregroundStyle(.white)
            .padding(18)
        }
        .frame(height: 210)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.white.opacity(0.16), lineWidth: 1)
        }
    }

    private var magicActionsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("魔法农场工具")
                        .font(.title3.bold())
                    Text("先加入草稿，保存时一次执行")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                GameAssetIcon(assetName: "GameUIFarmComputer", size: 64)
            }

            LazyVGrid(columns: magicActionColumns, spacing: 12) {
                MagicActionButton(
                    title: "给作物浇水",
                    countText: actionCountText(snapshot.unwateredCropCount, unit: "格待浇"),
                    assetName: "GameUIWateringCan",
                    tint: .blue,
                    isSelected: session.draft.farmActions.waterAllCrops,
                    isEnabled: snapshot.unwateredCropCount > 0 || session.draft.farmActions.waterAllCrops
                ) {
                    session.draft.farmActions.waterAllCrops.toggle()
                }
                MagicActionButton(
                    title: "清除散落石块",
                    countText: actionCountText(snapshot.stoneCount, unit: "块"),
                    assetName: "GameUIStone",
                    tint: .gray,
                    isSelected: session.draft.farmActions.clearStones,
                    isEnabled: snapshot.stoneCount > 0 || session.draft.farmActions.clearStones
                ) {
                    session.draft.farmActions.clearStones.toggle()
                }
                MagicActionButton(
                    title: "清除杂草",
                    countText: actionCountText(snapshot.weedCount, unit: "处"),
                    assetName: "GameUIWeeds",
                    tint: .green,
                    isSelected: session.draft.farmActions.clearWeeds,
                    isEnabled: snapshot.weedCount > 0 || session.draft.farmActions.clearWeeds
                ) {
                    session.draft.farmActions.clearWeeds.toggle()
                }
                MagicActionButton(
                    title: "清除树枝",
                    countText: actionCountText(snapshot.twigCount, unit: "根"),
                    assetName: "GameUITwig",
                    tint: .brown,
                    isSelected: session.draft.farmActions.clearTwigs,
                    isEnabled: snapshot.twigCount > 0 || session.draft.farmActions.clearTwigs
                ) {
                    session.draft.farmActions.clearTwigs.toggle()
                }
            }

            if session.draft.farmActions.hasChanges {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 10) {
                        selectedActionSummary
                        Spacer(minLength: 8)
                        cancelAllActionsButton
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        selectedActionSummary
                        cancelAllActionsButton
                    }
                }

                Divider()

                DisclosureGroup {
                    VStack(spacing: 10) {
                        ForEach(Array(pendingActionEntities.prefix(20))) { entity in
                            HStack(spacing: 9) {
                                Circle()
                                    .fill(pendingActionColor(entity))
                                    .frame(width: 9, height: 9)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text("\(pendingActionName(entity)) · \(entity.label)")
                                        .font(.caption.weight(.medium))
                                    Text(coordinateText(entity))
                                        .font(.caption2.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 0)
                            }
                        }

                        if pendingActionEntities.count > 20 {
                            Text("另有 \(pendingActionEntities.count - 20) 个对象，将在保存前的检查页再次汇总。")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(.top, 8)
                } label: {
                    GameLabel(
                        "查看预计处理明细（\(pendingActionEntities.count)）",
                        systemImage: "list.bullet.rectangle"
                    )
                    .font(.caption.weight(.semibold))
                }
            }
        }
        .padding(18)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22))
    }

    private var summaryGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            FarmMetricCard(title: "作物", value: snapshot.count(for: .crop), assetName: "GameUICropPlanner", color: .green)
            FarmMetricCard(title: "耕地", value: snapshot.tilledSoilCount, assetName: "GameUISkillFarming", color: .brown)
            FarmMetricCard(
                title: "树木",
                value: snapshot.count(for: .tree) + snapshot.count(for: .fruitTree),
                assetName: "GameOakTree",
                color: .green
            )
            FarmMetricCard(title: "放置物", value: snapshot.count(for: .object), assetName: "GameUIReview", color: .blue)
            FarmMetricCard(title: "建筑", value: snapshot.count(for: .building), assetName: "GameUIFarmhouse", color: .orange)
            FarmMetricCard(title: "户外动物", value: snapshot.count(for: .animal), assetName: "GameAnimalWhiteChicken", color: .pink)
            FarmMetricCard(title: "草地", value: snapshot.grassCount, assetName: "GameUIWeeds", color: .mint)
            FarmMetricCard(title: "大型资源/地形", value: snapshot.count(for: .resource), assetName: "GameUIStone", color: .gray)
        }
    }

    private var coordinateCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("存档坐标分布")
                        .font(.headline)
                    Text(coordinateSubtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("大图", systemImage: "arrow.up.left.and.arrow.down.right") {
                    showingExpandedMap = true
                }
                .font(.caption.weight(.semibold))
                .buttonStyle(.bordered)
            }

            FarmCoordinateCanvas(
                snapshot: snapshot,
                actions: session.draft.farmActions,
                visibleKinds: visibleKinds,
                selectedEntityID: selectedEntityID
            ) { entity in
                selectedEntityID = entity.id
            }
                .aspectRatio(1.28, contentMode: .fit)

            mapFilterBar

            if let selectedEntity {
                selectedEntityCard(selectedEntity)
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 105))], alignment: .leading, spacing: 8) {
                ForEach(FarmEntityKind.allCases) { kind in
                    if snapshot.count(for: kind) > 0 {
                        GameLabel(kind.displayName, systemImage: kind.systemImage)
                            .font(.caption)
                            .foregroundStyle(kind.color)
                    }
                }
            }

            Divider()

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 88))], alignment: .leading, spacing: 8) {
                MapLegendItem(title: "已浇水", color: .blue)
                MapLegendItem(title: "待浇水", color: .green)
                if snapshot.deadCropCount > 0 {
                    MapLegendItem(title: "已枯萎", color: .red)
                }
                if snapshot.stoneCount > 0 {
                    MapLegendItem(title: "石块", color: .gray)
                }
                if snapshot.weedCount > 0 {
                    MapLegendItem(title: "杂草", color: .green.opacity(0.72))
                }
                if snapshot.twigCount > 0 {
                    MapLegendItem(title: "树枝", color: .brown)
                }
            }
        }
        .padding(18)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
    }

    private func entityGroup(_ kind: FarmEntityKind) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                GameLabel(kind.displayName, systemImage: kind.systemImage)
                    .font(.headline)
                    .foregroundStyle(kind.color)
                Spacer()
                Text("\(snapshot.count(for: kind))")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            let groups = snapshot.groupedLabels(for: kind)
            ForEach(Array(groups.enumerated()), id: \.offset) { index, group in
                if index > 0 { Divider() }
                HStack {
                    Text(group.label)
                    Spacer()
                    Text("×\(group.count)")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }

            let positioned = positionedEntities(for: kind)
            if !positioned.isEmpty {
                Divider()
                DisclosureGroup("查看 \(positioned.count) 个具体坐标") {
                    ForEach(positioned) { entity in
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text(entity.label)
                                    .lineLimit(1)
                                Spacer()
                                Text(coordinateText(entity))
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                            if let detail = entity.detail, !detail.isEmpty {
                                Text(detail)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 3)
                    }
                }
                .font(.subheadline)
            }
        }
        .padding(18)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
    }

    private func positionedEntities(for kind: FarmEntityKind) -> [FarmEntity] {
        snapshot.entities
            .filter { $0.kind == kind && $0.tileX != nil && $0.tileY != nil }
            .sorted {
                if $0.tileY != $1.tileY { return ($0.tileY ?? 0) < ($1.tileY ?? 0) }
                if $0.tileX != $1.tileX { return ($0.tileX ?? 0) < ($1.tileX ?? 0) }
                return $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending
            }
    }

    private func coordinateText(_ entity: FarmEntity) -> String {
        guard let x = entity.tileX, let y = entity.tileY else { return "无坐标" }
        return "X \(coordinateComponent(x)) · Y \(coordinateComponent(y))"
    }

    private func coordinateComponent(_ value: Double) -> String {
        if value.rounded() == value { return String(format: "%.0f", value) }
        return value.formatted(.number.precision(.fractionLength(0...2)))
    }

    private var magicActionColumns: [GridItem] {
        dynamicTypeSize.isAccessibilitySize
            ? [GridItem(.flexible())]
            : [GridItem(.flexible()), GridItem(.flexible())]
    }

    private var selectedActionCount: Int {
        let actions = session.draft.farmActions
        let bulkCount = [actions.waterAllCrops, actions.clearStones, actions.clearWeeds, actions.clearTwigs]
            .filter { $0 }
            .count
        return bulkCount + (actions.debrisRemovalKeys.isEmpty ? 0 : 1) + (actions.cropWateringKeys.isEmpty ? 0 : 1)
    }

    private var selectedActionSummary: some View {
        GameLabel(
            "已选 \(selectedActionCount) 项，预计处理 \(selectedImpactCount) 个对象",
            systemImage: "checkmark.seal.fill"
        )
        .font(.caption)
        .foregroundStyle(.orange)
    }

    private var cancelAllActionsButton: some View {
        Button("全部取消") {
            session.draft.farmActions = FarmActionDraft()
        }
        .font(.caption.weight(.semibold))
    }

    private var selectedImpactCount: Int {
        snapshot.affectedEntities(by: session.draft.farmActions).count
    }

    private var pendingActionEntities: [FarmEntity] {
        snapshot.affectedEntities(by: session.draft.farmActions)
    }

    private func pendingActionName(_ entity: FarmEntity) -> String {
        switch entity.state {
        case .dry: "浇水"
        case .stone: "清除石块"
        case .weed: "清除杂草"
        case .twig: "清除树枝"
        case .watered, .dead, nil: "保持原样"
        }
    }

    private func pendingActionColor(_ entity: FarmEntity) -> Color {
        switch entity.state {
        case .dry: .blue
        case .stone: .gray
        case .weed: .green
        case .twig: .brown
        case .watered, .dead, nil: .secondary
        }
    }

    private var coordinateSubtitle: String {
        let originalCount = snapshot.positionedEntities.count
        let visibleCount = snapshot.visiblePositionedEntities(after: session.draft.farmActions).count
        guard visibleCount != originalCount else {
            return "绘制 \(originalCount) 个有坐标的实体"
        }
        return "预览显示 \(visibleCount) / \(originalCount) 个坐标实体"
    }

    private var selectedEntity: FarmEntity? {
        guard let selectedEntityID else { return nil }
        return snapshot.entities.first { $0.id == selectedEntityID }
    }

    private var mapFilterBar: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(FarmEntityKind.allCases) { kind in
                    let isVisible = visibleKinds.contains(kind)
                    Button {
                        if isVisible {
                            visibleKinds.remove(kind)
                        } else {
                            visibleKinds.insert(kind)
                        }
                    } label: {
                        GameLabel(kind.displayName, systemImage: kind.systemImage)
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 11)
                            .padding(.vertical, 7)
                            .foregroundStyle(isVisible ? Color.white : kind.color)
                            .background(
                                isVisible ? kind.color : kind.color.opacity(0.10),
                                in: Capsule()
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 2)
        }
        .scrollIndicators(.hidden)
    }

    private func selectedEntityCard(_ entity: FarmEntity) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                GameIcon(systemName: entity.kind.systemImage)
                    .foregroundStyle(entity.kind.color)
                    .frame(width: 28, height: 28)
                    .background(entity.kind.color.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 2) {
                    Text(entity.label)
                        .font(.headline)
                    Text(coordinateText(entity))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("关闭", systemImage: "xmark") {
                    selectedEntityID = nil
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
            }

            if let detail = entity.detail, !detail.isEmpty {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            FarmEntityActionButton(entity: entity, actions: $session.draft.farmActions)
        }
        .padding(14)
        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 15))
    }

    private func actionCountText(_ count: Int, unit: String) -> String {
        count == 0 ? "无需处理" : "\(count) \(unit)"
    }

    private var warningCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(snapshot.warnings, id: \.self) { warning in
                GameLabel(warning, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 18))
    }
}

private struct MagicActionButton: View {
    let title: String
    let countText: String
    let assetName: String
    let tint: Color
    let isSelected: Bool
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 9) {
                HStack {
                    GameAssetIcon(assetName: assetName, size: 28)
                    Spacer()
                    GameIcon(systemName: isSelected ? "checkmark.circle.fill" : "plus.circle", size: 20)
                        .font(.headline)
                }
                Text(title)
                    .font(.subheadline.bold())
                    .lineLimit(2)
                Text(countText)
                    .font(.caption.monospacedDigit())
                    .opacity(0.78)
            }
            .foregroundStyle(isSelected ? Color.white : tint)
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 116, alignment: .leading)
            .background(
                isSelected ? tint : tint.opacity(0.11),
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(tint.opacity(isSelected ? 0 : 0.28), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.48)
        .accessibilityValue(isSelected ? "已加入草稿" : (isEnabled ? "未选择" : "无需处理"))
    }
}

struct FarmCoordinateCanvas: View {
    let snapshot: FarmSnapshot
    let actions: FarmActionDraft
    let visibleKinds: Set<FarmEntityKind>
    let selectedEntityID: String?
    let onSelect: ((FarmEntity) -> Void)?

    private var displayedEntities: [FarmEntity] {
        var entities = snapshot.visiblePositionedEntities(after: actions)
        if let selected = snapshot.positionedEntities.first(where: { $0.id == selectedEntityID }),
           !entities.contains(where: { $0.id == selected.id }) {
            entities.append(selected)
        }
        return entities.filter { visibleKinds.contains($0.kind) }
    }

    init(
        snapshot: FarmSnapshot,
        actions: FarmActionDraft = FarmActionDraft(),
        visibleKinds: Set<FarmEntityKind> = Set(FarmEntityKind.allCases),
        selectedEntityID: String? = nil,
        onSelect: ((FarmEntity) -> Void)? = nil
    ) {
        self.snapshot = snapshot
        self.actions = actions
        self.visibleKinds = visibleKinds
        self.selectedEntityID = selectedEntityID
        self.onSelect = onSelect
    }

    var body: some View {
        GeometryReader { proxy in
            Canvas { context, size in
                drawTerrain(context: context, size: size)
                drawGrid(context: context, size: size)
                drawEntities(context: context, size: size)
            }
            .contentShape(Rectangle())
            .gesture(
                SpatialTapGesture()
                    .onEnded { value in
                        guard let entity = nearestEntity(to: value.location, size: proxy.size) else { return }
                        onSelect?(entity)
                    }
            )
        }
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.primary.opacity(0.08))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("农场坐标分布图")
        .accessibilityValue("显示 \(displayedEntities.count) 个实体")
        .accessibilityIdentifier("editor.map.canvas")
    }

    private func drawTerrain(context: GraphicsContext, size: CGSize) {
        // A neutral coordinate reference avoids inventing ponds or terrain
        // that are not present in the loaded save.
        context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(.secondarySystemBackground)))
    }

    private func drawGrid(context: GraphicsContext, size: CGSize) {
        var grid = Path()
        for step in 1..<10 {
            let x = size.width * CGFloat(step) / 10
            grid.move(to: CGPoint(x: x, y: 0))
            grid.addLine(to: CGPoint(x: x, y: size.height))
        }
        for step in 1..<8 {
            let y = size.height * CGFloat(step) / 8
            grid.move(to: CGPoint(x: 0, y: y))
            grid.addLine(to: CGPoint(x: size.width, y: y))
        }
        context.stroke(grid, with: .color(Color.primary.opacity(0.07)), lineWidth: 0.5)
    }

    private func drawEntities(context: GraphicsContext, size: CGSize) {
        let allPoints = snapshot.positionedEntities
        let points = displayedEntities
        guard !points.isEmpty else {
            let text = Text("没有可绘制的实体坐标").font(.callout).foregroundStyle(.secondary)
            context.draw(text, at: CGPoint(x: size.width / 2, y: size.height / 2))
            return
        }

        guard !allPoints.isEmpty, let transform = coordinateTransform(size: size) else { return }

        let sortedPoints = points.sorted { entityPriority($0) < entityPriority($1) }
        for entity in sortedPoints {
            guard let point = transform.point(for: entity) else { continue }
            let spriteSize: CGFloat = entity.kind == .building ? 20 : 12
            let pointRect = CGRect(
                x: point.x - spriteSize / 2,
                y: point.y - spriteSize / 2,
                width: spriteSize,
                height: spriteSize
            )
            if let sprite = GameArtwork.farmEntityImage(entity) ?? GameArtwork.uiImage(systemName: "questionmark") {
                context.draw(Image(uiImage: sprite).interpolation(.none), in: pointRect)
            }
            if entity.wateringKey != nil, actions.affects(entity) {
                context.stroke(Path(pointRect.insetBy(dx: -1, dy: -1)), with: .color(.blue), lineWidth: 1)
            }
            if entity.id == selectedEntityID {
                let selectionRect = pointRect.insetBy(dx: -5, dy: -5)
                context.stroke(
                    Path(ellipseIn: selectionRect),
                    with: .color(.orange),
                    lineWidth: 2.5
                )
            }
        }
    }

    private func nearestEntity(to location: CGPoint, size: CGSize) -> FarmEntity? {
        guard onSelect != nil, let transform = coordinateTransform(size: size) else { return nil }
        let points = displayedEntities
            .compactMap { entity -> (FarmEntity, CGFloat)? in
                guard let point = transform.point(for: entity) else { return nil }
                return (entity, hypot(point.x - location.x, point.y - location.y))
            }
        guard let nearest = points.min(by: { $0.1 < $1.1 }), nearest.1 <= 28 else { return nil }
        return nearest.0
    }

    private func coordinateTransform(size: CGSize) -> FarmCoordinateTransform? {
        let allPoints = snapshot.positionedEntities
        let xs = allPoints.compactMap(\.tileX)
        let ys = allPoints.compactMap(\.tileY)
        guard let rawMinX = xs.min(), let rawMaxX = xs.max(),
              let rawMinY = ys.min(), let rawMaxY = ys.max() else { return nil }
        return FarmCoordinateTransform(
            minX: min(0, rawMinX - 2),
            maxX: max(80, rawMaxX + 4),
            minY: min(0, rawMinY - 2),
            maxY: max(65, rawMaxY + 4),
            size: size
        )
    }

    private func entityPriority(_ entity: FarmEntity) -> Int {
        switch entity.kind {
        case .crop: 0
        case .object: 1
        case .tree, .fruitTree: 2
        case .animal: 3
        case .resource: 4
        case .building: 5
        }
    }
}

private struct FarmCoordinateTransform {
    let minX: Double
    let maxX: Double
    let minY: Double
    let maxY: Double
    let size: CGSize

    func point(for entity: FarmEntity) -> CGPoint? {
        guard let tileX = entity.tileX, let tileY = entity.tileY else { return nil }
        let inset: CGFloat = 8
        let xSpan = max(1, maxX - minX)
        let ySpan = max(1, maxY - minY)
        let drawWidth = max(1, size.width - inset * 2)
        let drawHeight = max(1, size.height - inset * 2)
        return CGPoint(
            x: inset + CGFloat((tileX - minX) / xSpan) * drawWidth,
            y: inset + CGFloat((tileY - minY) / ySpan) * drawHeight
        )
    }
}

private struct MapLegendItem: View {
    let title: String
    let color: Color

    var body: some View {
        Label {
            Text(title)
        } icon: {
            Circle()
                .fill(color)
                .frame(width: 9, height: 9)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}

struct ExpandedFarmMapView: View {
    let snapshot: FarmSnapshot
    @Binding var actions: FarmActionDraft
    @Environment(\.dismiss) private var dismiss
    @State private var zoom: CGFloat = 1
    @GestureState private var pinch: CGFloat = 1
    @State private var selectedEntityID: String?
    @State private var visibleKinds = Set(FarmEntityKind.allCases)
    @State private var showingEntityList = false

    init(snapshot: FarmSnapshot, actions: Binding<FarmActionDraft>) {
        self.snapshot = snapshot
        _actions = actions
    }

    init(snapshot: FarmSnapshot, actions: FarmActionDraft) {
        self.snapshot = snapshot
        _actions = .constant(actions)
    }

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                let baseWidth = max(320, proxy.size.width - 32)
                let effectiveZoom = min(4, max(1, zoom * pinch))

                ScrollView([.horizontal, .vertical]) {
                    FarmCoordinateCanvas(
                        snapshot: snapshot,
                        actions: actions,
                        visibleKinds: visibleKinds,
                        selectedEntityID: selectedEntityID
                    ) { entity in
                        selectedEntityID = entity.id
                    }
                        .frame(width: baseWidth * effectiveZoom, height: baseWidth * effectiveZoom / 1.28)
                        .padding(16)
                }
                .simultaneousGesture(
                    MagnifyGesture()
                        .updating($pinch) { value, state, _ in state = value.magnification }
                        .onEnded { value in zoom = min(4, max(1, zoom * value.magnification)) }
                )
                .background(Color(.systemGroupedBackground))
            }
            .navigationTitle("农场坐标大图")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("对象列表", systemImage: "list.bullet") { showingEntityList = true }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 10) {
                    filterBar

                    if let selectedEntity {
                        selectedEntityBar(selectedEntity)
                    }

                    HStack(spacing: 14) {
                        GameIcon(systemName: "minus.magnifyingglass")
                        Slider(value: $zoom, in: 1...4, step: 0.25)
                            .accessibilityLabel("地图缩放")
                        GameIcon(systemName: "plus.magnifyingglass")
                        Text("\(zoom, format: .number.precision(.fractionLength(0...2)))×")
                            .font(.caption.monospacedDigit())
                            .frame(width: 38, alignment: .trailing)
                        Button("复位") { zoom = 1 }
                            .font(.caption)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .background(.bar)
            }
        }
        .sheet(isPresented: $showingEntityList) {
            FarmEntityListView(snapshot: snapshot, actions: $actions) { entity in
                visibleKinds.insert(entity.kind)
                zoom = 1
                selectedEntityID = entity.id
            }
        }
    }

    private var selectedEntity: FarmEntity? {
        guard let selectedEntityID else { return nil }
        return snapshot.entities.first { $0.id == selectedEntityID }
    }

    private var filterBar: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(FarmEntityKind.allCases) { kind in
                    let isVisible = visibleKinds.contains(kind)
                    Button {
                        if isVisible {
                            visibleKinds.remove(kind)
                        } else {
                            visibleKinds.insert(kind)
                        }
                    } label: {
                        GameLabel(kind.displayName, systemImage: kind.systemImage)
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .foregroundStyle(isVisible ? Color.white : kind.color)
                            .background(
                                isVisible ? kind.color : kind.color.opacity(0.10),
                                in: Capsule()
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .scrollIndicators(.hidden)
    }

    private func selectedEntityBar(_ entity: FarmEntity) -> some View {
        HStack(spacing: 10) {
            GameIcon(systemName: entity.kind.systemImage)
                .foregroundStyle(entity.kind.color)
            VStack(alignment: .leading, spacing: 1) {
                Text(entity.label)
                    .font(.subheadline.bold())
                    .lineLimit(1)
                Text(coordinateText(entity))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)

            FarmEntityActionButton(entity: entity, actions: $actions)

            Button("关闭", systemImage: "xmark") {
                selectedEntityID = nil
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
    }

    private func coordinateText(_ entity: FarmEntity) -> String {
        guard let x = entity.tileX, let y = entity.tileY else { return "无坐标" }
        return "X \(coordinateComponent(x)) · Y \(coordinateComponent(y))"
    }

    private func coordinateComponent(_ value: Double) -> String {
        value.rounded() == value
            ? String(format: "%.0f", value)
            : value.formatted(.number.precision(.fractionLength(0...2)))
    }

}

private struct FarmMetricCard: View {
    let title: String
    let value: Int
    let assetName: String
    let color: Color

    var body: some View {
        HStack(spacing: 12) {
            GameAssetIcon(assetName: assetName, size: 30)
                .foregroundStyle(color)
                .frame(width: 30, height: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(value.formatted())
                    .font(.title3.bold().monospacedDigit())
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }
}

extension FarmEntityKind {
    var systemImage: String {
        switch self {
        case .crop: "leaf.fill"
        case .tree: "tree.fill"
        case .fruitTree: "tree.circle.fill"
        case .object: "shippingbox.fill"
        case .building: "house.fill"
        case .animal: "pawprint.fill"
        case .resource: "mountain.2.fill"
        }
    }

    var color: Color {
        switch self {
        case .crop: .green
        case .tree: .mint
        case .fruitTree: .teal
        case .object: .blue
        case .building: .orange
        case .animal: .pink
        case .resource: .gray
        }
    }
}
