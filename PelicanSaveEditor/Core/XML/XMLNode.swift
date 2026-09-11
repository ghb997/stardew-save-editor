import Foundation

/// A deliberately small XML tree that keeps every element and attribute from a
/// Stardew save while discarding formatting-only whitespace.
final class XMLNode {
    let name: String
    var attributes: [String: String]
    var text: String
    var children: [XMLNode]

    init(
        name: String,
        attributes: [String: String] = [:],
        text: String = "",
        children: [XMLNode] = []
    ) {
        self.name = name
        self.attributes = attributes
        self.text = text
        self.children = children
    }

    func child(named name: String) -> XMLNode? {
        children.first { $0.name == name }
    }

    func children(named name: String) -> [XMLNode] {
        children.filter { $0.name == name }
    }

    func value(named name: String) -> String? {
        child(named: name)?.text
    }

    func int(named name: String) -> Int? {
        value(named: name).flatMap(Int.init)
    }

    @discardableResult
    func setValue(_ value: String, named name: String, createIfMissing: Bool = false) -> Bool {
        if let existing = child(named: name) {
            existing.text = value
            existing.children.removeAll()
            return true
        }
        guard createIfMissing else { return false }
        children.append(XMLNode(name: name, text: value))
        return true
    }

    func deepCopy() -> XMLNode {
        XMLNode(
            name: name,
            attributes: attributes,
            text: text,
            children: children.map { $0.deepCopy() }
        )
    }

    /// Preorder traversal excluding self, without constructing a flattened copy
    /// of every subtree. Callers may stop as soon as the required node is found.
    var descendants: Descendants { Descendants(children: children) }

    struct Descendants: Sequence {
        let children: [XMLNode]

        func makeIterator() -> Iterator { Iterator(pending: Array(children.reversed())) }

        struct Iterator: IteratorProtocol {
            var pending: [XMLNode]

            mutating func next() -> XMLNode? {
                guard let node = pending.popLast() else { return nil }
                pending.append(contentsOf: node.children.reversed())
                return node
            }
        }
    }

    func firstDescendant(named name: String) -> XMLNode? {
        if self.name == name { return self }
        for child in children {
            if let match = child.firstDescendant(named: name) { return match }
        }
        return nil
    }

    func xmlString(includeDeclaration: Bool = false) -> String {
        var output = ""
        if includeDeclaration {
            output = "<?xml version=\"1.0\" encoding=\"utf-8\"?>"
        }
        appendXML(to: &output)
        return output
    }

    private func appendXML(to output: inout String) {
        output.append("<")
        output.append(name)
        for key in attributes.keys.sorted() {
            guard let value = attributes[key] else { continue }
            output.append(" ")
            output.append(key)
            output.append("=\"")
            output.append(Self.escapeAttribute(value))
            output.append("\"")
        }

        if children.isEmpty, text.isEmpty {
            output.append("/>")
            return
        }

        output.append(">")
        if children.isEmpty {
            output.append(Self.escapeText(text))
        } else {
            for child in children {
                child.appendXML(to: &output)
            }
        }
        output.append("</")
        output.append(name)
        output.append(">")
    }

    private static func escapeText(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    private static func escapeAttribute(_ text: String) -> String {
        escapeText(text)
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
            .replacingOccurrences(of: "\n", with: "&#10;")
            .replacingOccurrences(of: "\r", with: "&#13;")
            .replacingOccurrences(of: "\t", with: "&#9;")
    }
}
