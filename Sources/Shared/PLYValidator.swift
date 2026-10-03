import Foundation

public enum PLYPayloadKind: Sendable {
    case geometry
    case trainedSplat
}

/// Structural validation for PLY files crossing the device trust boundary. Geometry previews may
/// be ASCII or binary little-endian; trained splats must use finite float32 Gaussian properties.
public enum PLYValidator {
    public static let maximumVertexCount = 500_000
    public static let maximumFileByteCount: Int64 = 128 * 1_024 * 1_024
    private static let maximumASCIIVertexRowBytes = 1_048_576

    private struct Property {
        let type: String
        let name: String
        let offset: Int
        let size: Int
    }

    private struct Header {
        let format: String
        let vertexCount: Int
        let properties: [Property]
        let payloadOffset: Int
        let vertexStride: Int
    }

    private static let scalarSizes = [
        "char": 1, "uchar": 1, "int8": 1, "uint8": 1,
        "short": 2, "ushort": 2, "int16": 2, "uint16": 2,
        "int": 4, "uint": 4, "int32": 4, "uint32": 4, "float": 4, "float32": 4,
        "double": 8, "float64": 8,
    ]

    /// Checks the allocation bounds used by the splat viewer before handing a PLY file to
    /// MetalSplatter, whose reader trusts the vertex count in the header.
    public static func isWithinImportLimits(_ url: URL) -> Bool {
        guard let data = boundedData(at: url),
              let header = parseHeader(data),
              header.vertexCount <= maximumVertexCount,
              header.vertexStride > 0,
              header.payloadOffset <= data.count else { return false }
        if header.format == "ascii" { return true }
        return header.vertexCount <= (data.count - header.payloadOffset) / header.vertexStride
    }

    public static func isValid(_ url: URL, kind: PLYPayloadKind) -> Bool {
        guard let data = boundedData(at: url),
              let header = parseHeader(data),
              header.vertexCount > 0,
              header.vertexCount <= maximumVertexCount else { return false }
        let properties = Dictionary(uniqueKeysWithValues: header.properties.map { ($0.name, $0) })
        guard Set(["x", "y", "z"]).isSubset(of: Set(properties.keys)) else { return false }

        switch kind {
        case .geometry:
            return validateGeometry(data, header: header)
        case .trainedSplat:
            return validateTrainedSplat(data, header: header, properties: properties)
        }
    }

    private static func boundedData(at url: URL) -> Data? {
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey]),
              let fileSize = values.fileSize,
              fileSize > 0,
              Int64(fileSize) <= maximumFileByteCount,
              let data = try? Data(contentsOf: url, options: .mappedIfSafe),
              Int64(data.count) <= maximumFileByteCount else { return nil }
        return data
    }

    private static func parseHeader(_ data: Data) -> Header? {
        let lf = Data("end_header\n".utf8)
        let crlf = Data("end_header\r\n".utf8)
        guard let range = data.range(of: lf) ?? data.range(of: crlf),
              range.upperBound <= 1_048_576,
              let text = String(data: data[..<range.upperBound], encoding: .ascii) else { return nil }
        let lines = text.components(separatedBy: .newlines)
        guard lines.first?.trimmingCharacters(in: .whitespacesAndNewlines) == "ply",
              let formatLine = lines.first(where: { $0.hasPrefix("format ") }) else { return nil }
        let formatParts = formatLine.split(separator: " ")
        guard formatParts.count == 3, formatParts[2] == "1.0" else { return nil }
        let format = String(formatParts[1])
        guard format == "ascii" || format == "binary_little_endian" else { return nil }

        var vertexCount: Int?
        var parsingVertex = false
        var properties: [Property] = []
        var stride = 0
        for line in lines {
            let parts = line.split(separator: " ").map(String.init)
            if parts.count == 3, parts[0] == "element" {
                parsingVertex = parts[1] == "vertex"
                if parsingVertex {
                    guard vertexCount == nil, properties.isEmpty,
                          lines.first(where: { $0.hasPrefix("element ") }) == line else { return nil }
                    vertexCount = Int(parts[2])
                }
                continue
            }
            guard parsingVertex, parts.first == "property" else { continue }
            guard parts.count == 3, let size = scalarSizes[parts[1]],
                  !properties.contains(where: { $0.name == parts[2] }) else { return nil }
            properties.append(Property(type: parts[1], name: parts[2], offset: stride, size: size))
            stride += size
        }
        guard let vertexCount, vertexCount > 0, !properties.isEmpty else { return nil }
        return Header(
            format: format,
            vertexCount: vertexCount,
            properties: properties,
            payloadOffset: range.upperBound,
            vertexStride: stride
        )
    }

    private static func validateGeometry(
        _ data: Data,
        header: Header
    ) -> Bool {
        if header.format == "ascii" {
            let indices = Dictionary(uniqueKeysWithValues: header.properties.enumerated().map { ($0.element.name, $0.offset) })
            guard let x = indices["x"], let y = indices["y"], let z = indices["z"] else { return false }
            var cursor = header.payloadOffset
            for _ in 0..<header.vertexCount {
                while cursor < data.count, data[cursor] == 10 || data[cursor] == 13 { cursor += 1 }
                guard cursor < data.count else { return false }
                let rowStart = cursor
                while cursor < data.count, data[cursor] != 10, data[cursor] != 13 { cursor += 1 }
                guard cursor - rowStart <= maximumASCIIVertexRowBytes,
                      let row = String(data: data[rowStart..<cursor], encoding: .ascii) else { return false }
                let values = row.split(whereSeparator: \.isWhitespace)
                guard values.count == header.properties.count, max(x, y, z) < values.count,
                      let vx = Double(values[x]), let vy = Double(values[y]), let vz = Double(values[z]) else {
                    return false
                }
                guard vx.isFinite, vy.isFinite, vz.isFinite,
                      values.allSatisfy({ Double($0)?.isFinite == true }) else { return false }
            }
            return true
        }
        guard header.vertexStride > 0,
              header.vertexCount <= (data.count - header.payloadOffset) / header.vertexStride else { return false }
        return (0..<header.vertexCount).allSatisfy { vertex in
            header.properties.allSatisfy { property in
                return finiteScalar(
                    data,
                    offset: header.payloadOffset + vertex * header.vertexStride + property.offset,
                    property: property
                )
            }
        }
    }

    private static func validateTrainedSplat(
        _ data: Data,
        header: Header,
        properties: [String: Property]
    ) -> Bool {
        let required = Set([
            "x", "y", "z", "f_dc_0", "f_dc_1", "f_dc_2",
            "opacity", "scale_0", "scale_1", "scale_2",
            "rot_0", "rot_1", "rot_2", "rot_3",
        ])
        guard header.format == "binary_little_endian",
              required.isSubset(of: Set(properties.keys)),
              required.allSatisfy({ properties[$0]?.type == "float" || properties[$0]?.type == "float32" }),
              header.vertexStride > 0,
              header.vertexCount <= (data.count - header.payloadOffset) / header.vertexStride else { return false }
        return (0..<header.vertexCount).allSatisfy { vertex in
            header.properties.allSatisfy { property in
                return finiteScalar(
                    data,
                    offset: header.payloadOffset + vertex * header.vertexStride + property.offset,
                    property: property
                )
            }
        }
    }

    private static func finiteScalar(_ data: Data, offset: Int, property: Property) -> Bool {
        guard offset >= 0, offset + property.size <= data.count else { return false }
        switch property.type {
        case "float", "float32":
            let bits = UInt32(data[offset])
                | UInt32(data[offset + 1]) << 8
                | UInt32(data[offset + 2]) << 16
                | UInt32(data[offset + 3]) << 24
            return Float(bitPattern: bits).isFinite
        case "double", "float64":
            var bits = UInt64(0)
            for index in 0..<8 { bits |= UInt64(data[offset + index]) << UInt64(index * 8) }
            return Double(bitPattern: bits).isFinite
        default:
            return true
        }
    }
}
