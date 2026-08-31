import SwiftUI
import UIKit

struct TerminalScrollAccumulator {
    private var emittedRows = 0

    mutating func consume(translationY: CGFloat, cellHeight: CGFloat) -> Int {
        guard cellHeight > 0 else { return 0 }
        let totalRows = Int(-translationY / cellHeight)
        let delta = totalRows - emittedRows
        emittedRows = totalRows
        return delta
    }

    mutating func reset() {
        emittedRows = 0
    }
}

struct TerminalCanvas: UIViewRepresentable {
    var terminalFrame: TerminalFrame
    var focusGeneration: Int
    var onInput: (Data) -> Void
    var onResize: (UInt16, UInt16) -> Void
    var onScroll: (Int) -> Void
    var onPaste: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> TerminalCanvasView {
        let view = TerminalCanvasView()
        configure(view)
        view.focusGeneration = focusGeneration
        return view
    }

    func updateUIView(_ view: TerminalCanvasView, context: Context) {
        configure(view)
        if context.coordinator.lastFocusGeneration != focusGeneration {
            context.coordinator.lastFocusGeneration = focusGeneration
            view.becomeFirstResponder()
        }
    }

    private func configure(_ view: TerminalCanvasView) {
        if view.terminalFrame != terminalFrame {
            view.terminalFrame = terminalFrame
        }
        view.onInput = onInput
        view.onResize = onResize
        view.onScroll = onScroll
        view.onPaste = onPaste
    }

    final class Coordinator {
        var lastFocusGeneration = -1
    }
}

@MainActor
final class TerminalCanvasView: UIView, UIKeyInput {
    var terminalFrame = TerminalFrame.empty {
        didSet {
            if oldValue.text != terminalFrame.text {
                accessibilityValue = terminalFrame.text
            }
            invalidateDamage(previous: oldValue)
        }
    }
    var focusGeneration = 0
    var onInput: ((Data) -> Void)?
    var onResize: ((UInt16, UInt16) -> Void)?
    var onScroll: ((Int) -> Void)?
    var onPaste: (() -> Void)?

    private let fontSize: CGFloat = 13
    private lazy var regularFont = UIFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
    private lazy var boldFont = UIFont.monospacedSystemFont(ofSize: fontSize, weight: .bold)
    private var lastGridSize: (UInt16, UInt16)?
    private var scrollAccumulator = TerminalScrollAccumulator()

    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = true
        backgroundColor = UIColor(HerdieTheme.background)
        contentMode = .redraw
        isAccessibilityElement = true
        accessibilityLabel = "Terminal"
        accessibilityTraits = [.updatesFrequently]
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(focusTerminal)))
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        pan.cancelsTouchesInView = false
        addGestureRecognizer(pan)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override var canBecomeFirstResponder: Bool { true }
    var hasText: Bool { true }

    func insertText(_ text: String) {
        onInput?(Data(text.utf8))
    }

    func deleteBackward() {
        onInput?(Data([0x7F]))
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        reportGridSize()
    }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        context.setFillColor(UIColor(HerdieTheme.background).cgColor)
        context.fill(rect)
        guard terminalFrame.columns > 0, terminalFrame.rows > 0 else { return }

        let metrics = cellMetrics
        for cell in terminalFrame.cells {
            let origin = CGPoint(
                x: CGFloat(cell.column) * metrics.width,
                y: CGFloat(cell.row) * metrics.height
            )
            let cellRect = CGRect(origin: origin, size: metrics)
            guard cellRect.intersects(rect) else { continue }
            var foreground = color(cell.foreground, defaultColor: .white)
            var background = color(cell.background, defaultColor: UIColor(HerdieTheme.background))
            if cell.inverse { swap(&foreground, &background) }

            if background != UIColor(HerdieTheme.background) {
                context.setFillColor(background.cgColor)
                context.fill(cellRect)
            }

            guard cell.contents != " " else { continue }
            var attributes: [NSAttributedString.Key: Any] = [
                .font: cell.bold ? boldFont : regularFont,
                .foregroundColor: foreground
            ]
            if cell.underline {
                attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
            }
            if cell.italic {
                attributes[.obliqueness] = 0.16
            }
            (cell.contents as NSString).draw(
                at: CGPoint(x: origin.x, y: origin.y + 1),
                withAttributes: attributes
            )
        }

        if terminalFrame.cursor.visible,
           terminalFrame.scrollbackOffset == 0,
           cursorRect(terminalFrame.cursor, metrics: metrics).intersects(rect) {
            let cursorRect = cursorRect(terminalFrame.cursor, metrics: metrics)
            context.setFillColor(UIColor(HerdieTheme.accent).withAlphaComponent(0.55).cgColor)
            context.fill(cursorRect)
        }
    }

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        guard let key = presses.first?.key else {
            super.pressesBegan(presses, with: event)
            return
        }
        if key.modifierFlags.contains(.command), key.charactersIgnoringModifiers.lowercased() == "v" {
            onPaste?()
            return
        }
        let bytes: [UInt8]? = switch key.keyCode {
        case .keyboardUpArrow: [0x1B, 0x5B, 0x41]
        case .keyboardDownArrow: [0x1B, 0x5B, 0x42]
        case .keyboardRightArrow: [0x1B, 0x5B, 0x43]
        case .keyboardLeftArrow: [0x1B, 0x5B, 0x44]
        case .keyboardEscape: [0x1B]
        case .keyboardTab: [0x09]
        default: nil
        }
        if let bytes {
            onInput?(Data(bytes))
        } else {
            super.pressesBegan(presses, with: event)
        }
    }

    @objc private func focusTerminal() {
        becomeFirstResponder()
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        switch gesture.state {
        case .began:
            scrollAccumulator.reset()
        case .changed, .ended:
            let rows = scrollAccumulator.consume(
                translationY: gesture.translation(in: self).y,
                cellHeight: cellMetrics.height
            )
            if rows != 0 {
                onScroll?(rows)
            }
            if gesture.state == .ended {
                scrollAccumulator.reset()
            }
        case .cancelled, .failed:
            scrollAccumulator.reset()
        default:
            break
        }
    }

    private var cellMetrics: CGSize {
        let sample = ("W" as NSString).size(withAttributes: [.font: regularFont])
        return CGSize(width: ceil(sample.width), height: ceil(regularFont.lineHeight + 2))
    }

    private func reportGridSize() {
        let metrics = cellMetrics
        let columns = UInt16(max(1, min(Int(bounds.width / metrics.width), Int(UInt16.max))))
        let rows = UInt16(max(1, min(Int(bounds.height / metrics.height), Int(UInt16.max))))
        let size = (columns, rows)
        guard lastGridSize?.0 != size.0 || lastGridSize?.1 != size.1 else { return }
        lastGridSize = size
        onResize?(columns, rows)
    }

    private func invalidateDamage(previous: TerminalFrame) {
        let metrics = cellMetrics
        guard !terminalFrame.requiresFullRedraw,
              previous.columns == terminalFrame.columns,
              previous.rows == terminalFrame.rows
        else {
            setNeedsDisplay()
            return
        }
        for index in terminalFrame.damagedCellIndices where terminalFrame.cells.indices.contains(index) {
            setNeedsDisplay(cellRect(terminalFrame.cells[index], metrics: metrics).insetBy(dx: -1, dy: -1))
        }
        if previous.cursor.visible, previous.scrollbackOffset == 0 {
            setNeedsDisplay(cursorRect(previous.cursor, metrics: metrics))
        }
        if terminalFrame.cursor.visible, terminalFrame.scrollbackOffset == 0 {
            setNeedsDisplay(cursorRect(terminalFrame.cursor, metrics: metrics))
        }
    }

    private func cellRect(_ cell: TerminalCell, metrics: CGSize) -> CGRect {
        CGRect(
            x: CGFloat(cell.column) * metrics.width,
            y: CGFloat(cell.row) * metrics.height,
            width: metrics.width,
            height: metrics.height
        )
    }

    private func cursorRect(_ cursor: TerminalCursor, metrics: CGSize) -> CGRect {
        CGRect(
            x: CGFloat(cursor.column) * metrics.width,
            y: CGFloat(cursor.row) * metrics.height,
            width: metrics.width,
            height: metrics.height
        )
    }

    private func color(_ color: TerminalColor, defaultColor: UIColor) -> UIColor {
        switch color {
        case .default:
            defaultColor
        case let .rgb(red, green, blue):
            UIColor(
                red: CGFloat(red) / 255,
                green: CGFloat(green) / 255,
                blue: CGFloat(blue) / 255,
                alpha: 1
            )
        case let .indexed(index):
            indexedColor(index)
        }
    }

    private func indexedColor(_ index: UInt8) -> UIColor {
        let base: [UIColor] = [
            .black, .systemRed, .systemGreen, .systemYellow,
            .systemBlue, .systemPurple, .systemTeal, .lightGray,
            .darkGray, .red, .green, .yellow,
            .blue, .magenta, .cyan, .white
        ]
        if Int(index) < base.count { return base[Int(index)] }
        if index >= 232 {
            let value = CGFloat(8 + 10 * (Int(index) - 232)) / 255
            return UIColor(white: value, alpha: 1)
        }
        let cube = Int(index) - 16
        let red = cube / 36
        let green = (cube % 36) / 6
        let blue = cube % 6
        func channel(_ value: Int) -> CGFloat {
            CGFloat(value == 0 ? 0 : 55 + value * 40) / 255
        }
        return UIColor(red: channel(red), green: channel(green), blue: channel(blue), alpha: 1)
    }
}
