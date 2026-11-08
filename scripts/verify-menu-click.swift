// Explicit native UI check. Opens/closes Dev's Setup Guide and moves the pointer.
// Does not start recording, type, paste, or modify settings.
// --quit-at-end also verifies a physical click on Quit Coda Dev.
import AppKit
import ApplicationServices

func value(_ element: AXUIElement, _ key: String) -> CFTypeRef? {
    var result: CFTypeRef?
    return AXUIElementCopyAttributeValue(element, key as CFString, &result) == .success ? result : nil
}
func children(_ element: AXUIElement) -> [AXUIElement] { value(element, kAXChildrenAttribute) as? [AXUIElement] ?? [] }
func frame(_ element: AXUIElement) -> CGRect? {
    guard let p = value(element, kAXPositionAttribute), let s = value(element, kAXSizeAttribute),
          CFGetTypeID(p) == AXValueGetTypeID(), CFGetTypeID(s) == AXValueGetTypeID() else { return nil }
    var point = CGPoint.zero; var size = CGSize.zero
    guard AXValueGetValue(unsafeBitCast(p, to: AXValue.self), .cgPoint, &point),
          AXValueGetValue(unsafeBitCast(s, to: AXValue.self), .cgSize, &size) else { return nil }
    return CGRect(origin: point, size: size)
}
func wait(_ predicate: () -> Bool) -> Bool {
    let end = Date().addingTimeInterval(3)
    repeat {
        if predicate() { return true }
        RunLoop.current.run(until: .now.addingTimeInterval(0.03))
    } while Date() < end
    return predicate()
}
func title(_ element: AXUIElement) -> String {
    value(element, kAXTitleAttribute) as? String ?? value(element, kAXDescriptionAttribute) as? String ?? ""
}
func button(_ element: AXUIElement, named name: String, depth: Int = 0) -> AXUIElement? {
    guard depth < 8 else { return nil }
    if title(element) == name { return element }
    for child in children(element).prefix(40) { if let found = button(child, named: name, depth: depth + 1) { return found } }
    return nil
}
func click(_ element: AXUIElement) {
    guard let rect = frame(element), rect.width > 0, rect.height > 0 else { fatalError("Target has no clickable frame") }
    let point = CGPoint(x: rect.midX, y: rect.midY)
    CGWarpMouseCursorPosition(point)
    for type in [CGEventType.mouseMoved, .leftMouseDown, .leftMouseUp] {
        let event = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: point, mouseButton: .left)!
        event.flags = []
        event.setIntegerValueField(.mouseEventClickState, value: 1)
        event.post(tap: .cghidEventTap)
        RunLoop.current.run(until: .now.addingTimeInterval(0.08))
    }
}
guard AXIsProcessTrusted(), CGPreflightPostEventAccess() else { fatalError("Native automation access is required") }
guard let running = NSRunningApplication.runningApplications(withBundleIdentifier: "app.coda.notebook.dev").first else { fatalError("Open Coda Dev first") }
let app = AXUIElementCreateApplication(running.processIdentifier)
AXUIElementSetMessagingTimeout(app, 0.5)
func sheets() -> [AXUIElement] {
    (value(app, kAXWindowsAttribute) as? [AXUIElement] ?? []).flatMap(children).filter { value($0, kAXRoleAttribute) as? String == kAXSheetRole }
}
guard sheets().isEmpty else { fatalError("Close the existing sheet before running the menu test") }
var raw: CFTypeRef?
guard AXUIElementCopyAttributeValue(app, kAXExtrasMenuBarAttribute as CFString, &raw) == .success,
      let raw, CFGetTypeID(raw) == AXUIElementGetTypeID() else { fatalError("No Dev status-menu surface") }
let bar = unsafeBitCast(raw, to: AXUIElement.self)
guard let status = children(bar).first, let menu = children(status).first,
      let setup = children(menu).first(where: { title($0) == "Setup Guide" }),
      value(setup, kAXEnabledAttribute) as? Bool == true else { fatalError("Setup Guide unavailable; finish the current operation") }
let pointer = CGEvent(source: nil)?.location
// Activating the status item exposes the menu; selection below is a real mouse
// click, rather than an AXPress on the row (which bypasses the failing path).
_ = AXUIElementPerformAction(status, kAXPressAction as CFString)
guard wait({ (frame(menu)?.width ?? 0) > 0 }) else { fatalError("Status menu did not open") }
click(setup)
guard wait({ (frame(menu)?.width ?? 0) == 0 && !sheets().isEmpty }) else { fatalError("Physical Setup Guide click failed: menu remained open or no sheet appeared") }
guard let sheet = sheets().first, let close = button(sheet, named: "Close setup and continue later") else { fatalError("Setup sheet has no close control") }
click(close)
guard wait({ sheets().isEmpty }) else { fatalError("Physical setup-close click failed") }
if CommandLine.arguments.contains("--quit-at-end") {
    _ = AXUIElementPerformAction(status, kAXPressAction as CFString)
    guard wait({ (frame(menu)?.width ?? 0) > 0 }),
          let quit = children(menu).first(where: { title($0) == "Quit Coda Dev" }) else { fatalError("Quit menu did not open") }
    click(quit)
    guard wait({ running.isTerminated }) else { fatalError("Physical Quit click did not exit Dev") }
    print("PASS: physical Quit command exited Dev normally.")
}
if let pointer { CGWarpMouseCursorPosition(pointer) }
print("PASS: physical menu click opened Setup Guide, dismissed the menu, and the setup close button responded. Dev PID \(running.processIdentifier).")
