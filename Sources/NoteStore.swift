import Foundation

extension Notification.Name {
    static let scratchpadDidSave = Notification.Name("scratchpadDidSave")
}

class NoteStore {
    static let shared = NoteStore()

    private let jsonURL: URL
    private let legacyURL: URL
    private var saveWorkItem: DispatchWorkItem?

    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("Scratchpad")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        jsonURL = dir.appendingPathComponent("note.json")
        legacyURL = dir.appendingPathComponent("note.md")
    }

    func load() -> [Block] {
        if let data = try? Data(contentsOf: jsonURL),
           let blocks = try? JSONDecoder().decode([Block].self, from: data), !blocks.isEmpty {
            return blocks
        }
        if let md = try? String(contentsOf: legacyURL, encoding: .utf8), !md.isEmpty {
            return migrateMarkdown(md)
        }
        return [Block()]
    }

    func scheduleSave(_ blocks: [Block]) {
        saveWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            if let data = try? JSONEncoder().encode(blocks) {
                try? data.write(to: self.jsonURL, options: .atomic)
            }
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .scratchpadDidSave, object: nil)
            }
        }
        saveWorkItem = work
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    private func migrateMarkdown(_ md: String) -> [Block] {
        let lines = md.components(separatedBy: "\n")
        var blocks: [Block] = []
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }
            if trimmed == "---" {
                blocks.append(Block(type: .divider))
            } else if line.hasPrefix("### ") {
                blocks.append(Block(type: .heading1, content: String(line.dropFirst(4))))
            } else if line.hasPrefix("## ") {
                blocks.append(Block(type: .heading1, content: String(line.dropFirst(3))))
            } else if line.hasPrefix("# ") {
                blocks.append(Block(type: .heading1, content: String(line.dropFirst(2))))
            } else if line.hasPrefix("> ") {
                blocks.append(Block(type: .quote, content: String(line.dropFirst(2))))
            } else if line.hasPrefix("- ") || line.hasPrefix("* ") {
                blocks.append(Block(type: .bulletList, content: String(line.dropFirst(2))))
            } else if line.hasPrefix("[x] ") || line.hasPrefix("[X] ") {
                blocks.append(Block(type: .todo, content: String(line.dropFirst(4)), checked: true))
            } else if line.hasPrefix("[] ") {
                blocks.append(Block(type: .todo, content: String(line.dropFirst(3))))
            } else {
                blocks.append(Block(type: .text, content: line))
            }
        }
        return blocks.isEmpty ? [Block()] : blocks
    }
}
