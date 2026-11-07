import Foundation

/// The app's own copy of the game's saves.
///
/// PokeRogue keeps everything (account data `data_Guest`, runs `sessionData*_Guest`, settings) in the web page's
/// localStorage. iOS can clear web storage without asking (for example when the phone is low on space), so the page
/// script in `PageScripts` sends every change here and this keeps it as a plain file in Application Support:
///
///   Saves/localStorage.json            the latest copy (written atomically)
///   Saves/Backups/<yyyy-MM-dd>.json    one copy per day, the last `keepDays` days
///
/// At launch, if the page's storage is empty but this copy exists, the page script puts it back before the game
/// starts. This file is also what the NAS save sync will exchange.
final class SaveStore {
    static let keepDays = 14

    private let queue = DispatchQueue(label: "pokerogue.saves", qos: .utility)
    private let directory: URL
    private let backups: URL
    private let current: URL
    private var lastWritten: Data?

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        directory = base.appendingPathComponent("Saves", isDirectory: true)
        backups = directory.appendingPathComponent("Backups", isDirectory: true)
        current = directory.appendingPathComponent("localStorage.json")
        try? FileManager.default.createDirectory(at: backups, withIntermediateDirectories: true)
        lastWritten = try? Data(contentsOf: current)
    }

    /// The saved copy as a JSON object literal for the page script, or `null` when there is none (or it is damaged).
    func restoreLiteral() -> String {
        guard let data = try? Data(contentsOf: current),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: String],
              !object.isEmpty,
              let clean = try? JSONSerialization.data(withJSONObject: object),
              let text = String(data: clean, encoding: .utf8)
        else { return "null" }
        return text
    }

    /// Stores a full snapshot of the page's localStorage (a JSON object of string values) sent by the page.
    func write(snapshot json: String) {
        queue.async { [self] in
            guard let data = json.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: String]
            else { return }
            // Never replace a real save with an empty one (for example a page that loaded with no storage).
            if object.isEmpty, lastWritten != nil { return }
            guard data != lastWritten else { return }
            do {
                try data.write(to: current, options: .atomic)
                lastWritten = data
                backupToday(data)
            } catch {
                // Keep the previous good copy; the next change tries again.
            }
        }
    }

    private func backupToday(_ data: Data) {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        let today = backups.appendingPathComponent(formatter.string(from: Date()) + ".json")
        try? data.write(to: today, options: .atomic)

        // File names sort by date, so the oldest are first.
        let names = ((try? FileManager.default.contentsOfDirectory(atPath: backups.path)) ?? [])
            .filter { $0.hasSuffix(".json") }
            .sorted()
        for name in names.dropLast(Self.keepDays) {
            try? FileManager.default.removeItem(at: backups.appendingPathComponent(name))
        }
    }
}
