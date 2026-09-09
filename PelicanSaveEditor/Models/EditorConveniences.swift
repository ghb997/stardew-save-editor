import Foundation

enum BackpackRules {
    static let capacities = [12, 24, 36]
}

extension SaveDraft {
    var canResizeBackpack: Bool {
        guard let backpackCapacity else { return false }
        return BackpackRules.capacities.contains(backpackCapacity)
            && !inventory.isEmpty && inventory.count <= 36
    }

    var usableInventoryCount: Int {
        guard let backpackCapacity, BackpackRules.capacities.contains(backpackCapacity) else {
            return inventory.count
        }
        return min(backpackCapacity, inventory.count)
    }

    func canUseInventorySlot(_ index: Int) -> Bool {
        inventory.indices.contains(index) && index < usableInventoryCount
    }

    mutating func setBackpackCapacity(_ capacity: Int) throws {
        guard canResizeBackpack, BackpackRules.capacities.contains(capacity) else {
            throw SaveValidationError.invalid("当前存档未提供可调整的标准背包容量。")
        }
        guard !inventory.dropFirst(capacity).contains(where: { $0.item != nil }) else {
            throw SaveValidationError.invalid("第 \(capacity + 1) 格以后的槽位仍有物品，请先移到保留的空槽后再缩小背包。")
        }
        backpackCapacity = capacity
        let count = max(capacity, inventorySlotFloor)
        if inventory.count < count {
            inventory.append(contentsOf: (inventory.count..<count).map {
                InventorySlotDraft(id: $0, item: nil)
            })
        } else if inventory.count > count {
            inventory.removeLast(inventory.count - count)
        }
    }

    /// Capacity and items in newly unlocked slots form one dependency. Undoing
    /// expansion restores those slots too, while retaining edits in old slots.
    mutating func restoreBackpackCapacity(from original: SaveDraft) {
        let limit = original.usableInventoryCount
        for index in inventory.indices where index >= limit {
            inventory[index].item = original.inventory.indices.contains(index)
                ? original.inventory[index].item : nil
        }
        if inventory.count > original.inventory.count {
            inventory.removeLast(inventory.count - original.inventory.count)
        } else if inventory.count < original.inventory.count {
            inventory.append(contentsOf: original.inventory.dropFirst(inventory.count))
        }
        backpackCapacity = original.backpackCapacity
    }

    @discardableResult
    mutating func applyRelationshipBatch(_ action: RelationshipBatchAction, names: Set<String>) -> Int {
        var count = 0
        for index in friendships.indices where names.contains(friendships[index].name) {
            let old = friendships[index]
            switch action {
            case .fillHearts:
                if let target = FriendshipRules.fullHeartPoints(for: old) {
                    friendships[index].points = max(old.points, target)
                }
            case .resetGifts:
                if old.giftsToday != nil { friendships[index].giftsToday = 0 }
                if old.giftsThisWeek != nil { friendships[index].giftsThisWeek = 0 }
            }
            if old != friendships[index] { count += 1 }
        }
        return count
    }
}

enum RelationshipBatchAction: String, CaseIterable, Identifiable, Sendable {
    case fillHearts
    case resetGifts
    var id: String { rawValue }
    var title: String {
        switch self {
        case .fillHearts: "补满好感"
        case .resetGifts: "重置送礼次数"
        }
    }

    func willChange(_ friend: FriendshipDraft) -> Bool {
        switch self {
        case .fillHearts:
            guard let target = FriendshipRules.fullHeartPoints(for: friend) else { return false }
            return friend.points < target
        case .resetGifts:
            return (friend.giftsToday ?? 0) > 0 || (friend.giftsThisWeek ?? 0) > 0
        }
    }
}

enum FriendshipRules {
    static let dateableCharacters: Set<String> = [
        "Abigail", "Alex", "Elliott", "Emily", "Haley", "Harvey",
        "Leah", "Maru", "Penny", "Sam", "Sebastian", "Shane"
    ]

    static func maximumEditablePoints(for friend: FriendshipDraft) -> Int {
        if friend.status == .married { return 3_749 }
        if dateableCharacters.contains(friend.name), friend.status == .friendly { return 2_249 }
        return 2_749
    }

    static func fullHeartPoints(for friend: FriendshipDraft) -> Int? {
        guard friend.hasEditablePoints, friend.hasEditableStatus, npcChineseNames[friend.name] != nil else { return nil }
        switch friend.status {
        case .married: return 3_500
        case .friendly: return dateableCharacters.contains(friend.name) ? 2_000 : 2_500
        case .dating: return dateableCharacters.contains(friend.name) ? 2_500 : nil
        case .engaged, .divorced, .unknown: return nil
        }
    }
}

enum RelationshipFilter: String, CaseIterable, Identifiable {
    case all, dateable, others, gifting, edited
    var id: String { rawValue }
    var title: String {
        switch self {
        case .all: "全部"
        case .dateable: "可恋爱角色"
        case .others: "其他角色"
        case .gifting: "已送礼"
        case .edited: "已修改"
        }
    }

    func includes(_ friend: FriendshipDraft, original: FriendshipDraft?) -> Bool {
        switch self {
        case .all: true
        case .dateable: FriendshipRules.dateableCharacters.contains(friend.name)
        case .others: !FriendshipRules.dateableCharacters.contains(friend.name)
        case .gifting: (friend.giftsToday ?? 0) > 0 || (friend.giftsThisWeek ?? 0) > 0
        case .edited: original.map { $0 != friend } ?? false
        }
    }
}
