import Foundation

/// Unlike a task group, this deadline does not wait for an SDK operation that
/// ignores cancellation. Late results cannot resume the caller a second time.
@MainActor enum NoorOperationDeadline {
    static func run<Value>(seconds: Double = 25,
                           operation: @escaping @MainActor () async throws -> Value) async throws -> Value {
        let gate = Completion<Value>()
        return try await withTaskCancellationHandler(operation: {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                gate.continuation = continuation
                gate.work = Task {
                    do {
                        try Task.checkCancellation()
                        gate.finish(.success(try await operation()))
                    } catch { gate.finish(.failure(error)) }
                }
                gate.timer = Task {
                    do { try await Task.sleep(nanoseconds: UInt64(max(0.001, seconds) * 1_000_000_000)) }
                    catch { return }
                    gate.finish(.failure(URLError(.timedOut)))
                }
            }
        }, onCancel: {
            // The SDK may ignore cancellation, but its caller must return and
            // its child task must be marked cancelled immediately. Completion
            // remains actor-isolated and accepts only the first result.
            Task { @MainActor in gate.finish(.failure(CancellationError())) }
        })
    }
    @MainActor private final class Completion<Value> {
        var continuation: CheckedContinuation<Value, Error>?
        var work: Task<Void, Never>?
        var timer: Task<Void, Never>?
        func finish(_ result: Result<Value, Error>) {
            guard let continuation else { return }
            self.continuation = nil
            timer?.cancel(); work?.cancel(); timer = nil; work = nil
            continuation.resume(with: result)
        }
    }
}
