/// Presentation metrics shared by tracker summaries and detail pages.
enum TrackerMetrics {
    /// Adds the four observed category counts. This is not a unique-item count
    /// across categories or the game's weighted perfection percentage.
    static func collectionKindCount(_ insights: SaveInsights) -> Int {
        insights.shippedItemKinds
            + insights.caughtFishKinds
            + insights.mineralKinds
            + insights.artifactKinds
    }

    static func skillLevelSummary(_ skills: [SkillDraft]) -> (current: Int, total: Int) {
        let current = skills.reduce(0) { $0 + max(0, min(10, $1.level)) }
        return (current: current, total: skills.count * 10)
    }

    static func fraction(completed: Int, total: Int) -> Double? {
        guard total > 0 else { return nil }
        return Double(max(0, min(total, completed))) / Double(total)
    }

    static func statusText(warnings: [String], diffCount: Int) -> String {
        if !warnings.isEmpty { return "\(warnings.count) 项警告" }
        if diffCount > 0 { return "\(diffCount) 项草稿" }
        return "未发现警告"
    }

    static func isClear(warnings: [String], diffCount: Int) -> Bool {
        warnings.isEmpty && diffCount <= 0
    }
}
