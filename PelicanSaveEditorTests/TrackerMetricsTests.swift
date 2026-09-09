import XCTest
@testable import PelicanSaveEditor

final class TrackerMetricsTests: XCTestCase {
    func testWarningsRemainVisibleEvenWithoutDraftsOrAlongsideDrafts() {
        let warnings = ["未载入 SaveGameInfo", "未找到游戏版本字段"]
        for diffCount in [0, 3] {
            XCTAssertEqual(TrackerMetrics.statusText(warnings: warnings, diffCount: diffCount), "2 项警告")
            XCTAssertFalse(TrackerMetrics.isClear(warnings: warnings, diffCount: diffCount))
        }
    }

    func testDraftsAndClearStateHaveDistinctStatus() {
        XCTAssertEqual(TrackerMetrics.statusText(warnings: [], diffCount: 3), "3 项草稿")
        XCTAssertFalse(TrackerMetrics.isClear(warnings: [], diffCount: 3))
        XCTAssertEqual(TrackerMetrics.statusText(warnings: [], diffCount: 0), "未发现警告")
        XCTAssertTrue(TrackerMetrics.isClear(warnings: [], diffCount: 0))
    }

    func testProgressDoesNotInventCompletionForMissingTotals() {
        XCTAssertNil(TrackerMetrics.fraction(completed: 0, total: 0))
        XCTAssertNil(TrackerMetrics.fraction(completed: 5, total: 0))
        XCTAssertNil(TrackerMetrics.fraction(completed: 5, total: -1))
    }

    func testProgressStaysWithinItsDisplayRange() {
        XCTAssertEqual(TrackerMetrics.fraction(completed: -5, total: 10), 0)
        XCTAssertEqual(TrackerMetrics.fraction(completed: 4, total: 10), 0.4)
        XCTAssertEqual(TrackerMetrics.fraction(completed: 15, total: 10), 1)
    }

    func testSkillSummaryUsesAvailableSkillsAndClampsExtendedLevels() {
        let skills = [skill(.farming, level: -2), skill(.fishing, level: 7), skill(.mining, level: 15)]
        let summary = TrackerMetrics.skillLevelSummary(skills)
        XCTAssertEqual(summary.current, 17)
        XCTAssertEqual(summary.total, 30)
        XCTAssertEqual(skills.map(\.level), [-2, 7, 15], "Tracking must not mutate the save's values.")
    }

    func testEmptySkillsHaveNoArtificialMaximumOrCompletedProgress() {
        let summary = TrackerMetrics.skillLevelSummary([])
        XCTAssertEqual(summary.current, 0)
        XCTAssertEqual(summary.total, 0)
        XCTAssertNil(TrackerMetrics.fraction(completed: summary.current, total: summary.total))
    }

    func testCollectionFootprintIsAnObservedCountNotPerfection() {
        var insights = SaveInsights(
            weatherForTomorrow: nil, dailyLuck: nil,
            activeQuestCount: 0, achievementCount: 0,
            shippedItemKinds: 125, caughtFishKinds: 20, mineralKinds: 13, artifactKinds: 7,
            secretNoteCount: 0, eventCount: 0, mailFlagCount: 0,
            daysPlayed: nil, questsCompleted: nil, monstersKilled: nil, itemsShipped: nil, fishCaught: nil
        )
        XCTAssertEqual(TrackerMetrics.collectionKindCount(insights), 165)
        insights.achievementCount = 50
        insights.questsCompleted = 200
        insights.itemsShipped = 99_999
        XCTAssertEqual(TrackerMetrics.collectionKindCount(insights), 165,
                       "Achievements and quantities must not change a collection-kind count.")
        insights.shippedItemKinds = 0
        insights.caughtFishKinds = 0
        insights.mineralKinds = 0
        insights.artifactKinds = 0
        XCTAssertEqual(TrackerMetrics.collectionKindCount(insights), 0)
    }

    private func skill(_ key: SkillKey, level: Int) -> SkillDraft {
        SkillDraft(key: key, originalLevel: level, originalExperience: 0, level: level, experience: 0)
    }
}
