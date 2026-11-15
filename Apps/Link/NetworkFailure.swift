import Foundation
import Synchronization

final class NetworkFailure: Sendable {
    private let message = Mutex<String?>(nil)

    var latest: String? {
        message.withLock { $0 }
    }

    func record(_ error: Error) {
        message.withLock { $0 = error.localizedDescription }
    }
}
