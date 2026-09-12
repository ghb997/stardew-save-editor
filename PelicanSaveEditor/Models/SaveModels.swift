import Foundation

enum Season: String, CaseIterable, Codable, Identifiable, Sendable {
    case spring
    case summer
    case fall
    case winter

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .spring: "春"
        case .summer: "夏"
        case .fall: "秋"
        case .winter: "冬"
        }
    }

    var saveIndex: Int {
        switch self {
        case .spring: 0
        case .summer: 1
        case .fall: 2
        case .winter: 3
        }
    }

    init(saveIndex: Int) {
        self = Self.allCases.indices.contains(saveIndex) ? Self.allCases[saveIndex] : .spring
    }
}

enum FarmerGender: String, CaseIterable, Codable, Identifiable, Sendable {
    case male = "Male"
    case female = "Female"

    var id: String { rawValue }
    var displayName: String { self == .male ? "男" : "女" }
}

enum SkillKey: String, CaseIterable, Codable, Identifiable, Sendable {
    case farming
    case fishing
    case foraging
    case mining
    case combat

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .farming: "耕种"
        case .fishing: "钓鱼"
        case .foraging: "觅食"
        case .mining: "采矿"
        case .combat: "战斗"
        }
    }

    var fieldName: String { "\(rawValue)Level" }

    /// Order used by Stardew's `experiencePoints` array.
    var experienceIndex: Int {
        switch self {
        case .farming: 0
        case .fishing: 1
        case .foraging: 2
        case .mining: 3
        case .combat: 4
        }
    }

    static let experienceForLevel = [0, 100, 380, 770, 1_300, 2_150, 3_300, 4_800, 6_900, 10_000, 15_000]

    static func level(forExperience experience: Int) -> Int {
        experienceForLevel.lastIndex(where: { experience >= $0 }) ?? 0
    }
}

struct SkillDraft: Identifiable, Equatable, Sendable {
    var id: SkillKey { key }
    let key: SkillKey
    let originalLevel: Int
    let originalExperience: Int
    var level: Int
    var experience: Int

    var targetExperience: Int {
        guard experience == originalExperience, level != originalLevel else { return experience }
        return SkillKey.experienceForLevel[max(0, min(10, level))]
    }
}

struct ProfessionOption: Identifiable, Equatable, Sendable {
    let id: Int
    let skill: SkillKey
    let tier: Int
    let parentID: Int?
    let name: String
}

enum ProfessionCatalog {
    static let options: [ProfessionOption] = [
        ProfessionOption(id: 0, skill: .farming, tier: 5, parentID: nil, name: "牧场主"),
        ProfessionOption(id: 1, skill: .farming, tier: 5, parentID: nil, name: "耕种者"),
        ProfessionOption(id: 2, skill: .farming, tier: 10, parentID: 0, name: "鸡舍大师"),
        ProfessionOption(id: 3, skill: .farming, tier: 10, parentID: 0, name: "牧羊人"),
        ProfessionOption(id: 4, skill: .farming, tier: 10, parentID: 1, name: "制品生产家"),
        ProfessionOption(id: 5, skill: .farming, tier: 10, parentID: 1, name: "农业学家"),
        ProfessionOption(id: 6, skill: .fishing, tier: 5, parentID: nil, name: "渔夫"),
        ProfessionOption(id: 7, skill: .fishing, tier: 5, parentID: nil, name: "捕猎者"),
        ProfessionOption(id: 8, skill: .fishing, tier: 10, parentID: 6, name: "垂钓者"),
        ProfessionOption(id: 9, skill: .fishing, tier: 10, parentID: 6, name: "海盗"),
        ProfessionOption(id: 10, skill: .fishing, tier: 10, parentID: 7, name: "水手"),
        ProfessionOption(id: 11, skill: .fishing, tier: 10, parentID: 7, name: "诱饵大师"),
        ProfessionOption(id: 12, skill: .foraging, tier: 5, parentID: nil, name: "护林人"),
        ProfessionOption(id: 13, skill: .foraging, tier: 5, parentID: nil, name: "采集者"),
        ProfessionOption(id: 14, skill: .foraging, tier: 10, parentID: 12, name: "伐木工"),
        ProfessionOption(id: 15, skill: .foraging, tier: 10, parentID: 12, name: "萃取者"),
        ProfessionOption(id: 16, skill: .foraging, tier: 10, parentID: 13, name: "植物学家"),
        ProfessionOption(id: 17, skill: .foraging, tier: 10, parentID: 13, name: "追踪者"),
        ProfessionOption(id: 18, skill: .mining, tier: 5, parentID: nil, name: "矿工"),
        ProfessionOption(id: 19, skill: .mining, tier: 5, parentID: nil, name: "地质学家"),
        ProfessionOption(id: 20, skill: .mining, tier: 10, parentID: 18, name: "铁匠"),
        ProfessionOption(id: 21, skill: .mining, tier: 10, parentID: 18, name: "勘探者"),
        ProfessionOption(id: 22, skill: .mining, tier: 10, parentID: 19, name: "挖掘者"),
        ProfessionOption(id: 23, skill: .mining, tier: 10, parentID: 19, name: "宝石学家"),
        ProfessionOption(id: 24, skill: .combat, tier: 5, parentID: nil, name: "战士"),
        ProfessionOption(id: 25, skill: .combat, tier: 5, parentID: nil, name: "侦察员"),
        ProfessionOption(id: 26, skill: .combat, tier: 10, parentID: 24, name: "野蛮人"),
        ProfessionOption(id: 27, skill: .combat, tier: 10, parentID: 24, name: "防御者"),
        ProfessionOption(id: 28, skill: .combat, tier: 10, parentID: 25, name: "特技者"),
        ProfessionOption(id: 29, skill: .combat, tier: 10, parentID: 25, name: "亡命徒")
    ]

    static let knownIDs = Set(options.map(\.id))

    static func options(for skill: SkillKey) -> [ProfessionOption] {
        options.filter { $0.skill == skill }
    }

    static func name(for id: Int) -> String {
        options.first(where: { $0.id == id })?.name ?? "职业 \(id)"
    }
}

enum WalletUnlockKey: String, CaseIterable, Identifiable, Sendable {
    case dwarvishGuide = "HasDwarvishTranslationGuide"
    case rustyKey = "HasRustyKey"
    case clubCard = "HasClubCard"
    case specialCharm = "HasSpecialCharm"
    case skullKey = "HasSkullKey"
    case magnifyingGlass = "HasMagnifyingGlass"
    case darkTalisman = "HasDarkTalisman"
    case magicInk = "HasMagicInk"
    case townKey = "HasTownKey"
    case skullDoor = "HasUnlockedSkullDoor"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .dwarvishGuide: "矮人语翻译指南"
        case .rustyKey: "生锈的钥匙"
        case .clubCard: "俱乐部会员卡"
        case .specialCharm: "特殊魅力"
        case .skullKey: "骷髅钥匙"
        case .magnifyingGlass: "放大镜"
        case .darkTalisman: "黑暗护身符"
        case .magicInk: "魔法墨水"
        case .townKey: "小镇钥匙"
        case .skullDoor: "骷髅洞入口"
        }
    }

    var systemImage: String {
        switch self {
        case .dwarvishGuide: "text.book.closed.fill"
        case .rustyKey, .skullKey, .townKey: "key.fill"
        case .clubCard: "creditcard.fill"
        case .specialCharm: "sparkles"
        case .magnifyingGlass: "magnifyingglass"
        case .darkTalisman: "moon.stars.fill"
        case .magicInk: "pencil.and.scribble"
        case .skullDoor: "door.left.hand.open"
        }
    }

    var legacyFieldName: String {
        switch self {
        case .dwarvishGuide: "canUnderstandDwarves"
        case .rustyKey: "hasRustyKey"
        case .clubCard: "hasClubCard"
        case .specialCharm: "hasSpecialCharm"
        case .skullKey: "hasSkullKey"
        case .magnifyingGlass: "hasMagnifyingGlass"
        case .darkTalisman: "hasDarkTalisman"
        case .magicInk: "hasMagicInk"
        case .townKey: "HasTownKey"
        case .skullDoor: "hasUnlockedSkullDoor"
        }
    }
}

struct WalletUnlockDraft: Identifiable, Equatable, Sendable {
    var id: WalletUnlockKey { key }
    let key: WalletUnlockKey
    var isUnlocked: Bool
}

struct SaveInsights: Equatable, Sendable {
    var weatherForTomorrow: String?
    var dailyLuck: Double?
    var activeQuestCount: Int
    var achievementCount: Int
    var shippedItemKinds: Int
    var caughtFishKinds: Int
    var mineralKinds: Int
    var artifactKinds: Int
    var secretNoteCount: Int
    var eventCount: Int
    var mailFlagCount: Int
    var daysPlayed: Int?
    var questsCompleted: Int?
    var monstersKilled: Int?
    var itemsShipped: Int?
    var fishCaught: Int?
}

struct ProgressDraft: Equatable, Sendable {
    var qiGems: Int?
    var clubCoins: Int?
    var totalMoneyEarned: Int?
    var goldenWalnuts: Int?
    var piecesOfHay: Int?
    var deepestMineLevel: Int?
    var mineLowestLevelReached: Int?
    var professionIDs: Set<Int>
    var walletUnlocks: [WalletUnlockDraft]
    var insights: SaveInsights
}

struct FarmAnimalDraft: Identifiable, Equatable, Sendable {
    let id: String
    let type: String
    let home: String
    var name: String
    var friendship: Int
    var happiness: Int
    var fullness: Int
    var daysOwned: Int

    var localizedType: String {
        switch type.lowercased() {
        case "white cow": "白牛"
        case "brown cow": "棕牛"
        case "goat": "山羊"
        case "pig": "猪"
        case "sheep": "绵羊"
        case "white chicken": "白鸡"
        case "brown chicken": "棕鸡"
        case "blue chicken": "蓝鸡"
        case "void chicken": "虚空鸡"
        case "golden chicken": "金鸡"
        case "duck": "鸭"
        case "rabbit": "兔子"
        case "dinosaur": "恐龙"
        case "ostrich": "鸵鸟"
        default: type.isEmpty ? "农场动物" : type
        }
    }

    var hearts: Int { max(0, min(5, friendship / 200)) }
}

enum RelationshipStatus: String, CaseIterable, Codable, Identifiable, Sendable {
    case friendly = "Friendly"
    case dating = "Dating"
    case engaged = "Engaged"
    case married = "Married"
    case divorced = "Divorced"
    case unknown = "Unknown"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .friendly: "朋友"
        case .dating: "约会"
        case .engaged: "订婚"
        case .married: "已婚"
        case .divorced: "离婚"
        case .unknown: "未知"
        }
    }

    var safelyEditable: Bool { self == .friendly || self == .dating }
}

struct FriendshipDraft: Identifiable, Equatable, Sendable {
    var id: String { name }
    let name: String
    var points: Int
    var status: RelationshipStatus
    let originalPoints: Int
    let originalStatus: RelationshipStatus
    var giftsToday: Int? = nil
    var giftsThisWeek: Int? = nil
    var hasEditablePoints = true
    var hasEditableStatus = true

    var canEditStatus: Bool {
        hasEditableStatus && (originalStatus == .friendly || originalStatus == .dating)
    }

    var hearts: Int { max(0, points) / 250 }

    var localizedName: String { npcChineseNames[name] ?? name }
}

enum RecipeKind: String, CaseIterable, Codable, Identifiable, Sendable {
    case cooking
    case crafting

    var id: String { rawValue }
    var displayName: String { self == .cooking ? "烹饪" : "制作" }
    var containerName: String { self == .cooking ? "cookingRecipes" : "craftingRecipes" }
}

struct RecipeDraft: Identifiable, Equatable, Sendable {
    var id: String { "\(kind.rawValue):\(key)" }
    let key: String
    let kind: RecipeKind
    var unlocked: Bool
    var timesMade: Int
    let originallyUnlocked: Bool
    let originalTimesMade: Int
}

struct InventoryItemDraft: Identifiable, Equatable, Sendable {
    var id: UUID
    var itemID: String
    var name: String
    var chineseName: String?
    var objectType: String
    var stack: Int
    var quality: Int
    /// Sprite location from the game's item metadata. Nil keeps unknown/tool
    /// records on the generic symbol fallback rather than showing a wrong item.
    var spriteIndex: Int?
    var texture: String?
    var allowedQualities: [Int]
    var isEditable: Bool
    /// Complete item element used to preserve every field the editor does not understand.
    var templateXML: String

    var localizedName: String {
        guard let chineseName, !chineseName.isEmpty else { return name }
        return chineseName
    }

    var displayName: String { localizedName }

    func copied() -> InventoryItemDraft {
        var result = self
        result.id = UUID()
        return result
    }
}

struct InventorySlotDraft: Identifiable, Equatable, Sendable {
    let id: Int
    var item: InventoryItemDraft?
}

enum RoomDecorationKind: String, Identifiable, Equatable, Sendable {
    case wallpaper
    case flooring

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .wallpaper: "墙纸"
        case .flooring: "地板"
        }
    }
}

enum RoomDecorationStorage: Equatable, Sendable {
    case scalar(fieldName: String)
    case dictionary(containerName: String, key: String)
}

struct RoomDecorationDraft: Identifiable, Equatable, Sendable {
    let id: String
    let kind: RoomDecorationKind
    let roomKey: String
    let storage: RoomDecorationStorage
    var styleIndex: Int

    var localizedRoomName: String {
        switch roomKey.lowercased() {
        case "farmhouse", "main", "0": "主房间"
        case "bedroom", "1": "卧室"
        case "kitchen", "2": "厨房"
        case "nursery", "3": "婴儿房"
        case "southernroom", "southroom", "4": "南侧房间"
        case "upperleft": "左上房间"
        case "upperright": "右上房间"
        case "bottomright", "bottomright_left", "bottomright_right": "右下房间"
        case "bottomleft": "左下房间"
        case "entry", "hallway": "入口与走廊"
        default: roomKey
        }
    }
}

struct FarmhouseDraft: Equatable, Sendable {
    var upgradeLevel: Int?
    var decorations: [RoomDecorationDraft]

    var hasEditableContent: Bool {
        upgradeLevel != nil || !decorations.isEmpty
    }
}

struct FarmActionDraft: Equatable, Sendable {
    var waterAllCrops = false
    var clearStones = false
    var clearWeeds = false
    var clearTwigs = false
    var debrisRemovalKeys: Set<String> = []
    var cropWateringKeys: Set<String> = []

    var hasChanges: Bool {
        waterAllCrops || clearStones || clearWeeds || clearTwigs || !debrisRemovalKeys.isEmpty || !cropWateringKeys.isEmpty
    }
}

struct SaveDraft: Equatable, Sendable {
    var playerName: String
    var farmName: String
    var favoriteThing: String
    var money: Int
    var maxHealth: Int
    var maxStamina: Int
    var gender: FarmerGender
    /// User-facing 0...73 index. Values 56+ are converted to the game's 100+ range.
    var hair: Int
    var skin: Int
    var accessory: Int
    var year: Int
    var season: Season
    var day: Int
    var skills: [SkillDraft]
    var inventory: [InventorySlotDraft]
    var friendships: [FriendshipDraft]
    var recipes: [RecipeDraft]
    var farmhouse: FarmhouseDraft
    var progress: ProgressDraft
    var animals: [FarmAnimalDraft]
    var farmActions: FarmActionDraft
    /// Nil means the save does not expose a valid capacity field.
    var backpackCapacity: Int? = nil
    /// Keep originally serialized slots, including empty or extended slots.
    var inventorySlotFloor: Int = 0
    var appearanceColors: [FarmerColorField: FarmerColor] = [:]
    var storages: [StorageDraft] = []
    var machines: [MachineDraft] = []
    var weatherAndLuck = WeatherAndLuckDraft()
    var communityCenter = CommunityCenterData()
}

extension SaveDraft {
    mutating func setSkillLevel(_ level: Int, for key: SkillKey) {
        guard let index = skills.firstIndex(where: { $0.key == key }) else { return }
        let level = max(0, min(10, level))
        skills[index].level = level
        skills[index].experience = SkillKey.experienceForLevel[level]
        removeUnavailableProfessions(for: key, level: level)
    }

    mutating func setSkillExperience(_ experience: Int, for key: SkillKey) {
        guard let index = skills.firstIndex(where: { $0.key == key }) else { return }
        skills[index].experience = experience
        skills[index].level = SkillKey.level(forExperience: experience)
        removeUnavailableProfessions(for: key, level: skills[index].level)
    }

    mutating func setPrimaryProfession(_ professionID: Int?, for key: SkillKey) {
        let options = ProfessionCatalog.options(for: key)
        guard professionID == nil || options.contains(where: {
            $0.id == professionID && $0.tier == 5
        }) else { return }
        guard let level = skills.first(where: { $0.key == key })?.level else { return }
        progress.professionIDs.subtract(options.map(\.id))
        if level >= 5, let professionID { progress.professionIDs.insert(professionID) }
    }

    mutating func setSecondaryProfession(_ professionID: Int?, for key: SkillKey) {
        let options = ProfessionCatalog.options(for: key)
        guard professionID == nil || options.contains(where: {
            $0.id == professionID && $0.tier == 10
        }) else { return }
        progress.professionIDs.subtract(options.filter { $0.tier == 10 }.map(\.id))
        guard let professionID,
              skills.first(where: { $0.key == key })?.level == 10,
              let option = options.first(where: { $0.id == professionID }),
              let parent = option.parentID else { return }
        setPrimaryProfession(parent, for: key)
        progress.professionIDs.insert(professionID)
    }

    private mutating func removeUnavailableProfessions(for key: SkillKey, level: Int) {
        let unavailable = ProfessionCatalog.options(for: key).filter { $0.tier > level }
        progress.professionIDs.subtract(unavailable.map(\.id))
    }
}

struct SaveDiffGroup: Identifiable, Equatable, Sendable {
    var id: String { section }
    let section: String
    let diffs: [SaveDiff]
}

struct SaveDiff: Identifiable, Equatable, Sendable {
    let id: String
    let section: String
    let label: String
    let oldValue: String
    let newValue: String
    let affectsSaveGameInfo: Bool
}

struct LoadedSaveMetadata: Equatable, Sendable {
    let farmIdentifier: String
    let gameVersion: String
    let playTimeMilliseconds: Int64?
    let farmType: Int?
    let mainEncoding: SaveEncoding
    let infoEncoding: SaveEncoding?
    let warnings: [String]
}
