import FlickCore
import Foundation

func microseconds(sinceBoot seconds: TimeInterval) -> Microseconds {
    Microseconds((seconds * 1_000_000).rounded())
}
