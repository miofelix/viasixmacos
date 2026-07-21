import Foundation
import Yams

enum MihomoYAML {
    private static let maximumBytes = 8 * 1_024 * 1_024
    private static let maximumDepth = 64
    private static let maximumNodes = 200_000

    static func mapping(from data: Data) throws -> [String: Any] {
        guard data.count <= maximumBytes else {
            throw MihomoConfigurationError.configurationTooLarge(data.count)
        }
        guard let source = String(data: data, encoding: .utf8) else {
            throw MihomoConfigurationError.invalidUTF8
        }

        do {
            // Keep the parser alive while traversing the composed tree. Yams stores
            // anchors weakly on nodes, so the convenience `compose` function would
            // release their owner before `normalize` can reject them.
            let parser = try Parser(yaml: source)
            guard let root = try parser.singleRoot() else { return [:] }
            return try withExtendedLifetime(parser) {
                var remainingNodes = maximumNodes
                guard
                    let mapping = try normalize(
                        root,
                        depth: 0,
                        remainingNodes: &remainingNodes
                    ) as? [String: Any]
                else {
                    throw MihomoConfigurationError.topLevelMustBeMapping
                }
                return mapping
            }
        } catch let error as MihomoConfigurationError {
            throw error
        } catch {
            throw MihomoConfigurationError.invalidYAML(error.localizedDescription)
        }
    }

    static func data(from mapping: [String: Any], header: String? = nil) throws -> Data {
        let output: String
        do {
            output = try Yams.dump(object: mapping, allowUnicode: true, sortKeys: false)
        } catch {
            throw MihomoConfigurationError.invalidYAML(error.localizedDescription)
        }
        let normalized = output.hasSuffix("\n") ? output : output + "\n"
        let source = header.map { "# \($0)\n" + normalized } ?? normalized
        guard let data = source.data(using: .utf8) else {
            throw MihomoConfigurationError.invalidUTF8
        }
        guard data.count <= maximumBytes else {
            throw MihomoConfigurationError.configurationTooLarge(data.count)
        }
        return data
    }

    private static func normalize(
        _ node: Node,
        depth: Int,
        remainingNodes: inout Int
    ) throws -> Any {
        guard node.anchor == nil else {
            throw MihomoConfigurationError.unsupportedValue("YAML anchor 或 alias")
        }
        guard depth <= maximumDepth else {
            throw MihomoConfigurationError.configurationTooDeep
        }
        remainingNodes -= 1
        guard remainingNodes >= 0 else {
            throw MihomoConfigurationError.configurationTooComplex
        }
        switch node {
        case .mapping(let mapping):
            var normalized: [String: Any] = [:]
            normalized.reserveCapacity(mapping.count)
            for (keyNode, child) in mapping {
                guard
                    let key = try normalize(
                        keyNode,
                        depth: depth + 1,
                        remainingNodes: &remainingNodes
                    ) as? String,
                    keyNode.tag.rawValue == Tag.Name.str.rawValue
                else {
                    throw MihomoConfigurationError.nonStringMappingKey
                }
                normalized[key] = try normalize(
                    child,
                    depth: depth + 1,
                    remainingNodes: &remainingNodes
                )
            }
            return normalized
        case .sequence(let sequence):
            var normalized: [Any] = []
            normalized.reserveCapacity(sequence.count)
            for child in sequence {
                normalized.append(
                    try normalize(
                        child,
                        depth: depth + 1,
                        remainingNodes: &remainingNodes
                    )
                )
            }
            return normalized
        case .scalar(let scalar):
            switch node.tag.rawValue {
            case Tag.Name.str.rawValue:
                return scalar.string
            case Tag.Name.bool.rawValue:
                guard let value = node.bool else {
                    throw MihomoConfigurationError.unsupportedValue(scalar.string)
                }
                return value
            case Tag.Name.int.rawValue:
                guard let value = node.int else {
                    throw MihomoConfigurationError.unsupportedValue(scalar.string)
                }
                return value
            case Tag.Name.float.rawValue:
                guard let value = node.float, value.isFinite else {
                    throw MihomoConfigurationError.unsupportedValue(scalar.string)
                }
                return value
            case Tag.Name.null.rawValue:
                return NSNull()
            default:
                throw MihomoConfigurationError.unsupportedValue(node.tag.rawValue)
            }
        case .alias:
            throw MihomoConfigurationError.unsupportedValue("YAML alias")
        }
    }
}

extension Dictionary where Key == String, Value == Any {
    func string(_ key: String) -> String? {
        self[key] as? String
    }

    func bool(_ key: String) -> Bool? {
        if let value = self[key] as? Bool { return value }
        if let value = self[key] as? NSNumber { return value.boolValue }
        if let value = self[key] as? String {
            switch value.lowercased() {
            case "true", "yes", "1": return true
            case "false", "no", "0": return false
            default: return nil
            }
        }
        return nil
    }

    func int(_ key: String) -> Int? {
        if let value = self[key] as? Int { return value }
        if let value = self[key] as? NSNumber { return value.intValue }
        if let value = self[key] as? String { return Int(value) }
        return nil
    }

    func mapping(_ key: String) -> [String: Any]? {
        self[key] as? [String: Any]
    }

    func mappings(_ key: String) -> [[String: Any]]? {
        self[key] as? [[String: Any]]
    }
}
