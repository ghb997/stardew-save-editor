import Foundation

/// Reparse the produced XML and check that every reviewed operation took effect.
/// This verifies our own serialization, not the game's subsequent runtime behavior.
enum SaveIntentVerifier {
    static func verify(original: SaveDraft, intended: SaveDraft, reloaded: ParsedSaveDocument,
                       originalRoot: XMLNode) throws {
        let expected = SaveDiffBuilder.build(original: original, draft: intended)
        let observed = Dictionary(SaveDiffBuilder.build(original: original, draft: reloaded.draft)
            .map { ($0.id, $0.newValue) }, uniquingKeysWith: { first, _ in first })
        let specializedPrefixes = ["farm.", "machine:", "equipment:", "storage:", "inventory."]
        for diff in expected where !specializedPrefixes.contains(where: { diff.id.hasPrefix($0) }) {
            guard observed[diff.id] == diff.newValue else {
                throw SaveValidationError.invalid("写回验证未通过：\(diff.label)没有按草稿生效。原存档尚未写入，请撤销该项并检查存档字段。")
            }
        }
        if intended.backpackCapacity != original.backpackCapacity {
            guard reloaded.draft.backpackCapacity == intended.backpackCapacity else {
                throw SaveValidationError.invalid("背包容量未通过写回验证，原存档尚未写入。")
            }
        }
        try verifySlots(intended.inventory, actual: reloaded.draft.inventory, original: original.inventory)

        // These operations never add, remove or reorder equipment, containers or
        // machines. Their traversal order stays stable, while raw element paths
        // can shift after deleting debris or migrating a legacy wallet flag.
        if intended.equipment != original.equipment {
            guard intended.equipment.count == reloaded.draft.equipment.count else {
                throw SaveValidationError.invalid("装备数量未通过写回验证，原存档尚未写入。")
            }
            for (index, item) in intended.equipment.enumerated() where item != original.equipment[index] {
                let actual = reloaded.draft.equipment[index]
                guard item.name == actual.name, item.type == actual.type, item.location == actual.location,
                      item.fields.map(\.id) == actual.fields.map(\.id),
                      zip(item.fields, actual.fields).allSatisfy({ $0.0.value == $0.1.value }) else {
                    throw SaveValidationError.invalid("\(item.name)的装备属性未通过写回验证，原存档尚未写入。")
                }
            }
        }
        if intended.storages != original.storages {
            guard intended.storages.count == reloaded.draft.storages.count else {
                throw SaveValidationError.invalid("容器数量未通过写回验证，原存档尚未写入。")
            }
            for (index, storage) in intended.storages.enumerated() where storage != original.storages[index] {
                let actual = reloaded.draft.storages[index]
                guard storage.location == actual.location, storage.coordinate == actual.coordinate,
                      storage.name == actual.name else {
                    throw SaveValidationError.invalid("容器位置未通过写回验证，原存档尚未写入。")
                }
                try verifySlots(storage.slots, actual: actual.slots, original: original.storages[index].slots)
            }
        }
        for (index, machine) in intended.machines.enumerated() where machine.finish {
            guard reloaded.draft.machines.indices.contains(index) else {
                throw SaveValidationError.invalid("机器记录未通过写回验证，原存档尚未写入。")
            }
            let actual = reloaded.draft.machines[index]
            guard actual.name == machine.name, actual.location == machine.location,
                  actual.coordinate == machine.coordinate, actual.output == machine.output,
                  actual.minutes == 0, actual.wasReady else {
                throw SaveValidationError.invalid("机器完成状态未通过写回验证，原存档尚未写入。")
            }
        }
        if intended.farmActions.hasChanges {
            let before = FarmSnapshotExtractor.extract(from: originalRoot, cropCatalog: [])
            let after = FarmSnapshotExtractor.extract(from: reloaded.mainRoot, cropCatalog: [])
            for entity in before.affectedEntities(by: intended.farmActions) {
                if entity.kind == .crop {
                    // Snapshot IDs are display ordinals, not stable save identities.
                    let matches = after.entities.filter {
                        $0.kind == .crop && $0.tileX == entity.tileX && $0.tileY == entity.tileY
                    }
                    guard !matches.isEmpty, matches.allSatisfy({ $0.state == .watered }) else {
                        throw SaveValidationError.invalid("坐标作物未完成浇水，已取消写入。")
                    }
                } else if after.entities.contains(where: {
                    $0.kind == entity.kind && $0.state == entity.state
                        && $0.tileX == entity.tileX && $0.tileY == entity.tileY
                }) {
                    throw SaveValidationError.invalid("所选杂物未完成清理，已取消写入。")
                }
            }
        }
    }

    private static func verifySlots(_ intended: [InventorySlotDraft], actual: [InventorySlotDraft],
                                    original: [InventorySlotDraft]) throws {
        for slot in intended {
            let previous = original.first { $0.id == slot.id }?.item
            guard slot.item != previous else { continue }
            let stored = actual.first { $0.id == slot.id }?.item
            let matches: Bool
            switch (slot.item, stored) {
            case (nil, nil): matches = true
            case let (wanted?, found?):
                matches = wanted.itemID == found.itemID && wanted.objectType == found.objectType
                    && wanted.stack == found.stack && wanted.quality == found.quality
            default: matches = false
            }
            guard matches else {
                throw SaveValidationError.invalid("第 \(slot.id + 1) 格物品未通过写回验证，原存档尚未写入。")
            }
        }
    }
}
