import AppKit

// MARK: - NSColor palette  (Golden Bell scheme, no dark mode)

extension NSColor {
    // #E99D25
    static let scratchpadBackground = NSColor(red: 0.914, green: 0.616, blue: 0.145, alpha: 1)
    // #8C1010
    static let scratchpadRed        = NSColor(red: 0.549, green: 0.063, blue: 0.063, alpha: 1)

    static var scratchpadHeading:    NSColor { scratchpadRed }
    static var scratchpadText:       NSColor { scratchpadRed }
    static var scratchpadCursor:     NSColor { scratchpadRed }
    static var scratchpadDimmed:     NSColor { scratchpadRed.withAlphaComponent(0.18) }
    static var scratchpadBullet:     NSColor { scratchpadRed.withAlphaComponent(0.45) }
    static var scratchpadPlaceholder:NSColor { scratchpadRed.withAlphaComponent(0.32) }
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
