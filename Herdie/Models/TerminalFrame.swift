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
