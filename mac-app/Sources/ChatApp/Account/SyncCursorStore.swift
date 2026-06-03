import Foundation

struct SyncCursorStore {
    private let directory: URL
    private let fileManager: FileManager

    private var cursorFile: URL {
        directory.appendingPathComponent("sync-cursors.json", isDirectory: false)
    }

    init(directory: URL = SyncCursorStore.defaultDirectory(), fileManager: FileManager = .default) {
        self.directory = directory
        self.fileManager = fileManager
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func load(userId: String) -> Int {
        cursors()[userId]?.lastInboxSeq ?? 0
    }

    func save(userId: String, seq: Int) throws {
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        var values = cursors()
        values[userId] = SyncCursor(lastInboxSeq: seq)
        let data = try JSONEncoder().encode(values)
        try data.write(to: cursorFile, options: [.atomic])
    }

    private func cursors() -> [String: SyncCursor] {
        guard let data = try? Data(contentsOf: cursorFile) else {
            return [:]
        }
        return (try? JSONDecoder().decode([String: SyncCursor].self, from: data)) ?? [:]
    }

    private static func defaultDirectory() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ChatApp", isDirectory: true)
    }
}

private struct SyncCursor: Codable, Equatable, Sendable {
    let lastInboxSeq: Int
}
