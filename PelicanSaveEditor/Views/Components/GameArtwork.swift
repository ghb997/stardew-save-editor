import SwiftUI
import UIKit

/// All content images are unpainted crops of the bundled game textures.
/// Missing/modded textures have an explicit unknown state, never a guessed substitute.
@MainActor
enum GameArtwork {
    private struct Sprite {
        let id: String
        let name: String
        let type: String
        let asset: String
        let index: Int
        let height: Int
    }
    private static var cache: [String: UIImage] = [:]
    private static let crops: [CropDefinition] = (try? CropCatalog.load()) ?? []
    private static let sprites: [Sprite] = {
        guard let url = Bundle.main.url(forResource: "iteminfo", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let rows = try? JSONSerialization.jsonObject(with: data) as? [[Any]] else { return [] }
        return rows.compactMap { row in
            guard row.count == 2, let value = row[1] as? [String: Any],
                  let id = value["_key"] as? String, let name = value["name"] as? String,
                  let type = value["_type"] as? String else { return nil }
            let texture = (value["texture"] as? String ?? "springobjects.png").lowercased()
            let asset: String
            let height: Int
            switch type {
            case "Object":
                guard texture == "springobjects.png" || texture == "objects_2.png" else { return nil }
                asset = texture == "objects_2.png" ? "GameObjects2" : "GameSpringObjects"
                height = 16
            case "BigCraftable": asset = "GameCraftables"; height = 32
            case "Tool":
                guard texture == "tools.png" else { return nil }
                asset = "GameTools"; height = 16
            default: return nil
            }
            let menuIndex = (value["menuSpriteIndex"] as? Int) ?? -1
            let defaultIndex = (value["spriteIndex"] as? Int) ?? Int(id) ?? -1
            let index = type == "Tool" && menuIndex >= 0 ? menuIndex : defaultIndex
            guard index >= 0 else { return nil }
            return Sprite(id: id, name: name, type: type, asset: asset, index: index, height: height)
        }
    }()

    static func crop(asset: String, rect: CGRect) -> UIImage? {
        let key = "\(asset):\(rect)"
        if let cached = cache[key] { return cached }
        guard rect.minX >= 0, rect.minY >= 0, rect.width > 0, rect.height > 0,
              let source = UIImage(named: asset)?.cgImage,
              rect.maxX <= CGFloat(source.width), rect.maxY <= CGFloat(source.height),
              let cgImage = source.cropping(to: rect) else { return nil }
        let image = UIImage(cgImage: cgImage, scale: 1, orientation: .up)
        cache[key] = image
        return image
    }

    private static func image(_ sprite: Sprite) -> UIImage? {
        guard let source = UIImage(named: sprite.asset)?.cgImage else { return nil }
        let columns = source.width / 16
        guard columns > 0 else { return nil }
        return crop(asset: sprite.asset, rect: CGRect(x: (sprite.index % columns) * 16,
            y: (sprite.index / columns) * sprite.height, width: 16, height: sprite.height))
    }

    static func itemImage(id: String, type: String = "Object") -> UIImage? {
        guard let sprite = sprites.first(where: { $0.id == id && $0.type == type }) else { return nil }
        return image(sprite)
    }
    static func namedItemImage(_ name: String) -> UIImage? {
        guard let sprite = sprites.first(where: { $0.name == name }) else { return nil }
        return image(sprite)
    }
    static func npcPortrait(name: String) -> UIImage? {
        crop(asset: "GamePortrait" + assetSuffix(name), rect: CGRect(x: 0, y: 0, width: 64, height: 64))
    }
    static func buildingImage(type: String) -> UIImage? {
        switch type {
        case "Greenhouse", "温室":
            return crop(asset: "GameBuildingGreenhouse", rect: CGRect(x: 0, y: 160, width: 112, height: 160))
        case "FarmHouse", "农舍":
            return crop(asset: "GameBuildinghouses", rect: CGRect(x: 0, y: 0, width: 160, height: 144))
        case "Barn", "谷仓", "畜棚": return UIImage(named: "GameBuildingBarn")
        case "Coop", "鸡舍": return UIImage(named: "GameBuildingCoop")
        case "Silo", "筒仓": return UIImage(named: "GameBuildingSilo")
        default: return nil
        }
    }
    static func animalImage(type: String) -> UIImage? {
        let normalized = type.lowercased()
        let asset: String
        switch normalized {
        case "white chicken", "白鸡": asset = "WhiteChicken"
        case "brown chicken", "褐鸡", "棕鸡": asset = "BrownChicken"
        case "blue chicken", "蓝鸡": asset = "BlueChicken"
        case "void chicken", "虚空鸡": asset = "VoidChicken"
        case "golden chicken", "金鸡": asset = "GoldenChicken"
        case "white cow", "白牛": asset = "WhiteCow"
        case "brown cow", "褐牛", "棕牛": asset = "BrownCow"
        case "duck", "鸭": asset = "Duck"
        case "goat", "山羊": asset = "Goat"
        case "sheep", "绵羊": asset = "Sheep"
        case "pig", "猪": asset = "Pig"
        case "rabbit", "兔子": asset = "Rabbit"
        case "dinosaur", "恐龙": asset = "Dinosaur"
        case "ostrich", "鸵鸟": asset = "Ostrich"
        default: return nil
        }
        guard let sheet = UIImage(named: "GameAnimal" + asset)?.cgImage else { return nil }
        // Game animal sheets have four animation columns and four facing rows.
        let width = sheet.width / 4
        let height = sheet.height / 4
        return crop(asset: "GameAnimal" + asset, rect: CGRect(x: 0, y: 0, width: width, height: height))
    }

    static func surfaceImage(style: Int, isFlooring: Bool) -> UIImage? {
        guard style >= 0 else { return nil }
        if isFlooring {
            return crop(asset: "GameWallsAndFloors", rect: CGRect(x: (style % 8) * 32,
                y: 336 + (style / 8) * 32, width: 32, height: 32))
        }
        guard style < 112 else { return nil }
        return crop(asset: "GameWallsAndFloors", rect: CGRect(x: (style % 16) * 16,
            y: (style / 16) * 48, width: 16, height: 48))
    }

    static func appearanceImage(category: String, index: Int) -> UIImage? {
        guard index >= 0 else { return nil }
        switch category {
        case "hair":
            guard index <= 73 else { return nil }
            let second = index >= 56
            let local = second ? index - 56 : index
            // Same layout as the reference repository's Character.svelte.
            return crop(asset: second ? "GameHair2" : "GameHair1", rect: CGRect(x: (local % 8) * 16,
                y: (local / 8) * (second ? 128 : 96), width: 16, height: 16))
        case "accessory":
            guard index < 30 else { return nil }
            return crop(asset: "GameAccessories", rect: CGRect(x: (index % 8) * 16,
                y: (index / 8) * 32, width: 16, height: 16))
        case "skin":
            // No original skin palette texture is bundled; show the numeric value.
            return nil
        default: return nil
        }
    }

    static func recipeImage(key: String, kind: RecipeKind) -> UIImage? {
        let aliases = ["Cheese Cauli.": "Cheese Cauliflower", "Vegetable Medley": "Vegetable Medley"]
        let name = aliases[key] ?? key
        let types = kind == .cooking ? ["Object"] : ["Object", "BigCraftable"]
        guard let sprite = sprites.first(where: { $0.name == name && types.contains($0.type) }) else { return nil }
        return image(sprite)
    }

    static func farmEntityImage(_ entity: FarmEntity) -> UIImage? {
        let parts = entity.detail?.components(separatedBy: " · ") ?? []
        switch entity.kind {
        case .animal:
            return animalImage(type: parts.first ?? entity.label)
        case .object:
            // Several objects share display names (e.g. eight House Plants).
            // Use the saved ID and type; a name fallback can show the wrong variant.
            guard let idPart = parts.first(where: { $0.hasPrefix("ID ") }) else { return nil }
            var id = String(idPart.dropFirst(3))
            var type = parts.contains("大型制造物") ? "BigCraftable" : "Object"
            if id.hasPrefix("(BC)") { type = "BigCraftable"; id = String(id.dropFirst(4)) }
            else if id.hasPrefix("(O)") { type = "Object"; id = String(id.dropFirst(3)) }
            return itemImage(id: id, type: type)
        case .crop:
            guard let seedPart = parts.first(where: { $0.hasPrefix("种子 ") }),
                  let definition = crops.first(where: { $0.seedID == String(seedPart.dropFirst(3)) }) else { return nil }
            // The product icon identifies the crop; it is not its growth-stage sprite.
            return itemImage(id: definition.id)
        case .building:
            return buildingImage(type: parts.first ?? entity.label)
        default:
            return nil
        }
    }

    static func uiImage(systemName: String) -> UIImage? {
        let name = systemName.lowercased()
        if name.contains("house") { return buildingImage(type: "FarmHouse") }
        if name.contains("person") { return crop(asset: "GameFarmerBase", rect: CGRect(x: 0, y: 0, width: 16, height: 32)) }
        if name.contains("paw") { return animalImage(type: "White Chicken") }
        if name.contains("drop") { return namedItemImage("Watering Can") }
        if name.contains("hammer") || name.contains("pickaxe") { return namedItemImage("Pickaxe") }
        if name.contains("wrench") || name.contains("gamecontroller") { return namedItemImage("Hoe") }
        if name.contains("scissors") { return namedItemImage("Axe") }
        if name.contains("fish") { return itemImage(id: "128") }
        if name.contains("carrot") || name.contains("leaf") { return itemImage(id: "Carrot") }
        if name.contains("tree") { return itemImage(id: "309") }
        if name.contains("heart") { return itemImage(id: "787") }
        if name.contains("diamond") || name.contains("sparkles") { return itemImage(id: "72") }
        if name.contains("trophy") || name.contains("star") { return itemImage(id: "434") }
        if name.contains("sun") { return itemImage(id: "421") }
        if name.contains("snow") { return itemImage(id: "414") }
        if name.contains("flame") { return itemImage(id: "382") }
        if name.contains("fork") { return itemImage(id: "194") }
        if name.contains("cup") { return itemImage(id: "395") }
        if name.contains("book") || name.contains("list") { return itemImage(id: "102") }
        if name.contains("dollar") || name.contains("banknote") || name.contains("creditcard") { return itemImage(id: "336") }
        if name.contains("mountain") { return itemImage(id: "390") }
        if name.contains("map") { return UIImage(named: "GameSaveSummary") }
        if name.contains("shippingbox") || name.contains("externaldrive") || name.contains("tray") { return namedItemImage("Chest") }
        if name.contains("lock") || name.contains("shield") { return itemImage(id: "74") }
        if name.contains("eyeglasses") || name.contains("eye") { return appearanceImage(category: "accessory", index: 6) }
        if name.contains("paint") { return itemImage(id: "454") }
        if name.contains("gear") { return namedItemImage("Furnace") }
        return itemImage(id: "MysteryBox")
    }

    private static func assetSuffix(_ value: String) -> String {
        value.filter { $0.isASCII && ($0.isLetter || $0.isNumber) }
    }
}

struct GameIcon: View {
    let systemName: String
    var size: CGFloat = 24
    var body: some View {
        Group {
            if let glyph {
                Text(glyph).font(.system(size: size * 0.72, weight: .semibold))
            } else if let image = GameArtwork.uiImage(systemName: systemName) {
                Image(uiImage: image).resizable().interpolation(.none).scaledToFit()
            } else { Text("?").font(.headline) }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
    private var glyph: String? {
        if systemName.contains("checkmark") { return "✓" }
        if systemName.contains("xmark") { return "×" }
        if systemName.contains("chevron.right") { return "›" }
        if systemName.contains("chevron.left") { return "‹" }
        if systemName.contains("arrow.uturn") { return "↶" }
        if systemName.contains("arrow.clockwise") { return "↻" }
        if systemName.contains("arrow.right") { return "→" }
        if systemName.contains("arrow.up") { return "↑" }
        if systemName.contains("plus") && !systemName.contains("externaldrive") { return "+" }
        if systemName.contains("minus") { return "−" }
        if systemName.contains("exclamation") { return "!" }
        return nil
    }
}

struct GameLabel: View {
    let title: String
    let systemImage: String
    init(_ title: String, systemImage: String) { self.title = title; self.systemImage = systemImage }
    var body: some View { Label { Text(title) } icon: { GameIcon(systemName: systemImage, size: 20) } }
}

struct GameAnimalPortrait: View {
    let type: String
    var size: CGFloat = 40
    var body: some View {
        Group {
            if let image = GameArtwork.animalImage(type: type) {
                Image(uiImage: image).resizable().interpolation(.none).scaledToFit()
            } else {
                Text("无预览")
                    .font(.system(size: max(9, min(12, size / 4))))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }.frame(width: size, height: size)
            .accessibilityLabel(GameArtwork.animalImage(type: type) == nil ? "\(type)，无贴图预览" : type)
    }
}

struct GameNPCPortrait: View {
    let name: String
    var size: CGFloat = 48
    var body: some View {
        Group {
            if let image = GameArtwork.npcPortrait(name: name) {
                Image(uiImage: image).resizable().interpolation(.none).scaledToFit()
            } else { Text("无预览").font(.caption2).foregroundStyle(.secondary) }
        }.frame(width: size, height: size).accessibilityHidden(true)
    }
}
