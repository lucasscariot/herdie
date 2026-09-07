import SwiftUI
import UIKit

struct TerminalScrollAccumulator {
    private var emittedRows = 0

    mutating func consume(translationY: CGFloat, cellHeight: CGFloat) -> Int {
        guard cellHeight > 0 else { return 0 }
        let totalRows = Int(translationY / cellHeight)
        let delta = totalRows - emittedRows
        emittedRows = totalRows
        return delta
    }

    mutating func reset() {
        emittedRows = 0
    }
}

struct TerminalPanNavigation {
    enum Axis { case horizontal, vertical }
    private var axis: Axis?

    mutating func update(_ translation: CGPoint) -> Bool {
        if axis == nil, max(abs(translation.x), abs(translation.y)) >= 10 {
            axis = abs(translation.x) > abs(translation.y) * 1.5 ? .horizontal : .vertical
        }
        return axis == .vertical
    }

    mutating func finish(_ translation: CGPoint) -> Bool? {
        defer { self = Self() }
        guard axis == .horizontal, abs(translation.x) >= 60,
              abs(translation.x) > abs(translation.y) * 1.5 else { return nil }
        return translation.x < 0
    }
}

struct TerminalCanvas: UIViewRepresentable {
    var terminalFrame: TerminalFrame
    var theme: TerminalTheme
    var fontSize: CGFloat
    var bottomClearance: CGFloat = 0
    var toolbarActions: [ToolbarAction]
    var controlArmed: Bool
    var onToolbarAction: (ToolbarAction) -> Void
    var focusGeneration: Int
    var onInput: (Data) -> Void
    var onResize: (UInt16, UInt16) -> Void
    var onScroll: (Int) -> Void
    var onSwitchPane: (Bool) -> Void
    var onPaste: () -> Void
    var onFocusChanged: (Bool) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> TerminalCanvasView {
        let view = TerminalCanvasView()
        configure(view)
        view.focusGeneration = focusGeneration
        context.coordinator.lastFocusGeneration = focusGeneration
        return view
    }

    func updateUIView(_ view: TerminalCanvasView, context: Context) {
        configure(view)
        if context.coordinator.lastFocusGeneration != focusGeneration {
            context.coordinator.lastFocusGeneration = focusGeneration
            // UIKit focus changes must run after SwiftUI finishes updating its view graph.
            let generation = focusGeneration
            let coordinator = context.coordinator
            DispatchQueue.main.async { [weak view, weak coordinator] in
                guard coordinator?.lastFocusGeneration == generation,
                      let view, view.window != nil else { return }
                view.becomeFirstResponder()
            }
        }
    }

    private func configure(_ view: TerminalCanvasView) {
        view.theme = theme
        view.fontSize = fontSize
        view.onToolbarAction = onToolbarAction
        view.configureAccessory(actions: toolbarActions, controlArmed: controlArmed)
        if view.terminalFrame != terminalFrame {
            view.terminalFrame = terminalFrame
        }
        view.onInput = onInput
        view.bottomClearance = bottomClearance
        view.onResize = onResize
        view.onScroll = onScroll
        view.onSwitchPane = onSwitchPane
        view.onPaste = onPaste
        view.onFocusChanged = onFocusChanged
    }

    final class Coordinator {
        var lastFocusGeneration = -1
    }
}

@MainActor
final class TerminalCanvasView: UIView, UIKeyInput, UIContextMenuInteractionDelegate {
    var terminalFrame = TerminalFrame.empty {
        didSet {
            lastTextRow = terminalFrame.cells.last(where: { !$0.contents.trimmingCharacters(in: .whitespaces).isEmpty })?.row ?? 0
            if oldValue.text != terminalFrame.text {
                accessibilityValue = terminalFrame.text
            }
            if oldValue.text != terminalFrame.text || oldValue.columns != terminalFrame.columns || oldValue.rows != terminalFrame.rows || oldValue.cells != terminalFrame.cells {
                replaceLinks([])
                linkDetectionTask?.cancel()
                linkDetectionTask = Task { [weak self] in
                    do { try await Task.sleep(for: .milliseconds(150)) } catch { return }
                    self?.detectLinks()
                }
            }
            invalidateDamage(previous: oldValue)
        }
    }
    private var lastTextRow: UInt16 = 0
    private var links: [TerminalLink] = []
    private var linkDetectionTask: Task<Void, Never>?
    var onOpenLink: (URL) -> Void = { UIApplication.shared.open($0) }
    var focusGeneration = 0
    var onInput: ((Data) -> Void)?
    var onResize: ((UInt16, UInt16) -> Void)?
    var onScroll: ((Int) -> Void)?
    var onSwitchPane: ((Bool) -> Void)?
    var onPaste: (() -> Void)?
    var onFocusChanged: ((Bool) -> Void)?

    var fontSize: CGFloat = 14 {
        didSet { if oldValue != fontSize { updateTypography() } }
    }
    var theme: TerminalTheme = .herdie {
        didSet {
            if oldValue != theme {
                updateAppearance()
            }
        }
    }
    var bottomClearance: CGFloat = 0 {
        didSet { if oldValue != bottomClearance { setNeedsDisplay() } }
    }
    private func contentOffset(for frame: TerminalFrame) -> CGFloat {
        // Keep the last line in view while a keyboard resize is awaiting a remote frame,
        // even when there is no floating dock clearance.
        guard frame.scrollbackOffset == 0 else { return 0 }
        let lastTextRow = frame.cells.last(where: { !$0.contents.trimmingCharacters(in: .whitespaces).isEmpty })?.row ?? 0
        let lastRow = max(frame.cursor.row, lastTextRow)
        return max(0, CGFloat(Int(lastRow) + 1) * cellMetrics.height - max(0, bounds.height - bottomClearance))
    }
    private var contentOffset: CGFloat {
        guard terminalFrame.scrollbackOffset == 0 else { return 0 }
        let lastRow = max(terminalFrame.cursor.row, lastTextRow)
        return max(0, CGFloat(Int(lastRow) + 1) * cellMetrics.height - max(0, bounds.height - bottomClearance))
    }
    private var terminalBackground: UIColor { theme.background(for: traitCollection.userInterfaceStyle) }
    private lazy var regularFont = UIFontMetrics(forTextStyle: .caption1).scaledFont(for: UIFont.monospacedSystemFont(ofSize: fontSize, weight: .regular), compatibleWith: traitCollection)
    private lazy var boldFont = UIFontMetrics(forTextStyle: .caption1).scaledFont(for: UIFont.monospacedSystemFont(ofSize: fontSize, weight: .bold), compatibleWith: traitCollection)
    private var lastGridSize: (UInt16, UInt16)?
    private var scrollAccumulator = TerminalScrollAccumulator()
    private var panNavigation = TerminalPanNavigation()

    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = true
        backgroundColor = terminalBackground
        contentMode = .redraw
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (view: TerminalCanvasView, _: UITraitCollection) in
            view.updateAppearance()
        }
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { (view: TerminalCanvasView, _: UITraitCollection) in
            view.updateTypography()
        }
        isAccessibilityElement = true
        accessibilityLabel = "Terminal"
        accessibilityTraits = [.updatesFrequently]
        accessibilityHint = "Tap a web link to open it. Hold a link to open or copy it. Use the keyboard button to type."
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        addGestureRecognizer(tap)
        addInteraction(UIContextMenuInteraction(delegate: self))
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        pan.cancelsTouchesInView = false
        addGestureRecognizer(pan)
        tap.require(toFail: pan)
    }

    required init?(coder: NSCoder) {
        nil
    }

    var onToolbarAction: ((ToolbarAction) -> Void)?
    private var accessoryActions: [ToolbarAction] = []
    private var accessoryControlArmed = false
    private lazy var accessoryToolbar: UIToolbar = {
        let toolbar = UIToolbar(frame: CGRect(x: 0, y: 0, width: 320, height: 40))
        toolbar.autoresizingMask = [.flexibleWidth]
        toolbar.isTranslucent = true
        let appearance = UIToolbarAppearance()
        appearance.configureWithDefaultBackground()
        appearance.backgroundEffect = UIBlurEffect(style: .systemChromeMaterial)
        appearance.shadowColor = .clear
        toolbar.standardAppearance = appearance
        toolbar.scrollEdgeAppearance = appearance
        toolbar.compactAppearance = appearance
        toolbar.tintColor = UIColor(HerdieTheme.accent)
        return toolbar
    }()

    override var inputAccessoryView: UIView? { accessoryToolbar }

    func configureAccessory(actions: [ToolbarAction], controlArmed: Bool) {
        guard accessoryActions != actions || accessoryControlArmed != controlArmed || accessoryToolbar.items == nil else { return }
        accessoryActions = actions
        accessoryControlArmed = controlArmed
        func action(_ item: ToolbarAction) -> UIAction {
            UIAction(title: item.title, image: item.systemImage.flatMap(UIImage.init(systemName:)),
                     state: item == .control && controlArmed ? .on : .off) { [weak self] _ in
                if item == .paste { self?.onPaste?() } else { self?.onToolbarAction?(item) }
            }
        }
        var items = actions.prefix(4).map { item in
            let button = UIBarButtonItem(title: item.systemImage == nil ? item.title : nil,
                                         image: item.systemImage.flatMap(UIImage.init(systemName:)), primaryAction: action(item))
            button.accessibilityLabel = item.title
            button.accessibilityIdentifier = "terminal-key-\(item.rawValue)"
            if item == .control {
                button.style = .plain
                button.accessibilityValue = controlArmed ? "On" : "Off"
            }
            return button
        }
        if actions.count > 4 {
            let more = UIBarButtonItem(image: UIImage(systemName: "ellipsis"), menu: UIMenu(children: actions.dropFirst(4).map(action)))
            more.accessibilityLabel = "More terminal keys"
            items.append(more)
        }
        items.append(UIBarButtonItem(systemItem: .flexibleSpace))
        let hide = UIBarButtonItem(image: UIImage(systemName: "keyboard.chevron.compact.down"), primaryAction: UIAction { [weak self] _ in
            self?.resignFirstResponder()
        })
        hide.accessibilityLabel = "Hide keyboard"
        hide.accessibilityIdentifier = "terminal-hide-keyboard"
        items.append(hide)
        for item in items {
            if #available(iOS 26.0, *) { item.hidesSharedBackground = true }
            let armed = item.accessibilityIdentifier == "terminal-key-control" && controlArmed
            item.tintColor = armed ? UIColor(HerdieTheme.accent) : .label
            item.setTitleTextAttributes([.font: UIFont.systemFont(ofSize: 14, weight: armed ? .bold : .medium),
                                         .foregroundColor: armed ? UIColor(HerdieTheme.accent) : UIColor.label], for: .normal)
            item.setTitleTextAttributes([.font: UIFont.systemFont(ofSize: 14, weight: .bold)], for: .highlighted)
            if let image = item.image {
                item.image = image.applyingSymbolConfiguration(UIImage.SymbolConfiguration(pointSize: 16, weight: .regular))
            }
        }
        accessoryToolbar.setItems(items, animated: false)
        accessoryToolbar.barStyle = traitCollection.userInterfaceStyle == .dark ? .black : .default
    }

    private func updateAppearance() {
        backgroundColor = terminalBackground
        accessoryToolbar.barStyle = traitCollection.userInterfaceStyle == .dark ? .black : .default
        keyboardAppearance = traitCollection.userInterfaceStyle == .dark ? .dark : .light
        setNeedsDisplay()
        if isFirstResponder {
            DispatchQueue.main.async { [weak self] in self?.reloadInputViews() }
        }
    }

    override var canBecomeFirstResponder: Bool { true }
    @discardableResult
    override func becomeFirstResponder() -> Bool {
        let became = super.becomeFirstResponder()
        if became { reportFocus() }
        return became
    }

    @discardableResult
    override func resignFirstResponder() -> Bool {
        let resigned = super.resignFirstResponder()
        if resigned { reportFocus() }
        return resigned
    }

    private func reportFocus() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.onFocusChanged?(self.isFirstResponder)
        }
    }

    var hasText: Bool { true }
    var keyboardAppearance: UIKeyboardAppearance = .default

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

    private func updateTypography() {
        regularFont = UIFontMetrics(forTextStyle: .caption1).scaledFont(for: UIFont.monospacedSystemFont(ofSize: fontSize, weight: .regular), compatibleWith: traitCollection)
        boldFont = UIFontMetrics(forTextStyle: .caption1).scaledFont(for: UIFont.monospacedSystemFont(ofSize: fontSize, weight: .bold), compatibleWith: traitCollection)
        let sample = ("W" as NSString).size(withAttributes: [.font: regularFont])
        cellMetrics = CGSize(width: sample.width, height: ceil(regularFont.lineHeight + 2))
        setNeedsLayout()
        setNeedsDisplay()
    }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        context.setFillColor(terminalBackground.cgColor)
        context.fill(rect)
        guard terminalFrame.columns > 0, terminalFrame.rows > 0 else { return }

        let metrics = cellMetrics
        let contentOffset = self.contentOffset
        // Cells are row-major. Skip rows outside the dirty rect before touching glyphs.
        let visibleRows = Self.drawingRows(in: rect.offsetBy(dx: 0, dy: contentOffset), cellHeight: metrics.height, rows: Int(terminalFrame.rows))
        let columns = Int(terminalFrame.columns)
        let start = min(visibleRows.lowerBound * columns, terminalFrame.cells.count)
        let end = min(visibleRows.upperBound * columns, terminalFrame.cells.count)
        struct PalettePair: Hashable { let foreground: UIColor; let background: UIColor }
        var foregroundCache: [PalettePair: UIColor] = [:]
        for cell in terminalFrame.cells[start..<end] {
            let origin = CGPoint(
                x: CGFloat(cell.column) * metrics.width,
                y: CGFloat(cell.row) * metrics.height - contentOffset
            )
            let cellRect = CGRect(origin: origin, size: metrics)
            guard cellRect.intersects(rect) else { continue }
            var foreground = theme.resolve(cell.foreground, style: traitCollection.userInterfaceStyle)
            var background = theme.resolve(cell.background, isBackground: true, style: traitCollection.userInterfaceStyle)
            if cell.inverse { swap(&foreground, &background) }
            let pair = PalettePair(foreground: foreground, background: background)
            if let cached = foregroundCache[pair] {
                foreground = cached
            } else {
                foreground = theme.legibleForeground(foreground, on: background, style: traitCollection.userInterfaceStyle)
                foregroundCache[pair] = foreground
            }

            if background != terminalBackground {
                context.setFillColor(background.cgColor)
                context.fill(cellRect)
            }

            guard cell.contents != " " else { continue }
            var attributes: [NSAttributedString.Key: Any] = [
                .font: cell.bold ? boldFont : regularFont,
                .foregroundColor: foreground
            ]
            if cell.underline || links.contains(where: { $0.row == Int(cell.row) && $0.columns.contains(Int(cell.column)) }) {
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

    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        if openLink(at: gesture.location(in: self)) { return }
        toggleKeyboard()
    }

    @discardableResult
    func openLink(at point: CGPoint) -> Bool {
        guard let link = link(at: point) else { return false }
        onOpenLink(link.url)
        return true
    }

    private func link(at point: CGPoint) -> TerminalLink? {
        guard bounds.contains(point) else { return nil }
        detectLinks()
        let row = Int((point.y + contentOffset) / cellMetrics.height)
        let column = Int(point.x / cellMetrics.width)
        return links.first { $0.row == row && $0.columns.contains(column) }
    }

    private func detectLinks() {
        linkDetectionTask?.cancel()
        replaceLinks(TerminalLinkDetector.links(in: terminalFrame))
    }

    private func replaceLinks(_ updated: [TerminalLink]) {
        guard links != updated else { return }
        for link in links + updated {
            setNeedsDisplay(CGRect(x: CGFloat(link.columns.lowerBound) * cellMetrics.width,
                                   y: CGFloat(link.row) * cellMetrics.height - contentOffset,
                                   width: CGFloat(link.columns.count) * cellMetrics.width,
                                   height: cellMetrics.height))
        }
        links = updated
        accessibilityCustomActions = updated.map { link in
            UIAccessibilityCustomAction(name: "Open \(link.url.absoluteString)") { [weak self] _ in
                self?.onOpenLink(link.url)
                return self != nil
            }
        }
    }

    func contextMenuInteraction(_ interaction: UIContextMenuInteraction, configurationForMenuAtLocation location: CGPoint) -> UIContextMenuConfiguration? {
        guard let link = link(at: location) else { return nil }
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
            UIMenu(title: link.url.absoluteString, children: [
                UIAction(title: "Open Link", image: UIImage(systemName: "safari")) { _ in self?.onOpenLink(link.url) },
                UIAction(title: "Copy Link", image: UIImage(systemName: "doc.on.doc")) { _ in UIPasteboard.general.url = link.url }
            ])
        }
    }

    private func toggleKeyboard() {
        if isFirstResponder {
            resignFirstResponder()
        } else {
            window?.endEditing(true)
        }
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        switch gesture.state {
        case .began:
            scrollAccumulator.reset()
            panNavigation = TerminalPanNavigation()
        case .changed, .ended:
            let translation = gesture.translation(in: self)
            if panNavigation.update(translation) {
                let rows = scrollAccumulator.consume(
                    translationY: translation.y,
                    cellHeight: cellMetrics.height
                )
                if rows != 0 {
                    onScroll?(rows)
                }
            }
            if gesture.state == .ended {
                if let forward = panNavigation.finish(translation) {
                    onSwitchPane?(forward)
                }
                scrollAccumulator.reset()
            }
        case .cancelled, .failed:
            scrollAccumulator.reset()
            panNavigation = TerminalPanNavigation()
        default:
            break
        }
    }

    private lazy var cellMetrics: CGSize = {
        let sample = ("W" as NSString).size(withAttributes: [.font: regularFont])
        return CGSize(width: sample.width, height: ceil(regularFont.lineHeight + 2))
    }()

    static func drawingRows(in rect: CGRect, cellHeight: CGFloat, rows: Int) -> Range<Int> {
        guard cellHeight > 0, rows > 0, !rect.isEmpty else { return 0..<0 }
        let first = max(0, min(rows, Int(floor(rect.minY / cellHeight))))
        let last = max(first, min(rows, Int(ceil(rect.maxY / cellHeight))))
        return first..<last
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
        guard contentOffset(for: previous) == contentOffset,
              !terminalFrame.requiresFullRedraw,
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
            y: CGFloat(cell.row) * metrics.height - contentOffset,
            width: metrics.width,
            height: metrics.height
        )
    }

    private func cursorRect(_ cursor: TerminalCursor, metrics: CGSize) -> CGRect {
        CGRect(
            x: CGFloat(cursor.column) * metrics.width,
            y: CGFloat(cursor.row) * metrics.height - contentOffset,
            width: metrics.width,
            height: metrics.height
        )
    }

}
