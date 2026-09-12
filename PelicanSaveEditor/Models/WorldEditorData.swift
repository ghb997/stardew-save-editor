import Foundation

/// Element indices are stable within the immutable source tree and its copy.
/// They are never resolved against another farm or a tree already saved to disk.
struct SaveNodePath: Hashable, Sendable {
    let indices: [Int]
    var id: String { indices.map(String.init).joined(separator: ".") }
    func child(_ index: Int) -> SaveNodePath { SaveNodePath(indices: indices + [index]) }
    func resolve(in root: XMLNode) -> XMLNode? {
        var node = root
        for index in indices {
            guard node.children.indices.contains(index) else { return nil }
            node = node.children[index]
        }
        return node
    }
}

enum ExistingSaveValue {
    static func scalar(_ node: XMLNode?) -> String? {
        guard let node, node.children.isEmpty,
              !["true", "1"].contains((node.attributes["xsi:nil"] ?? node.attributes["nil"] ?? "false").lowercased()) else { return nil }
        return node.text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    static func field(_ name: String, in node: XMLNode) -> String? {
        let matches = node.children(named: name)
        return matches.count == 1 ? scalar(matches[0]) : nil
    }
    static func bool(_ text: String?) -> Bool? {
        switch text?.lowercased() {
        case "true", "1": true
        case "false", "0": false
        default: nil
        }
    }
    static func type(_ node: XMLNode) -> String {
        node.attributes["xsi:type"] ?? node.attributes["type"] ?? node.name
    }
    static func dictionary(_ node: XMLNode?) -> [XMLNode] {
        guard let node else { return [] }
        if node.children.count == 1, let wrapper = node.children.first,
           wrapper.name.hasPrefix("SerializableDictionary") { return wrapper.children(named: "item") }
        return node.children(named: "item")
    }
    static func locationTitle(_ name: String) -> String {
        ["Farm": "农场", "FarmHouse": "农舍", "Greenhouse": "温室", "Cellar": "地窖",
         "IslandWest": "姜岛农场", "IslandFarmHouse": "姜岛农舍", "Town": "鹈鹕镇",
         "Forest": "煤矿森林", "Beach": "海滩", "Shed": "棚屋", "Big Shed": "大棚屋"][name] ?? name
    }
}

struct LocatedWorldObject {
    let node: XMLNode
    let path: SaveNodePath
    let location: String
    let coordinate: String
    let isFridge: Bool
}

enum WorldObjectIndex {
    /// One traversal confined to world locations; never visits player inventories.
    static func collect(_ root: XMLNode) -> [LocatedWorldObject] {
        guard let index = root.children.firstIndex(where: { $0.name == "locations" }) else { return [] }
        var result: [LocatedWorldObject] = []
        func walk(_ node: XMLNode, path: SaveNodePath, location: String) {
            let location = ExistingSaveValue.field("name", in: node).flatMap { name in
                (node.name == "GameLocation" || node.name == "indoors") ? name : nil
            } ?? location
            if node.name == "objects" {
                let container: XMLNode
                let containerPath: SaveNodePath
                if node.children.count == 1, let first = node.children.first,
                   first.name.hasPrefix("SerializableDictionary") {
                    container = first; containerPath = path.child(0)
                } else { container = node; containerPath = path }
                let keys = container.children.compactMap { $0.child(named: "key")?.xmlString() }
                let counts = Dictionary(keys.map { ($0, 1) }, uniquingKeysWith: +)
                for (i, entry) in container.children.enumerated() where entry.name == "item" {
                    guard let key = entry.child(named: "key"), counts[key.xmlString()] == 1,
                          let vector = key.child(named: "Vector2"),
                          let x = ExistingSaveValue.field("X", in: vector).flatMap(Int.init),
                          let y = ExistingSaveValue.field("Y", in: vector).flatMap(Int.init),
                          let v = entry.children.firstIndex(where: { $0.name == "value" }),
                          entry.children[v].children.count == 1 else { continue }
                    result.append(LocatedWorldObject(node: entry.children[v].children[0],
                        path: containerPath.child(i).child(v).child(0), location: location,
                        coordinate: "X \(x) · Y \(y)", isFridge: false))
                }
                return
            }
            if node.name == "fridge" {
                if node.child(named: "items") != nil {
                    result.append(LocatedWorldObject(node: node, path: path, location: location,
                                                     coordinate: "室内冰箱", isFridge: true))
                } else if node.children.count == 1, let chest = node.children.first,
                          chest.name == "Chest" {
                    result.append(LocatedWorldObject(node: chest, path: path.child(0), location: location,
                                                     coordinate: "室内冰箱", isFridge: true))
                }
                return
            }
            // Item/furniture contents are separate schemas, not world locations.
            guard !["items", "furniture", "terrainFeatures", "characters", "animals"].contains(node.name) else { return }
            for (i, child) in node.children.enumerated() { walk(child, path: path.child(i), location: location) }
        }
        walk(root.children[index], path: SaveNodePath(indices: [index]), location: "未知地点")
        return result
    }
}

enum SavedWeather: String, CaseIterable, Identifiable, Sendable {
    case sun = "Sun", rain = "Rain", wind = "Wind", storm = "Storm", snow = "Snow"
    var id: String { rawValue }
    var title: String {
        switch self { case .sun: "晴天"; case .rain: "雨天"; case .wind: "大风"; case .storm: "雷雨"; case .snow: "下雪" }
    }
    var number: Int {
        switch self { case .sun: 0; case .rain: 1; case .wind: 2; case .storm: 3; case .snow: 5 }
    }
    static func parse(_ raw: String) -> SavedWeather? {
        allCases.first { $0.rawValue.lowercased() == raw.lowercased() || String($0.number) == raw }
    }
}

struct WeatherField: Equatable, Sendable {
    let path: SaveNodePath
    let raw: String
    func encoded(_ weather: SavedWeather) -> String { Int(raw) != nil ? String(weather.number) : weather.rawValue }
}

struct WeatherDraft: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let fields: [WeatherField]
    let original: SavedWeather
    var selected: SavedWeather
}

struct WeatherAndLuckDraft: Equatable, Sendable {
    var regions: [WeatherDraft] = []
    var dailyLuck: Double? = nil
    var notes: [String] = []

    static func extract(_ root: XMLNode) -> Self {
        var result = Self()
        var fields: [String: [WeatherField]] = [:]
        func record(_ parent: XMLNode, path: SaveNodePath, region: String) {
            let matches = parent.children(named: "weatherForTomorrow")
            guard !matches.isEmpty else { return }
            guard matches.count == 1,
                  let i = parent.children.firstIndex(where: { $0.name == "weatherForTomorrow" }) else {
                fields[region, default: []].append(WeatherField(path: path, raw: "重复字段")); return
            }
            let raw = ExistingSaveValue.scalar(parent.children[i]) ?? "未知值"
            fields[region, default: []].append(WeatherField(path: path.child(i), raw: raw))
        }
        record(root, path: SaveNodePath(indices: []), region: "Default")
        if root.children(named: "locationWeather").count > 1 {
            fields["Default", default: []].append(WeatherField(path: SaveNodePath(indices: []), raw: "重复天气上下文"))
        }
        if let i = root.children.firstIndex(where: { $0.name == "locationWeather" }) {
            let container = root.children[i]
            let wrapped = container.children.count == 1 && container.children[0].name.hasPrefix("SerializableDictionary")
            let dictionary = wrapped ? container.children[0] : container
            let base = wrapped ? SaveNodePath(indices: [i, 0]) : SaveNodePath(indices: [i])
            for (j, entry) in dictionary.children.enumerated() where entry.name == "item" {
                guard let key = entry.child(named: "key")?.value(named: "string"),
                      ["Default", "Island"].contains(key),
                      let v = entry.children.firstIndex(where: { $0.name == "value" }),
                      entry.children[v].children.count == 1 else { continue }
                let weather = entry.children[v].children[0]
                guard weather.name == "LocationWeather" else { continue }
                record(weather, path: base.child(j).child(v).child(0), region: key)
            }
        }
        for key in fields.keys.sorted() {
            let values = fields[key] ?? []
            let parsed = values.compactMap { SavedWeather.parse($0.raw) }
            guard parsed.count == values.count, let first = parsed.first,
                  Set(parsed).count == 1, values.count <= (key == "Default" ? 2 : 1) else {
                result.notes.append("\(key == "Default" ? "山谷" : "姜岛")明日天气含特殊、未知或冲突值，保留原样。")
                continue
            }
            result.regions.append(WeatherDraft(id: key, title: key == "Default" ? "山谷明日天气" : "姜岛明日天气",
                                              fields: values, original: first, selected: first))
        }
        if let luck = ExistingSaveValue.field("dailyLuck", in: root).flatMap(Double.init), luck.isFinite {
            result.dailyLuck = luck
        }
        return result
    }
}

struct MachineDraft: Identifiable, Equatable, Sendable {
    var id: String { path.id }
    let path: SaveNodePath
    let name: String
    let location: String
    let coordinate: String
    let output: String
    let minutes: Int
    let wasReady: Bool
    var finish = false
    var canFinish: Bool { minutes > 0 && !wasReady }
}

enum MachineEditorRules {
    static let names = ["12": "小桶", "13": "熔炉", "15": "罐头瓶", "16": "压酪机", "17": "织布机",
                        "19": "产油机", "20": "回收机", "21": "宝石复制机", "24": "蛋黄酱机",
                        "114": "煤炭窑", "246": "咖啡机", "Dehydrator": "脱水机", "FishSmoker": "鱼类烟熏机",
                        "HeavyFurnace": "重型熔炉"]
    static func extract(_ objects: [LocatedWorldObject], catalog: [String: CatalogItem]) -> [MachineDraft] {
        objects.compactMap { object in
            let node = object.node
            guard ExistingSaveValue.type(node) == "Object",
                  ExistingSaveValue.bool(ExistingSaveValue.field("bigCraftable", in: node)) == true,
                  let id = ExistingSaveValue.field("itemId", in: node) ?? ExistingSaveValue.field("parentSheetIndex", in: node),
                  let name = names[id],
                  let minutes = ExistingSaveValue.field("minutesUntilReady", in: node).flatMap(Int.init), (0...Int(Int32.max)).contains(minutes),
                  let ready = ExistingSaveValue.bool(ExistingSaveValue.field("readyForHarvest", in: node)),
                  node.children(named: "heldObject").count == 1, let held = node.child(named: "heldObject"),
                  ExistingSaveValue.type(held) == "Object", held.child(named: "name") != nil,
                  ExistingSaveValue.bool(held.attributes["xsi:nil"] ?? held.attributes["nil"]) != true else { return nil }
            let outputID = held.value(named: "itemId") ?? held.value(named: "parentSheetIndex") ?? ""
            return MachineDraft(path: object.path, name: name, location: object.location, coordinate: object.coordinate,
                                output: catalog[outputID]?.displayName ?? held.value(named: "name") ?? "加工物品",
                                minutes: minutes, wasReady: ready)
        }
    }
}
