import Foundation

enum BlockType: String, Codable {
    case text, heading1, bulletList, todo, quote, divider

    var nextBlockType: BlockType {
        switch self {
        case .bulletList, .todo: return self
        default: return .text
        }
    }

    var label: String {
        switch self {
        case .text: return "Text"
        case .heading1: return "H1"
        case .bulletList: return "List"
        case .todo: return "Todo"
        case .quote: return "Quote"
        case .divider: return "Divider"
        }
    }

    static let addMenuTypes: [BlockType] = [.text, .heading1, .bulletList, .todo, .quote, .divider]
}

struct Block: Codable {
    var id: UUID
    var type: BlockType
    var content: String
    var checked: Bool

    init(id: UUID = UUID(), type: BlockType = .text, content: String = "", checked: Bool = false) {
        self.id = id
        self.type = type
        self.content = content
        self.checked = checked
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        content = try c.decodeIfPresent(String.self, forKey: .content) ?? ""
        checked = try c.decodeIfPresent(Bool.self, forKey: .checked) ?? false
        // Migrate removed heading types to heading1
        let rawType = try c.decode(String.self, forKey: .type)
        if rawType == "heading2" || rawType == "heading3" {
            type = .heading1
        } else {
            type = BlockType(rawValue: rawType) ?? .text
        }
    }
}
