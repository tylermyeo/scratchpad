import AppKit
import QuartzCore

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.appearance = NSAppearance(named: .aqua)
        registerFonts()
        setupMainMenu()
        setupStatusItem()
        setupPopover()
    }

    private func registerFonts() {
        guard let resourceURL = Bundle.main.resourceURL else { return }
        let fontsURL = resourceURL.appendingPathComponent("Fonts")
        guard let files = try? FileManager.default.contentsOfDirectory(at: fontsURL, includingPropertiesForKeys: nil) else { return }
        for url in files where url.pathExtension == "ttf" || url.pathExtension == "otf" {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }

    private func setupMainMenu() {
        let mainMenu = NSMenu()

        // Edit menu — required for Cmd+C/V/X/Z/A to reach the text view
        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu
        mainMenu.addItem(editItem)

        NSApp.mainMenu = mainMenu
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = statusItem.button else { return }
        button.wantsLayer = true
        let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .light)
        button.image = NSImage(systemSymbolName: "pencil", accessibilityDescription: "Scratchpad")?
            .withSymbolConfiguration(config)
        button.action = #selector(togglePopover)
        button.target = self
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    private func setupPopover() {
        popover = NSPopover()
        popover.contentSize = NSSize(width: 380, height: 560)
        popover.behavior = .transient
        popover.animates = true
        let vc = ContentViewController()
        vc.onPinToggle = { [weak self] pinned in
            self?.setPinned(pinned)
        }
        popover.contentViewController = vc
    }

    private func setPinned(_ pinned: Bool) {
        popover.behavior = pinned ? .applicationDefined : .transient
        if let window = popover.contentViewController?.view.window {
            window.level = pinned ? .floating : .normal
        }
    }

    @objc func togglePopover() {
        guard let button = statusItem.button else { return }

        if NSApp.currentEvent?.type == .rightMouseUp {
            let menu = NSMenu()
            menu.addItem(withTitle: "Quit Scratchpad", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
            statusItem.menu = menu
            button.performClick(nil)
            statusItem.menu = nil
            return
        }

        if popover.isShown {
            if let vc = popover.contentViewController as? ContentViewController, vc.isPinned {
                vc.setPin(false)
                setPinned(false)
            }
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            // Trigger entrance animation after the popover has opened
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
                guard let vc = self?.popover.contentViewController as? ContentViewController else { return }
                vc.onPopoverShown()
            }
        }
    }

}
