import CoreGraphics
import Foundation

struct CaptureResult: Sendable {
    var text: String
    var context: String?
    var selectionBounds: CGRect?
    var origin: InputOrigin
}

func withTimeout<T: Sendable>(seconds: Double, _ op: @escaping @Sendable () async -> T?) async -> T? {
    await withTaskGroup(of: T?.self) { group in
        group.addTask { await op() }
        group.addTask {
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            return nil
        }
        let first = await group.next() ?? nil
        group.cancelAll()
        return first
    }
}
