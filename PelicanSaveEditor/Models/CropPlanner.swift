import Foundation

struct CropSeedPrice: Codable, Hashable, Sendable {
    let place: String
    let price: Int
}

struct CropHarvestQuantity: Codable, Hashable, Sendable {
    let min: Int
    let max: Int
}

struct CropDefinition: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let category: String
    let seasons: [Season]
    let growsOnGingerIsland: Bool
    let growDays: Int
    let phaseDays: [Int]
    let regrowDays: Int?
    let seedID: String
    let seedName: String
    let seedBuyPrices: [CropSeedPrice]
    let cropSellPrice: Int
    let harvestQuantity: CropHarvestQuantity
    let extraHarvestChance: Double
    let harvestMaxIncreasePerFarmingLevel: Double
    let trellis: Bool
    let giant: Bool
    let tillerEligible: Bool

    var chineseName: String { CropCatalog.chineseNames[name] ?? name }

    var displayName: String {
        chineseName == name ? name : "\(chineseName) · \(name)"
    }

    var isPaddyCrop: Bool { id == "271" || id == "830" }
    var isIndoorOnly: Bool { id == "90" }
    var isTeaBush: Bool { id == "815" }

    var cheapestSeedPrice: CropSeedPrice? {
        seedBuyPrices.min { lhs, rhs in
            if lhs.price != rhs.price { return lhs.price < rhs.price }
            return lhs.place < rhs.place
        }
    }
}

enum CropCatalogError: LocalizedError {
    case resourceMissing
    case invalidData

    var errorDescription: String? {
        switch self {
        case .resourceMissing: "内置作物目录不存在。"
        case .invalidData: "内置作物目录格式无效。"
        }
    }
}

enum CropCatalog {
    static func load(bundle: Bundle = .main) throws -> [CropDefinition] {
        guard let url = bundle.url(forResource: "cropinfo", withExtension: "json") else {
            throw CropCatalogError.resourceMissing
        }
        let data = try Data(contentsOf: url)
        let crops = try JSONDecoder().decode([CropDefinition].self, from: data)
        guard crops.count == 47,
              Set(crops.map(\.id)).count == crops.count,
              crops.allSatisfy({
                  $0.growDays > 0
                      && $0.phaseDays.reduce(0, +) == $0.growDays
                      && $0.harvestQuantity.min > 0
                      && $0.harvestQuantity.max >= $0.harvestQuantity.min
                      && (0..<1).contains($0.extraHarvestChance)
              }) else {
            throw CropCatalogError.invalidData
        }
        return crops.sorted {
            $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
    }

    static let chineseNames: [String: String] = [
        "Parsnip": "防风草", "Green Bean": "青豆", "Cauliflower": "花椰菜",
        "Potato": "土豆", "Garlic": "蒜", "Kale": "甘蓝菜", "Rhubarb": "大黄",
        "Strawberry": "草莓", "Unmilled Rice": "未碾米", "Tulip": "郁金香",
        "Blue Jazz": "蓝爵", "Carrot": "胡萝卜", "Coffee Bean": "咖啡豆",
        "Melon": "甜瓜", "Tomato": "西红柿", "Blueberry": "蓝莓",
        "Hot Pepper": "辣椒", "Radish": "萝卜", "Red Cabbage": "红叶卷心菜",
        "Starfruit": "杨桃", "Hops": "啤酒花", "Poppy": "虞美人",
        "Summer Spangle": "夏季亮片", "Summer Squash": "夏南瓜", "Taro Root": "芋头",
        "Corn": "玉米", "Wheat": "小麦", "Sunflower": "向日葵", "Pumpkin": "南瓜",
        "Eggplant": "茄子", "Artichoke": "洋蓟", "Amaranth": "苋菜", "Grape": "葡萄",
        "Cranberries": "蔓越莓", "Bok Choy": "小白菜", "Yam": "山药", "Beet": "甜菜",
        "Sweet Gem Berry": "宝石甜莓", "Fairy Rose": "玫瑰仙子", "Broccoli": "西兰花",
        "Powdermelon": "霜瓜", "Ancient Fruit": "上古水果", "Cactus Fruit": "仙人掌果子",
        "Pineapple": "菠萝", "Qi Fruit": "齐瓜", "Tea Leaves": "茶叶", "Fiber": "纤维"
    ]
}

enum CropEnvironment: String, CaseIterable, Identifiable, Sendable {
    case outdoors
    case protected

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .outdoors: "露天农场"
        case .protected: "温室或姜岛"
        }
    }
}

enum CropGrowthFertilizer: String, CaseIterable, Identifiable, Sendable {
    case none
    case speedGro
    case deluxeSpeedGro
    case hyperSpeedGro

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .none: "不使用"
        case .speedGro: "生长激素（10%）"
        case .deluxeSpeedGro: "高级生长激素（25%）"
        case .hyperSpeedGro: "顶级生长激素（33%）"
        }
    }

    var speedIncrease: Float {
        switch self {
        case .none: 0
        case .speedGro: 0.10
        case .deluxeSpeedGro: 0.25
        case .hyperSpeedGro: 0.33
        }
    }
}

struct CropCalendarDate: Hashable, Comparable, Sendable {
    let year: Int
    let season: Season
    let day: Int

    init(year: Int, season: Season, day: Int) {
        self.year = max(1, year)
        self.season = season
        self.day = max(1, min(28, day))
    }

    var absoluteDay: Int {
        ((year - 1) * 112) + (season.saveIndex * 28) + (day - 1)
    }

    var displayName: String {
        "第 \(year) 年 · \(season.displayName)季 \(day) 日"
    }

    func addingDays(_ count: Int) -> CropCalendarDate {
        Self.from(absoluteDay: max(0, absoluteDay + count))
    }

    static func < (lhs: CropCalendarDate, rhs: CropCalendarDate) -> Bool {
        lhs.absoluteDay < rhs.absoluteDay
    }

    private static func from(absoluteDay: Int) -> CropCalendarDate {
        let year = (absoluteDay / 112) + 1
        let dayOfYear = absoluteDay % 112
        let season = Season(saveIndex: dayOfYear / 28)
        return CropCalendarDate(year: year, season: season, day: (dayOfYear % 28) + 1)
    }
}

struct CropPlanInput: Sendable {
    let crop: CropDefinition
    let startDate: CropCalendarDate
    let planningDays: Int
    let quantity: Int
    let environment: CropEnvironment
    let fertilizer: CropGrowthFertilizer
    let hasAgriculturist: Bool
    let hasPaddyWaterBonus: Bool
    let hasTiller: Bool
}

struct CropPlan: Sendable {
    let effectiveGrowthDays: Int
    let harvestDates: [CropCalendarDate]
    let planningEndDate: CropCalendarDate
    let minimumProduce: Int
    let maximumBaseProduce: Int
    let minimumGrossRevenue: Int
    let maximumBaseGrossRevenue: Int
    let seedCost: Int?
    let minimumNetRevenue: Int?
    let maximumBaseNetRevenue: Int?
    let notes: [String]

    var harvestCount: Int { harvestDates.count }
}

enum CropPlanner {
    static func makePlan(_ input: CropPlanInput) -> CropPlan {
        let horizon = max(1, min(1_120, input.planningDays))
        let quantity = max(1, min(99_999, input.quantity))
        let endDate = input.startDate.addingDays(horizon - 1)
        var notes: [String] = []

        var speedIncrease: Float = 0
        if !input.crop.isTeaBush {
            speedIncrease += input.fertilizer.speedIncrease
            if input.hasAgriculturist { speedIncrease += 0.10 }
            if input.crop.isPaddyCrop, input.hasPaddyWaterBonus { speedIncrease += 0.25 }
        } else {
            notes.append("茶树不是普通作物，生长激素与农业学家不会缩短其 20 天成熟期。")
        }

        let effectiveGrowthDays = input.crop.isTeaBush
            ? input.crop.growDays
            : adjustedGrowthDays(phaseDays: input.crop.phaseDays, speedIncrease: speedIncrease)

        var harvestDates: [CropCalendarDate] = []
        let canPlant: Bool
        if input.crop.isIndoorOnly, input.environment == .outdoors {
            canPlant = false
            notes.append("仙人掌种子不能在露天农场种植；请选择温室或姜岛。")
        } else if input.crop.isTeaBush {
            canPlant = true
            harvestDates = teaHarvestDates(input: input, endDate: endDate)
        } else if input.environment == .outdoors,
                  !input.crop.seasons.contains(input.startDate.season) {
            canPlant = false
            notes.append("所选作物不能在当前季节的露天农场播种。")
        } else {
            canPlant = true
            harvestDates = standardHarvestDates(
                input: input,
                effectiveGrowthDays: effectiveGrowthDays,
                endDate: endDate
            )
        }

        if harvestDates.isEmpty, notes.isEmpty {
            notes.append("在所选规划区间内没有可收获日期。")
        }
        if input.crop.giant {
            notes.append("收益仅按普通收获计算，不计 3×3 巨型作物的随机产量。")
        }
        if input.crop.harvestQuantity.max > input.crop.harvestQuantity.min {
            notes.append("基础产量是游戏在随机额外产物判定前的最小—最大值。")
        }
        if input.crop.extraHarvestChance > 0 {
            let percent = input.crop.extraHarvestChance.formatted(.percent.precision(.fractionLength(0...1)))
            notes.append("每次收获还会以 \(percent) 概率重复判定额外产物；随机部分不计入基础收益。")
        }
        if input.crop.harvestMaxIncreasePerFarmingLevel > 0 {
            notes.append("额外产量还会受玩家耕种等级影响，本页只计算保底基础产量。")
        }
        if input.crop.trellis {
            notes.append("这是棚架作物，规划地块时需要保留可通行路径。")
        }
        if input.crop.name == "Sunflower" {
            notes.append("收获向日葵还会掉落 0—2 颗种子；种子成本按每轮重新购买计算，因此净收益偏保守。")
        }

        let harvestCount = harvestDates.count
        let minimumProduce = harvestCount * quantity * input.crop.harvestQuantity.min
        let maximumProduce = harvestCount * quantity * input.crop.harvestQuantity.max
        let unitPrice = input.hasTiller && input.crop.tillerEligible
            ? Int(Double(input.crop.cropSellPrice) * 1.10)
            : input.crop.cropSellPrice
        let minimumGross = minimumProduce * unitPrice
        let maximumGross = maximumProduce * unitPrice

        let seedPurchases: Int
        if !canPlant {
            seedPurchases = 0
        } else if input.crop.regrowDays != nil || input.crop.isTeaBush {
            seedPurchases = quantity
        } else {
            seedPurchases = quantity * max(1, harvestCount)
        }
        let seedCost = input.crop.cheapestSeedPrice.map { $0.price * seedPurchases }

        return CropPlan(
            effectiveGrowthDays: effectiveGrowthDays,
            harvestDates: harvestDates,
            planningEndDate: endDate,
            minimumProduce: minimumProduce,
            maximumBaseProduce: maximumProduce,
            minimumGrossRevenue: minimumGross,
            maximumBaseGrossRevenue: maximumGross,
            seedCost: seedCost,
            minimumNetRevenue: seedCost.map { minimumGross - $0 },
            maximumBaseNetRevenue: seedCost.map { maximumGross - $0 },
            notes: notes
        )
    }

    /// Mirrors `HoeDirt.applySpeedIncreases`: the game calculates the removal
    /// count with single-precision floats, then removes at most three days from
    /// each visual phase while keeping the first phase at one day or longer.
    static func adjustedGrowthDays(phaseDays: [Int], speedIncrease: Float) -> Int {
        let baseDays = phaseDays.reduce(0, +)
        guard baseDays > 0, speedIncrease > 0 else { return max(1, baseDays) }

        var adjustedPhases = phaseDays
        // Preserve the game's observed float-operand rounding behavior before
        // Math.Ceiling. In particular, 10 days × 10% removes two days.
        let floatOperandProduct = Double(Float(baseDays)) * Double(speedIncrease)
        var daysToRemove = Int(ceil(floatOperandProduct))
        var tries = 0

        while daysToRemove > 0, tries < 3 {
            for index in adjustedPhases.indices {
                if index > 0 || adjustedPhases[index] > 1 {
                    adjustedPhases[index] -= 1
                    daysToRemove -= 1
                }
                if daysToRemove <= 0 { break }
            }
            tries += 1
        }

        // The game can decrement a non-first phase below zero. Such a phase is
        // skipped by daily growth rather than making the crop mature backwards.
        let effectiveDays = adjustedPhases.reduce(0) { $0 + max(0, $1) }
        return max(1, effectiveDays)
    }

    private static func standardHarvestDates(
        input: CropPlanInput,
        effectiveGrowthDays: Int,
        endDate: CropCalendarDate
    ) -> [CropCalendarDate] {
        var result: [CropCalendarDate] = []
        var growingFrom = input.startDate
        var nextHarvest = growingFrom.addingDays(effectiveGrowthDays)

        while nextHarvest <= endDate,
              isValidGrowthSpan(from: growingFrom, through: nextHarvest, input: input) {
            result.append(nextHarvest)
            growingFrom = nextHarvest
            if let regrowDays = input.crop.regrowDays, regrowDays > 0 {
                nextHarvest = nextHarvest.addingDays(regrowDays)
            } else {
                nextHarvest = nextHarvest.addingDays(effectiveGrowthDays)
            }
        }
        return result
    }

    private static func teaHarvestDates(
        input: CropPlanInput,
        endDate: CropCalendarDate
    ) -> [CropCalendarDate] {
        let maturityDate = input.startDate.addingDays(input.crop.growDays)
        guard maturityDate <= endDate else {
            return []
        }

        var result: [CropCalendarDate] = []
        var date = maturityDate
        while date <= endDate {
            let seasonAllowed = input.environment == .protected || date.season != .winter
            if seasonAllowed, (22...28).contains(date.day) {
                result.append(date)
            }
            date = date.addingDays(1)
        }
        return result
    }

    private static func isValidGrowthSpan(
        from start: CropCalendarDate,
        through end: CropCalendarDate,
        input: CropPlanInput
    ) -> Bool {
        guard input.environment == .outdoors else { return true }
        var date = start
        while date <= end {
            if !input.crop.seasons.contains(date.season) { return false }
            date = date.addingDays(1)
        }
        return true
    }
}
