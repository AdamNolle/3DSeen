import Foundation

public enum PLYPayloadKind: Sendable {
    case geometry
    case trainedSplat
}

/// Structural validation for PLY files crossing the device trust boundary. Geometry previews may
/// be ASCII or binary little-endian; trained splats must use finite float32 Gaussian properties.
public enum PLYValidator {
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

    public static func isValid(_ url: URL, kind: PLYPayloadKind) -> Bool {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe),
              let header = parseHeader(data),
              header.vertexCount > 0 else { return false }
        let properties = Dictionary(uniqueKeysWithValues: header.properties.map { ($0.name, $0) })
        guard Set(["x", "y", "z"]).isSubset(of: Set(properties.keys)) else { return false }

        switch kind {
        case .geometry:
            return validateGeometry(data, header: header, properties: properties)
        case .trainedSplat:
            return validateTrainedSplat(data, header: header, properties: properties)
        }
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
        let format = formatLine.split(separator: " ").dropFirst().first.map(String.init) ?? ""
        guard format == "ascii" || format == "binary_little_endian" else { return nil }

        var vertexCount: Int?
        var parsingVertex = false
        var properties: [Property] = []
        var stride = 0
        for line in lines {
            let parts = line.split(separator: " ").map(String.init)
            if parts.count == 3, parts[0] == "element" {
                parsingVertex = parts[1] == "vertex"
                if parsingVertex { vertexCount = Int(parts[2]) }
                continue
            }
            guard parsingVertex, parts.first == "property" else { continue }
            guard parts.count == 3, let size = scalarSizes[parts[1]] else { return nil }
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
        header: Header,
        properties: [String: Property]
    ) -> Bool {
        if header.format == "ascii" {
            guard let payload = String(data: data[header.payloadOffset...], encoding: .ascii) else { return false }
            let rows = payload.split(whereSeparator: \.isNewline)
            guard rows.count >= header.vertexCount else { return false }
            let indices = Dictionary(uniqueKeysWithValues: header.properties.enumerated().map { ($0.element.name, $0.offset) })
            guard let x = indices["x"], let y = indices["y"], let z = indices["z"] else { return false }
            return sampledIndices(count: header.vertexCount).allSatisfy { index in
                let values = rows[index].split(whereSeparator: \.isWhitespace)
                guard max(x, y, z) < values.count,
                      let vx = Double(values[x]), let vy = Double(values[y]), let vz = Double(values[z]) else {
                    return false
                }
                return vx.isFinite && vy.isFinite && vz.isFinite
            }
        }
        guard header.vertexStride > 0,
              data.count >= header.payloadOffset + header.vertexCount * header.vertexStride else { return false }
        return sampledIndices(count: header.vertexCount).allSatisfy { vertex in
            ["x", "y", "z"].allSatisfy { name in
                guard let property = properties[name] else { return false }
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
              required.allSatisfy({ properties[$0]?.size == 4 }),
              header.vertexStride > 0,
              data.count >= header.payloadOffset + header.vertexCount * header.vertexStride else { return false }
        return sampledIndices(count: header.vertexCount).allSatisfy { vertex in
            required.allSatisfy { name in
                guard let property = properties[name] else { return false }
                return finiteScalar(
                    data,
                    offset: header.payloadOffset + vertex * header.vertexStride + property.offset,
                    property: property
                )
            }
        }
    }

    private static func sampledIndices(count: Int) -> [Int] {
        count <= 1_024 ? Array(0..<count) : [0, count / 2, count - 1]
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
