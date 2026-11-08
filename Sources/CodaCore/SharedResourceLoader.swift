import Foundation

/// Coalesces concurrent preparation without leaving cancelled callers waiting on
/// an unstructured task. The final waiter cancels the underlying operation.
public actor SharedResourceLoader<Value: Sendable, Progress: Sendable> {
    public typealias ProgressHandler = @Sendable (Progress) -> Void
    private let factory: @Sendable (@escaping ProgressHandler) async throws -> Value
    private var value: Value?
    private var loading: Task<Void, Never>?
    private var generation = UUID()
    private var latestProgress: Progress?
    private struct Waiter {
        let continuation: CheckedContinuation<Value, Error>
        let progress: ProgressHandler
    }
    private var waiters: [UUID: Waiter] = [:]
    var activeWaiterCount: Int { waiters.count }
    public init(factory: @escaping @Sendable (@escaping ProgressHandler) async throws -> Value) {
        self.factory = factory
    }
    public func get(progress: @escaping ProgressHandler = { _ in }) async throws -> Value {
        try Task.checkCancellation()
        if let value { return value }
        let id = UUID()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                waiters[id] = Waiter(continuation: continuation, progress: progress)
                if let latestProgress { progress(latestProgress) }
                if loading == nil { startLoading() }
            }
        } onCancel: { Task { await self.cancelWaiter(id) } }
    }
    private func startLoading() {
        guard loading == nil, !waiters.isEmpty else { return }
        let token = UUID(); generation = token
        loading = Task { [factory] in
            do {
                let prepared = try await factory { update in
                    Task { await self.publish(update, generation: token) }
                }
                try Task.checkCancellation()
                complete(.success(prepared), generation: token)
            } catch { complete(.failure(error), generation: token) }
        }
    }
    private func publish(_ update: Progress, generation token: UUID) {
        guard token == generation, loading?.isCancelled == false else { return }
        latestProgress = update
        for waiter in waiters.values { waiter.progress(update) }
    }
    private func cancelWaiter(_ id: UUID) {
        guard let waiter = waiters.removeValue(forKey: id) else { return }
        waiter.continuation.resume(throwing: CancellationError())
        if waiters.isEmpty { loading?.cancel() }
    }
    private func complete(_ result: Result<Value, Error>, generation token: UUID) {
        guard token == generation else { return }
        let wasCancelled = loading?.isCancelled == true
        loading = nil; latestProgress = nil
        if wasCancelled {
            // New callers may arrive while the abandoned SDK stage unwinds.
            // Keep their continuations and start a fresh stage once it settles;
            // they did not cancel and must never inherit its CancellationError.
            startLoading()
            return
        }
        if case .success(let prepared) = result { value = prepared }
        let pending = waiters; waiters.removeAll()
        for waiter in pending.values { waiter.continuation.resume(with: result) }
    }
}
