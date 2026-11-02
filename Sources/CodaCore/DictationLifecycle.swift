import Foundation

public enum DictationMode: String, CaseIterable, Sendable { case toggle, hold }
public enum DictationIntent: Equatable, Sendable { case none, begin, finish, cancel }
public struct DictationLifecycle: Sendable {
    public enum Phase: String, Sendable { case idle, arming, listening, processing, cancelling, ready, failed }
    public private(set) var phase: Phase = .idle
    public private(set) var id: UUID?
    private var keyIsDown = false
    public init() {}
    public var busy: Bool { [.arming, .listening, .processing, .cancelling].contains(phase) }
    public mutating func keyDown(mode: DictationMode) -> DictationIntent {
        guard !keyIsDown else { return .none }
        keyIsDown = true
        if phase == .listening { return mode == .toggle ? .finish : .none }
        return busy ? .none : .begin
    }
    public mutating func keyUp(mode: DictationMode) -> DictationIntent {
        guard keyIsDown else { return .none }
        keyIsDown = false
        guard mode == .hold else { return .none }
        if phase == .arming { return .cancel }
        return phase == .listening ? .finish : .none
    }
    public mutating func begin(meetingBusy: Bool, modelReady: Bool) -> UUID? {
        guard !busy, !meetingBusy, modelReady else { return nil }
        let token = UUID(); id = token; phase = .arming; return token
    }
    public mutating func listening(_ token: UUID) -> Bool {
        guard id == token, phase == .arming else { return false }
        phase = .listening; return true
    }
    public mutating func processing() -> UUID? {
        guard phase == .listening, let id else { return nil }
        phase = .processing; return id
    }
    public func accepts(_ token: UUID) -> Bool { id == token && phase != .cancelling }
    public mutating func complete(_ token: UUID) -> Bool {
        guard id == token, phase == .processing else { return false }
        phase = .ready; return true
    }
    public mutating func fail(_ token: UUID) {
        guard id == token else { return }
        phase = phase == .cancelling ? .idle : .failed; id = nil
    }
    public mutating func cancel() {
        // Keep a held-key latch until key-up; Escape must not let autorepeat restart capture.
        if phase == .processing || phase == .cancelling { phase = .cancelling }
        else { phase = .idle; id = nil }
    }
    public mutating func resetKeys() { keyIsDown = false }
    public mutating func settled(_ token: UUID) {
        guard id == token, phase == .cancelling else { return }
        id = nil; phase = .idle
    }
}

/// All conditions must hold immediately before a direct AX write. The guarded paste adapter separately rechecks focus and never sends Enter.
public struct InsertionConditions: Sendable {
    public var trusted: Bool
    public var secure: Bool
    public var originalAppFocused: Bool
    public var sameElement: Bool
    public var sameSelection: Bool
    public var focusUnchanged: Bool
    public var writable: Bool
    public init(trusted: Bool, secure: Bool, originalAppFocused: Bool, sameElement: Bool, sameSelection: Bool, focusUnchanged: Bool, writable: Bool) {
        self.trusted = trusted; self.secure = secure; self.originalAppFocused = originalAppFocused
        self.sameElement = sameElement; self.sameSelection = sameSelection; self.focusUnchanged = focusUnchanged; self.writable = writable
    }
    public var mayInsert: Bool { trusted && !secure && originalAppFocused && sameElement && sameSelection && focusUnchanged && writable }
}
