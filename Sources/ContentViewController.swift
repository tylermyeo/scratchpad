import AppKit
import QuartzCore

// MARK: - Warm background view

class BackgroundView: NSView {
    override var isFlipped: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.scratchpadBackground.setFill()
        dirtyRect.fill()
    }
    override var isOpaque: Bool { true }
}

// MARK: - Edge-softening gradient overlay (CAGradientLayer-based)

class GradientOverlayView: NSView {
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    private var topGradient: CAGradientLayer!
    private var bottomGradient: CAGradientLayer!

    override init(frame: NSRect) {
        super.init(frame: frame)
        setup()
    }
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        wantsLayer = true
        layer?.masksToBounds = true

        topGradient = CAGradientLayer()
        topGradient.startPoint = CGPoint(x: 0.5, y: 0)
        topGradient.endPoint = CGPoint(x: 0.5, y: 1)

        bottomGradient = CAGradientLayer()
        bottomGradient.startPoint = CGPoint(x: 0.5, y: 0)
        bottomGradient.endPoint = CGPoint(x: 0.5, y: 1)

        layer?.addSublayer(topGradient)
        layer?.addSublayer(bottomGradient)
        updateColors()
    }

    override func layout() {
        super.layout()
        let fadeSize: CGFloat = 36
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        topGradient.frame = CGRect(x: 0, y: 0, width: bounds.width, height: fadeSize)
        bottomGradient.frame = CGRect(x: 0, y: bounds.height - fadeSize, width: bounds.width, height: fadeSize)
        CATransaction.commit()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateColors()
    }

    private func updateColors() {
        // Resolve the dynamic color to a concrete CGColor
        let isDark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let bgColor: NSColor = isDark
            ? NSColor(red: 0.118, green: 0.110, blue: 0.102, alpha: 1)
            : NSColor(red: 0.976, green: 0.969, blue: 0.957, alpha: 1)
        let solid = bgColor.cgColor
        let clear = bgColor.withAlphaComponent(0).cgColor

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        // Top: solid → clear (opaque at top edge, fading down)
        topGradient.colors = [solid, clear]
        // Bottom: clear → solid (fading to opaque at bottom edge)
        bottomGradient.colors = [clear, solid]
        CATransaction.commit()
    }
}

// MARK: - Text view with placeholder

class ScratchpadTextView: NSTextView {
    var showPlaceholder: Bool = true {
        didSet { needsDisplay = true }
    }

    // Prevent the 0.01pt marker font from leaking into cursor/typing attributes
    override var typingAttributes: [NSAttributedString.Key: Any] {
        get {
            var attrs = super.typingAttributes
            if let font = attrs[.font] as? NSFont, font.pointSize < 1 {
                attrs[.font] = NSFont.systemFont(ofSize: 15, weight: .regular)
            }
            return attrs
        }
        set {
            var attrs = newValue
            if let font = attrs[.font] as? NSFont, font.pointSize < 1 {
                attrs[.font] = NSFont.systemFont(ofSize: 15, weight: .regular)
            }
            super.typingAttributes = attrs
        }
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard let ts = textStorage else { super.mouseDown(with: event); return }
        // Hit-test against drawn checkbox icon rects (with generous padding)
        for (iconRect, _, attrRange) in checkboxRects() {
            let clickRect = iconRect.insetBy(dx: -6, dy: -6)
            guard clickRect.contains(point) else { continue }
            let marker = (ts.string as NSString).substring(with: attrRange)
            let replacement: String
            switch marker {
            case "[]":  replacement = "[x]"
            case "[x]", "[X]": replacement = "[]"
            case "\u{2610}": replacement = "[x]"
            case "\u{2611}": replacement = "[]"
            default: continue
            }
            ts.beginEditing()
            ts.replaceCharacters(in: attrRange, with: replacement)
            ts.endEditing()
            NoteStore.shared.scheduleSave(ts.string)
            return
        }
        super.mouseDown(with: event)
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        for (iconRect, _, _) in checkboxRects() {
            addCursorRect(iconRect.insetBy(dx: -4, dy: -4), cursor: .pointingHand)
        }
    }

    /// Returns (iconRect, isChecked, attrRange) for each checkbox in the document.
    private func checkboxRects() -> [(NSRect, Bool, NSRange)] {
        guard let ts = textStorage, let lm = layoutManager, let tc = textContainer else { return [] }
        var results: [(NSRect, Bool, NSRange)] = []
        let fullRange = NSRange(location: 0, length: ts.length)
        let nsString = ts.string as NSString
        ts.enumerateAttribute(.checkboxRange, in: fullRange, options: []) { value, attrRange, _ in
            guard let checked = value as? NSNumber else { return }
            let glyphRange = lm.glyphRange(forCharacterRange: attrRange, actualCharacterRange: nil)
            let lineRect = lm.lineFragmentRect(forGlyphAt: glyphRange.location, effectiveRange: nil)
            let iconSize: CGFloat = 15
            let x = lineRect.origin.x + textContainerInset.width + 1
            // Center vertically with the first visible body glyph on the line. Geometric center of
            // the line fragment sits too high relative to the text because of line-height leading.
            let y: CGFloat
            let lineCharRange = nsString.lineRange(for: NSRange(location: attrRange.location, length: 0))
            var idx = attrRange.location + attrRange.length
            var textMidY: CGFloat?
            while idx < lineCharRange.upperBound && idx < ts.length {
                if let font = ts.attribute(.font, at: idx, effectiveRange: nil) as? NSFont, font.pointSize >= 8 {
                    let gRange = lm.glyphRange(forCharacterRange: NSRange(location: idx, length: 1), actualCharacterRange: nil)
                    if gRange.length > 0 {
                        let b = lm.boundingRect(forGlyphRange: gRange, in: tc)
                        if b.width > 0 || b.height > 0 {
                            textMidY = b.midY
                            break
                        }
                    }
                }
                idx += 1
            }
            if let midY = textMidY {
                y = midY + textContainerInset.height - iconSize / 2 + 4
            } else {
                y = lineRect.origin.y + textContainerInset.height + (lineRect.height - iconSize) / 2
            }
            let iconRect = NSRect(x: x, y: y, width: iconSize, height: iconSize)
            results.append((iconRect, checked.boolValue, attrRange))
        }
        return results
    }

    private func drawCheckboxes(in dirtyRect: NSRect) {
        for (iconRect, isChecked, _) in checkboxRects() {
            guard iconRect.intersects(dirtyRect) else { continue }
            let symbolName = isChecked ? "checkmark.square.fill" : "square"
            guard let img = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil) else { continue }
            let tint = isChecked ? NSColor.scratchpadHeading : NSColor.labelColor.withAlphaComponent(0.40)
            let config = NSImage.SymbolConfiguration(paletteColors: [tint])
                .applying(NSImage.SymbolConfiguration(pointSize: 13, weight: .medium))
            let configured = img.withSymbolConfiguration(config) ?? img
            configured.draw(in: iconRect)
        }
    }

    private func drawBlockquoteBorders(in dirtyRect: NSRect) {
        guard let ts = textStorage, let lm = layoutManager, let _ = textContainer else { return }
        let fullRange = NSRange(location: 0, length: ts.length)
        ts.enumerateAttribute(.blockquote, in: fullRange, options: []) { value, attrRange, _ in
            guard value != nil else { return }
            let glyphRange = lm.glyphRange(forCharacterRange: attrRange, actualCharacterRange: nil)
            guard glyphRange.length > 0 else { return }
            let lineRect = lm.lineFragmentRect(forGlyphAt: glyphRange.location, effectiveRange: nil)
            let x: CGFloat = textContainerInset.width + 6
            let y = lineRect.origin.y + textContainerInset.height + 2
            let height = lineRect.height - 4
            let barRect = NSRect(x: x, y: y, width: 2.5, height: height)
            guard barRect.intersects(dirtyRect) else { return }
            let color = NSColor.scratchpadHeading.withAlphaComponent(0.22)
            color.setFill()
            NSBezierPath(roundedRect: barRect, xRadius: 1.25, yRadius: 1.25).fill()
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        drawBlockquoteBorders(in: dirtyRect)
        drawCheckboxes(in: dirtyRect)
        guard string.isEmpty, showPlaceholder else { return }
        let xOffset = textContainerInset.width + (textContainer?.lineFragmentPadding ?? 5)
        let yOffset = textContainerInset.height
        let isDark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let gray: CGFloat = isDark ? 0.70 : 0.55
        let baseLineHeight = NSFont.systemFont(ofSize: 15).pointSize * 1.6
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.minimumLineHeight = baseLineHeight
        paragraphStyle.maximumLineHeight = baseLineHeight
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 15, weight: .regular),
            .foregroundColor: NSColor(white: gray, alpha: 1),
            .paragraphStyle: paragraphStyle
        ]
        let placeholderRect = NSRect(x: xOffset, y: yOffset,
                                     width: bounds.width - xOffset * 2,
                                     height: baseLineHeight + 4)
        NSAttributedString(string: "Type something...", attributes: attrs).draw(in: placeholderRect)
    }
}

// MARK: - Help button with hover popover

class HelpButton: NSButton {
    private var helpPopover: NSPopover?
    private var trackingArea: NSTrackingArea?
    private var dismissWorkItem: DispatchWorkItem?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = trackingArea { removeTrackingArea(t) }
        trackingArea = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self)
        addTrackingArea(trackingArea!)
    }

    override func mouseEntered(with event: NSEvent) {
        dismissWorkItem?.cancel()
        guard helpPopover == nil else { return }
        let popover = NSPopover()
        popover.behavior = .semitransient
        popover.contentViewController = HelpPopoverViewController()
        popover.show(relativeTo: bounds, of: self, preferredEdge: .maxY)
        helpPopover = popover
    }

    override func mouseExited(with event: NSEvent) {
        let work = DispatchWorkItem { [weak self] in
            self?.helpPopover?.performClose(nil)
            self?.helpPopover = nil
        }
        dismissWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }
}

class HelpPopoverViewController: NSViewController {
    override func loadView() {
        let shortcuts: [(syntax: String, label: String)] = [
            ("# ## ###", "Headings"),
            ("**text**", "Bold"),
            ("*text*", "Italic"),
            ("`code`", "Code"),
            ("- item", "List"),
            ("> text", "Quote"),
            ("---", "Divider"),
            ("[]", "Checkbox"),
        ]

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 5

        let monoFont = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        let labelFont = NSFont.systemFont(ofSize: 11, weight: .regular)

        for shortcut in shortcuts {
            let row = NSStackView()
            row.orientation = .horizontal
            row.spacing = 10

            let syntaxField = NSTextField(labelWithString: shortcut.syntax)
            syntaxField.font = monoFont
            syntaxField.textColor = NSColor.scratchpadHeading
            syntaxField.setContentHuggingPriority(.defaultHigh, for: .horizontal)
            syntaxField.widthAnchor.constraint(equalToConstant: 72).isActive = true

            let labelField = NSTextField(labelWithString: shortcut.label)
            labelField.font = labelFont
            labelField.textColor = NSColor.secondaryLabelColor

            row.addArrangedSubview(syntaxField)
            row.addArrangedSubview(labelField)
            stack.addArrangedSubview(row)
        }

        stack.edgeInsets = NSEdgeInsets(top: 10, left: 12, bottom: 10, right: 12)
        self.view = stack
    }
}

// MARK: - Content view controller

class ContentViewController: NSViewController {
    var textView: ScratchpadTextView!
    private let highlighter = MarkdownHighlighter()

    private var wordCountLabel: NSTextField!
    private var helpButton: HelpButton!
    private var wordCountTimer: Timer?
    private var fadeOutWorkItem: DispatchWorkItem?

    override func loadView() {
        let bg = BackgroundView(frame: NSRect(x: 0, y: 0, width: 380, height: 560))
        bg.wantsLayer = true

        // Scroll view
        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.scrollerStyle = .overlay
        scrollView.borderType = .noBorder
        scrollView.contentInsets = NSEdgeInsets(top: 8, left: 0, bottom: 40, right: 0)

        // Use default TextKit stack — set highlighter as delegate after creation
        textView = ScratchpadTextView(frame: scrollView.bounds)
        textView.textStorage?.delegate = highlighter
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = .width
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        textView.drawsBackground = false
        textView.isRichText = false
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextCompletionEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.allowsCharacterPickerTouchBarItem = false
        textView.insertionPointColor = .scratchpadCursor
        textView.selectedTextAttributes = [
            .backgroundColor: NSColor.scratchpadCursor.withAlphaComponent(0.2)
        ]
        textView.textContainerInset = NSSize(width: 22, height: 20)
        textView.delegate = self

        let content = NoteStore.shared.load()
        if !content.isEmpty {
            textView.string = content
            textView.showPlaceholder = false
            if let ts = textView.textStorage {
                ts.beginEditing()
                highlighter.applyFullStyles(to: ts)
                ts.endEditing()
            }
        }
        scrollView.documentView = textView

        // Word count — bottom right, fades in after typing pause
        wordCountLabel = NSTextField(labelWithString: "")
        wordCountLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular)
        wordCountLabel.textColor = NSColor.scratchpadPlaceholder
        wordCountLabel.drawsBackground = false
        wordCountLabel.isBezeled = false
        wordCountLabel.isEditable = false
        wordCountLabel.isSelectable = false
        wordCountLabel.wantsLayer = true
        wordCountLabel.alphaValue = 0
        wordCountLabel.translatesAutoresizingMaskIntoConstraints = false

        // Help button — bottom left, subtle
        helpButton = HelpButton()
        helpButton.title = "?"
        helpButton.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        helpButton.isBordered = false
        helpButton.contentTintColor = NSColor.scratchpadPlaceholder
        helpButton.alphaValue = 0.35
        helpButton.translatesAutoresizingMaskIntoConstraints = false

        // Gradient overlay — uses CAGradientLayer, passes all events through
        let overlay = GradientOverlayView()
        overlay.translatesAutoresizingMaskIntoConstraints = false

        bg.addSubview(scrollView)
        bg.addSubview(overlay)
        bg.addSubview(wordCountLabel)
        bg.addSubview(helpButton)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: bg.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bg.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: bg.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: bg.trailingAnchor),

            overlay.topAnchor.constraint(equalTo: bg.topAnchor),
            overlay.bottomAnchor.constraint(equalTo: bg.bottomAnchor),
            overlay.leadingAnchor.constraint(equalTo: bg.leadingAnchor),
            overlay.trailingAnchor.constraint(equalTo: bg.trailingAnchor),

            wordCountLabel.trailingAnchor.constraint(equalTo: bg.trailingAnchor, constant: -16),
            wordCountLabel.bottomAnchor.constraint(equalTo: bg.bottomAnchor, constant: -14),

            helpButton.leadingAnchor.constraint(equalTo: bg.leadingAnchor, constant: 16),
            helpButton.bottomAnchor.constraint(equalTo: bg.bottomAnchor, constant: -12)
        ])

        self.view = bg
    }

    // Called by AppDelegate after popover is shown
    func onPopoverShown() {
        view.window?.makeFirstResponder(textView)
        playEntranceAnimation()
    }

    // MARK: - Entrance animation

    private func playEntranceAnimation() {
        guard let layer = view.layer else { return }

        let spring = CAMediaTimingFunction(controlPoints: 0.16, 1.0, 0.3, 1.0)

        let slide = CABasicAnimation(keyPath: "transform.translation.y")
        slide.fromValue = -14
        slide.toValue = 0

        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0.0
        fade.toValue = 1.0

        let group = CAAnimationGroup()
        group.animations = [slide, fade]
        group.duration = 0.35
        group.timingFunction = spring
        group.fillMode = .backwards

        layer.add(group, forKey: "entrance")
    }
}

// MARK: - Text delegate + word count

extension ContentViewController: NSTextViewDelegate {
    func textDidChange(_ notification: Notification) {
        guard let tv = notification.object as? NSTextView else { return }

        NoteStore.shared.scheduleSave(tv.string)
        textView.showPlaceholder = tv.string.isEmpty
        scheduleWordCount(text: tv.string)
    }

    private func scheduleWordCount(text: String) {
        // Cancel any pending timers/animations
        wordCountTimer?.invalidate()
        fadeOutWorkItem?.cancel()

        // Immediately hide
        wordCountLabel.alphaValue = 0

        guard !text.isEmpty else { return }

        let count = text.split(whereSeparator: \.isWhitespace).count
        wordCountLabel.stringValue = count == 1 ? "1 word" : "\(count) words"

        // After 1.5s of inactivity, fade in
        wordCountTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: false) { [weak self] _ in
            guard let self else { return }

            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.4
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                ctx.allowsImplicitAnimation = true
                self.wordCountLabel.alphaValue = 0.5
            })

            // After lingering 3s, fade out
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                NSAnimationContext.runAnimationGroup({ ctx in
                    ctx.duration = 0.6
                    ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
                    ctx.allowsImplicitAnimation = true
                    self.wordCountLabel.alphaValue = 0
                })
            }
            self.fadeOutWorkItem = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0, execute: work)
        }
    }
}
