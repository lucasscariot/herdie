import Foundation

enum ToolbarAction: String, Codable, CaseIterable, Identifiable, Sendable {
    case control
    case escape
    case tab
    case herdrPrefix
    case up
    case down
    case left
    case right
    case paste
    case composer
    case keyboard

    var id: Self { self }

    var title: String {
        switch self {
        case .control: "Ctrl"
        case .escape: "Esc"
        case .tab: "Tab"
        case .herdrPrefix: "Herdr"
        case .up: "Up"
        case .down: "Down"
        case .left: "Left"
        case .right: "Right"
        case .paste: "Paste"
        case .composer: "Compose"
        case .keyboard: "Keyboard"
        }
    }

    var systemImage: String? {
        switch self {
        case .control, .escape, .tab: nil
        case .herdrPrefix: "point.3.connected.trianglepath.dotted"
        case .up: "arrow.up"
        case .down: "arrow.down"
        case .left: "arrow.left"
        case .right: "arrow.right"
        case .paste: "clipboard"
        case .composer: "bubble.left"
        case .keyboard: "keyboard"
        }
    }

    var byteSequence: Data? {
        switch self {
        case .control, .paste, .composer, .keyboard: nil
        case .escape: Data([0x1B])
        case .tab: Data([0x09])
        case .herdrPrefix: Data([0x00])
        case .up: Data([0x1B, 0x5B, 0x41])
        case .down: Data([0x1B, 0x5B, 0x42])
        case .right: Data([0x1B, 0x5B, 0x43])
        case .left: Data([0x1B, 0x5B, 0x44])
        }
    }

    static let defaults: [ToolbarAction] = [
        .control, .escape, .tab, .herdrPrefix, .up, .paste, .composer, .keyboard
    ]
}
