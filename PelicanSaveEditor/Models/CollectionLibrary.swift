import Foundation

enum CollectionKind: String, CaseIterable, Identifiable, Sendable {
    case museum = "博物馆", fish = "钓鱼", minerals = "矿物发现", artifacts = "古物发现", shipping = "出货记录"
    var id: String { rawValue }
    var field: String {
        switch self { case .museum: "museumPieces"; case .fish: "fishCaught"; case .minerals: "mineralsFound"; case .artifacts: "archaeologyFound"; case .shipping: "basicShipped" }
    }
    func includes(_ item: CatalogItem) -> Bool {
        switch self {
        case .museum: ["Arch", "Minerals"].contains(item.objectType)
        case .fish: item.objectType == "Fish"
        case .minerals: item.objectType == "Minerals"
        case .artifacts: item.objectType == "Arch"
        case .shipping: true
        }
    }
    var scope: String {
        switch self {
        case .museum: "按博物馆实际摆放记录核对 95 种原版捐赠品。发现过古物不代表已经捐赠。"
        case .fish: "按内置鱼类目录查看捕获记录，不代表游戏完美度的全部规则。"
        case .minerals, .artifacts: "这是主玩家的发现记录；博物馆捐赠请切换到博物馆分类。"
        case .shipping: "按内置可添加物品目录查看出货记录；其中部分物品不计入游戏出货成就。"
        }
    }
}

enum CollectionState: String, CaseIterable, Identifiable, Sendable {
    case recorded = "已有记录", missing = "缺少记录", unknown = "无法确认"
    var id: String { rawValue }
}

struct CollectionEntry: Identifiable, Sendable {
    var id: String { "\(kind.id):\(item.id)" }
    let kind: CollectionKind
    let item: CatalogItem
    let state: CollectionState
    let count: Int?
}

struct CollectionSection: Identifiable, Sendable {
    var id: String { kind.id }
    let kind: CollectionKind
    let entries: [CollectionEntry]
    let notes: [String]
}

enum CollectionLibrary {
    static func extract(_ root: XMLNode, catalog: [CatalogItem]) -> [CollectionSection] {
        CollectionKind.allCases.map { kind in
            var notes: [String] = []
            var complete = true
            var values: [String: Int] = [:]
            var uncertain = Set<String>()
            var museumPositions: [String: String] = [:]
            let containers: [XMLNode]
            if kind == .museum {
                let locations = root.children(named: "locations")
                let museums = locations.count == 1 ? locations[0].children.filter {
                    ExistingSaveValue.field("name", in: $0) == "ArchaeologyHouse"
                        || ExistingSaveValue.field("name", in: $0) == "LibraryMuseum"
                        || ExistingSaveValue.type($0) == "LibraryMuseum"
                } : []
                containers = museums.count == 1 ? museums[0].children(named: kind.field) : []
            } else if root.children(named: "player").count == 1 {
                containers = root.child(named: "player")?.children(named: kind.field) ?? []
            } else { containers = [] }
            if containers.count != 1 || !validContainer(containers[0]) {
                complete = false
                notes.append("存档未提供唯一、有效的\(kind.rawValue)记录，未出现的物品显示为无法确认。")
            } else {
                let container = containers[0]
                let records = ExistingSaveValue.dictionary(container)
                let wrapped = container.children.count == 1 && container.children[0].name.hasPrefix("SerializableDictionary")
                if (wrapped && !validContainer(container.children[0]))
                    || (wrapped ? container.children[0].children.count != records.count : container.children.count != records.count) {
                    complete = false
                }
                for record in records {
                    let key = record.child(named: "key")
                    let value = record.child(named: "value")
                    let rawID = kind == .museum ? singleScalar(value) : singleScalar(key)
                    guard let rawID, let id = itemID(rawID) else { complete = false; continue }
                    guard record.children(named: "key").count == 1, record.children(named: "value").count == 1,
                          validContainer(record) else { uncertain.insert(id); complete = false; continue }
                    let count: Int?
                    if kind == .museum {
                        guard let position = museumPosition(key) else { uncertain.insert(id); complete = false; continue }
                        if let previous = museumPositions[position] {
                            uncertain.insert(previous); uncertain.insert(id)
                        }
                        museumPositions[position] = id
                        count = 1
                    } else if kind == .fish || kind == .artifacts { count = recordCount(value) }
                    else { count = singleScalar(value).flatMap(Int.init) }
                    guard let count, count >= 0 else { uncertain.insert(id); continue }
                    if values[id] != nil { uncertain.insert(id) }
                    else { values[id] = count }
                }
                if !complete || !uncertain.isEmpty { notes.append("部分记录含异常或重复数据；不能确认的项目不会被当作未收集。") }
            }
            let candidates = catalog.filter(kind.includes).sorted {
                $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
            }
            let entries = candidates.map { item -> CollectionEntry in
                let count = values[item.id]
                let state: CollectionState
                if uncertain.contains(item.id) { state = .unknown }
                else if let count, count > 0 { state = .recorded }
                else if complete { state = .missing }
                else { state = .unknown }
                return CollectionEntry(kind: kind, item: item, state: state, count: count)
            }
            let extra = Set(values.keys).subtracting(candidates.map(\.id)).count
            if extra > 0 { notes.append("另有 \(extra) 个目录外物品记录，原始数据完整保留。") }
            return CollectionSection(kind: kind, entries: entries, notes: notes)
        }
    }

    private static func singleScalar(_ node: XMLNode?) -> String? {
        guard let node, validContainer(node), node.children.count == 1,
              ["string", "int", "long", "unsignedInt"].contains(node.children[0].name) else { return nil }
        return ExistingSaveValue.scalar(node.children[0])
    }
    private static func validContainer(_ node: XMLNode) -> Bool {
        ExistingSaveValue.bool(node.attributes["xsi:nil"] ?? node.attributes["nil"]) != true
            && node.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    private static func recordCount(_ node: XMLNode?) -> Int? {
        // Fish and artifact records normally store count plus a second statistic.
        // Preserve compatibility with older scalar-count records as well.
        if let scalar = singleScalar(node) { return Int(scalar) }
        guard let node, validContainer(node), node.children.count == 1,
              let array = node.child(named: "ArrayOfInt"), validContainer(array), array.children.count == 2,
              array.children.allSatisfy({ $0.name == "int" }),
              let first = ExistingSaveValue.scalar(array.children[0]).flatMap(Int.init), first >= 0,
              let second = ExistingSaveValue.scalar(array.children[1]).flatMap(Int.init), second >= 0 else { return nil }
        return first
    }
    private static func museumPosition(_ node: XMLNode?) -> String? {
        guard let node, validContainer(node), node.children.count == 1,
              let vector = node.child(named: "Vector2"), validContainer(vector),
              let x = ExistingSaveValue.field("X", in: vector).flatMap(Double.init),
              let y = ExistingSaveValue.field("Y", in: vector).flatMap(Double.init),
              x.isFinite, y.isFinite, x.rounded() == x, y.rounded() == y,
              abs(x) <= 1_000_000, abs(y) <= 1_000_000 else { return nil }
        return "\(Int(x)):\(Int(y))"
    }
    private static func itemID(_ raw: String) -> String? {
        let id = raw.hasPrefix("(O)") ? String(raw.dropFirst(3)) : raw
        guard !id.isEmpty, !id.hasPrefix("("), !id.contains(where: { $0.isWhitespace }) else { return nil }
        if let number = Int(id) { return number >= 0 ? String(number) : nil }
        return id
    }
}
