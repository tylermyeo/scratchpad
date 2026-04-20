import AppKit

// MARK: - Inline styling (bold, italic, code within a block's text storage)

enum InlineStyler {
    static func apply(to storage: NSTextStorage, baseFont: NSFont) {
        let text = storage.string
        let range = NSRange(location: 0, length: (text as NSString).length)
        guard range.length > 0 else { return }

        applyPattern(#"\*\*(.*?)\*\*"#, to: storage, text: text, in: range) { s, full, content in
            let font = (s.attribute(.font, at: content.location, effectiveRange: nil) as? NSFont) ?? baseFont
            s.addAttribute(.font, value: font.withBold(), range: content)
            dimMarkers(full: full, content: content, in: s)
        }

        applyPattern(#"(?<!\*)\*(?!\*)(.*?)(?<!\*)\*(?!\*)"#, to: storage, text: text, in: range) { s, full, content in
            let font = (s.attribute(.font, at: content.location, effectiveRange: nil) as? NSFont) ?? baseFont
            s.addAttribute(.font, value: font.withItalic(), range: content)
            dimMarkers(full: full, content: content, in: s)
        }

        applyPattern(#"`([^`\n]+)`"#, to: storage, text: text, in: range) { s, full, content in
            let size = baseFont.pointSize * 0.87
            let codeFont = NSFont(name: "Menlo", size: size) ?? NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
            s.addAttributes([
                .font: codeFont,
                .foregroundColor: NSColor.scratchpadHeading,
                .backgroundColor: NSColor.scratchpadHeading.withAlphaComponent(0.08)
            ], range: content)
            dimMarkers(full: full, content: content, in: s)
        }
    }

    private static func dimMarkers(full: NSRange, content: NSRange, in storage: NSTextStorage) {
        let tiny = NSFont.systemFont(ofSize: 9)
        let openLen = content.location - full.location
        if openLen > 0 {
            storage.addAttributes([.foregroundColor: NSColor.scratchpadDimmed, .font: tiny],
                                  range: NSRange(location: full.location, length: openLen))
        }
        let closeStart = content.location + content.length
        let closeLen = full.location + full.length - closeStart
        if closeLen > 0 {
            storage.addAttributes([.foregroundColor: NSColor.scratchpadDimmed, .font: tiny],
                                  range: NSRange(location: closeStart, length: closeLen))
        }
    }

    private static func applyPattern(
        _ pattern: String, to storage: NSTextStorage, text: String, in range: NSRange,
        apply: (NSTextStorage, NSRange, NSRange) -> Void
    ) {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return }
        let ns = text as NSString
        regex.enumerateMatches(in: text, range: range) { match, _, _ in
            guard let m = match, m.numberOfRanges >= 2 else { return }
            let full = m.range(at: 0)
            let content = m.range(at: 1)
            guard full.location != NSNotFound, content.location != NSNotFound,
                  full.upperBound <= ns.length, content.upperBound <= ns.length else { return }
            apply(storage, full, content)
        }
    }
}

// MARK: - Block row delegate

protocol BlockRowDelegate: AnyObject {
    func blockRowContentChanged(_ row: BlockRowView)
    func blockRowPressedReturn(_ row: BlockRowView)
    func blockRowPressedBackspaceOnEmpty(_ row: BlockRowView)
    func blockRowRequestFocusPrevious(_ row: BlockRowView)
    func blockRowRequestFocusNext(_ row: BlockRowView)
    func blockRowNeedsHeightUpdate(_ row: BlockRowView)
}

// MARK: - BlockTextView

class BlockTextView: NSTextView {
    weak var containingRow: BlockRowView?

    override func keyDown(with event: NSEvent) {
        guard let row = containingRow else { super.keyDown(with: event); return }
        switch event.keyCode {
        case 36: // Return
            row.rowDelegate?.blockRowPressedReturn(row)
        case 51 where string.isEmpty: // Backspace on empty block
            row.rowDelegate?.blockRowPressedBackspaceOnEmpty(row)
        case 126 where selectedRange().location == 0: // Up at start
            row.rowDelegate?.blockRowRequestFocusPrevious(row)
        case 125 where selectedRange().location == (string as NSString).length: // Down at end
            row.rowDelegate?.blockRowRequestFocusNext(row)
        default:
            super.keyDown(with: event)
        }
    }

    override func didChangeText() {
        super.didChangeText()
        containingRow?.rowDelegate?.blockRowNeedsHeightUpdate(containingRow!)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard string.isEmpty, let placeholder = containingRow?.placeholderText else { return }
        let xOff = textContainerInset.width + (textContainer?.lineFragmentPadding ?? 5)
        let yOff = textContainerInset.height
        let font = (typingAttributes[.font] as? NSFont) ?? NSFont.systemFont(ofSize: 15)
        let isDark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.scratchpadText.withAlphaComponent(isDark ? 0.25 : 0.28)
        ]
        let rect = NSRect(x: xOff, y: yOff, width: bounds.width - xOff * 2, height: font.pointSize * 2)
        NSAttributedString(string: placeholder, attributes: attrs).draw(in: rect)
    }
}

// MARK: - BlockRowView

class BlockRowView: NSView {
    weak var rowDelegate: BlockRowDelegate?
    var block: Block
    var index: Int = 0

    var placeholderText: String {
        switch block.type {
        case .heading1: return "Heading"
        case .bulletList: return "List item"
        case .todo: return "To-do"
        case .quote: return "Quote"
        default: return "Type something..."
        }
    }

    private(set) var textView: BlockTextView?
    private var checkboxButton: NSButton?
    // Explicit height constraint — updated after layout knows the real row width
    private var heightConstraint: NSLayoutConstraint!

    init(block: Block) {
        self.block = block
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        heightConstraint = heightAnchor.constraint(equalToConstant: 28)
        heightConstraint.isActive = true
        build()
    }
    required init?(coder: NSCoder) { fatalError() }

    // MARK: Build

    private func build() {
        subviews.forEach { $0.removeFromSuperview() }
        textView = nil
        checkboxButton = nil

        switch block.type {
        case .divider:
            buildDivider()
        case .bulletList:
            buildWithPrefix(makeBulletLabel())
        case .todo:
            buildWithPrefix(makeCheckboxButton())
        default:
            buildTextOnly()
        }
        applyBlockStyle()
    }

    private func buildDivider() {
        heightConstraint.constant = 28
        let line = NSView()
        line.translatesAutoresizingMaskIntoConstraints = false
        line.wantsLayer = true
        line.layer?.backgroundColor = NSColor.scratchpadHeading.withAlphaComponent(0.18).cgColor
        addSubview(line)
        NSLayoutConstraint.activate([
            line.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            line.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
            line.centerYAnchor.constraint(equalTo: centerYAnchor),
            line.heightAnchor.constraint(equalToConstant: 1)
        ])
    }

    private func buildTextOnly() {
        let tv = makeTextView()
        addSubview(tv)
        NSLayoutConstraint.activate([
            tv.topAnchor.constraint(equalTo: topAnchor),
            tv.leadingAnchor.constraint(equalTo: leadingAnchor),
            tv.trailingAnchor.constraint(equalTo: trailingAnchor),
            tv.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        textView = tv
    }

    private func buildWithPrefix(_ prefix: NSView) {
        let tv = makeTextView()
        addSubview(prefix)
        addSubview(tv)
        // Center prefix with the first line of text (inset 5pt + lineHeight 22.5pt / 2)
        let firstLineCenter: CGFloat = 16
        NSLayoutConstraint.activate([
            prefix.centerYAnchor.constraint(equalTo: topAnchor, constant: firstLineCenter),
            prefix.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 18),
            prefix.widthAnchor.constraint(equalToConstant: 22),

            tv.topAnchor.constraint(equalTo: topAnchor),
            tv.bottomAnchor.constraint(equalTo: bottomAnchor),
            tv.leadingAnchor.constraint(equalTo: prefix.trailingAnchor),
            tv.trailingAnchor.constraint(equalTo: trailingAnchor)
        ])
        textView = tv
    }

    private func makeTextView() -> BlockTextView {
        let tv = BlockTextView()
        tv.translatesAutoresizingMaskIntoConstraints = false
        tv.isRichText = false
        tv.allowsUndo = true
        tv.drawsBackground = false
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        tv.textContainer?.widthTracksTextView = true
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.isAutomaticTextCompletionEnabled = false
        tv.isAutomaticSpellingCorrectionEnabled = false
        tv.isAutomaticTextReplacementEnabled = false
        tv.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        tv.insertionPointColor = .scratchpadCursor
        tv.selectedTextAttributes = [.backgroundColor: NSColor.scratchpadCursor.withAlphaComponent(0.2)]
        tv.textContainerInset = NSSize(width: 18, height: 5)
        tv.containingRow = self
        tv.delegate = self
        tv.string = block.content
        return tv
    }

    private func makeBulletLabel() -> NSTextField {
        let label = NSTextField(labelWithString: "•")
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = NSFont.systemFont(ofSize: 10, weight: .black)
        label.textColor = .scratchpadBullet
        label.alignment = .center
        return label
    }

    private func makeCheckboxButton() -> NSButton {
        let btn = NSButton()
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.isBordered = false
        btn.title = ""
        btn.target = self
        btn.action = #selector(toggleCheckbox)
        updateCheckboxImage(btn)
        checkboxButton = btn
        return btn
    }

    @objc private func toggleCheckbox() {
        block.checked.toggle()
        if let btn = checkboxButton { updateCheckboxImage(btn) }
        applyBlockStyle()
        rowDelegate?.blockRowContentChanged(self)
    }

    private func updateCheckboxImage(_ btn: NSButton) {
        let name = block.checked ? "checkmark.square.fill" : "square"
        let tint = block.checked ? NSColor.scratchpadHeading : NSColor.scratchpadText.withAlphaComponent(0.40)
        let config = NSImage.SymbolConfiguration(paletteColors: [tint])
            .applying(NSImage.SymbolConfiguration(pointSize: 13, weight: .medium))
        btn.image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(config)
    }

    // MARK: Styling

    func applyBlockStyle() {
        guard let tv = textView, let ts = tv.textStorage else { return }
        let (font, color, inset) = styleForType(block.type)

        let para = NSMutableParagraphStyle()
        para.minimumLineHeight = font.pointSize * 1.5
        para.maximumLineHeight = font.pointSize * 1.5

        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: para
        ]

        ts.beginEditing()
        ts.setAttributes(attrs, range: NSRange(location: 0, length: ts.length))
        InlineStyler.apply(to: ts, baseFont: font)
        if block.type == .todo && block.checked {
            ts.addAttributes([
                .strikethroughStyle: NSUnderlineStyle.single.rawValue,
                .strikethroughColor: NSColor.scratchpadDimmed,
                .foregroundColor: NSColor.scratchpadPlaceholder
            ], range: NSRange(location: 0, length: ts.length))
        }
        ts.endEditing()

        tv.textContainerInset = inset
        tv.typingAttributes = attrs
    }

    private func styleForType(_ type: BlockType) -> (NSFont, NSColor, NSSize) {
        let bodyFont = NSFont(name: "SpaceGrotesk-Medium", size: 15)
            ?? NSFont.systemFont(ofSize: 15, weight: .medium)
        switch type {
        case .heading1:
            let f = NSFont(name: "SpaceGrotesk-Bold", size: 24)
                ?? NSFont.systemFont(ofSize: 24, weight: .bold)
            return (f, .scratchpadHeading, NSSize(width: 18, height: 8))
        case .quote:
            return (bodyFont, NSColor.scratchpadHeading.withAlphaComponent(0.55), NSSize(width: 26, height: 5))
        case .bulletList, .todo:
            return (bodyFont, .scratchpadText, NSSize(width: 4, height: 5))
        default:
            return (bodyFont, .scratchpadText, NSSize(width: 18, height: 5))
        }
    }

    // MARK: Height

    /// Called by BlockEditorView after it knows the real row width.
    /// Returns true if the height constraint changed.
    @discardableResult
    func updateHeight(rowWidth: CGFloat) -> Bool {
        guard block.type != .divider else { return false }
        guard let tv = textView, let lm = tv.layoutManager, let tc = tv.textContainer else { return false }

        // Compute usable text container width from the row width
        let prefixOffset: CGFloat = (block.type == .bulletList || block.type == .todo) ? 40 : 0
        let tvWidth = rowWidth - prefixOffset
        let containerWidth = tvWidth - tv.textContainerInset.width * 2
        guard containerWidth > 0 else { return false }

        tc.containerSize = NSSize(width: containerWidth, height: CGFloat.greatestFiniteMagnitude)
        lm.ensureLayout(for: tc)
        let used = lm.usedRect(for: tc)
        let newHeight = max(ceil(used.height) + tv.textContainerInset.height * 2, 28)

        if abs(heightConstraint.constant - newHeight) > 0.5 {
            heightConstraint.constant = newHeight
            return true
        }
        return false
    }

    // MARK: Draw

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        if block.type == .quote { drawQuoteBorder(in: dirtyRect) }
    }

    private func drawQuoteBorder(in dirtyRect: NSRect) {
        let bar = NSRect(x: 8, y: 4, width: 2.5, height: bounds.height - 8)
        guard bar.intersects(dirtyRect) else { return }
        NSColor.scratchpadHeading.withAlphaComponent(0.22).setFill()
        NSBezierPath(roundedRect: bar, xRadius: 1.25, yRadius: 1.25).fill()
    }
}

// MARK: - BlockRowView: NSTextViewDelegate

extension BlockRowView: NSTextViewDelegate {
    func textDidChange(_ notification: Notification) {
        block.content = textView?.string ?? ""
        applyBlockStyle()
        rowDelegate?.blockRowContentChanged(self)
    }
}

// MARK: - AddBlockButton

class AddBlockButton: NSView {
    var onSelectType: ((BlockType) -> Void)?

    private var trackingArea: NSTrackingArea?
    private var plusIcon: NSTextField!
    private var pillRow: NSStackView!
    private var isExpanded = false

    override init(frame: NSRect) {
        super.init(frame: frame)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        setup()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func setup() {
        plusIcon = NSTextField(labelWithString: "+")
        plusIcon.translatesAutoresizingMaskIntoConstraints = false
        plusIcon.font = NSFont.systemFont(ofSize: 13, weight: .light)
        plusIcon.textColor = NSColor.scratchpadHeading
        plusIcon.alphaValue = 0.28
        addSubview(plusIcon)

        pillRow = NSStackView()
        pillRow.translatesAutoresizingMaskIntoConstraints = false
        pillRow.orientation = .horizontal
        pillRow.spacing = 5
        pillRow.alphaValue = 0
        addSubview(pillRow)

        for type in BlockType.addMenuTypes {
            pillRow.addArrangedSubview(makePill(type))
        }

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 40),
            plusIcon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            plusIcon.centerYAnchor.constraint(equalTo: centerYAnchor),
            pillRow.centerYAnchor.constraint(equalTo: centerYAnchor),
            pillRow.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16)
        ])
    }

    private func makePill(_ type: BlockType) -> NSView {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.wantsLayer = true
        container.layer?.cornerRadius = 5

        let label = NSTextField(labelWithString: type.label)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        label.textColor = NSColor.scratchpadText.withAlphaComponent(0.6)
        container.addSubview(label)

        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: container.topAnchor, constant: 3),
            label.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -3),
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 7),
            label.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -7)
        ])

        updatePillBackground(container, hovered: false)

        let click = NSClickGestureRecognizer(target: self, action: #selector(pillTapped(_:)))
        container.addGestureRecognizer(click)
        container.identifier = NSUserInterfaceItemIdentifier(type.rawValue)

        let hover = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: container)
        container.addTrackingArea(hover)

        return container
    }

    private func updatePillBackground(_ view: NSView, hovered: Bool) {
        view.layer?.backgroundColor = hovered
            ? NSColor.scratchpadHeading.withAlphaComponent(0.12).cgColor
            : NSColor.scratchpadText.withAlphaComponent(0.06).cgColor
    }

    @objc private func pillTapped(_ recognizer: NSClickGestureRecognizer) {
        guard let view = recognizer.view,
              let raw = view.identifier?.rawValue,
              let type = BlockType(rawValue: raw) else { return }
        onSelectType?(type)
    }

    // Forward hover events from pill containers
    override func mouseEntered(with event: NSEvent) {
        // If it's a pill's tracking area, highlight it
        if let pill = event.trackingArea?.owner as? NSView, pill.superview == pillRow {
            updatePillBackground(pill, hovered: true)
            return
        }
        expand()
    }

    override func mouseExited(with event: NSEvent) {
        if let pill = event.trackingArea?.owner as? NSView, pill.superview == pillRow {
            updatePillBackground(pill, hovered: false)
            return
        }
        collapse()
    }

    private func expand() {
        guard !isExpanded else { return }
        isExpanded = true

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.18
            ctx.allowsImplicitAnimation = true
            plusIcon.alphaValue = 0
        }

        let pills = pillRow.arrangedSubviews
        pills.forEach { $0.alphaValue = 0 }

        for (i, pill) in pills.enumerated() {
            let delay = Double(i) * 0.032
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                let slide = CABasicAnimation(keyPath: "transform.translation.x")
                slide.fromValue = -6
                slide.toValue = 0
                slide.duration = 0.28
                slide.timingFunction = CAMediaTimingFunction(controlPoints: 0.16, 1.0, 0.3, 1.0)
                pill.layer?.add(slide, forKey: "slide")

                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = 0.18
                    ctx.allowsImplicitAnimation = true
                    pill.alphaValue = 1
                }
            }
        }
        pillRow.alphaValue = 1
    }

    private func collapse() {
        guard isExpanded else { return }
        isExpanded = false

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            ctx.allowsImplicitAnimation = true
            pillRow.alphaValue = 0
            plusIcon.alphaValue = 0.28
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = trackingArea { removeTrackingArea(t) }
        trackingArea = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self)
        addTrackingArea(trackingArea!)
    }
}

// MARK: - BlockEditorDelegate

protocol BlockEditorDelegate: AnyObject {
    func blockEditorDidChange(_ blocks: [Block])
}

// MARK: - BlockEditorView

class BlockEditorView: NSView, BlockRowDelegate {
    weak var delegate: BlockEditorDelegate?

    private(set) var blocks: [Block] = []
    private var rowViews: [BlockRowView] = []

    private var stackView: NSStackView!
    private var addButton: AddBlockButton!
    private var isUpdatingLayout = false

    override var isFlipped: Bool { true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        setup()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func setup() {
        stackView = NSStackView()
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.orientation = .vertical
        stackView.alignment = .leading
        stackView.spacing = 2
        stackView.edgeInsets = NSEdgeInsets(top: 16, left: 0, bottom: 64, right: 0)
        addSubview(stackView)
        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: topAnchor),
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor)
        ])

        addButton = AddBlockButton()
        addButton.onSelectType = { [weak self] type in
            self?.appendBlock(Block(type: type))
        }
    }

    // MARK: Load

    func load(blocks: [Block]) {
        self.blocks = blocks
        rebuildRows()
    }

    // MARK: Layout

    override func layout() {
        super.layout()
        guard !isUpdatingLayout else { return }
        let rowWidth = stackView.frame.width
        guard rowWidth > 0 else { updateSelfHeight(); return }

        isUpdatingLayout = true
        var changed = false
        for row in rowViews {
            if row.updateHeight(rowWidth: rowWidth) { changed = true }
        }
        isUpdatingLayout = false

        if changed { stackView.layoutSubtreeIfNeeded() }
        updateSelfHeight()
    }

    private func updateSelfHeight() {
        let contentHeight = stackView.fittingSize.height
        let minHeight = enclosingScrollView?.contentView.frame.height ?? 200
        let newHeight = max(contentHeight, minHeight)
        if abs(frame.height - newHeight) > 0.5 {
            var f = frame
            f.size.height = newHeight
            frame = f
        }
    }

    // MARK: Row management

    private func rebuildRows() {
        stackView.arrangedSubviews.forEach { stackView.removeArrangedSubview($0); $0.removeFromSuperview() }
        rowViews = []

        for (i, block) in blocks.enumerated() {
            let row = makeRow(for: block, at: i)
            stackView.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: stackView.widthAnchor).isActive = true
            rowViews.append(row)
        }

        stackView.addArrangedSubview(addButton)
        addButton.widthAnchor.constraint(equalTo: stackView.widthAnchor).isActive = true

        needsLayout = true
    }

    private func makeRow(for block: Block, at index: Int) -> BlockRowView {
        let row = BlockRowView(block: block)
        row.index = index
        row.rowDelegate = self
        return row
    }

    // MARK: Block mutations

    private func insertBlock(_ block: Block, at index: Int) {
        // Save scroll position so rebuildRows doesn't cause a jump
        let savedScrollY = enclosingScrollView?.contentView.bounds.origin.y ?? 0
        blocks.insert(block, at: index)
        rebuildRows()
        if let sv = enclosingScrollView {
            sv.contentView.scroll(to: NSPoint(x: 0, y: savedScrollY))
            sv.reflectScrolledClipView(sv.contentView)
        }
        focusRow(at: index)
        // Smoothly scroll new row into view if needed
        DispatchQueue.main.async { [weak self] in
            guard let self, index < self.rowViews.count else { return }
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.25
                ctx.allowsImplicitAnimation = true
                self.rowViews[index].scrollToVisible(self.rowViews[index].bounds)
            }
        }
        notifyChange()
    }

    private func appendBlock(_ block: Block) {
        insertBlock(block, at: blocks.count)
    }

    private func deleteRow(_ row: BlockRowView) {
        let index = row.index
        if blocks.count == 1 {
            blocks[0] = Block(type: .text)
            rebuildRows()
            focusRow(at: 0)
            notifyChange()
            return
        }
        blocks.remove(at: index)
        rebuildRows()
        focusRow(at: max(0, index - 1), atEnd: true)
        notifyChange()
    }

    func focusRow(at index: Int, atEnd: Bool = false) {
        guard index < rowViews.count else { return }
        let row = rowViews[index]
        guard let tv = row.textView else { return }
        window?.makeFirstResponder(tv)
        let pos = atEnd ? (tv.string as NSString).length : 0
        tv.setSelectedRange(NSRange(location: pos, length: 0))
    }

    private func notifyChange() {
        delegate?.blockEditorDidChange(blocks)
    }

    // MARK: BlockRowDelegate

    func blockRowContentChanged(_ row: BlockRowView) {
        guard row.index < blocks.count else { return }
        blocks[row.index] = row.block
        notifyChange()
    }

    func blockRowNeedsHeightUpdate(_ row: BlockRowView) {
        let rowWidth = stackView.frame.width
        guard rowWidth > 0 else { return }
        if row.updateHeight(rowWidth: rowWidth) {
            stackView.layoutSubtreeIfNeeded()
            updateSelfHeight()
        }
    }

    func blockRowPressedReturn(_ row: BlockRowView) {
        if row.block.content.isEmpty && row.block.type != .text && row.block.type != .divider {
            blocks[row.index].type = .text
            let idx = row.index
            rebuildRows()
            focusRow(at: idx)
            notifyChange()
            return
        }
        insertBlock(Block(type: row.block.type.nextBlockType), at: row.index + 1)
    }

    func blockRowPressedBackspaceOnEmpty(_ row: BlockRowView) {
        deleteRow(row)
    }

    func blockRowRequestFocusPrevious(_ row: BlockRowView) {
        guard row.index > 0 else { return }
        focusRow(at: row.index - 1, atEnd: true)
    }

    func blockRowRequestFocusNext(_ row: BlockRowView) {
        guard row.index + 1 < rowViews.count else { return }
        focusRow(at: row.index + 1)
    }
}
