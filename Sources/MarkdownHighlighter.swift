import AppKit

// MARK: - NSColor palette

extension NSColor {
    /// Warm cream / warm near-black depending on appearance
    static var scratchpadBackground: NSColor {
        NSColor(name: nil) { appearance in
            switch appearance.bestMatch(from: [.darkAqua, .aqua]) {
            case .darkAqua:
                return NSColor(red: 0.118, green: 0.110, blue: 0.102, alpha: 1) // #1E1C1A
            default:
                return NSColor(red: 0.976, green: 0.969, blue: 0.957, alpha: 1) // #F9F7F4
            }
        }
    }

    /// Muted sienna — warm, not loud
    static var scratchpadHeading: NSColor {
        NSColor(name: nil) { appearance in
            switch appearance.bestMatch(from: [.darkAqua, .aqua]) {
            case .darkAqua:
                return NSColor(red: 0.780, green: 0.490, blue: 0.310, alpha: 1)
            default:
                return NSColor(red: 0.627, green: 0.322, blue: 0.176, alpha: 1) // sienna
            }
        }
    }

    /// Warm amber cursor
    static var scratchpadCursor: NSColor {
        NSColor(red: 0.85, green: 0.55, blue: 0.25, alpha: 1)
    }

    /// For dimmed syntax markers (**, *, #, `)
    static var scratchpadDimmed: NSColor {
        NSColor.labelColor.withAlphaComponent(0.12)
    }

    /// For list bullets and structural glyphs
    static var scratchpadBullet: NSColor {
        NSColor(name: nil) { appearance in
            switch appearance.bestMatch(from: [.darkAqua, .aqua]) {
            case .darkAqua:
                return NSColor(red: 0.780, green: 0.490, blue: 0.310, alpha: 0.50)
            default:
                return NSColor(red: 0.627, green: 0.322, blue: 0.176, alpha: 0.45)
            }
        }
    }

    /// Placeholder "Type something..."
    static var scratchpadPlaceholder: NSColor {
        NSColor(name: nil) { appearance in
            switch appearance.bestMatch(from: [.darkAqua, .aqua]) {
            case .darkAqua:
                return NSColor(white: 0.48, alpha: 1)
            default:
                return NSColor(white: 0.58, alpha: 1)
            }
        }
    }
}

// MARK: - NSFont helpers

extension NSFont {
    func withBold() -> NSFont {
        let descriptor = fontDescriptor.withSymbolicTraits(.bold)
        return NSFont(descriptor: descriptor, size: pointSize) ?? self
    }

    func withItalic() -> NSFont {
        let descriptor = fontDescriptor.withSymbolicTraits(.italic)
        return NSFont(descriptor: descriptor, size: pointSize) ?? self
    }
}

// MARK: - Custom attribute for checkbox click detection

extension NSAttributedString.Key {
    static let checkboxRange = NSAttributedString.Key("scratchpad.checkboxRange")
    static let blockquote = NSAttributedString.Key("scratchpad.blockquote")
}

// MARK: - Markdown highlighter

class MarkdownHighlighter: NSObject, NSTextStorageDelegate {

    private let baseFont = NSFont.systemFont(ofSize: 15, weight: .regular)
    private lazy var baseLineHeight: CGFloat = baseFont.pointSize * 1.6
    private lazy var baseAttributes: [NSAttributedString.Key: Any] = {
        let baseParagraph = NSMutableParagraphStyle()
        baseParagraph.minimumLineHeight = baseLineHeight
        baseParagraph.maximumLineHeight = baseLineHeight
        baseParagraph.paragraphSpacing = 4
        return [
            .font: baseFont,
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: baseParagraph
        ]
    }()

    // didProcessEditing — attribute changes here do NOT expand the edited
    // range that was already reported to the layout manager, preserving
    // the cursor position.
    func textStorage(
        _ textStorage: NSTextStorage,
        didProcessEditing editedMask: NSTextStorageEditActions,
        range editedRange: NSRange,
        changeInLength delta: Int
    ) {
        guard editedMask.contains(.editedCharacters) else { return }
        let text = textStorage.string
        let nsText = text as NSString
        guard nsText.length > 0 else { return }
        let paragraphRange = nsText.paragraphRange(for: editedRange)
        applyStyles(to: textStorage, in: paragraphRange)
    }

    // Full-document restyle (used on initial load)
    func applyFullStyles(to storage: NSTextStorage) {
        let nsText = storage.string as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)
        guard fullRange.length > 0 else { return }
        applyStyles(to: storage, in: fullRange)
    }

    private func applyStyles(to storage: NSTextStorage, in range: NSRange) {
        let text = storage.string
        let nsText = text as NSString

        storage.setAttributes(baseAttributes, range: range)

        nsText.enumerateSubstrings(in: range, options: .byParagraphs) { substring, substringRange, _, _ in
            guard let line = substring else { return }
            self.applyBlockStyle(line: line, range: substringRange, to: storage)
        }

        applyInlineStyles(to: storage, text: text, in: range)
    }

    // MARK: - Block styles

    private func applyBlockStyle(line: String, range: NSRange, to storage: NSTextStorage) {

        if line.hasPrefix("### ") {
            let h3Font = NSFont(name: "NewYorkSmall-Semibold", size: 16)
                ?? NSFont(name: "NewYork-Semibold", size: 16)
                ?? NSFont.systemFont(ofSize: 16, weight: .semibold)
            let h3Paragraph = NSMutableParagraphStyle()
            let h3Line = h3Font.pointSize * 1.35
            h3Paragraph.minimumLineHeight = h3Line
            h3Paragraph.maximumLineHeight = h3Line
            h3Paragraph.paragraphSpacing = 4
            h3Paragraph.paragraphSpacingBefore = 12
            storage.addAttributes([
                .font: h3Font,
                .foregroundColor: NSColor.scratchpadHeading,
                .paragraphStyle: h3Paragraph
            ], range: range)
            shrinkMarker(length: 4, in: range, storage: storage)

        } else if line.hasPrefix("## ") {
            let h2Font = NSFont(name: "NewYorkMedium-Semibold", size: 20)
                ?? NSFont(name: "NewYork-Semibold", size: 20)
                ?? NSFont.systemFont(ofSize: 20, weight: .semibold)
            let h2Paragraph = NSMutableParagraphStyle()
            let h2Line = h2Font.pointSize * 1.3
            h2Paragraph.minimumLineHeight = h2Line
            h2Paragraph.maximumLineHeight = h2Line
            h2Paragraph.paragraphSpacing = 5
            h2Paragraph.paragraphSpacingBefore = 16
            storage.addAttributes([
                .font: h2Font,
                .foregroundColor: NSColor.scratchpadHeading,
                .paragraphStyle: h2Paragraph
            ], range: range)
            shrinkMarker(length: 3, in: range, storage: storage)

        } else if line.hasPrefix("# ") {
            let h1Font = NSFont(name: "NewYorkLarge-Bold", size: 26)
                ?? NSFont(name: "NewYork-Bold", size: 26)
                ?? NSFont.systemFont(ofSize: 26, weight: .bold)
            let h1Paragraph = NSMutableParagraphStyle()
            let h1Line = h1Font.pointSize * 1.25
            h1Paragraph.minimumLineHeight = h1Line
            h1Paragraph.maximumLineHeight = h1Line
            h1Paragraph.paragraphSpacing = 6
            h1Paragraph.paragraphSpacingBefore = 18
            storage.addAttributes([
                .font: h1Font,
                .foregroundColor: NSColor.scratchpadHeading,
                .paragraphStyle: h1Paragraph
            ], range: range)
            shrinkMarker(length: 2, in: range, storage: storage)

        } else if line.trimmingCharacters(in: .whitespaces) == "---" {
            let dividerParagraph = NSMutableParagraphStyle()
            dividerParagraph.minimumLineHeight = 6
            dividerParagraph.maximumLineHeight = 6
            dividerParagraph.paragraphSpacing = 8
            dividerParagraph.paragraphSpacingBefore = 8
            storage.addAttributes([
                .foregroundColor: NSColor.clear,
                .strikethroughStyle: NSUnderlineStyle.single.rawValue,
                .strikethroughColor: NSColor.scratchpadHeading.withAlphaComponent(0.2),
                .paragraphStyle: dividerParagraph,
                .font: NSFont.systemFont(ofSize: 6)
            ], range: range)

        } else if line.hasPrefix("[] ") || line.hasPrefix("[x] ") || line.hasPrefix("[X] ")
                    || line.hasPrefix("\u{2610} ") || line.hasPrefix("\u{2611} ") {
            let isChecked = line.hasPrefix("[x] ") || line.hasPrefix("[X] ") || line.hasPrefix("\u{2611}")
            let isLegacy = line.hasPrefix("\u{2610}") || line.hasPrefix("\u{2611}")
            let markerLen = isLegacy ? 1 : (isChecked ? 3 : 2)
            let listParagraph = NSMutableParagraphStyle()
            listParagraph.minimumLineHeight = baseLineHeight
            listParagraph.maximumLineHeight = baseLineHeight
            listParagraph.firstLineHeadIndent = 20
            listParagraph.headIndent = 20
            listParagraph.paragraphSpacing = 1
            listParagraph.paragraphSpacingBefore = 2
            storage.addAttribute(.paragraphStyle, value: listParagraph, range: range)
            // Hide marker with near-zero-width font so [] and [x] occupy the same space
            let markerRange = NSRange(location: range.location, length: markerLen)
            storage.addAttributes([
                .foregroundColor: NSColor.clear,
                .font: NSFont.systemFont(ofSize: 0.01),
                .checkboxRange: isChecked as NSNumber
            ], range: markerRange)
            // Also collapse the space after the marker
            let hideLen = markerLen + 1
            if range.length >= hideLen {
                let spaceRange = NSRange(location: range.location + markerLen, length: 1)
                storage.addAttributes([
                    .foregroundColor: NSColor.clear,
                    .font: NSFont.systemFont(ofSize: 0.01)
                ], range: spaceRange)
            }
            // If checked: strikethrough + dim the content
            let contentStart = hideLen
            if isChecked && range.length > contentStart {
                let contentRange = NSRange(location: range.location + contentStart, length: range.length - contentStart)
                storage.addAttributes([
                    .strikethroughStyle: NSUnderlineStyle.single.rawValue,
                    .strikethroughColor: NSColor.scratchpadDimmed,
                    .foregroundColor: NSColor.scratchpadPlaceholder
                ], range: contentRange)
            }

        } else if line.hasPrefix("- ") || line.hasPrefix("* ") {
            let listParagraph = NSMutableParagraphStyle()
            listParagraph.minimumLineHeight = baseLineHeight
            listParagraph.maximumLineHeight = baseLineHeight
            let tabStop = NSTextTab(textAlignment: .left, location: 18)
            listParagraph.tabStops = [tabStop]
            listParagraph.headIndent = 18
            listParagraph.paragraphSpacing = 1
            listParagraph.paragraphSpacingBefore = 2
            storage.addAttribute(.paragraphStyle, value: listParagraph, range: range)
            // Hide the raw marker character and replace with a styled bullet
            let markerRange = NSRange(location: range.location, length: 1)
            storage.addAttributes([
                .foregroundColor: NSColor.scratchpadBullet,
                .font: NSFont.systemFont(ofSize: 10, weight: .black)
            ], range: markerRange)
            // Replace displayed character with a centered dot via glyph substitution isn't
            // possible in plain NSTextStorage, so we color the dash warmly and shrink it

        } else if line.hasPrefix("> ") {
            let quoteFont = NSFont(name: "NewYorkSmall-RegularItalic", size: 15)
                ?? NSFont(name: "NewYork-RegularItalic", size: 15)
                ?? baseFont.withItalic()
            let quoteParagraph = NSMutableParagraphStyle()
            quoteParagraph.minimumLineHeight = baseLineHeight
            quoteParagraph.maximumLineHeight = baseLineHeight
            quoteParagraph.headIndent = 20
            quoteParagraph.firstLineHeadIndent = 20
            quoteParagraph.paragraphSpacing = 2
            storage.addAttributes([
                .font: quoteFont,
                .foregroundColor: NSColor.scratchpadHeading.withAlphaComponent(0.50),
                .paragraphStyle: quoteParagraph
            ], range: range)
            // Shrink the > marker to near-invisible
            shrinkMarker(length: 2, in: range, storage: storage)
            // Tag for left-border drawing
            storage.addAttribute(.blockquote, value: true as NSNumber, range: range)
        }
    }

    /// Shrink and fade heading/quote markers so they recede visually
    private func shrinkMarker(length: Int, in range: NSRange, storage: NSTextStorage) {
        let markerLen = min(length, range.length)
        guard markerLen > 0 else { return }
        let markerRange = NSRange(location: range.location, length: markerLen)
        storage.addAttributes([
            .foregroundColor: NSColor.scratchpadDimmed,
            .font: NSFont.systemFont(ofSize: 9, weight: .regular)
        ], range: markerRange)
    }

    // MARK: - Inline styles

    private func applyInlineStyles(to storage: NSTextStorage, text: String, in range: NSRange) {
        applyRegex(#"\*\*(.*?)\*\*"#, to: storage, text: text, in: range) { s, full, content in
            let base = s.attribute(.font, at: content.location, effectiveRange: nil) as? NSFont
                ?? NSFont.systemFont(ofSize: 15)
            s.addAttribute(.font, value: base.withBold(), range: content)
            self.shrinkSyntaxMarkers(full: full, content: content, storage: s)
        }

        applyRegex(#"(?<!\*)\*(?!\*)(.*?)(?<!\*)\*(?!\*)"#, to: storage, text: text, in: range) { s, full, content in
            let base = s.attribute(.font, at: content.location, effectiveRange: nil) as? NSFont
                ?? NSFont.systemFont(ofSize: 15)
            s.addAttribute(.font, value: base.withItalic(), range: content)
            self.shrinkSyntaxMarkers(full: full, content: content, storage: s)
        }

        applyRegex(#"`([^`\n]+)`"#, to: storage, text: text, in: range) { s, full, content in
            let codeFont = NSFont(name: "Menlo", size: 12.5)
                ?? NSFont.monospacedSystemFont(ofSize: 12.5, weight: .regular)
            s.addAttributes([
                .font: codeFont,
                .foregroundColor: NSColor.scratchpadHeading,
                .backgroundColor: NSColor.scratchpadHeading.withAlphaComponent(0.08)
            ], range: content)
            self.shrinkSyntaxMarkers(full: full, content: content, storage: s)
        }
    }

    /// Shrink and fade inline syntax markers (**, *, `) so content takes focus
    private func shrinkSyntaxMarkers(full: NSRange, content: NSRange, storage: NSTextStorage) {
        let markerFont = NSFont.systemFont(ofSize: 9, weight: .regular)
        let openLen = content.location - full.location
        if openLen > 0 {
            let r = NSRange(location: full.location, length: openLen)
            storage.addAttributes([
                .foregroundColor: NSColor.scratchpadDimmed,
                .font: markerFont
            ], range: r)
        }
        let closeStart = content.location + content.length
        let closeLen = full.location + full.length - closeStart
        if closeLen > 0 {
            let r = NSRange(location: closeStart, length: closeLen)
            storage.addAttributes([
                .foregroundColor: NSColor.scratchpadDimmed,
                .font: markerFont
            ], range: r)
        }
    }

    // MARK: - Regex helper

    private func applyRegex(
        _ pattern: String,
        to storage: NSTextStorage,
        text: String,
        in range: NSRange,
        apply: (NSTextStorage, NSRange, NSRange) -> Void
    ) {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return }
        let nsText = text as NSString
        regex.enumerateMatches(in: text, range: range) { match, _, _ in
            guard let match = match, match.numberOfRanges >= 2 else { return }
            let fullRange = match.range(at: 0)
            let contentRange = match.range(at: 1)
            guard fullRange.location != NSNotFound, contentRange.location != NSNotFound,
                  fullRange.upperBound <= nsText.length,
                  contentRange.upperBound <= nsText.length else { return }
            apply(storage, fullRange, contentRange)
        }
    }
}
