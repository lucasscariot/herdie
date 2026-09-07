import Foundation

typealias TerminalColor = AnsiColor
typealias TerminalCell = CellSnapshot
typealias TerminalCursor = CursorSnapshot

enum TerminalUpdateError: Error {
    case invalidFullFrame
    case incompatibleDelta
    case cellOutsideGrid
}

struct TerminalFrame: Equatable, Sendable {
    var columns: UInt16
    var rows: UInt16
    var scrollbackOffset: UInt32
    var cursor: TerminalCursor
    var cells: [TerminalCell]
    var text: String
    var damagedCellIndices: [Int]
    var requiresFullRedraw: Bool

    static let empty = TerminalFrame(
        columns: 80,
        rows: 24,
        scrollbackOffset: 0,
        cursor: TerminalCursor(row: 0, column: 0, visible: false),
        cells: [],
        text: "",
        damagedCellIndices: [],
        requiresFullRedraw: true
    )

    mutating func apply(_ update: TerminalUpdate) throws {
        let cellCount = Int(update.columns) * Int(update.rows)
        if update.full {
            guard update.cells.count == cellCount else {
                throw TerminalUpdateError.invalidFullFrame
            }
            columns = update.columns
            rows = update.rows
            cells = update.cells
            damagedCellIndices = []
            requiresFullRedraw = true
        } else {
            guard columns == update.columns, rows == update.rows, cells.count == cellCount else {
                throw TerminalUpdateError.incompatibleDelta
            }
            var damage: [Int] = []
            damage.reserveCapacity(update.cells.count)
            for cell in update.cells {
                let index = Int(cell.row) * Int(columns) + Int(cell.column)
                guard cell.row < rows, cell.column < columns, cells.indices.contains(index) else {
                    throw TerminalUpdateError.cellOutsideGrid
                }
                cells[index] = cell
                damage.append(index)
            }
            damagedCellIndices = damage
            requiresFullRedraw = false
        }
        scrollbackOffset = update.scrollbackOffset
        cursor = update.cursor
        text = update.text
    }
}

struct TerminalLink: Equatable {
    let url: URL
    let row: Int
    let columns: Range<Int>
}

enum TerminalLinkDetector {
    static func matches(in text: String) -> [(range: NSRange, url: URL)] {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return [] }
        let source = text as NSString
        return detector.matches(in: text, range: NSRange(location: 0, length: source.length)).compactMap { result in
            guard let url = result.url, let scheme = url.scheme?.lowercased(),
                  ["http", "https"].contains(scheme), url.host != nil else { return nil }
            let visible = source.substring(with: result.range).lowercased()
            guard visible.hasPrefix("https://") || visible.hasPrefix("http://") else { return nil }
            return (result.range, url)
        }
    }

    static func links(in frame: TerminalFrame) -> [TerminalLink] {
        let width = Int(frame.columns)
        guard width > 0, frame.cells.count == width * Int(frame.rows) else { return [] }
        var links: [TerminalLink] = []
        for row in 0..<Int(frame.rows) {
            var text = ""
            var columns: [Int] = []
            for column in 0..<width {
                let contents = frame.cells[row * width + column].contents
                text += contents
                columns += Array(repeating: column, count: contents.utf16.count)
            }
            for match in matches(in: text) {
                guard match.range.length > 0, NSMaxRange(match.range) <= columns.count else { continue }
                let first = columns[match.range.location]
                let last = columns[NSMaxRange(match.range) - 1] + 1
                // Without soft-wrap metadata, a URL continuing on the next row is ambiguous.
                // Do not open its incomplete prefix as a different destination.
                if last == width, row + 1 < Int(frame.rows),
                   !frame.cells[(row + 1) * width].contents.trimmingCharacters(in: .whitespaces).isEmpty {
                    continue
                }
                links.append(TerminalLink(url: match.url, row: row, columns: first..<last))
            }
        }
        return links
    }
}
