import Foundation
import Testing
@testable import CodaCore

private actor LoadProbe {
    var starts = 0
    var cancelled = false
    func start() { starts += 1 }
    func cancel() { cancelled = true }
}

@Test func resourceLoaderCoalescesAndCachesPreparation() async throws {
    let probe = LoadProbe()
    let loader = SharedResourceLoader<Int, Double> { progress in
        await probe.start(); progress(0.5)
        try await Task.sleep(for: .milliseconds(30))
        return 42
    }
    async let first = loader.get()
    async let second = loader.get()
    let values = try await [first, second]
    #expect(values == [42, 42])
    #expect(try await loader.get() == 42)
    #expect(await probe.starts == 1)
}

@Test func cancellingOneConsumerKeepsAnotherPreparationAlive() async throws {
    let probe = LoadProbe()
    let loader = SharedResourceLoader<Int, Double> { _ in
        await probe.start()
        try await Task.sleep(for: .milliseconds(120))
        return 7
    }
    let first = Task { try await loader.get() }
    let second = Task { try await loader.get() }
    while await loader.activeWaiterCount < 2 { await Task.yield() }
    first.cancel()
    await #expect(throws: CancellationError.self) { try await first.value }
    #expect(try await second.value == 7)
    #expect(await probe.starts == 1)
}

@Test func cancellingLastConsumerCancelsUnderlyingPreparation() async throws {
    let probe = LoadProbe()
    let loader = SharedResourceLoader<Int, Double> { _ in
        await probe.start()
        do { try await Task.sleep(for: .seconds(10)); return 7 }
        catch { await probe.cancel(); throw error }
    }
    let consumer = Task { try await loader.get() }
    while await probe.starts == 0 { await Task.yield() }
    consumer.cancel()
    await #expect(throws: CancellationError.self) { try await consumer.value }
    for _ in 0..<1000 {
        if await probe.cancelled { break }
        await Task.yield()
    }
    #expect(await probe.cancelled)
    #expect(await loader.activeWaiterCount == 0)
}

private actor UnwindingLoadGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var opened = false
    func wait() async {
        if opened { return }
        await withCheckedContinuation { continuation = $0 }
    }
    func open() { opened = true; continuation?.resume(); continuation = nil }
}

@Test func aNewDictationWaitsForAnAbandonedLoadThenGetsAFreshModel() async throws {
    let gate = UnwindingLoadGate()
    let probe = LoadProbe()
    let loader = SharedResourceLoader<Int, Double> { _ in
        await probe.start()
        let attempt = await probe.starts
        if attempt == 1 { await gate.wait() } // Simulates an SDK stage which cannot stop immediately.
        return attempt
    }
    let cancelled = Task { try await loader.get() }
    while await probe.starts == 0 { await Task.yield() }
    cancelled.cancel()
    await #expect(throws: CancellationError.self) { try await cancelled.value }
    let nextDictation = Task { try await loader.get() }
    while await loader.activeWaiterCount == 0 { await Task.yield() }
    await gate.open()
    #expect(try await nextDictation.value == 2)
    #expect(await probe.starts == 2)
    #expect(try await loader.get() == 2)
}
