import Foundation
import zlib

enum SaveEncoding: String, Codable, Sendable {
    case plainXML
    case zlib

    var displayName: String {
        switch self {
        case .plainXML: "普通 XML"
        case .zlib: "zlib 压缩"
        }
    }
}

struct DecodedSave: Sendable {
    let xmlData: Data
    let encoding: SaveEncoding
    let hadUTF8BOM: Bool
}

enum SaveCodecError: LocalizedError {
    case unsupportedData
    case compressionFailed
    case decompressionFailed

    var errorDescription: String? {
        switch self {
        case .unsupportedData:
            "文件既不是普通 XML，也不是受支持的 zlib 存档。"
        case .compressionFailed:
            "压缩存档失败。"
        case .decompressionFailed:
            "解压存档失败，文件可能已损坏。"
        }
    }
}

enum SaveCodec {
    private static let utf8BOM = Data([0xEF, 0xBB, 0xBF])

    static func decode(_ data: Data) throws -> DecodedSave {
        if looksLikeXML(data) {
            let hasBOM = data.starts(with: utf8BOM)
            return DecodedSave(
                xmlData: hasBOM ? data.dropFirst(3) : data,
                encoding: .plainXML,
                hadUTF8BOM: hasBOM
            )
        }

        if let inflated = try? decompressZlib(data),
           looksLikeXML(inflated) {
            let hasBOM = inflated.starts(with: utf8BOM)
            return DecodedSave(
                xmlData: hasBOM ? inflated.dropFirst(3) : inflated,
                encoding: .zlib,
                hadUTF8BOM: hasBOM
            )
        }
        throw SaveCodecError.unsupportedData
    }

    static func encode(xmlData: Data, encoding: SaveEncoding, includeBOM: Bool) throws -> Data {
        var source = Data()
        if includeBOM { source.append(utf8BOM) }
        source.append(xmlData)

        switch encoding {
        case .plainXML:
            return source
        case .zlib:
            do {
                return try compressZlib(source)
            } catch {
                throw SaveCodecError.compressionFailed
            }
        }
    }

    private static func looksLikeXML(_ data: Data) -> Bool {
        // XML's opening delimiter and whitespace are ASCII. Inspect bytes so a
        // multibyte character crossing an arbitrary prefix boundary cannot make
        // a valid UTF-8 save look like compressed or unsupported data.
        let bytes = data.starts(with: utf8BOM) ? data.dropFirst(3) : data[...]
        let whitespace: Set<UInt8> = [0x09, 0x0A, 0x0D, 0x20]
        return bytes.first(where: { !whitespace.contains($0) }) == 0x3C
    }

    private static func compressZlib(_ data: Data) throws -> Data {
        guard !data.isEmpty else { throw SaveCodecError.compressionFailed }

        let sourceLength = uLong(data.count)
        var destinationLength = uLongf(compressBound(sourceLength))
        var destination = Data(count: Int(destinationLength))
        let status = data.withUnsafeBytes { sourceBuffer in
            destination.withUnsafeMutableBytes { destinationBuffer in
                compress2(
                    destinationBuffer.bindMemory(to: Bytef.self).baseAddress,
                    &destinationLength,
                    sourceBuffer.bindMemory(to: Bytef.self).baseAddress,
                    sourceLength,
                    Z_DEFAULT_COMPRESSION
                )
            }
        }
        guard status == Z_OK else { throw SaveCodecError.compressionFailed }
        destination.count = Int(destinationLength)
        return destination
    }

    private static func decompressZlib(_ data: Data) throws -> Data {
        guard !data.isEmpty else { throw SaveCodecError.decompressionFailed }

        // Stardew's compressed saves contain a regular RFC 1950 zlib stream.
        // Grow the destination conservatively and cap it to avoid decompression bombs.
        let maximumSize = 256 * 1024 * 1024
        guard data.count <= maximumSize else { throw SaveCodecError.decompressionFailed }
        let scaledSize = data.count.multipliedReportingOverflow(by: 4)
        let initialSize = scaledSize.overflow ? maximumSize : scaledSize.partialValue
        var capacity = min(max(initialSize, 64 * 1024), maximumSize)

        while capacity <= maximumSize {
            var destination = Data(count: capacity)
            var destinationLength = uLongf(capacity)
            let status = data.withUnsafeBytes { sourceBuffer in
                destination.withUnsafeMutableBytes { destinationBuffer in
                    uncompress(
                        destinationBuffer.bindMemory(to: Bytef.self).baseAddress,
                        &destinationLength,
                        sourceBuffer.bindMemory(to: Bytef.self).baseAddress,
                        uLong(data.count)
                    )
                }
            }

            if status == Z_OK {
                destination.count = Int(destinationLength)
                return destination
            }
            guard status == Z_BUF_ERROR, capacity < maximumSize else {
                throw SaveCodecError.decompressionFailed
            }
            capacity = min(capacity * 2, maximumSize)
        }

        throw SaveCodecError.decompressionFailed
    }
}
