import XCTest
@testable import Herdie

final class TerminalFrameTests: XCTestCase {
    func testAppliesTheStableRustFullUpdateContract() throws {
        let update = TerminalUpdate(
            columns: 2,
            rows: 1,
            scrollbackOffset: 0,
            cursor: TerminalCursor(row: 0, column: 1, visible: true),
            cells: [
                TerminalCell.fixture(column: 0, contents: "H", foreground: .indexed(index: 2), bold: true),
                TerminalCell.fixture(column: 1, contents: " ")
            ],
            text: "H",
            full: true
        )
        var frame = TerminalFrame.empty
        try frame.apply(update)

        XCTAssertEqual(frame.columns, 2)
        XCTAssertEqual(frame.cells[0].contents, "H")
        XCTAssertEqual(frame.cells[0].foreground, .indexed(index: 2))
        XCTAssertTrue(frame.cells[0].bold)
        XCTAssertTrue(frame.requiresFullRedraw)
    }

    func testAppliesAnIncrementalUpdateWithoutReplacingUnchangedCells() throws {
        var frame = TerminalFrame.fixture(contents: "AB")
        let update = TerminalUpdate(
            columns: 2,
            rows: 1,
            scrollbackOffset: 0,
            cursor: TerminalCursor(row: 0, column: 1, visible: true),
            cells: [.fixture(column: 1, contents: "C")],
            text: "AC",
            full: false
        )

        try frame.apply(update)

        XCTAssertEqual(frame.cells.map(\.contents), ["A", "C"])
        XCTAssertEqual(frame.damagedCellIndices, [1])
        XCTAssertFalse(frame.requiresFullRedraw)
    }

    func testScrollGestureUsesNaturalIOSDirectionAndEmitsOnlyNewWholeRows() {
        var accumulator = TerminalScrollAccumulator()

        XCTAssertEqual(accumulator.consume(translationY: -8, cellHeight: 18), 0)
        XCTAssertEqual(accumulator.consume(translationY: -20, cellHeight: 18), -1)
        XCTAssertEqual(accumulator.consume(translationY: -57, cellHeight: 18), -2)
        XCTAssertEqual(accumulator.consume(translationY: -40, cellHeight: 18), 1)
        accumulator.reset()
        XCTAssertEqual(accumulator.consume(translationY: 20, cellHeight: 18), 1)
    }
}

private extension TerminalFrame {
    static func fixture(contents: String) -> TerminalFrame {
        let cells = contents.enumerated().map { column, character in
            TerminalCell(
                row: 0,
                column: UInt16(column),
                contents: String(character),
                foreground: .default,
                background: .default,
                bold: false,
                italic: false,
                underline: false,
                inverse: false
            )
        }
        return TerminalFrame(
            columns: UInt16(cells.count),
            rows: 1,
            scrollbackOffset: 0,
            cursor: TerminalCursor(row: 0, column: 0, visible: true),
            cells: cells,
            text: contents,
            damagedCellIndices: [],
            requiresFullRedraw: true
        )
    }
}

private extension TerminalCell {
    static func fixture(
        column: UInt16,
        contents: String,
        foreground: TerminalColor = .default,
        bold: Bool = false
    ) -> TerminalCell {
        TerminalCell(
            row: 0,
            column: column,
            contents: contents,
            foreground: foreground,
            background: .default,
            bold: bold,
            italic: false,
            underline: false,
            inverse: false
        )
    }
}
