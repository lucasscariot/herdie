import XCTest
@testable import Herdie

final class TerminalFrameTests: XCTestCase {
    func testDecodesTheStableRustSnapshotContract() throws {
        let json = #"{"columns":2,"rows":1,"scrollback_offset":0,"cursor":{"row":0,"column":1,"visible":true},"cells":[{"row":0,"column":0,"contents":"P","foreground":{"kind":"indexed","index":2},"background":{"kind":"default"},"bold":true,"italic":false,"underline":false,"inverse":false},{"row":0,"column":1,"contents":" ","foreground":{"kind":"default"},"background":{"kind":"default"},"bold":false,"italic":false,"underline":false,"inverse":false}],"text":"P"}"#

        let frame = try TerminalFrame.decode(json)

        XCTAssertEqual(frame.columns, 2)
        XCTAssertEqual(frame.cells[0].contents, "P")
        XCTAssertEqual(frame.cells[0].foreground, .indexed(index: 2))
        XCTAssertTrue(frame.cells[0].bold)
    }
}
