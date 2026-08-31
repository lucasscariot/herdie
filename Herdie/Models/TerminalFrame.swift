import Foundation

enum TerminalColor: Equatable, Sendable {
    case `default`
    case indexed(index: UInt8)
    case rgb(red: UInt8, green: UInt8, blue: UInt8)
}

extension TerminalColor: Codable {
    private enum CodingKeys: String, CodingKey {
        case kind
        case index
        case red
        case green
        case blue
    }

    private enum Kind: String, Codable {
        case `default`
        case indexed
        case rgb
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .default:
            self = .default
        case .indexed:
            self = .indexed(index: try container.decode(UInt8.self, forKey: .index))
        case .rgb:
            self = .rgb(
                red: try container.decode(UInt8.self, forKey: .red),
                green: try container.decode(UInt8.self, forKey: .green),
                blue: try container.decode(UInt8.self, forKey: .blue)
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .default:
            try container.encode(Kind.default, forKey: .kind)
        case let .indexed(index):
            try container.encode(Kind.indexed, forKey: .kind)
            try container.encode(index, forKey: .index)
        case let .rgb(red, green, blue):
            try container.encode(Kind.rgb, forKey: .kind)
            try container.encode(red, forKey: .red)
            try container.encode(green, forKey: .green)
            try container.encode(blue, forKey: .blue)
        }
    }
}

struct TerminalCell: Codable, Equatable, Sendable {
    var row: UInt16
    var column: UInt16
    var contents: String
    var foreground: TerminalColor
    var background: TerminalColor
    var bold: Bool
    var italic: Bool
    var underline: Bool
    var inverse: Bool
}

struct TerminalCursor: Codable, Equatable, Sendable {
    var row: UInt16
    var column: UInt16
    var visible: Bool
}

struct TerminalFrame: Codable, Equatable, Sendable {
    var columns: UInt16
    var rows: UInt16
    var scrollbackOffset: UInt32
    var cursor: TerminalCursor
    var cells: [TerminalCell]
    var text: String

    static let empty = TerminalFrame(
        columns: 80,
        rows: 24,
        scrollbackOffset: 0,
        cursor: TerminalCursor(row: 0, column: 0, visible: false),
        cells: [],
        text: ""
    )

    static func decode(_ json: String) throws -> TerminalFrame {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(TerminalFrame.self, from: Data(json.utf8))
    }
}
