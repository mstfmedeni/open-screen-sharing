import Foundation
import Network

/// Picks one of a computer's addresses: each is tried in order, a moment after the one before, and the first that
/// takes a TCP connection wins. A later address can win while an earlier one is still timing out (away from home,
/// the home network's address), but an earlier one that answers within the stagger is preferred.
nonisolated enum AddressRace {
    static let stagger: TimeInterval = 0.3
    static let timeout: TimeInterval = 5

    /// The first of `hosts` answering on `port`; nil when none does within the timeout.
    static func first(of hosts: [String], port: Int) async -> String? {
        guard hosts.count > 1, let port = NWEndpoint.Port(rawValue: UInt16(clamping: port)) else { return hosts.first }
        return await withTaskGroup(of: String?.self) { group in
            for (index, host) in hosts.enumerated() {
                group.addTask {
                    try? await Task.sleep(nanoseconds: UInt64(stagger * Double(index) * 1_000_000_000))
                    guard !Task.isCancelled else { return nil }
                    return await answers(host, port: port) ? host : nil
                }
            }
            var finished = 0
            for await result in group {
                finished += 1
                if let result {
                    group.cancelAll()
                    return result
                }
                if finished == hosts.count { break }
            }
            return nil
        }
    }

    private final class Once: @unchecked Sendable {
        private let lock = NSLock()
        private var done = false

        func claim() -> Bool {
            lock.lock()
            defer { lock.unlock() }
            guard !done else { return false }
            done = true
            return true
        }
    }

    private static func answers(_ host: String, port: NWEndpoint.Port) async -> Bool {
        let connection = NWConnection(host: NWEndpoint.Host(host), port: port, using: .tcp)
        let result = await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
                let once = Once()
                let finish: @Sendable (Bool) -> Void = { value in
                    if once.claim() { continuation.resume(returning: value) }
                }
                connection.stateUpdateHandler = { state in
                    switch state {
                    case .ready: finish(true)
                    // No route or refused: not this one (waiting would only retry it).
                    case .failed, .cancelled, .waiting: finish(false)
                    default: break
                    }
                }
                connection.start(queue: .global(qos: .userInitiated))
                DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { finish(false) }
            }
        } onCancel: {
            connection.cancel()
        }
        connection.cancel()
        return result
    }
}
