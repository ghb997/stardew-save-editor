import SwiftUI

enum EditorToolCategory: String, CaseIterable, Identifiable {
    case common, farmer, items, farm, progress
    var id: String { rawValue }
    var title: String {
        switch self {
        case .common: "常用修改"
        case .farmer: "人物成长"
        case .items: "物品收集"
        case .farm: "农场经营"
        case .progress: "进度解锁"
        }
    }
}

enum EditorToolEntry: Identifiable {
    case editor(SaveEditorSection)
    case expanded(ExpandedEditorTool)
    case map

    static var all: [Self] {
        SaveEditorSection.allCases.filter { $0 != .review }.map(Self.editor)
            + ExpandedEditorTool.allCases.map(Self.expanded) + [.map]
    }

    static func visible(in category: EditorToolCategory, query: String) -> [Self] {
        let terms = query.split(whereSeparator: \.isWhitespace).map(String.init)
        if !terms.isEmpty {
            return all.filter { entry in
                terms.allSatisfy {
                    (entry.title + entry.subtitle + entry.category.title + entry.keywords)
                        .localizedStandardContains($0)
                }
            }
        }
        if category == .common {
            let ids = ["character", "inventory", "equipment", "relationships", "weather"]
            return ids.compactMap { id in all.first { $0.id == id } }
        }
        return all.filter { $0.category == category }
    }

    var id: String {
        switch self {
        case .editor(let section): section.rawValue
        case .expanded(let tool): tool.rawValue
        case .map: "map"
        }
    }

    var category: EditorToolCategory {
        switch self {
        case .editor(.character), .editor(.appearance), .editor(.relationships), .editor(.skills): .farmer
        case .editor(.inventory), .editor(.recipes), .expanded(.equipment), .expanded(.storage), .expanded(.collections): .items
        case .editor(.farmhouse), .editor(.animals), .expanded(.weather), .expanded(.machines), .map: .farm
        case .editor(.progress), .editor(.wallet), .expanded(.bundles), .editor(.review): .progress
        }
    }

    var title: String {
        switch self {
        case .editor(let section): section.title
        case .expanded(let tool): tool.title
        case .map: "魔法地图"
        }
    }

    var subtitle: String {
        switch self {
        case .editor(.character): "名称、金币、生命、体力与日期"
        case .editor(.appearance): "发型、肤色、饰品与颜色"
        case .editor(.farmhouse): "农舍升级与房间装饰"
        case .editor(.inventory): "背包容量、物品、数量与品质"
        case .editor(.progress): "齐钻、齐币、核桃、干草与矿洞"
        case .editor(.relationships): "好感、送礼次数与人物关系"
        case .editor(.skills): "经验、等级与职业分支"
        case .editor(.wallet): "钥匙、特殊道具与钱包能力"
        case .editor(.animals): "动物名称、好感与状态"
        case .editor(.recipes): "烹饪与制作配方"
        case .editor(.review): "核对草稿、备份、保存与导出"
        case .expanded(.storage): "按地点管理箱子和冰箱物品"
        case .expanded(.weather): "明日天气与每日运气"
        case .expanded(.machines): "查找机器、预览并完成加工"
        case .expanded(.bundles): "献祭进度与缺失材料补给"
        case .expanded(.equipment): "工具升级、武器与鞋子属性"
        case .expanded(.collections): "博物馆、钓鱼、矿物与出货记录"
        case .map: "查看坐标、批量浇水与清理杂物"
        }
    }

    private var keywords: String {
        switch self {
        case .editor(.character): "金钱 钱 时间 季节 年 月 日 农夫"
        case .editor(.relationships): "友情 爱心 NPC 结婚"
        case .editor(.progress): "金色核桃 姜岛 沙漠"
        case .expanded(.equipment): "斧头 镐 锄头 水壶 钓鱼竿 剑 靴子"
        case .expanded(.collections): "古物 化石 鱼 捐赠"
        case .map: "石块 杂草 树枝 作物"
        default: ""
        }
    }

    var symbol: String {
        switch self {
        case .editor(let section): section.systemImage
        case .expanded(let tool): tool.symbol
        case .map: "map.fill"
        }
    }

    var artworkName: String? {
        switch self {
        case .editor(let section): section.artworkName
        case .map: "GameUIFarmComputer"
        default: nil
        }
    }

    var tint: Color {
        switch category {
        case .common, .farmer: .purple
        case .items: .brown
        case .farm: .green
        case .progress: .blue
        }
    }
}
