import Foundation

enum RoomStyleRules {
    static func standardStyles(for kind: RoomDecorationKind, query: String = "") -> [Int] {
        let range = kind == .wallpaper ? 0...111 : 0...55
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return range.filter { text.isEmpty || String($0).contains(text) }
    }

    static func matchingRooms(in house: FarmhouseDraft, query: String) -> [String] {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        var seen = Set<String>()
        return house.decorations.compactMap {
            guard text.isEmpty || $0.roomKey.localizedCaseInsensitiveContains(text)
                || $0.localizedRoomName.localizedCaseInsensitiveContains(text) else { return nil }
            return seen.insert($0.roomKey).inserted ? $0.roomKey : nil
        }
    }

    static func targets(in house: FarmhouseDraft, source: RoomDecorationDraft, rooms: Set<String>) -> [RoomDecorationDraft] {
        guard (0...9_999).contains(source.styleIndex) else { return [] }
        return house.decorations.filter {
            $0.kind == source.kind && rooms.contains($0.roomKey) && $0.styleIndex != source.styleIndex
        }
    }
}

extension FarmhouseDraft {
    mutating func applyStyle(from source: RoomDecorationDraft, rooms: Set<String>) {
        let ids = Set(RoomStyleRules.targets(in: self, source: source, rooms: rooms).map(\.id))
        for index in decorations.indices where ids.contains(decorations[index].id) {
            decorations[index].styleIndex = source.styleIndex
        }
    }

    mutating func restoreRoom(_ key: String, from original: FarmhouseDraft) {
        for index in decorations.indices where decorations[index].roomKey == key {
            if let old = original.decorations.first(where: { $0.id == decorations[index].id }) {
                decorations[index] = old
            }
        }
    }
}
