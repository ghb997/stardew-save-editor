import SwiftUI

struct CropCalculatorView: View {
    let catalog: [CropDefinition]
    @Environment(\.dismiss) private var dismiss

    @State private var selectedCropID: String
    @State private var year: Int
    @State private var season: Season
    @State private var day: Int
    @State private var planningDays = 28
    @State private var quantity = 1
    @State private var environment: CropEnvironment = .outdoors
    @State private var fertilizer: CropGrowthFertilizer = .none
    @State private var hasAgriculturist = false
    @State private var hasPaddyWaterBonus = false
    @State private var hasTiller = false

    init(catalog: [CropDefinition], session: SaveSession?) {
        self.catalog = catalog
        let initialCrop = catalog.first(where: { crop in
            guard let session else { return crop.name == "Parsnip" }
            return crop.seasons.contains(session.draft.season)
        }) ?? catalog.first
        _selectedCropID = State(initialValue: initialCrop?.id ?? "")
        _year = State(initialValue: session?.draft.year ?? 1)
        _season = State(initialValue: session?.draft.season ?? .spring)
        _day = State(initialValue: session?.draft.day ?? 1)
    }

    private var selectedCrop: CropDefinition? {
        catalog.first { $0.id == selectedCropID }
    }

    private var plan: CropPlan? {
        guard let selectedCrop else { return nil }
        return CropPlanner.makePlan(CropPlanInput(
            crop: selectedCrop,
            startDate: CropCalendarDate(year: year, season: season, day: day),
            planningDays: planningDays,
            quantity: quantity,
            environment: environment,
            fertilizer: fertilizer,
            hasAgriculturist: hasAgriculturist,
            hasPaddyWaterBonus: hasPaddyWaterBonus,
            hasTiller: hasTiller
        ))
    }

    var body: some View {
        NavigationStack {
            Group {
                if catalog.isEmpty {
                    GameEmptyState(
                        title: "作物目录不可用",
                        systemImage: "leaf.fill",
                        message: "内置作物数据没有成功载入。"
                    )
                } else {
                    Form {
                        cropSection
                        calendarSection
                        growthSection
                        resultSection
                        revenueSection
                        explanationSection
                    }
                }
            }
            .navigationTitle("农作物计算器")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }

    private var cropSection: some View {
        Section {
            Picker("作物", selection: $selectedCropID) {
                ForEach(catalog) { crop in
                    Text(crop.displayName).tag(crop.id)
                }
            }

            if let crop = selectedCrop {
                HStack(spacing: 14) {
                    GameItemIcon(id: crop.id, size: 52)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(crop.displayName)
                            .font(.headline)
                        Text("收获物 ID \(crop.id)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                LabeledContent("适宜季节", value: cropSeasonText(crop))
                LabeledContent("基础成熟时间", value: crop.isTeaBush ? "20 天（茶树规则）" : "\(crop.growDays) 天")
                if let regrow = crop.regrowDays, !crop.isTeaBush {
                    LabeledContent("再次收获", value: "每 \(regrow) 天")
                } else if !crop.isTeaBush {
                    LabeledContent("收获方式", value: "收获后重新播种")
                }
                LabeledContent("基础售价", value: "\(crop.cropSellPrice.formatted())g")
                if let seed = crop.cheapestSeedPrice {
                    LabeledContent("最低种子价", value: "\(seed.price.formatted())g · \(seed.place)")
                } else {
                    LabeledContent("种子购入价", value: "无固定商店价格")
                }
            }
        } header: {
            GameAssetLabel("作物", assetName: "GameUICropPlanner", iconSize: 24)
        }
    }

    private var calendarSection: some View {
        Section {
            Stepper("第 \(year) 年", value: $year, in: 1...99)
            Picker("播种季节", selection: $season) {
                ForEach(Season.allCases) { value in
                    Text(value.displayName).tag(value)
                }
            }
            Stepper("播种日：\(day) 日", value: $day, in: 1...28)
            Stepper("规划区间：\(planningDays) 天", value: $planningDays, in: 7...112, step: 7)
            Picker("种植地点", selection: $environment) {
                ForEach(CropEnvironment.allCases) { value in
                    Text(value.displayName).tag(value)
                }
            }
            .adaptiveSegmentedPicker()
        } header: {
            Text("日期与地点")
        } footer: {
            Text("露天农场会检查跨季存活条件；温室或姜岛按全年可生长计算。")
        }
    }

    private var growthSection: some View {
        Section("种植条件") {
            Stepper("种植格数：\(quantity)", value: $quantity, in: 1...9_999)
            if selectedCrop?.isTeaBush == true {
                LabeledContent("生长加速", value: "不适用于茶树")
            } else {
                Picker("生长肥料", selection: $fertilizer) {
                    ForEach(CropGrowthFertilizer.allCases) { value in
                        Text(value.displayName).tag(value)
                    }
                }
                Toggle("农业学家职业（再快 10%）", isOn: $hasAgriculturist)
            }
            if selectedCrop?.isPaddyCrop == true {
                Toggle("邻近水源（水稻/芋头快 25%）", isOn: $hasPaddyWaterBonus)
            }
            if selectedCrop?.tillerEligible == true {
                Toggle("农耕人职业（作物售价 +10%）", isOn: $hasTiller)
            }
        }
    }

    @ViewBuilder
    private var resultSection: some View {
        if let plan {
            Section("收获计划") {
                LabeledContent("规划截止", value: plan.planningEndDate.displayName)
                LabeledContent("实际成熟时间", value: "\(plan.effectiveGrowthDays) 天")
                LabeledContent("收获次数", value: "\(plan.harvestCount) 次")
                LabeledContent("基础产量", value: produceRange(plan))

                if !plan.harvestDates.isEmpty {
                    DisclosureGroup("查看全部收获日期") {
                        ForEach(Array(plan.harvestDates.enumerated()), id: \.offset) { index, date in
                            LabeledContent("第 \(index + 1) 次", value: date.displayName)
                        }
                    }
                }

                ForEach(plan.notes, id: \.self) { note in
                    GameLabel(note, systemImage: "info.circle.fill")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
            }
        }
    }

    @ViewBuilder
    private var revenueSection: some View {
        if let plan {
            Section {
                LabeledContent("基础总收入", value: currencyRange(
                    minimum: plan.minimumGrossRevenue,
                    maximum: plan.maximumBaseGrossRevenue
                ))
                if let seedCost = plan.seedCost {
                    LabeledContent("种子成本", value: "\(seedCost.formatted())g")
                } else {
                    LabeledContent("种子成本", value: "无金币定价，未计入")
                }
                if let minimumNet = plan.minimumNetRevenue,
                   let maximumNet = plan.maximumBaseNetRevenue {
                    LabeledContent("基础净收入", value: currencyRange(
                        minimum: minimumNet,
                        maximum: maximumNet
                    ))
                }
            } header: {
                Text("收益")
            } footer: {
                Text("按普通品质和目录记录的最低金币购入价计算；商店营业、库存、随机价格、品质、加工品与随机额外产物需另行判断。")
            }
        }
    }

    private var explanationSection: some View {
        Section("计算依据") {
            Text("成熟天数按游戏对各生长阶段的单精度浮点加速规则计算；多次收获作物成熟后按再生天数排期，单次收获作物按当天收获后立即补种排期。茶树按成熟后每季 22—28 日产叶的独立规则计算。")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private func cropSeasonText(_ crop: CropDefinition) -> String {
        var values = crop.seasons.map(\.displayName)
        if crop.growsOnGingerIsland { values.append("姜岛全年") }
        if crop.isIndoorOnly { return "仅室内或姜岛" }
        return values.isEmpty ? "特殊地点" : values.joined(separator: "、")
    }

    private func produceRange(_ plan: CropPlan) -> String {
        if plan.minimumProduce == plan.maximumBaseProduce {
            return "\(plan.minimumProduce.formatted()) 个"
        }
        return "\(plan.minimumProduce.formatted())—\(plan.maximumBaseProduce.formatted()) 个"
    }

    private func currencyRange(minimum: Int, maximum: Int) -> String {
        if minimum == maximum { return "\(minimum.formatted())g" }
        return "\(minimum.formatted())—\(maximum.formatted())g"
    }
}
