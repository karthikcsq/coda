import SwiftUI
import CodaCore

private typealias DictionaryState<Value> = SwiftUI.State<Value>

struct DictionaryPage: View {
    @Bindable var controller: DictationController
    @DictionaryState private var query = ""
    @DictionaryState private var adding = false
    @DictionaryState private var editing: CustomWord?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let mint = CodaStyle.mint
    private var dictionary: CustomDictionary { controller.dictionary }
    private func matches(_ word: CustomWord) -> Bool {
        query.isEmpty || word.word.localizedCaseInsensitiveContains(query) || word.original?.localizedCaseInsensitiveContains(query) == true
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                CodaPageHeader(icon: "character.book.closed", title: "Dictionary",
                               subtitle: "\(dictionary.approved.count) custom \(dictionary.approved.count == 1 ? "word" : "words") guiding recognition on this Mac.") {
                    Button { adding = true } label: { Label("Add word", systemImage: "plus") }
                        .buttonStyle(CodaPrimaryButtonStyle()).accessibilityIdentifier("coda.dictionary.add")
                }
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 13) {
                        Image(systemName: "sparkles").foregroundStyle(mint).font(.system(size: 19))
                        VStack(alignment: .leading, spacing: 5) {
                            Text("Learn from corrections").font(.system(size: 14, weight: .medium))
                            Text(controller.learnWords ? "New spellings appear in a pop-up for you to review." : "Learning is paused. Your custom words still apply.")
                                .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 12)
                        Toggle("Learn from corrections", isOn: $controller.learnWords).labelsHidden().toggleStyle(.switch).tint(mint)
                    }
                    DisclosureGroup("How learning works") {
                        Text("Coda watches the field it just dictated into for up to 60 seconds. Small spelling corrections become suggestions. Add a word to guide future dictations, or dismiss it to stop seeing that spelling. Some editors do not expose text changes through Accessibility.")
                            .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true).padding(.top, 8)
                    }.font(.system(size: 11)).foregroundStyle(.secondary)
                }.codaCard(padding: 20)
                CodaSearchField(prompt: "Search your dictionary", text: $query)
                if let error = dictionary.error { CodaNotice(kind: .caution, text: error) }
                section("Possible custom words", words: dictionary.possible.filter(matches), possible: true)
                section("Custom words", words: dictionary.approved.filter(matches), possible: false)
            }.codaPageInsets()
                .animation(CodaStyle.motion(reduceMotion, duration: 0.22), value: dictionary.words)
        }.accessibilityIdentifier("coda.dictionary.page")
            .sheet(isPresented: $adding) { DictionaryWordEditor(dictionary: dictionary, word: nil) }
            .sheet(item: $editing) { word in DictionaryWordEditor(dictionary: dictionary, word: word) }
    }
    private func section(_ title: String, words: [CustomWord], possible: Bool) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 9) {
                Text(title).font(CodaStyle.sectionFont)
                CodaCountBadge(count: words.count, tint: possible ? mint : CodaStyle.muted)
            }
            if words.isEmpty {
                CodaEmptyState(
                    icon: query.isEmpty ? (possible ? "checkmark.circle" : "textformat.abc") : "magnifyingglass",
                    title: query.isEmpty ? (possible ? "No words to review" : "No custom words yet") : "No matching words",
                    message: query.isEmpty ? (possible ? (controller.learnWords ? "Correct a name or unfamiliar term after dictating to suggest it here." : "Turn learning on to suggest words from your corrections.") : "Add names, technical terms and phrases you use often.") : "Try another spelling.",
                    tint: possible ? mint : CodaStyle.muted)
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(words) { word in
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 7) {
                                Text(word.word).font(.system(size: 15, weight: .medium)).textSelection(.enabled).lineLimit(2)
                                if let original = word.original {
                                    HStack(spacing: 6) {
                                        Text(original).strikethrough().lineLimit(1)
                                        Image(systemName: "arrow.right").font(.system(size: 9))
                                        Text(word.word).foregroundStyle(possible ? mint : Color.secondary).lineLimit(1)
                                    }.font(.system(size: 11)).foregroundStyle(.secondary)
                                        .accessibilityLabel("Corrected from \(original) to \(word.word)")
                                }
                            }.frame(maxWidth: .infinity, alignment: .leading)
                            if possible {
                                Button { dictionary.approve(word.id) } label: {
                                    Text("Add").font(.system(size: 12, weight: .medium)).foregroundStyle(mint)
                                        .padding(.horizontal, 14).frame(height: 30).background(mint.opacity(0.12), in: Capsule())
                                }.buttonStyle(.plain).accessibilityLabel("Add \(word.word) to custom words")
                                Button("Edit") { editing = word }.accessibilityLabel("Edit suggested word \(word.word)")
                                Button("Dismiss") { dictionary.dismiss(word.id) }.accessibilityLabel("Dismiss \(word.word)")
                            } else {
                                Button("Edit") { editing = word }.accessibilityLabel("Edit custom word \(word.word)")
                                Button("Remove") { dictionary.dismiss(word.id) }.accessibilityLabel("Remove custom word \(word.word)")
                            }
                        }.buttonStyle(.plain).font(.system(size: 12)).padding(18)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                        if word.id != words.last?.id { Divider().opacity(0.3).padding(.horizontal, 18) }
                    }
                }.background(CodaStyle.sunken, in: RoundedRectangle(cornerRadius: CodaStyle.radiusLarge))
                    .overlay(RoundedRectangle(cornerRadius: CodaStyle.radiusLarge).strokeBorder(CodaStyle.hairline))
            }
        }
    }
}

private struct DictionaryWordEditor: View {
    let dictionary: CustomDictionary
    let word: CustomWord?
    @DictionaryState private var spelling: String
    @Environment(\.dismiss) private var dismiss
    init(dictionary: CustomDictionary, word: CustomWord?) {
        self.dictionary = dictionary; self.word = word; _spelling = DictionaryState(initialValue: word?.word ?? "")
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(word == nil ? "Add custom word" : "Edit custom word").font(.title2)
            TextField("Word or phrase", text: $spelling).textFieldStyle(.roundedBorder).onSubmit(save)
                .accessibilityIdentifier("coda.dictionary.spelling")
            Text("Up to 60 characters and four words. Keep the spelling and capitalization you want to use.").font(.caption).foregroundStyle(.secondary)
            if let error = dictionary.error { Text(error).font(.callout).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true) }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button(word?.status == .approved ? "Save" : "Add word", action: save).keyboardShortcut(.defaultAction)
                    .disabled(CustomVocabulary.cleaned(spelling).isEmpty)
            }
        }.padding(28).frame(width: 430).preferredColorScheme(.dark)
    }
    private func save() {
        let saved = word.map { dictionary.approve($0.id, spelling: spelling) } ?? dictionary.add(spelling)
        if saved { dismiss() }
    }
}
