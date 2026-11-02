import Foundation

/// Event-only state; never consumes a key event. A fresh chord needs both keys released.
public struct ModifierChord: Sendable {
    public enum Action: Equatable, Sendable { case none, arm, down, up, cancel }
    private var waiting = false
    private var active = false
    private var blocked = false
    public init() {}
    public mutating func update(control: Bool, option: Bool, extraModifier: Bool, otherKey: Bool = false) -> Action {
        if !control && !option {
            let wasActive = active
            waiting = false; active = false; blocked = false
            return wasActive ? .up : .none
        }
        if otherKey || extraModifier {
            let wasActive = active
            waiting = false; active = false; blocked = true
            return wasActive ? .cancel : .none
        }
        if !control || !option {
            let wasActive = active
            waiting = false; active = false
            if wasActive { blocked = true }
            return wasActive ? .up : .none
        }
        guard !blocked, !waiting, !active else { return .none }
        waiting = true
        return .arm
    }
    public mutating func activate() -> Action {
        guard waiting, !blocked, !active else { return .none }
        waiting = false; active = true; return .down
    }
    public mutating func interrupt() -> Action {
        let wasActive = active
        waiting = false; active = false; blocked = true
        return wasActive ? .cancel : .none
    }
}
