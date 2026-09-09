import Foundation

enum FarmEntityKind: String, CaseIterable, Identifiable, Sendable {
    case crop
    case tree
    case fruitTree
    case object
    case building
    case animal
    case resource

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .crop: "作物"
        case .tree: "普通树木"
        case .fruitTree: "果树"
        case .object: "放置物与杂物"
        case .building: "建筑"
        case .animal: "户外动物"
        case .resource: "大型资源与地形"
        }
    }
}

enum FarmEntityState: String, Hashable, Sendable {
    case watered
    case dry
    case dead
    case stone
    case weed
    case twig
}

enum FarmDebrisKind: String, Hashable, Sendable {
    case stone
    case weed
    case twig
}

enum FarmActionKey {
    static func crop(x: Double, y: Double) -> String { "crop:\(coordinate(x)):\(coordinate(y))" }
    static func debris(kind: FarmDebrisKind, x: Double, y: Double) -> String {
        "debris:\(kind.rawValue):\(coordinate(x)):\(coordinate(y))"
    }

    private static func coordinate(_ value: Double) -> String {
        value.rounded() == value ? String(format: "%.0f", value) : String(value)
    }
}

enum FarmDebrisClassifier {
    private static let stoneIDs: Set<String> = ["343", "450", "668", "670", "751", "760", "762"]
    private static let weedIDs: Set<String> = [
        "0", "313", "314", "315", "316", "317", "318", "319", "320", "321",
        "674", "675", "784", "785", "786", "792", "793", "794"
    ]
    private static let twigIDs: Set<String> = ["294", "295"]

    /// Item IDs are scoped by type. A BigCraftable "0" is a house plant,
    /// while Object "0" is debris; never strip arbitrary mod namespaces.
    static func kind(in object: XMLNode) -> FarmDebrisKind? {
        guard ["Object", "Item"].contains(object.name),
              object.value(named: "bigCraftable") != "true",
              object.value(named: "bigCraftable") != "1",
              object.child(named: "items") == nil else { return nil }
        if let held = object.child(named: "heldObject"),
           held.attributes["xsi:nil"] != "true", held.attributes["nil"] != "true",
           !held.children.isEmpty || !held.text.isEmpty { return nil }
        let serializedType = object.attributes["xsi:type"] ?? object.attributes["type"]
        guard serializedType == nil || serializedType == "Object" else { return nil }
        guard let id = vanillaObjectID(object.value(named: "itemId")
            ?? object.value(named: "parentSheetIndex")) else { return nil }
        if stoneIDs.contains(id) { return .stone }
        if weedIDs.contains(id) { return .weed }
        if twigIDs.contains(id) { return .twig }
        return nil
    }

    private static func vanillaObjectID(_ rawID: String?) -> String? {
        guard var id = rawID?.trimmingCharacters(in: .whitespacesAndNewlines),
              !id.isEmpty else { return nil }
        if id.hasPrefix("StardewValley:") { id.removeFirst("StardewValley:".count) }
        if id.hasPrefix("(O)") { id.removeFirst(3) }
        guard !id.isEmpty, id.utf8.allSatisfy({ (48...57).contains($0) }) else { return nil }
        return id
    }

}

struct FarmEntity: Identifiable, Hashable, Sendable {
    let id: String
    let kind: FarmEntityKind
    let label: String
    let detail: String?
    let tileX: Double?
    let tileY: Double?
    let state: FarmEntityState?
    let actionKey: String?

    var wateringKey: String? {
        guard kind == .crop, state == .dry, let tileX, let tileY, tileX.isFinite, tileY.isFinite else { return nil }
        return FarmActionKey.crop(x: tileX, y: tileY)
    }
}

enum FarmCropRules {
    static func state(in feature: XMLNode) -> FarmEntityState? {
        let type = feature.attributes["xsi:type"] ?? feature.attributes["type"] ?? feature.name
        guard type == "HoeDirt", feature.children(named: "crop").count == 1,
              !["true", "1"].contains(feature.attributes["xsi:nil"] ?? feature.attributes["nil"] ?? ""),
              let crop = feature.child(named: "crop"), !crop.children.isEmpty,
              !["true", "1"].contains(crop.attributes["xsi:nil"] ?? crop.attributes["nil"] ?? "") else { return nil }
        if ["dead", "netDead"].contains(where: { ["true", "1"].contains(crop.value(named: $0) ?? "") }) { return .dead }
        let field = feature.child(named: "state") ?? feature.child(named: "netState")
        guard let field, feature.children(named: field.name).count == 1 else { return nil }
        guard let raw = AppearanceColorCodec.scalar(field), let state = Int(raw), state >= 0 else { return nil }
        return state == 0 ? .dry : .watered
    }
}

struct FarmSnapshot: Sendable {
    let farmLocationName: String
    let entities: [FarmEntity]
    let tilledSoilCount: Int
    let grassCount: Int
    let warnings: [String]

    var positionedEntities: [FarmEntity] {
        entities.filter { $0.tileX != nil && $0.tileY != nil }
    }

    var wateredCropCount: Int {
        entities.lazy.filter { $0.kind == .crop && $0.state == .watered }.count
    }

    var unwateredCropCount: Int {
        entities.lazy.filter { $0.kind == .crop && $0.state == .dry }.count
    }

    var deadCropCount: Int {
        entities.lazy.filter { $0.kind == .crop && $0.state == .dead }.count
    }

    var stoneCount: Int { entities.lazy.filter { $0.state == .stone }.count }
    var weedCount: Int { entities.lazy.filter { $0.state == .weed }.count }
    var twigCount: Int { entities.lazy.filter { $0.state == .twig }.count }

    func visiblePositionedEntities(after actions: FarmActionDraft) -> [FarmEntity] {
        positionedEntities.filter { entity in
            if let key = entity.actionKey, actions.debrisRemovalKeys.contains(key) { return false }
            return switch entity.state {
            case .stone: !actions.clearStones
            case .weed: !actions.clearWeeds
            case .twig: !actions.clearTwigs
            default: true
            }
        }
    }

    func affectedEntities(by actions: FarmActionDraft) -> [FarmEntity] {
        entities.filter { entity in
            if let key = entity.wateringKey, actions.cropWateringKeys.contains(key) { return true }
            if let key = entity.actionKey, actions.debrisRemovalKeys.contains(key) { return true }
            return switch entity.state {
            case .dry: actions.waterAllCrops
            case .stone: actions.clearStones
            case .weed: actions.clearWeeds
            case .twig: actions.clearTwigs
            case .watered, .dead, nil: false
            }
        }
    }

    func count(for kind: FarmEntityKind) -> Int {
        entities.lazy.filter { $0.kind == kind }.count
    }

    func groupedLabels(for kind: FarmEntityKind) -> [(label: String, count: Int)] {
        let grouped = Dictionary(grouping: entities.filter { $0.kind == kind }, by: \.label)
        return grouped.map { (label: $0.key, count: $0.value.count) }.sorted {
            if $0.count != $1.count { return $0.count > $1.count }
            return $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending
        }
    }
}

enum FarmSnapshotExtractor {
    static func extract(from root: XMLNode, cropCatalog: [CropDefinition]) -> FarmSnapshot {
        guard let locations = root.child(named: "locations") else {
            return FarmSnapshot(
                farmLocationName: "Farm",
                entities: [],
                tilledSoilCount: 0,
                grassCount: 0,
                warnings: ["存档中没有 locations 字段，无法分析农场地图。"]
            )
        }

        let locationNodes = descendants(of: locations).filter { node in
            node.name == "GameLocation" || node.attributes["xsi:type"] != nil
        }
        guard let farm = locationNodes.first(where: { $0.value(named: "name") == "Farm" })
            ?? locationNodes.first(where: { normalizedType(of: $0) == "Farm" }) else {
            return FarmSnapshot(
                farmLocationName: "Farm",
                entities: [],
                tilledSoilCount: 0,
                grassCount: 0,
                warnings: ["存档中没有找到 Farm 地图节点。"]
            )
        }

        let cropsBySeedID = Dictionary(
            cropCatalog.map { ($0.seedID, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        var entities: [FarmEntity] = []
        var tilledSoilCount = 0
        var grassCount = 0
        var ordinal = 0

        func append(
            kind: FarmEntityKind,
            label: String,
            detail: String? = nil,
            coordinate: (Double, Double)?,
            state: FarmEntityState? = nil,
            actionKey: String? = nil
        ) {
            let id = "\(kind.rawValue).\(ordinal)"
            ordinal += 1
            entities.append(FarmEntity(
                id: id,
                kind: kind,
                label: label,
                detail: detail,
                tileX: coordinate?.0,
                tileY: coordinate?.1,
                state: state,
                actionKey: actionKey
            ))
        }

        if let objects = farm.child(named: "objects") {
            for item in objects.children(named: "item") {
                let coordinate = dictionaryCoordinate(from: item)
                let value = item.child(named: "value") ?? item
                let object = value.children.first ?? value
                guard !isNilNode(object) else { continue }
                let englishName = object.value(named: "name")
                    ?? object.value(named: "itemId")
                    ?? "未知物件"
                let label = ItemCatalog.chineseNames[englishName] ?? englishName
                let detailParts = [
                    object.value(named: "itemId").map { "ID \($0)" },
                    object.value(named: "stack").map { "数量 \($0)" },
                    object.value(named: "bigCraftable") == "true" ? "大型制造物" : nil
                ].compactMap { $0 }
                let debrisKind = FarmDebrisClassifier.kind(in: object)
                append(
                    kind: .object,
                    label: label,
                    detail: detailParts.isEmpty ? nil : detailParts.joined(separator: " · "),
                    coordinate: coordinate,
                    state: debrisKind.map(debrisState),
                    actionKey: coordinate.flatMap { point in
                        debrisKind.map { FarmActionKey.debris(kind: $0, x: point.0, y: point.1) }
                    }
                )
            }
        }

        if let terrain = farm.child(named: "terrainFeatures") {
            for item in terrain.children(named: "item") {
                let coordinate = dictionaryCoordinate(from: item)
                let value = item.child(named: "value") ?? item
                let feature = value.children.first ?? value
                let type = normalizedType(of: feature)

                if type.contains("HoeDirt") || feature.child(named: "crop") != nil {
                    tilledSoilCount += 1
                    guard let crop = feature.child(named: "crop"), !isNilNode(crop) else { continue }
                    let seedID = firstDirectValue(in: crop, names: ["netSeedIndex", "seedIndex"])
                        ?? crop.firstDescendant(named: "netSeedIndex")?.text
                        ?? "?"
                    let definition = cropsBySeedID[seedID]
                    let label = definition?.chineseName ?? "作物种子 \(seedID)"
                    let phase = firstDirectValue(in: crop, names: ["currentPhase", "phaseToShow"])
                    let state = FarmCropRules.state(in: feature)
                    let detail = [
                        "种子 \(seedID)",
                        phase.map { "阶段 \($0)" },
                        state == .watered ? "已浇水" : (state == .dry ? "未浇水" : nil),
                        state == .dead ? "已枯萎" : nil,
                        state == nil ? "未知浇水状态，只读" : nil
                    ].compactMap { $0 }.joined(separator: " · ")
                    append(
                        kind: .crop,
                        label: label,
                        detail: detail,
                        coordinate: coordinate,
                        state: state
                    )
                } else if type.contains("FruitTree") {
                    let treeID = firstDirectValue(in: feature, names: ["treeId", "indexOfFruit"])
                    let detail = [
                        treeID.map { "类型 \($0)" },
                        feature.value(named: "growthStage").map { "阶段 \($0)" }
                    ].compactMap { $0 }.joined(separator: " · ")
                    append(
                        kind: .fruitTree,
                        label: "果树",
                        detail: detail.isEmpty ? nil : detail,
                        coordinate: coordinate
                    )
                } else if type.contains("Tree") {
                    let treeType = feature.value(named: "treeType")
                    append(
                        kind: .tree,
                        label: "普通树木",
                        detail: treeType.map { "类型 \($0)" },
                        coordinate: coordinate
                    )
                } else if type.contains("Grass") {
                    grassCount += 1
                }
            }
        }

        if let buildings = farm.child(named: "buildings") {
            for building in directOrWrappedNodes(in: buildings, named: "Building") {
                let rawType = building.value(named: "buildingType") ?? normalizedType(of: building)
                let label = buildingChineseName(rawType)
                let coordinate = directCoordinate(
                    in: building,
                    xNames: ["tileX", "TileX"],
                    yNames: ["tileY", "TileY"]
                )
                let detail = [
                    rawType.isEmpty ? nil : rawType,
                    building.value(named: "daysOfConstructionLeft").flatMap { $0 == "0" ? nil : "施工剩余 \($0) 天" }
                ].compactMap { $0 }.joined(separator: " · ")
                append(
                    kind: .building,
                    label: label,
                    detail: detail.isEmpty ? nil : detail,
                    coordinate: coordinate
                )
            }
        }

        if let animals = farm.child(named: "animals") {
            for item in animals.children(named: "item") {
                let value = item.child(named: "value") ?? item
                guard let animal = value.firstDescendant(named: "FarmAnimal") ?? value.children.first else {
                    continue
                }
                let type = animal.value(named: "type") ?? normalizedType(of: animal)
                let name = animal.value(named: "name") ?? type
                let localizedType = animalChineseType(type)
                let coordinate = pixelCoordinate(in: animal)
                append(
                    kind: .animal,
                    label: name.isEmpty ? "农场动物" : (name == type ? localizedType : name),
                    detail: type.isEmpty || type == name ? nil : localizedType,
                    coordinate: coordinate
                )
            }
        }

        if let clumps = farm.child(named: "resourceClumps") {
            for clump in directOrWrappedNodes(in: clumps, named: "ResourceClump") {
                let index = clump.value(named: "parentSheetIndex") ?? "?"
                let coordinate = vectorCoordinate(in: clump.child(named: "tile") ?? clump)
                append(
                    kind: .resource,
                    label: resourceClumpName(index),
                    detail: "资源编号 \(index)",
                    coordinate: coordinate
                )
            }
        }

        if let largeFeatures = farm.child(named: "largeTerrainFeatures") {
            for feature in largeFeatures.children where !isNilNode(feature) {
                let type = normalizedType(of: feature)
                let coordinate = directCoordinate(
                    in: feature,
                    xNames: ["tileX", "TileX"],
                    yNames: ["tileY", "TileY"]
                ) ?? vectorCoordinate(in: feature.child(named: "tilePosition") ?? feature)
                append(
                    kind: .resource,
                    label: type.isEmpty ? "大型地形物" : type,
                    coordinate: coordinate
                )
            }
        }

        var warnings: [String] = []
        if entities.isEmpty, tilledSoilCount == 0, grassCount == 0 {
            warnings.append("已找到 Farm 节点，但其中没有可识别的地图实体。")
        }
        let missingCoordinateCount = entities.count - entities.filter { $0.tileX != nil && $0.tileY != nil }.count
        if missingCoordinateCount > 0 {
            warnings.append("有 \(missingCoordinateCount) 个实体缺少可用坐标，已计入统计但未绘制在坐标图中。")
        }

        return FarmSnapshot(
            farmLocationName: farm.value(named: "name") ?? "Farm",
            entities: entities,
            tilledSoilCount: tilledSoilCount,
            grassCount: grassCount,
            warnings: warnings
        )
    }

    private static func descendants(of node: XMLNode) -> [XMLNode] {
        node.children.flatMap { child in [child] + descendants(of: child) }
    }

    private static func normalizedType(of node: XMLNode) -> String {
        let raw = node.attributes["xsi:type"] ?? node.attributes["type"] ?? node.name
        return raw.split(separator: ":").last.map(String.init) ?? raw
    }

    private static func isNilNode(_ node: XMLNode) -> Bool {
        node.attributes["xsi:nil"] == "true" || node.attributes["nil"] == "true"
    }

    private static func firstDirectValue(in node: XMLNode, names: [String]) -> String? {
        for name in names {
            if let value = node.value(named: name), !value.isEmpty { return value }
        }
        return nil
    }

    private static func directOrWrappedNodes(in container: XMLNode, named name: String) -> [XMLNode] {
        container.children.flatMap { child -> [XMLNode] in
            if child.name == name { return [child] }
            if let match = child.firstDescendant(named: name) { return [match] }
            return []
        }
    }

    private static func dictionaryCoordinate(from item: XMLNode) -> (Double, Double)? {
        guard let key = item.child(named: "key") else { return nil }
        return vectorCoordinate(in: key.firstDescendant(named: "Vector2") ?? key)
    }

    private static func vectorCoordinate(in node: XMLNode) -> (Double, Double)? {
        directCoordinate(in: node, xNames: ["X", "x"], yNames: ["Y", "y"])
    }

    private static func directCoordinate(
        in node: XMLNode,
        xNames: [String],
        yNames: [String]
    ) -> (Double, Double)? {
        let x = xNames.lazy.compactMap { node.value(named: $0).flatMap(Double.init) }.first
        let y = yNames.lazy.compactMap { node.value(named: $0).flatMap(Double.init) }.first
        guard let x, let y, x.isFinite, y.isFinite else { return nil }
        return (x, y)
    }

    private static func pixelCoordinate(in node: XMLNode) -> (Double, Double)? {
        guard let position = node.child(named: "position") ?? node.firstDescendant(named: "Position"),
              let coordinate = vectorCoordinate(in: position) else { return nil }
        return (coordinate.0 / 64.0, coordinate.1 / 64.0)
    }

    private static func buildingChineseName(_ raw: String) -> String {
        let lower = raw.lowercased()
        if lower.contains("deluxe barn") { return "豪华畜棚" }
        if lower.contains("big barn") { return "大畜棚" }
        if lower.contains("barn") { return "畜棚" }
        if lower.contains("deluxe coop") { return "豪华鸡舍" }
        if lower.contains("big coop") { return "大鸡舍" }
        if lower.contains("coop") { return "鸡舍" }
        if lower.contains("silo") { return "筒仓" }
        if lower.contains("stable") { return "马厩" }
        if lower.contains("fish pond") { return "鱼塘" }
        if lower.contains("mill") { return "磨坊" }
        if lower.contains("shed") { return "小屋" }
        if lower.contains("cabin") { return "联机小屋" }
        if lower.contains("greenhouse") { return "温室" }
        if lower.contains("well") { return "水井" }
        return raw.isEmpty ? "建筑" : raw
    }

    private static func resourceClumpName(_ index: String) -> String {
        switch index {
        case "600": "大树桩"
        case "602": "空心圆木"
        case "622": "陨石"
        case "672": "巨石"
        default: "大型资源"
        }
    }

    private static func animalChineseType(_ raw: String) -> String {
        switch raw.lowercased() {
        case "white cow": "白牛"
        case "brown cow": "棕牛"
        case "goat": "山羊"
        case "pig": "猪"
        case "sheep": "绵羊"
        case "white chicken": "白鸡"
        case "brown chicken": "棕鸡"
        case "blue chicken": "蓝鸡"
        case "void chicken": "虚空鸡"
        case "golden chicken": "金鸡"
        case "duck": "鸭"
        case "rabbit": "兔子"
        case "dinosaur": "恐龙"
        case "ostrich": "鸵鸟"
        default: raw.isEmpty ? "农场动物" : raw
        }
    }

    private static func debrisState(_ kind: FarmDebrisKind) -> FarmEntityState {
        switch kind {
        case .stone: .stone
        case .weed: .weed
        case .twig: .twig
        }
    }
}
