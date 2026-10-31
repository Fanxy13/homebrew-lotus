// Lotus AI – an answer that arrives in pieces (the model's reply, a web page). macOS has URLSession.bytes(for:);
// Linux and Windows do not, so there the same thing is made from a delegate: the headers come first, then the body
// as the server sends it. The rest of the program reads both the same way:
//
//   let (bytes, response) = try await openStream(session, request)
//   for try await line in bytes.lines { … }          for try await byte in bytes { … }          bytes.cancel()

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

#if canImport(FoundationNetworking)

typealias StreamedBytes = LiveBytes

// follow: false answers a redirect itself (as the page reader does: it checks every hop)
func openStream(_ session: URLSession, _ request: URLRequest, follow: Bool = true) async throws -> (StreamedBytes, URLResponse) {
    let live = LiveBytes(configuration: session.configuration, follow: follow)
    let response = try await withTaskCancellationHandler {
        try await live.start(request)
    } onCancel: {
        live.task?.cancel()
    }
    return (live, response)
}

final class LiveBytes: NSObject, URLSessionDataDelegate, AsyncSequence, @unchecked Sendable {    // every field is guarded by lock
    typealias Element = UInt8

    private let configuration: URLSessionConfiguration
    private let follow: Bool
    private let lock = NSLock()
    private var chunks: [Data] = []
    private var finished = false
    private var failure: Error?
    private var waiting: CheckedContinuation<Void, Never>?
    private var answer: CheckedContinuation<URLResponse, Error>?
    private(set) var task: URLSessionDataTask?

    func cancel() { task?.cancel() }

    init(configuration: URLSessionConfiguration, follow: Bool) {
        self.configuration = configuration
        self.follow = follow
    }

    func start(_ request: URLRequest) async throws -> URLResponse {
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<URLResponse, Error>) in
            lock.lock()
            answer = c
            lock.unlock()
            let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
            let t = session.dataTask(with: request)
            task = t
            t.resume()
            session.finishTasksAndInvalidate()      // the session lets go of this object when the task is done
        }
    }

    // ── what the network tells us ──
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        lock.lock()
        let c = answer
        answer = nil
        lock.unlock()
        c?.resume(returning: response)
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        lock.lock()
        chunks.append(data)
        lock.unlock()
        wake()
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        lock.lock()
        finished = true
        failure = error
        let c = answer
        answer = nil
        lock.unlock()
        c?.resume(throwing: error ?? URLError(.badServerResponse))
        wake()
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(follow ? request : nil)
    }

    private func wake() {
        lock.lock()
        let c = waiting
        waiting = nil
        lock.unlock()
        c?.resume()
    }

    // ── what the program reads ──
    private enum Pull { case chunk(Data), done(Error?), wait }

    private func pull() -> Pull {
        lock.lock()
        defer { lock.unlock() }
        if !chunks.isEmpty { return .chunk(chunks.removeFirst()) }
        if finished { return .done(failure) }
        return .wait
    }

    private func park(_ c: CheckedContinuation<Void, Never>) {
        lock.lock()
        if !chunks.isEmpty || finished || Task.isCancelled {
            lock.unlock()
            c.resume()
            return
        }
        waiting = c
        lock.unlock()
    }

    // The next piece that arrived; nil when the answer is complete; throws when it broke off
    func nextChunk() async throws -> Data? {
        while true {
            switch pull() {
            case .chunk(let d): return d
            case .done(let error):
                if let error = error { throw error }
                return nil
            case .wait:
                await withTaskCancellationHandler {
                    await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in park(c) }
                } onCancel: {
                    task?.cancel()
                }
                if Task.isCancelled { task?.cancel(); throw CancellationError() }
            }
        }
    }

    struct Iterator: AsyncIteratorProtocol {
        let live: LiveBytes
        var chunk = Data()
        var at = 0

        mutating func next() async throws -> UInt8? {
            while at >= chunk.count {
                guard let d = try await live.nextChunk() else { return nil }
                chunk = d
                at = 0
            }
            defer { at += 1 }
            return chunk[chunk.startIndex + at]
        }
    }

    func makeAsyncIterator() -> Iterator { Iterator(live: self) }

    // Lines, split at \n, \r or \r\n; empty lines are left out (as URLSession.AsyncBytes.lines does)
    struct Lines: AsyncSequence {
        typealias Element = String
        let live: LiveBytes

        struct LineIterator: AsyncIteratorProtocol {
            let live: LiveBytes
            var pending = Data()

            mutating func next() async throws -> String? {
                while true {
                    if let i = pending.firstIndex(where: { $0 == 10 || $0 == 13 }) {
                        let line = Data(pending[pending.startIndex..<i])
                        var cut = pending.index(after: i)
                        if pending[i] == 13, cut < pending.endIndex, pending[cut] == 10 { cut = pending.index(after: cut) }
                        pending = Data(pending[cut...])
                        if line.isEmpty { continue }
                        return String(decoding: line, as: UTF8.self)
                    }
                    guard let d = try await live.nextChunk() else {
                        if pending.isEmpty { return nil }
                        let rest = pending
                        pending = Data()
                        return String(decoding: rest, as: UTF8.self)
                    }
                    pending.append(d)
                }
            }
        }

        func makeAsyncIterator() -> LineIterator { LineIterator(live: live) }
    }

    var lines: Lines { Lines(live: self) }
}

#else

typealias StreamedBytes = URLSession.AsyncBytes

func openStream(_ session: URLSession, _ request: URLRequest, follow: Bool = true) async throws -> (StreamedBytes, URLResponse) {
    try await session.bytes(for: request)       // the session's own delegate decides about redirects
}

extension URLSession.AsyncBytes {
    func cancel() { task.cancel() }
}

#endif
