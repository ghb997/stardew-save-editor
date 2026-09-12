import SwiftUI

struct WeatherEditorView: View {
    @Bindable var session: SaveSession
    @State private var luckText = ""
    @State private var error: String?
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("明日天气会在下一天由游戏读取，节日、婚礼和特殊事件可能覆盖选择。每日运气只影响已保存的当前值，新一天仍由游戏重新计算。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("明日天气") {
                    ForEach(session.draft.weatherAndLuck.regions.indices, id: \.self) { index in
                        let region = session.draft.weatherAndLuck.regions[index]
                        VStack(alignment: .leading, spacing: 8) {
                            Picker(region.title, selection: $session.draft.weatherAndLuck.regions[index].selected) {
                                ForEach(SavedWeather.allCases.filter { region.id != "Island" || [.sun, .rain, .storm].contains($0) || $0 == region.original }) { value in
                                    Text(value.title).tag(value)
                                }
                            }
                            .accessibilityIdentifier("weather.region.\(region.id)")
                            Text("原始：\(region.original.title) → 草稿：\(region.selected.title)")
                                .font(.caption).foregroundStyle(.secondary)
                            Button("恢复\(region.title)") { session.draft.weatherAndLuck.regions[index].selected = region.original }
                                .font(.caption).disabled(region.selected == region.original)
                        }
                    }
                    if session.draft.weatherAndLuck.regions.isEmpty { Text("没有可编辑的标准明日天气字段。").foregroundStyle(.secondary) }
                    ForEach(session.draft.weatherAndLuck.notes, id: \.self) { Text($0).font(.caption).foregroundStyle(.secondary) }
                }
                Section("每日运气") {
                    if let value = session.draft.weatherAndLuck.dailyLuck {
                        LabeledContent("当前草稿", value: String(format: "%.4f", value))
                            .accessibilityIdentifier("weather.luck.current")
                        LabeledContent("原始数值", value: session.originalDraft.weatherAndLuck.dailyLuck.map { String(format: "%.4f", $0) } ?? "未提供")
                        HStack {
                            TextField("-0.1 至 0.1", text: $luckText).keyboardType(.numbersAndPunctuation)
                                .textInputAutocapitalization(.never).autocorrectionDisabled()
                                .accessibilityIdentifier("weather.luck.input")
                            Button("应用数值") { applyLuck() }.accessibilityIdentifier("weather.luck.apply")
                        }
                        Button("最好运气（0.1）") { setLuck(0.1) }.accessibilityIdentifier("weather.luck.best")
                        Button("中性运气（0）") { setLuck(0) }
                        Button("最差运气（-0.1）") { setLuck(-0.1) }
                        Button("恢复原始运气") {
                            session.draft.weatherAndLuck.dailyLuck = session.originalDraft.weatherAndLuck.dailyLuck
                            luckText = session.draft.weatherAndLuck.dailyLuck.map { String($0) } ?? ""
                            error = nil
                        }.accessibilityIdentifier("weather.luck.restore")
                    } else { Text("存档未提供有效运气值，保留原样。").foregroundStyle(.secondary) }
                    if let error { Text(error).foregroundStyle(.red).accessibilityIdentifier("weather.luck.error") }
                }
            }
            .navigationTitle("天气与运气").navigationBarTitleDisplayMode(.inline)
            .onAppear { luckText = session.draft.weatherAndLuck.dailyLuck.map { String($0) } ?? "" }
        }
    }
    private func setLuck(_ value: Double) {
        session.draft.weatherAndLuck.dailyLuck = value; luckText = String(value); error = nil
    }
    private func applyLuck() {
        guard let value = Double(luckText.trimmingCharacters(in: .whitespacesAndNewlines)), value.isFinite,
              (-0.1...0.1).contains(value) else { error = "请输入 -0.1 至 0.1 之间的数值。"; return }
        setLuck(value); KeyboardReturnAction.dismiss()
    }
}
