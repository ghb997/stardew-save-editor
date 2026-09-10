import SwiftUI
import UIKit

struct AppearanceColorsEditor: View {
    @Bindable var session: SaveSession
    @State private var field: FarmerColorField = .hair

    var body: some View {
        Form {
            Section {
                Picker("颜色部位", selection: $field) {
                    ForEach(FarmerColorField.allCases) { field in
                        Text(field.title).tag(field)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("editor.appearance.colorField")
            }
            if session.draft.appearanceColors[field] != nil {
                AppearanceColorControls(session: session, field: field).id(field)
            } else {
                Section {
                    ContentUnavailableView("没有可编辑的\(field.title)", systemImage: "paintpalette",
                        description: Text("这份存档未提供有效颜色，保留当前外观。"))
                }
            }
        }
        .accessibilityIdentifier("editor.appearance.colorForm")
        .navigationTitle("外观颜色")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct AppearanceColorControls: View {
    @Bindable var session: SaveSession
    let field: FarmerColorField
    @State private var hexInput = ""

    private var current: FarmerColor { session.draft.appearanceColors[field]! }
    private var original: FarmerColor { session.originalDraft.appearanceColors[field]! }
    private let presets = ["302820", "604020", "B77C43", "E5C277", "8E3B46", "42847B", "5364A3", "E2D7C7"]

    var body: some View {
        Group {
        Section("原始与当前") {
            HStack(spacing: 20) {
                colorSample(original, title: "原始")
                Image(systemName: "arrow.right").foregroundStyle(.secondary)
                colorSample(current, title: "当前草稿")
            }
            .frame(maxWidth: .infinity)
            Text(current.hex)
                .font(.headline.monospaced())
                .accessibilityIdentifier("editor.appearance.color.current")
        }
        Section {
            ColorPicker("选择颜色", selection: colorBinding, supportsOpacity: false)
            LabeledContent("十六进制色值") {
                TextField("#RRGGBB", text: $hexInput)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .multilineTextAlignment(.trailing)
                    .font(.body.monospaced())
                    .accessibilityIdentifier("editor.appearance.color.hex")
                    .onSubmit { applyHex(); KeyboardReturnAction.dismiss() }
            }
            Button("应用色值") { applyHex(); KeyboardReturnAction.dismiss() }
                .disabled(FarmerColor(hex: hexInput, alpha: current.alpha) == nil)
                .accessibilityIdentifier("editor.appearance.color.applyHex")
            Text("RGB：\(current.red) / \(current.green) / \(current.blue)")
                .font(.caption.monospaced()).foregroundStyle(.secondary)
        } header: {
            Text(field.title)
        } footer: {
            Text("色块显示所选颜色；游戏中的光照和人物贴图会影响实际显示效果。")
        }
        Section("常用颜色") {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 58))], spacing: 12) {
                ForEach(presets, id: \.self) { hex in
                    Button {
                        session.draft.appearanceColors[field] = FarmerColor(hex: hex, alpha: current.alpha)
                    } label: {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(FarmerColor(hex: hex)!.swiftUIColor)
                            .frame(height: 48)
                            .overlay { RoundedRectangle(cornerRadius: 10).stroke(.secondary.opacity(0.3)) }
                            .overlay { if current.hex == "#" + hex { Image(systemName: "checkmark.circle.fill").foregroundStyle(.white, .black) } }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("颜色 #\(hex)")
                    .accessibilityIdentifier("editor.appearance.color.preset.\(hex)")
                }
            }
            Button("恢复原始\(field.title)") { session.draft.appearanceColors[field] = original }
                .disabled(current == original)
                .accessibilityIdentifier("editor.appearance.color.restore")
        }
        }
        .onAppear { hexInput = current.hex }
        .onChange(of: current) { _, value in hexInput = value.hex }
    }

    private func colorSample(_ color: FarmerColor, title: String) -> some View {
        VStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 12).fill(color.swiftUIColor).frame(height: 64)
                .overlay { RoundedRectangle(cornerRadius: 12).stroke(.secondary.opacity(0.3)) }
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(color.hex).font(.caption.monospaced())
        }
    }

    private var colorBinding: Binding<Color> {
        Binding(get: { current.swiftUIColor }, set: { color in
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            guard UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a) else { return }
            func byte(_ value: CGFloat) -> Int { Int((min(1, max(0, value)) * 255).rounded()) }
            session.draft.appearanceColors[field] = FarmerColor(red: byte(r), green: byte(g), blue: byte(b), alpha: current.alpha)
        })
    }

    private func applyHex() {
        if let color = FarmerColor(hex: hexInput, alpha: current.alpha) { session.draft.appearanceColors[field] = color }
    }
}

extension FarmerColor {
    var swiftUIColor: Color { Color(red: Double(red) / 255, green: Double(green) / 255, blue: Double(blue) / 255) }
}
