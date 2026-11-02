import AppKit
import WebKit

@MainActor final class OpaqueEditor: NSTextView {
    override func accessibilitySelectedTextRange() -> NSRange {
        NSRange(location: NSNotFound, length: 0)
    }
    override func accessibilityValue() -> String? { nil }
    override func accessibilityRole() -> NSAccessibility.Role? { .group }
}

@MainActor final class Fixture: NSObject, NSApplicationDelegate, WKNavigationDelegate, WKScriptMessageHandler {
    var window: NSWindow!
    var field: NSTextField!
    var web: WKWebView?
    var opaque: NSTextView?
    let output = URL(fileURLWithPath: "/tmp/coda-insertion-fixture-\(getpid()).txt")
    func save(_ text: String) { try? text.write(to: output, atomically: true, encoding: .utf8) }
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        if let text = message.body as? String { save(text) }
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Match ordinary editor command routing; without an Edit menu, WebKit
        // does not receive Cmd-V and produces a misleading paste-test failure.
        let mainMenu = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        appItem.submenu = appMenu; mainMenu.addItem(appItem)
        let editItem = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        let edit = NSMenu(title: "Edit")
        edit.addItem(NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        editItem.submenu = edit; mainMenu.addItem(editItem); NSApp.mainMenu = mainMenu
        window = NSWindow(contentRect: NSRect(x: 220, y: 220, width: 560, height: 230), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Coda synthetic insertion test — disposable"
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 560, height: 230))
        let label = NSTextField(labelWithString: "Synthetic text only. This fixture closes automatically.")
        label.frame = NSRect(x: 24, y: 170, width: 510, height: 25); container.addSubview(label)
        save("Before ")
        if ProcessInfo.processInfo.arguments.contains("--web") {
            let config = WKWebViewConfiguration()
            config.userContentController.add(self, name: "fixture")
            let web = WKWebView(frame: NSRect(x: 24, y: 65, width: 510, height: 90), configuration: config)
            self.web = web; web.navigationDelegate = self; container.addSubview(web)
            let html = "<html><body><input id='fixture' aria-label='Synthetic test field' value='Before ' style='width:95%;font-size:18px'></body></html>"
            let page = ProcessInfo.processInfo.arguments.contains("--textarea")
                ? html.replacingOccurrences(of: "<input id='fixture' aria-label='Synthetic test field' value='Before ' style='width:95%;font-size:18px'>", with: "<textarea id='fixture' aria-label='Synthetic test field' style='width:95%;font-size:18px'>Before </textarea>") : html
            let content = ProcessInfo.processInfo.arguments.contains("--contenteditable")
                ? "<html><body><div id='fixture' role='textbox' contenteditable='true'>Before </div></body></html>" : page
            web.loadHTMLString(content, baseURL: nil)
        } else if ProcessInfo.processInfo.arguments.contains("--opaque") {
            let editor = OpaqueEditor(frame: NSRect(x: 24, y: 65, width: 510, height: 90))
            editor.isRichText = false; editor.string = "Before "
            opaque = editor; container.addSubview(editor)
        } else {
            field = NSTextField(string: "Before ")
            field.frame = NSRect(x: 24, y: 105, width: 510, height: 35); container.addSubview(field)
        }
        window.contentView = container
        NSApp.setActivationPolicy(.regular)
        window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
        if let field {
            window.makeFirstResponder(field)
            field.currentEditor()?.selectedRange = NSRange(location: 7, length: 0)
        }
        if let opaque { window.makeFirstResponder(opaque); opaque.setSelectedRange(NSRange(location: 7, length: 0)) }
        Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                if let opaque = self.opaque { self.save(opaque.string) }
                else if let field = self.field { self.save(field.currentEditor()?.string ?? field.stringValue) }
            }
        }
        Timer.scheduledTimer(withTimeInterval: 120, repeats: false) { _ in
            Task { @MainActor in NSApp.terminate(nil) }
        }
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        window.makeFirstResponder(webView)
        webView.evaluateJavaScript("""
        const f=document.getElementById('fixture'); f.focus();
        if(f.setSelectionRange) { f.setSelectionRange(7,7); }
        else { const r=document.createRange(); r.selectNodeContents(f); r.collapse(false); const s=getSelection(); s.removeAllRanges(); s.addRange(r); }
        f.addEventListener('input',()=>window.webkit.messageHandlers.fixture.postMessage(f.value ?? f.textContent));
        """)
    }
}
@main struct FixtureMain {
    @MainActor static func main() {
        let app = NSApplication.shared
        let fixture = Fixture()
        app.delegate = fixture
        app.run()
    }
}
