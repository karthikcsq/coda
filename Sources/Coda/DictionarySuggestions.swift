import AppKit
import Observation
import SwiftUI
import QuartzCore
import CodaCore

/// Presentation is separate from dictionary state: closing a notice keeps every
/// unreviewed word, while Dismiss explicitly suppresses that spelling.
@MainActor @Observable final class DictionarySuggestions {
    private(set) var current: CustomWord?
    private(set) var added = false
    private(set) var queue: [CustomWord] = []
    private(set) var error: String?
    private(set) var hovering = false
    @ObservationIgnored var onReview: (() -> Void)?
    @ObservationIgnored var preferredFrame: CGRect?
    @ObservationIgnored private var seen: Set<String>
    @ObservationIgnored private var timer: Task<Void, Never>?
    @ObservationIgnored private var window: DictionarySuggestionWindow?
    private let dictionary: CustomDictionary
    private let preview: Bool
    var remaining: Int { queue.count }

    init(dictionary: CustomDictionary, preview: Bool = false) {
        self.dictionary = dictionary; self.preview = preview
        // Existing suggestions are already waiting in Dictionary; do not replay
        // a stack of notices on launch or after a restart.
        seen = Set(dictionary.possible.map { CustomVocabulary.key($0.word) })
        dictionary.onPossibleWordsChanged = { [weak self] in self?.reconcile() }
    }
    private func reconcile() {
        let possible = dictionary.possible
        let live = Set(possible.map(\.id))
        queue.removeAll { !live.contains($0.id) }
        for word in possible where seen.insert(CustomVocabulary.key(word.word)).inserted { queue.append(word) }
        if let current, !added, !live.contains(current.id) { self.current = nil }
        if current == nil { advance() }
        else { present() }
    }
    func approve() {
        guard let current, !added else { return }
        // The dictionary's synchronous change callback must not replace the
        // current card before its success confirmation has appeared.
        added = true
        if dictionary.approve(current.id) { error = nil; present() }
        else { added = false; error = dictionary.error; scheduleTimeout() }
    }
    func dismissWord() {
        guard let current, !added else { return }
        if !dictionary.dismiss(current.id) { error = dictionary.error; scheduleTimeout() }
    }
    func close() {
        timer?.cancel(); timer = nil; queue.removeAll(); current = nil; added = false; error = nil; hovering = false
        window?.hide()
    }
    func review() { close(); onReview?() }
    func setHovering(_ value: Bool) {
        hovering = value
        if value { timer?.cancel(); timer = nil } else { scheduleTimeout() }
    }
    /// Advancing after confirmation also supports deterministic lifecycle tests.
    func finishPresentation() {
        guard current != nil else { return }
        if added { current = nil; advance() } else { close() }
    }
    private func advance() {
        timer?.cancel(); timer = nil; added = false; error = nil
        current = queue.isEmpty ? nil : queue.removeFirst()
        if current == nil { window?.hide() } else { present() }
    }
    private func present() {
        guard current != nil else { return }
        if !preview {
            if window == nil { window = DictionarySuggestionWindow(notice: self) }
            window?.show(preferredFrame: preferredFrame)
        }
        scheduleTimeout()
    }
    private func scheduleTimeout() {
        timer?.cancel(); timer = nil
        guard !preview, current != nil, !hovering, error == nil else { return }
        let id = current?.id, wasAdded = added
        timer = Task { [weak self] in
            do { try await Task.sleep(for: wasAdded ? .seconds(1.5) : .seconds(10)) } catch { return }
            guard let self, !Task.isCancelled, self.current?.id == id, self.added == wasAdded else { return }
            self.finishPresentation()
        }
    }
}

final class DictionaryNoticePanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private final class DictionaryNoticeHostingView: NSHostingView<DictionarySuggestionCard> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

@MainActor final class DictionarySuggestionWindow {
    let panel: NSPanel
    private var generation = UUID()
    init(notice: DictionarySuggestions) {
        panel = DictionaryNoticePanel(contentRect: CGRect(x: 0, y: 0, width: 392, height: 264), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .floating; panel.isOpaque = false; panel.backgroundColor = .clear
        panel.hasShadow = true; panel.hidesOnDeactivate = false; panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = DictionaryNoticeHostingView(rootView: DictionarySuggestionCard(notice: notice))
        panel.setAccessibilityLabel("Coda custom word suggestion")
    }
    func show(preferredFrame: CGRect?) {
        generation = UUID()
        if panel.isVisible {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.12
                panel.animator().alphaValue = 1
            }
            return
        }
        let screen = NSScreen.screens.first { $0.visibleFrame == preferredFrame } ?? NSScreen.main ?? NSScreen.screens.first
        guard let screen else { return }
        let visible = screen.visibleFrame
        let final = CGRect(x: visible.maxX - panel.frame.width - 20, y: visible.minY + 20, width: panel.frame.width, height: panel.frame.height)
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        panel.setFrame(reduceMotion ? final : final.offsetBy(dx: 0, dy: -8), display: false)
        panel.alphaValue = reduceMotion ? 1 : 0
        panel.orderFrontRegardless()
        guard !reduceMotion else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.22; context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1; panel.animator().setFrame(final, display: true)
        }
    }
    func hide() {
        guard panel.isVisible else { return }
        let token = UUID(); generation = token
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion { panel.orderOut(nil); return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.16; panel.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.generation == token else { return }
                self.panel.orderOut(nil)
            }
        }
    }
}

struct DictionarySuggestionCard: View {
    @Bindable var notice: DictionarySuggestions
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let mint = Color(red: 0.62, green: 0.86, blue: 0.76)
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 9) {
                Image(systemName: notice.added ? "checkmark.circle.fill" : "character.book.closed.fill").foregroundStyle(mint)
                Text(notice.added ? "Added to dictionary" : "Possible custom word").font(.system(size: 12, weight: .medium))
                Spacer()
                Button { notice.close() } label: { Image(systemName: "xmark").font(.system(size: 10, weight: .semibold)).frame(width: 24, height: 24) }
                    .buttonStyle(.plain).foregroundStyle(.secondary).accessibilityLabel("Close suggestion; keep word for review")
                    .help("Review this word later in Dictionary")
            }
            if let word = notice.current {
                VStack(alignment: .leading, spacing: 7) {
                    Text(word.word).font(.system(size: 24, weight: .medium)).lineLimit(2).minimumScaleFactor(0.75)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if let original = word.original {
                        HStack(spacing: 6) {
                            Text(original).strikethrough().lineLimit(1)
                            Image(systemName: "arrow.right").font(.system(size: 10))
                            Text(word.word).lineLimit(1)
                        }.font(.system(size: 12)).foregroundStyle(.secondary)
                            .accessibilityLabel("Corrected from \(original) to \(word.word)")
                    }
                }.id(word.id).transition(.opacity)
            }
            Spacer(minLength: 0)
            if let error = notice.error {
                Text(error).font(.system(size: 11)).foregroundStyle(.orange).lineLimit(2)
            }
            if notice.added {
                Text("Ready for your next dictation.").font(.system(size: 12)).foregroundStyle(.secondary)
            } else {
                HStack(spacing: 10) {
                    Button { notice.approve() } label: {
                        Label("Add word", systemImage: "plus").font(.system(size: 12, weight: .semibold))
                            .padding(.horizontal, 14).frame(height: 32).background(mint, in: Capsule()).foregroundStyle(CodaStyle.onAccent)
                    }.buttonStyle(.plain).accessibilityIdentifier("coda.dictionary.notice.add")
                    Button("Dismiss") { notice.dismissWord() }.buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(.secondary)
                        .help("Do not suggest this spelling again")
                    Spacer()
                }
            }
            HStack {
                Text(notice.remaining > 0 ? "\(notice.remaining) more to review" : "Saved on this Mac").font(.system(size: 10)).foregroundStyle(.secondary)
                Spacer()
                Button("Open dictionary") { notice.review() }.buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(mint)
            }
        }.padding(20).frame(width: 376, height: 248)
            .background(CodaStyle.sheet, in: RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(.white.opacity(0.12)))
            .padding(8).frame(width: 392, height: 264)
            .preferredColorScheme(.light).environment(\.colorScheme, .light).foregroundStyle(CodaStyle.ink)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: notice.current?.id)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: notice.added)
            .onHover { notice.setHovering($0) }
            .accessibilityElement(children: .contain).accessibilityLabel("Dictionary word suggestion")
    }
}
