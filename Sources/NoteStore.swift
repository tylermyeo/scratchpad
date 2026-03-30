import Foundation

extension Notification.Name {
    static let scratchpadDidSave = Notification.Name("scratchpadDidSave")
}

class NoteStore {
    static let shared = NoteStore()

    private let fileURL: URL
    private var saveWorkItem: DispatchWorkItem?

    private init() {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        let dir = appSupport.appendingPathComponent("Scratchpad")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("note.md")
    }

    func load() -> String {
        (try? String(contentsOf: fileURL, encoding: .utf8)) ?? ""
    }

    /// Debounced save — waits 500ms after the last call before writing to disk
    func scheduleSave(_ content: String) {
        saveWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            try? content.write(to: self.fileURL, atomically: true, encoding: .utf8)
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .scratchpadDidSave, object: nil)
            }
        }
        saveWorkItem = work
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.5, execute: work)
    }
}
