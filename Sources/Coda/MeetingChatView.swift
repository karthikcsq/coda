import SwiftUI
import CodaCore

private typealias ChatState<Value> = SwiftUI.State<Value>

/// Ask Codex follow-up questions about a meeting's summary. Timestamps in answers link back to the transcript.
struct MeetingChatView: View {
    @Bindable var model: AppModel
    let meeting: Meeting
    /// Shows a cited transcript segment, switching to the Transcript tab.
    var onCite: (String) -> Void
    @ChatState private var draft = ""
    @FocusState private var composerFocused: Bool

    private var messages: [ChatMessage] { model.chats[meeting.id] ?? [] }
    private var pending: Bool { model.chatPending.contains(meeting.id) }
    private var canSend: Bool { !pending && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    static let suggestions = ["What are my action items?", "What's still undecided?", "Draft a follow-up email", "What did the summary leave out?"]

    var body: some View {
        if meeting.summary == nil {
            ScrollView {
                CodaEmptyState(icon: "bubble.left.and.text.bubble.right", title: "Summarize first",
                               message: "Chat answers questions about this meeting's AI summary, checked against the transcript. Generate a summary to start.",
                               tint: CodaStyle.mint) {
                    Button("Summarize with OpenAI…") { model.showSummaryConsent = true }
                        .buttonStyle(CodaPrimaryButtonStyle()).disabled(model.isOccupied).padding(.top, 10)
                }
                .padding(.top, 24).codaColumn()
            }
        } else {
            VStack(spacing: 0) {
                conversation
                Rectangle().fill(CodaStyle.hairline).frame(height: 1)
                composer.padding(.vertical, 14).codaColumn()
            }
        }
    }

    private var conversation: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(spacing: 8) {
                        Image(systemName: "sparkles").font(.system(size: 11)).foregroundStyle(CodaStyle.mint)
                        Text("Answers come from Codex using this meeting's summary and transcript. Check cited timestamps.")
                            .font(CodaStyle.secondaryFont).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 12)
                        if !messages.isEmpty {
                            Button("Clear") { model.clearChat() }.buttonStyle(CodaQuietButtonStyle()).disabled(pending)
                        }
                    }
                    if messages.isEmpty && !pending { suggestionList }
                    ForEach(messages) { message in bubble(message).id(message.id) }
                    if pending { thinking.id("pending") }
                    if let error = model.chatErrors[meeting.id] { CodaNotice(kind: .caution, text: error).id("error") }
                    Color.clear.frame(height: 1).id("end")
                }
                .padding(.top, 22).padding(.bottom, 24)
                .codaColumn()
            }
            .onAppear { proxy.scrollTo("end", anchor: .bottom) }
            .onChange(of: messages.count) { _, _ in withAnimation { proxy.scrollTo("end", anchor: .bottom) } }
            .onChange(of: pending) { _, _ in withAnimation { proxy.scrollTo("end", anchor: .bottom) } }
        }
    }

    private var suggestionList: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Ask about this meeting").font(CodaStyle.sectionFont)
            CodaFlowLayout(spacing: 8) {
                ForEach(Self.suggestions, id: \.self) { suggestion in
                    Button(suggestion) { send(suggestion) }.buttonStyle(CodaSecondaryButtonStyle())
                }
            }
        }
    }

    @ViewBuilder private func bubble(_ message: ChatMessage) -> some View {
        if message.role == .user {
            HStack {
                Spacer(minLength: 120)
                Text(message.text).font(CodaStyle.bodyFont).foregroundStyle(CodaStyle.ink)
                    .lineSpacing(3).textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(CodaStyle.selected, in: RoundedRectangle(cornerRadius: CodaStyle.radius))
            }
            .accessibilityElement(children: .combine).accessibilityLabel("You: " + message.text)
        } else {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "sparkles").font(.system(size: 12)).foregroundStyle(CodaStyle.mint)
                    .frame(width: 24, height: 24).background(CodaStyle.mint.opacity(0.12), in: Circle())
                    .accessibilityHidden(true)
                Text(Self.rendered(message.text, meeting: meeting))
                    .font(CodaStyle.bodyFont).foregroundStyle(CodaStyle.ink)
                    .tint(CodaStyle.mint).lineSpacing(4).textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .environment(\.openURL, OpenURLAction { url in
                        guard url.scheme == "coda-segment", let id = url.host() else { return .systemAction }
                        onCite(id); return .handled
                    })
                Spacer(minLength: 40)
            }
            .accessibilityElement(children: .contain).accessibilityLabel("Codex: " + message.text)
        }
    }

    private var thinking: some View {
        HStack(spacing: 10) {
            ProgressView().controlSize(.small)
            Text("Codex is reading the meeting…").font(CodaStyle.secondaryFont).foregroundStyle(.secondary)
            Button("Stop") { model.cancelChat() }.buttonStyle(CodaQuietButtonStyle())
        }
        .padding(.leading, 36)
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField("Ask about this meeting…", text: $draft, axis: .vertical)
                .textFieldStyle(.plain).font(CodaStyle.bodyFont).lineLimit(1...5)
                .focused($composerFocused)
                .onSubmit { send(draft) }
                .padding(.horizontal, 14).padding(.vertical, 9)
                .background(CodaStyle.raised, in: RoundedRectangle(cornerRadius: CodaStyle.radius))
                .overlay(RoundedRectangle(cornerRadius: CodaStyle.radius).strokeBorder(composerFocused ? CodaStyle.strongEdge : CodaStyle.hairline))
                .accessibilityLabel("Question about this meeting")
            Button { send(draft) } label: { Image(systemName: "arrow.up").font(.system(size: 13, weight: .bold)) }
                .buttonStyle(CodaPrimaryButtonStyle()).disabled(!canSend)
                .keyboardShortcut(.return, modifiers: .command)
                .accessibilityLabel("Send question")
        }
    }

    private func send(_ text: String) {
        guard !pending, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        model.askChat(text)
        draft = ""
    }

    /// Markdown answer, with `[mm:ss]` citations turned into links to the matching transcript segment.
    nonisolated static func rendered(_ text: String, meeting: Meeting) -> AttributedString {
        let linked = linkCitations(text, segments: meeting.segments)
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: linked, options: options)) ?? AttributedString(text)
    }

    nonisolated static func linkCitations(_ text: String, segments: [Segment]) -> String {
        guard let pattern = try? Regex(#"\[((?:\d{1,2}:)?\d{1,2}:\d{2})\](?!\()"#) else { return text }
        return text.replacing(pattern) { match in
            let stamp = String(text[match.range]).trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
            guard let segment = segment(at: stamp, in: segments) else { return String(text[match.range]) }
            return "[\(stamp)](coda-segment://\(segment.id))"
        }
    }

    /// Exact timestamp first; otherwise the segment in progress at that moment.
    nonisolated static func segment(at stamp: String, in segments: [Segment]) -> Segment? {
        if let exact = segments.first(where: { timestamp($0.start) == stamp }) { return exact }
        let parts = stamp.split(separator: ":").compactMap { Double($0) }
        guard parts.count >= 2 else { return nil }
        let seconds = parts.reduce(0) { $0 * 60 + $1 }
        return segments.last { $0.start <= seconds + 0.999 }
    }
}
