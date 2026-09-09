import Foundation

struct FarmTileRegion: Equatable {
    let minX: Double, maxX: Double, minY: Double, maxY: Double
    var isValid: Bool {
        [minX, maxX, minY, maxY].allSatisfy(\.isFinite) && minX <= maxX && minY <= maxY
    }
    func contains(_ entity: FarmEntity) -> Bool {
        guard isValid, let x = entity.tileX, let y = entity.tileY else { return false }
        return (minX...maxX).contains(x) && (minY...maxY).contains(y)
    }
}

enum FarmMapScope: String, CaseIterable, Identifiable {
    case all, actionable, pending
    var id: String { rawValue }
    var title: String {
        switch self {
        case .all: "全部"
        case .actionable: "可操作"
        case .pending: "待处理"
        }
    }
}

struct FarmMapQuery {
    var text = ""
    var kind: FarmEntityKind?
    var scope: FarmMapScope = .all
    var region: FarmTileRegion?

    func matches(_ entity: FarmEntity, actions: FarmActionDraft) -> Bool {
        if let kind, entity.kind != kind { return false }
        if let region, !region.contains(entity) { return false }
        if scope == .actionable && entity.actionKey == nil && entity.wateringKey == nil { return false }
        if scope == .pending && !actions.affects(entity) { return false }
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return query.isEmpty || [entity.label, entity.detail ?? "", entity.coordinateDescription]
            .contains { $0.localizedCaseInsensitiveContains(query) }
    }
}

enum FarmScopedAction: String, CaseIterable, Identifiable {
    case water, clear
    var id: String { rawValue }
    var title: String { self == .water ? "浇水" : "清理杂物" }
    func candidates(_ entities: [FarmEntity], actions: FarmActionDraft) -> [FarmEntity] {
        entities.filter {
            !actions.affects($0) && (self == .water ? $0.wateringKey != nil : $0.actionKey != nil)
        }
    }
}

extension FarmActionDraft {
    func coveredByBulk(_ entity: FarmEntity) -> Bool {
        switch entity.state {
        case .dry: waterAllCrops
        case .stone: clearStones
        case .weed: clearWeeds
        case .twig: clearTwigs
        default: false
        }
    }
    func individuallySelected(_ entity: FarmEntity) -> Bool {
        entity.actionKey.map(debrisRemovalKeys.contains) == true
            || entity.wateringKey.map(cropWateringKeys.contains) == true
    }
    func affects(_ entity: FarmEntity) -> Bool { coveredByBulk(entity) || individuallySelected(entity) }

    mutating func toggle(_ entity: FarmEntity) {
        guard !coveredByBulk(entity) else { return }
        if let key = entity.wateringKey {
            if !cropWateringKeys.insert(key).inserted { cropWateringKeys.remove(key) }
        } else if let key = entity.actionKey {
            if !debrisRemovalKeys.insert(key).inserted { debrisRemovalKeys.remove(key) }
        }
    }

    mutating func apply(_ action: FarmScopedAction, to entities: [FarmEntity]) {
        for entity in action.candidates(entities, actions: self) {
            if action == .water, let key = entity.wateringKey { cropWateringKeys.insert(key) }
            if action == .clear, let key = entity.actionKey { debrisRemovalKeys.insert(key) }
        }
    }
}
