import Foundation

enum FarmerColorField: String, CaseIterable, Identifiable, Sendable {
    case hair = "hairstyleColor", eyes = "eyeColor", pants = "pantsColor"
    var id: String { rawValue }
    var title: String {
        switch self {
        case .hair: "发色"
        case .eyes: "眼睛颜色"
        case .pants: "裤子颜色"
        }
    }
}

struct FarmerColor: Equatable, Sendable {
    var red: Int
    var green: Int
    var blue: Int
    var alpha: Int = 255

    var isValid: Bool { [red, green, blue, alpha].allSatisfy { (0...255).contains($0) } }
    var hex: String { String(format: "#%02X%02X%02X", red, green, blue) }
    var packed: UInt32 { UInt32(red) | UInt32(green) << 8 | UInt32(blue) << 16 | UInt32(alpha) << 24 }

    init(red: Int, green: Int, blue: Int, alpha: Int = 255) {
        self.red = red; self.green = green; self.blue = blue; self.alpha = alpha
    }

    init?(hex: String, alpha: Int = 255) {
        let text = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        let digits = text.hasPrefix("#") ? String(text.dropFirst()) : text
        guard digits.utf8.count == 6,
              digits.utf8.allSatisfy({ (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0) }),
              let value = UInt32(digits, radix: 16), (0...255).contains(alpha) else { return nil }
        self.init(red: Int(value >> 16), green: Int((value >> 8) & 255), blue: Int(value & 255), alpha: alpha)
    }

    init(packed: UInt32) {
        self.init(red: Int(packed & 255), green: Int((packed >> 8) & 255),
                  blue: Int((packed >> 16) & 255), alpha: Int(packed >> 24))
    }
}

enum AppearanceColorCodec {
    static func scalar(_ node: XMLNode?) -> String? {
        guard let node, node.children.isEmpty,
              !["true", "1"].contains(node.attributes["xsi:nil"] ?? node.attributes["nil"] ?? "") else { return nil }
        return node.text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func read(_ field: FarmerColorField, from player: XMLNode) -> FarmerColor? {
        guard player.children(named: field.rawValue).count == 1,
              let node = player.child(named: field.rawValue),
              !["true", "1"].contains(node.attributes["xsi:nil"] ?? node.attributes["nil"] ?? "") else { return nil }
        let channels = ["R", "G", "B", "A"]
        let hasChannels = channels.contains { node.child(named: $0) != nil }
        var color: FarmerColor?
        if hasChannels {
            let values = channels.compactMap { name -> Int? in
                guard node.children(named: name).count == 1 else { return nil }
                return scalar(node.child(named: name)).flatMap(Int.init)
            }
            guard values.count == 4, values.allSatisfy({ (0...255).contains($0) }) else { return nil }
            color = FarmerColor(red: values[0], green: values[1], blue: values[2], alpha: values[3])
        }
        if node.child(named: "PackedValue") != nil {
            guard node.children(named: "PackedValue").count == 1,
                  let packed = scalar(node.child(named: "PackedValue")).flatMap(UInt32.init),
                  color == nil || color?.packed == packed else { return nil }
            color = FarmerColor(packed: packed)
        }
        return color
    }

    static func apply(_ colors: [FarmerColorField: FarmerColor], original: [FarmerColorField: FarmerColor],
                      to player: XMLNode) {
        for field in FarmerColorField.allCases {
            guard var color = colors[field], color != original[field],
                  let existing = read(field, from: player), let node = player.child(named: field.rawValue) else { continue }
            color.alpha = existing.alpha
            for (name, value) in [("R", color.red), ("G", color.green), ("B", color.blue)] {
                if let channel = node.child(named: name), Int(channel.text) != value { channel.text = String(value) }
            }
            if let packed = node.child(named: "PackedValue") { packed.text = String(color.packed) }
        }
    }
}
