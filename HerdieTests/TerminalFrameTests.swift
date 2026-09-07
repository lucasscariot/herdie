import XCTest
@testable import Herdie

final class TerminalFrameTests: XCTestCase {
    func testDetectsWebURLsWithoutTrailingPunctuationAndRejectsOtherSchemes() {
        let text = "See https://example.com/path?q=one&n=2, http://localhost:3000/test. mailto:a@example.com file:///tmp/test javascript:alert(1)"
        XCTAssertEqual(TerminalLinkDetector.matches(in: text).map { $0.url.absoluteString }, [
            "https://example.com/path?q=one&n=2", "http://localhost:3000/test"
        ])
    }

    func testLinkHitRangesUseTerminalColumnsRatherThanUTF16Offsets() {
        let frame = TerminalFrame.fixture(contents: "👋 é https://example.com!")
        let links = TerminalLinkDetector.links(in: frame)
        XCTAssertEqual(links.count, 1)
        XCTAssertEqual(links.first?.columns, 4..<23)
        XCTAssertEqual(links.first?.url.absoluteString, "https://example.com")
    }

    func testDoesNotOpenAnAmbiguousURLAtARowBoundary() {
        var frame = TerminalFrame.fixture(contents: "https://example.com")
        let width = frame.columns
        frame.rows = 2
        frame.cells += (0..<width).map { column in
            TerminalCell(row: 1, column: column, contents: "a", foreground: .default, background: .default,
                         bold: false, italic: false, underline: false, inverse: false)
        }
        XCTAssertTrue(TerminalLinkDetector.links(in: frame).isEmpty)
    }

    @MainActor
    func testCanvasOpensTheCurrentLinkAndNeverUsesAStaleDestination() {
        let view = TerminalCanvasView(frame: CGRect(x: 0, y: 0, width: 500, height: 100))
        view.terminalFrame = .fixture(contents: "https://example.com")
        var opened: [URL] = []
        view.onOpenLink = { opened.append($0) }
        XCTAssertTrue(view.openLink(at: CGPoint(x: 1, y: 1)))
        XCTAssertEqual(opened.first?.absoluteString, "https://example.com")
        view.terminalFrame = .fixture(contents: "Output has changed")
        XCTAssertFalse(view.openLink(at: CGPoint(x: 1, y: 1)))
        XCTAssertEqual(opened.count, 1)
        XCTAssertFalse(view.openLink(at: CGPoint(x: -1, y: 1)))
    }

    func testLightTerminalMaintainsContrastForRemoteColours() {
        let light = TerminalTheme.herdie.background(for: .light)
        let dark = TerminalTheme.herdie.background(for: .dark)
        XCTAssertNotEqual(light, dark)
        for background in [light, UIColor(red: 0.3, green: 0.1, blue: 0.1, alpha: 1)] {
            for foreground in [UIColor.white, .cyan, .yellow, .gray] {
                let adjusted = TerminalTheme.herdie.legibleForeground(foreground, on: background, style: .light)
                XCTAssertGreaterThanOrEqual(TerminalTheme.contrast(adjusted, background), 4.5)
            }
        }
        XCTAssertEqual(TerminalTheme.herdie.resolve(.rgb(red: 40, green: 44, blue: 52), isBackground: true, style: .light), light)
    }

    func testHerdieThemeUnifiesNeutralPanelsAndPreservesColouredHighlights() {
        let grey = TerminalColor.rgb(red: 40, green: 44, blue: 52)
        XCTAssertEqual(TerminalTheme.herdie.resolve(grey, isBackground: true), TerminalTheme.herdie.background(for: .dark))
        XCTAssertNotEqual(TerminalTheme.remote.resolve(grey, isBackground: true), TerminalTheme.herdie.background(for: .dark))
        let highlight = TerminalColor.rgb(red: 180, green: 30, blue: 40)
        XCTAssertEqual(TerminalTheme.herdie.resolve(highlight, isBackground: true), TerminalTheme.remote.resolve(highlight, isBackground: true))
        XCTAssertEqual(TerminalTheme.herdie.resolve(highlight), TerminalTheme.remote.resolve(highlight))
        XCTAssertNotEqual(TerminalTheme.herdie.resolve(.indexed(index: 6)), TerminalTheme.remote.resolve(.indexed(index: 6)))
    }

    func testHorizontalSwipesSwitchOnceAndVerticalGesturesStayScrolling() {
        var pan = TerminalPanNavigation()
        XCTAssertFalse(pan.update(CGPoint(x: -25, y: 3)))
        XCTAssertEqual(pan.finish(CGPoint(x: -90, y: 10)), true)
        XCTAssertNil(pan.finish(CGPoint(x: -90, y: 10)))
        XCTAssertFalse(pan.update(CGPoint(x: 25, y: 3)))
        XCTAssertEqual(pan.finish(CGPoint(x: 90, y: 10)), false)
        XCTAssertTrue(pan.update(CGPoint(x: 2, y: 20)))
        XCTAssertTrue(pan.update(CGPoint(x: 90, y: 25)))
        XCTAssertNil(pan.finish(CGPoint(x: 90, y: 25)))
        XCTAssertFalse(pan.update(CGPoint(x: 20, y: 0)))
        XCTAssertNil(pan.finish(CGPoint(x: 40, y: 0)))
    }

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
