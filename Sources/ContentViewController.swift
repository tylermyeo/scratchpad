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

// MARK: - Edge-softening gradient overlay

class GradientOverlayView: NSView {
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    private var topGradient: CAGradientLayer!
    private var bottomGradient: CAGradientLayer!

    override init(frame: NSRect) { super.init(frame: frame); setup() }
    required init?(coder: NSCoder) { super.init(coder: coder); setup() }

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
        let bg = NSColor.scratchpadBackground
        let solid = bg.cgColor
        let clear = bg.withAlphaComponent(0).cgColor
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        topGradient.colors = [solid, clear]
        bottomGradient.colors = [clear, solid]
        CATransaction.commit()
    }
}

// MARK: - Proximity tracking view

class MouseTrackingView: NSView {
    var onMouseEntered: (() -> Void)?
    var onMouseExited: (() -> Void)?
    private var trackingArea: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = trackingArea { removeTrackingArea(t) }
        trackingArea = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self)
        addTrackingArea(trackingArea!)
    }

    override func mouseEntered(with event: NSEvent) { onMouseEntered?() }
    override func mouseExited(with event: NSEvent) { onMouseExited?() }
}

// MARK: - Content view controller

class ContentViewController: NSViewController {
    private var blockEditor: BlockEditorView!
    private var wordCountLabel: NSTextField!
    private var pinButton: NSButton!
    private var pinHoverZone: MouseTrackingView!
    private var wordCountTimer: Timer?
    private var fadeOutWork: DispatchWorkItem?

    var isPinned = false
    var onPinToggle: ((Bool) -> Void)?

    override func loadView() {
        let bg = BackgroundView(frame: NSRect(x: 0, y: 0, width: 380, height: 560))
        bg.wantsLayer = true

        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.horizontalScrollElasticity = .none
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.scrollerStyle = .overlay
        scrollView.borderType = .noBorder
        scrollView.contentInsets = NSEdgeInsets(top: 8, left: 0, bottom: 40, right: 0)

        blockEditor = BlockEditorView(frame: NSRect(x: 0, y: 0, width: 380, height: 560))
        blockEditor.translatesAutoresizingMaskIntoConstraints = false
        blockEditor.delegate = self
        blockEditor.load(blocks: NoteStore.shared.load())
        scrollView.documentView = blockEditor
        blockEditor.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor).isActive = true

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

        // Pin button — hidden until cursor enters the hover zone
        pinButton = NSButton()
        pinButton.isBordered = false
        pinButton.alphaValue = 0
        pinButton.action = #selector(togglePin)
        pinButton.target = self
        pinButton.translatesAutoresizingMaskIntoConstraints = false
        updatePinButtonImage()

        // Larger invisible zone at top-right that triggers pin button visibility
        pinHoverZone = MouseTrackingView()
        pinHoverZone.translatesAutoresizingMaskIntoConstraints = false
        pinHoverZone.onMouseEntered = { [weak self] in self?.setPinButtonVisible(true) }
        pinHoverZone.onMouseExited = { [weak self] in
            guard let self, !self.isPinned else { return }
            self.setPinButtonVisible(false)
        }

        let overlay = GradientOverlayView()
        overlay.translatesAutoresizingMaskIntoConstraints = false

        bg.addSubview(scrollView)
        bg.addSubview(overlay)
        bg.addSubview(wordCountLabel)
        bg.addSubview(pinHoverZone)
        pinHoverZone.addSubview(pinButton)

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

            // Hover zone: top-right corner, 72×48
            pinHoverZone.trailingAnchor.constraint(equalTo: bg.trailingAnchor),
            pinHoverZone.topAnchor.constraint(equalTo: bg.topAnchor),
            pinHoverZone.widthAnchor.constraint(equalToConstant: 72),
            pinHoverZone.heightAnchor.constraint(equalToConstant: 48),

            // Pin button centered in hover zone
            pinButton.centerXAnchor.constraint(equalTo: pinHoverZone.centerXAnchor),
            pinButton.centerYAnchor.constraint(equalTo: pinHoverZone.centerYAnchor),
        ])

        view = bg
    }

    @objc private func togglePin() {
        setPin(!isPinned)
        onPinToggle?(isPinned)
        setPinButtonVisible(true)
    }

    func setPin(_ pinned: Bool) {
        isPinned = pinned
        updatePinButtonImage()
        if pinned { setPinButtonVisible(true) }
    }

    private func setPinButtonVisible(_ visible: Bool) {
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            ctx.allowsImplicitAnimation = true
            pinButton.alphaValue = visible ? 1.0 : 0
        }
    }

    private func updatePinButtonImage() {
        let symbolName = isPinned ? "pin.fill" : "pin"
        let config = NSImage.SymbolConfiguration(pointSize: 12, weight: .medium)
        pinButton?.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: isPinned ? "Unpin" : "Pin")?
            .withSymbolConfiguration(config)
        pinButton?.contentTintColor = isPinned ? NSColor.scratchpadHeading : NSColor.scratchpadPlaceholder
    }

    func onPopoverShown() {
        blockEditor.focusRow(at: 0, atEnd: true)
        playEntranceAnimation()
    }

    private func playEntranceAnimation() {
        guard let layer = view.layer else { return }
        let spring = CAMediaTimingFunction(controlPoints: 0.16, 1.0, 0.3, 1.0)
        let slide = CABasicAnimation(keyPath: "transform.translation.y")
        slide.fromValue = -14; slide.toValue = 0
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0.0; fade.toValue = 1.0
        let group = CAAnimationGroup()
        group.animations = [slide, fade]
        group.duration = 0.35
        group.timingFunction = spring
        group.fillMode = .backwards
        layer.add(group, forKey: "entrance")
    }
}

// MARK: - BlockEditorDelegate + word count

extension ContentViewController: BlockEditorDelegate {
    func blockEditorDidChange(_ blocks: [Block]) {
        NoteStore.shared.scheduleSave(blocks)
        let total = blocks.reduce(0) { $0 + $1.content.split(whereSeparator: \.isWhitespace).count }
        scheduleWordCount(total)
    }

    private func scheduleWordCount(_ count: Int) {
        wordCountTimer?.invalidate()
        fadeOutWork?.cancel()
        wordCountLabel.alphaValue = 0
        guard count > 0 else { return }
        wordCountLabel.stringValue = count == 1 ? "1 word" : "\(count) words"

        wordCountTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: false) { [weak self] _ in
            guard let self else { return }
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.4
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                ctx.allowsImplicitAnimation = true
                self.wordCountLabel.alphaValue = 0.5
            }
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = 0.6
                    ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
                    ctx.allowsImplicitAnimation = true
                    self.wordCountLabel.alphaValue = 0
                }
            }
            self.fadeOutWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0, execute: work)
        }
    }
}
