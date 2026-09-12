import Foundation

enum ExpandedEditorChanges {
    static func validate(_ draft: SaveDraft, original: SaveDraft) throws {
        guard draft.storages.map(\.id) == original.storages.map(\.id),
              draft.machines.map(\.id) == original.machines.map(\.id),
              draft.communityCenter == original.communityCenter else {
            throw SaveValidationError.invalid("不能新增、移除容器或机器，也不能直接更改献祭记录。")
        }
        for (storage, old) in zip(draft.storages, original.storages) where storage != old {
            try StorageEditorRules.validate(storage, original: old)
        }
        for (machine, old) in zip(draft.machines, original.machines) where machine != old {
            var metadata = machine
            metadata.finish = old.finish
            guard metadata == old, old.canFinish else { throw SaveValidationError.invalid("只能完成已有且正在加工的标准机器。") }
        }
        guard draft.weatherAndLuck.regions.map(\.id) == original.weatherAndLuck.regions.map(\.id),
              draft.weatherAndLuck.notes == original.weatherAndLuck.notes else {
            throw SaveValidationError.invalid("天气来源已改变，请重新读取存档。")
        }
        for (weather, old) in zip(draft.weatherAndLuck.regions, original.weatherAndLuck.regions) {
            var metadata = weather
            metadata.selected = old.selected
            guard metadata == old else { throw SaveValidationError.invalid("不能创建新的天气字段。") }
            if weather.selected != old.selected, weather.id == "Island", ![.sun, .rain, .storm].contains(weather.selected) {
                throw SaveValidationError.invalid("姜岛仅支持晴天、雨天和雷雨。")
            }
        }
        if draft.weatherAndLuck.dailyLuck != original.weatherAndLuck.dailyLuck {
            guard original.weatherAndLuck.dailyLuck != nil, let luck = draft.weatherAndLuck.dailyLuck,
                  luck.isFinite, (-0.1...0.1).contains(luck) else {
                throw SaveValidationError.invalid("每日运气须在 -0.1 至 0.1 之间，且原存档须有有效字段。")
            }
        }
    }

    static func apply(_ draft: SaveDraft, original: SaveDraft, to root: XMLNode) throws {
        for (storage, old) in zip(draft.storages, original.storages) where storage != old {
            try StorageEditorRules.apply(storage, original: old, to: root)
        }
        for (machine, old) in zip(draft.machines, original.machines) where machine.finish && !old.finish {
            guard let node = machine.path.resolve(in: root),
                  node.int(named: "minutesUntilReady") == old.minutes,
                  ExistingSaveValue.bool(ExistingSaveValue.field("readyForHarvest", in: node)) == old.wasReady else {
                throw SaveValidationError.invalid("机器来源已改变，无法写回。")
            }
            node.setValue("0", named: "minutesUntilReady")
            node.setValue("true", named: "readyForHarvest")
        }
        for (weather, old) in zip(draft.weatherAndLuck.regions, original.weatherAndLuck.regions) where weather.selected != old.selected {
            for field in old.fields {
                guard let node = field.path.resolve(in: root), ExistingSaveValue.scalar(node) == field.raw else {
                    throw SaveValidationError.invalid("天气字段已改变，无法写回。")
                }
                node.text = field.encoded(weather.selected)
            }
        }
        if draft.weatherAndLuck.dailyLuck != original.weatherAndLuck.dailyLuck, let luck = draft.weatherAndLuck.dailyLuck {
            root.setValue(String(luck), named: "dailyLuck")
        }
    }

    static func diffs(original: SaveDraft, draft: SaveDraft) -> [SaveDiff] {
        var result: [SaveDiff] = []
        func add(_ id: String, _ section: String, _ title: String, _ old: String, _ new: String) {
            result.append(SaveDiff(id: id, section: section, label: title, oldValue: old, newValue: new, affectsSaveGameInfo: false))
        }
        for (storage, old) in zip(draft.storages, original.storages) {
            for (slot, previous) in zip(storage.slots, old.slots) where slot != previous {
                add("storage:\(storage.id):\(slot.id)", "箱子与冰箱", "\(storage.title) · \(storage.coordinate) · 第 \(slot.id + 1) 格",
                    describe(previous.item), describe(slot.item))
            }
        }
        for (machine, old) in zip(draft.machines, original.machines) where machine.finish != old.finish {
            add("machine:\(machine.id)", "机器加工", "\(ExistingSaveValue.locationTitle(machine.location)) · \(machine.name) · \(machine.coordinate)",
                "\(machine.output) · 剩余 \(machine.minutes) 分钟", "完成加工，回游戏领取")
        }
        for (weather, old) in zip(draft.weatherAndLuck.regions, original.weatherAndLuck.regions) where weather.selected != old.selected {
            add("weather:\(weather.id)", "天气与运气", weather.title, old.selected.title, weather.selected.title)
        }
        if draft.weatherAndLuck.dailyLuck != original.weatherAndLuck.dailyLuck {
            add("weather:luck", "天气与运气", "每日运气", original.weatherAndLuck.dailyLuck.map { String($0) } ?? "未提供",
                draft.weatherAndLuck.dailyLuck.map { String($0) } ?? "未提供")
        }
        return result
    }

    static func undo(_ id: String, original: SaveDraft, draft: inout SaveDraft) {
        for i in draft.storages.indices where original.storages.indices.contains(i) {
            for j in draft.storages[i].slots.indices where original.storages[i].slots.indices.contains(j) {
                if id == "storage:\(draft.storages[i].id):\(j)" { draft.storages[i].slots[j] = original.storages[i].slots[j] }
            }
        }
        for i in draft.machines.indices where original.machines.indices.contains(i) {
            if id == "machine:\(draft.machines[i].id)" { draft.machines[i] = original.machines[i] }
        }
        for i in draft.weatherAndLuck.regions.indices where original.weatherAndLuck.regions.indices.contains(i) {
            if id == "weather:\(draft.weatherAndLuck.regions[i].id)" { draft.weatherAndLuck.regions[i] = original.weatherAndLuck.regions[i] }
        }
        if id == "weather:luck" { draft.weatherAndLuck.dailyLuck = original.weatherAndLuck.dailyLuck }
    }

    private static func describe(_ item: InventoryItemDraft?) -> String {
        item.map { "\($0.localizedName) ×\($0.stack) · 品质 \($0.quality)" } ?? "空槽位"
    }
}
