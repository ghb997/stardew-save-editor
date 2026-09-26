import Foundation

struct VerifiedExportReview: Identifiable, Sendable {
    let id = UUID()
    let target: SaveSource
    let localMainHash: String
    let localInfoHash: String?
    let targetMainHash: String
    let targetInfoHash: String?
    let localDescription: String
    let targetDescription: String
    let targetChanged: Bool
    let identityWarning: Bool
}

enum VerifiedExportRules {
    static func review(local: SaveSource, pair: SavePairData, origin: LocalCopyRecord,
                       target: SaveSource, targetPair: SavePairData) throws -> VerifiedExportReview {
        guard local.farmIdentifier == target.farmIdentifier, local.identity != target.identity,
              pair.info != nil, targetPair.info != nil else {
            throw SaveValidationError.invalid("请选择同一农场的游戏目录，其中必须有主存档与 SaveGameInfo；不能选择应用副本自身。")
        }
        let source = try SaveParser.parse(mainData: pair.main, infoData: pair.info, catalog: [], recipeCatalog: [:])
        let destination = try SaveParser.parse(mainData: targetPair.main, infoData: targetPair.info, catalog: [], recipeCatalog: [:])
        func identifier(_ node: XMLNode?, _ keys: [String]) throws -> String? {
            try SaveParser.stableIdentity(in: node, names: keys)
        }
        var verifiedIdentity = false
        for (a, b) in try [
            (identifier(source.mainRoot, ["uniqueIDForThisGame"]), identifier(destination.mainRoot, ["uniqueIDForThisGame"])),
            (identifier(source.mainRoot.child(named: "player"), ["uniqueMultiplayerID", "UniqueMultiplayerID"]),
             identifier(destination.mainRoot.child(named: "player"), ["uniqueMultiplayerID", "UniqueMultiplayerID"]))
        ] {
            if let a, let b {
                guard a == b else { throw SaveValidationError.invalid("目标目录属于另一份农场或另一位玩家，已阻止覆盖。") }
                verifiedIdentity = true
            }
        }
        func description(_ parsed: ParsedSaveDocument) -> String {
            let d = parsed.draft
            return "\(d.farmName) · \(d.playerName)\n第 \(d.year) 年 · \(d.season.displayName)季 \(d.day) 日 · \(d.money) 金币"
        }
        let isOrigin = origin.originMainHash != nil && targetPair.mainHash == origin.originMainHash
            && targetPair.infoHash == origin.originInfoHash
        let isAlreadyExported = targetPair.mainHash == pair.mainHash && targetPair.infoHash == pair.infoHash
        return VerifiedExportReview(target: target, localMainHash: pair.mainHash, localInfoHash: pair.infoHash,
            targetMainHash: targetPair.mainHash, targetInfoHash: targetPair.infoHash,
            localDescription: description(source), targetDescription: description(destination),
            targetChanged: !isOrigin && !isAlreadyExported, identityWarning: !verifiedIdentity)
    }
}
