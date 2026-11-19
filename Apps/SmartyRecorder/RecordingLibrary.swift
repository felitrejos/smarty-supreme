import SmartyCore
import Foundation
import Observation

@MainActor
@Observable
final class RecordingLibrary {
    private(set) var files: [URL] = []
    private let folder = URL.documentsDirectory

    func save(_ recording: Recording) async throws {
        let name = "\(recording.activity.code)_p\(recording.participant)_\(Self.timestamp()).csv"
        let file = folder.appending(path: name)
        try await Task.detached(priority: .userInitiated) {
            try RecordingCSV.encode(recording).write(to: file, atomically: true, encoding: .utf8)
        }.value
        try reload()
    }

    func delete(at offsets: IndexSet) throws {
        for index in offsets {
            try FileManager.default.removeItem(at: files[index])
        }
        try reload()
    }

    func reload() throws {
        files = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "csv" }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
    }

    private static func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: .now)
    }
}
