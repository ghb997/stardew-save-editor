import Foundation

enum XMLTreeError: LocalizedError {
    case emptyDocument
    case malformed(String)

    var errorDescription: String? {
        switch self {
        case .emptyDocument:
            "XML 文件为空。"
        case let .malformed(message):
            "存档不是有效的 XML：\(message)"
        }
    }
}

final class XMLTreeParser: NSObject, XMLParserDelegate {
    private var stack: [XMLNode] = []
    private var root: XMLNode?
    private var parserError: Error?

    func parse(_ data: Data) throws -> XMLNode {
        stack.removeAll(keepingCapacity: true)
        root = nil
        parserError = nil

        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.shouldProcessNamespaces = false
        parser.shouldReportNamespacePrefixes = false
        parser.shouldResolveExternalEntities = false

        guard parser.parse() else {
            let message = parserError?.localizedDescription
                ?? parser.parserError?.localizedDescription
                ?? "未知解析错误"
            throw XMLTreeError.malformed(message)
        }
        guard let root else { throw XMLTreeError.emptyDocument }
        return root
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        let node = XMLNode(
            name: qName ?? elementName,
            attributes: attributeDict
        )
        if let parent = stack.last {
            parent.children.append(node)
        } else {
            root = node
        }
        stack.append(node)
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        stack.last?.text.append(string)
    }

    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        guard let string = String(data: CDATABlock, encoding: .utf8) else { return }
        stack.last?.text.append(string)
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        guard let node = stack.popLast() else { return }
        if !node.children.isEmpty,
           node.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            node.text = ""
        }
    }

    func parser(_ parser: XMLParser, parseErrorOccurred parseError: Error) {
        parserError = parseError
    }
}

