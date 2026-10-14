import Foundation
import Network

/// A TCP channel to the scrcpy server (through `adb forward`), with exact-length
/// reads. All callbacks arrive on the channel's serial queue.
final class SocketChannel {
    let label: String
    private let queue: DispatchQueue
    private var conn: NWConnection?
    private var closed = false

    init(label: String) {
        self.label = label
        self.queue = DispatchQueue(label: "dexclient.\(label)")
    }

    /// Connect, retrying for a few seconds: with `adb forward` + `tunnel_forward`
    /// the server may not be listening yet when we first try.
    func connect(port: UInt16, timeout: TimeInterval = 8, completion: @escaping (Bool) -> Void) {
        let deadline = Date().addingTimeInterval(timeout)
        attempt(port: port, deadline: deadline, completion: completion)
    }

    private func attempt(port: UInt16, deadline: Date, completion: @escaping (Bool) -> Void) {
        guard !closed else { completion(false); return }
        let conn = NWConnection(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port)!, using: .tcp)
        self.conn = conn
        conn.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                self.conn?.stateUpdateHandler = nil
                completion(true)
            case .failed, .cancelled:
                self.conn?.stateUpdateHandler = nil
                if Date() < deadline, !self.closed {
                    self.queue.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                        self?.attempt(port: port, deadline: deadline, completion: completion)
                    }
                } else {
                    completion(false)
                }
            default:
                break
            }
        }
        conn.start(queue: queue)
    }

    /// Read exactly `length` bytes (accumulating partial reads), or nil on error/close.
    func readExact(_ length: Int, completion: @escaping (Data?) -> Void) {
        conn?.receive(minimumIncompleteLength: length, maximumLength: length) { data, _, isComplete, error in
            if let data, data.count == length {
                completion(data)
            } else if isComplete || error != nil {
                completion(nil)
            } else {
                // Should not happen with minimumIncompleteLength, but be safe.
                completion(nil)
            }
        }
    }

    func write(_ data: Data) {
        conn?.send(content: data, completion: .contentProcessed { _ in })
    }

    func close() {
        closed = true
        conn?.stateUpdateHandler = nil
        conn?.cancel()
        conn = nil
    }
}
