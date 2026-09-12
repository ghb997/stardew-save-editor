import Foundation

enum RecipeWriteRules {
    static func extract(player: XMLNode, catalog: [RecipeKind: [String]]) -> [RecipeDraft] {
        RecipeKind.allCases.flatMap { kind -> [RecipeDraft] in
            let containers = player.children(named: kind.containerName)
            let container = containers.first
            let contents = container.map(dictionaryContainer)
            let entries = contents?.children(named: "item") ?? []
            let grouped = Dictionary(grouping: entries, by: { entryKey($0) ?? "" })
            let known = Set(catalog[kind] ?? [])
            let keys = known.union(grouped.keys.filter { !$0.isEmpty }).sorted()
            let usableContainer = containers.count <= 1 && (container.map(validContainer) ?? true)
                && (contents.map { validContainer($0) && $0.children.count == entries.count } ?? true)
                && grouped[""] == nil
            return keys.map { key in
                let matches = grouped[key] ?? []
                let count = matches.count == 1 ? entryCount(matches[0]) : nil
                let unlocked = !matches.isEmpty
                return RecipeDraft(key: key, kind: kind, unlocked: unlocked, timesMade: count ?? 0,
                    originallyUnlocked: unlocked, originalTimesMade: count ?? 0,
                    isEditable: usableContainer && known.contains(key)
                        && (matches.isEmpty || (matches.count == 1 && count.map { (0...Int(Int32.max)).contains($0) } == true)))
            }
        }
    }

    static func validate(_ recipes: [RecipeDraft], original: [RecipeDraft]) throws {
        guard recipes.map(\.id) == original.map(\.id) else {
            throw SaveValidationError.invalid("配方范围已改变，请重新读取存档。")
        }
        for (recipe, old) in zip(recipes, original) where recipe != old {
            guard old.isEditable, recipe.isEditable == old.isEditable,
                  recipe.originallyUnlocked == old.originallyUnlocked, recipe.originalTimesMade == old.originalTimesMade,
                  (0...Int(Int32.max)).contains(recipe.timesMade) else {
                throw SaveValidationError.invalid("配方记录重复、计数无效或来自未知扩展，不能修改。")
            }
        }
    }

    static func apply(_ recipes: [RecipeDraft], original: [RecipeDraft], to player: XMLNode) {
        for kind in RecipeKind.allCases {
            let changed = zip(recipes, original).filter { $0.0.kind == kind && $0.0 != $0.1 }
            guard !changed.isEmpty else { continue }
            let container: XMLNode
            if let existing = player.child(named: kind.containerName) { container = dictionaryContainer(existing) }
            else {
                container = XMLNode(name: kind.containerName)
                player.children.append(container)
            }
            for (recipe, old) in changed {
                let index = container.children.firstIndex {
                    $0.name == "item" && entryKey($0) == recipe.key
                }
                if !recipe.unlocked {
                    if let index { container.children.remove(at: index) }
                } else if let index {
                    if recipe.timesMade != old.timesMade {
                        container.children[index].child(named: "value")?.setValue(String(recipe.timesMade), named: "int")
                    }
                } else {
                    container.children.append(XMLNode(name: "item", children: [
                        XMLNode(name: "key", children: [XMLNode(name: "string", text: recipe.key)]),
                        XMLNode(name: "value", children: [XMLNode(name: "int", text: String(recipe.timesMade))])
                    ]))
                }
            }
        }
    }

    private static func validContainer(_ node: XMLNode) -> Bool {
        ExistingSaveValue.bool(node.attributes["xsi:nil"] ?? node.attributes["nil"]) != true
            && node.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    private static func dictionaryContainer(_ node: XMLNode) -> XMLNode {
        if node.children.count == 1, let wrapper = node.children.first,
           wrapper.name.hasPrefix("SerializableDictionary") { return wrapper }
        return node
    }
    private static func entryKey(_ node: XMLNode) -> String? {
        guard validContainer(node), node.children(named: "key").count == 1,
              let key = node.child(named: "key"), validContainer(key), key.children.count == 1,
              let value = ExistingSaveValue.field("string", in: key), !value.isEmpty else { return nil }
        return value
    }
    private static func entryCount(_ node: XMLNode) -> Int? {
        guard node.children(named: "value").count == 1, let value = node.child(named: "value"),
              validContainer(value), value.children.count == 1 else { return nil }
        return ExistingSaveValue.field("int", in: value).flatMap(Int.init)
    }
}
