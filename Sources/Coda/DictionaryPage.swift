import SwiftUI
import CodaCore

private typealias DictionaryState<Value> = SwiftUI.State<Value>

struct DictionaryPage: View {
    @Bindable var controller: DictationController
    @DictionaryState private var query = ""
    @DictionaryState private var adding = false
    @DictionaryState private var editing: CustomWord?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let mint = Color(red: 0.62, green: 0.86, blue: 0.76)
    private var dictionary: CustomDictionary { controller.dictionary }
    private func matches(_ word: CustomWord) -> Bool {
        query.isEmpty || word.word.localizedCaseInsensitiveContains(query) || word.original?.localizedCaseInsensitiveContains(query) == true
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                HStack(spacing: 14) {
                    Image(systemName: "character.book.closed").font(.system(size: 24, weight: .light)).foregroundStyle(mint)
                        .frame(width: 50, height: 50).background(mint.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Dictionary").font(.system(size: 28, weight: .medium, design: .rounded))
                        Text("\(dictionary.approved.count) custom \(dictionary.approved.count == 1 ? "word" : "words")").font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button { adding = true } label: {
                        Label("Add word", systemImage: "plus").font(.system(size: 12, weight: .semibold))
                            .padding(.horizontal, 15).frame(height: 36).background(mint, in: Capsule()).foregroundStyle(Color(white: 0.1))
                    }.buttonStyle(.plain).accessibilityIdentifier("coda.dictionary.add")
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
                }.padding(20).background(Color.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.white.opacity(0.06)))
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Search your dictionary", text: $query).textFieldStyle(.plain).font(.system(size: 13))
                    if !query.isEmpty {
                        Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                            .buttonStyle(.plain).accessibilityLabel("Clear dictionary search")
                    }
                }.padding(.horizontal, 14).frame(height: 42).background(Color.white.opacity(0.025), in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.white.opacity(0.09)))
                if let error = dictionary.error { Label(error, systemImage: "exclamationmark.triangle").font(.callout).foregroundStyle(.orange) }
                section("Possible custom words", words: dictionary.possible.filter(matches), possible: true)
                section("Custom words", words: dictionary.approved.filter(matches), possible: false)
            }.padding(36).frame(maxWidth: .infinity, alignment: .leading)
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: dictionary.words)
        }.accessibilityIdentifier("coda.dictionary.page")
            .sheet(isPresented: $adding) { DictionaryWordEditor(dictionary: dictionary, word: nil) }
            .sheet(item: $editing) { word in DictionaryWordEditor(dictionary: dictionary, word: word) }
    }
    private func section(_ title: String, words: [CustomWord], possible: Bool) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 9) {
                Text(title).font(.system(size: 15, weight: .semibold))
                Text("\(words.count)").font(.system(size: 11, weight: .medium)).foregroundStyle(possible ? mint : Color.secondary)
                    .padding(.horizontal, 7).padding(.vertical, 3).background((possible ? mint : Color.white).opacity(0.08), in: Capsule())
            }
            if words.isEmpty {
                HStack(spacing: 13) {
                    Image(systemName: query.isEmpty ? (possible ? "checkmark.circle" : "textformat.abc") : "magnifyingglass")
                        .font(.system(size: 23, weight: .light)).foregroundStyle(possible ? mint : Color.secondary)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(query.isEmpty ? (possible ? "No words to review" : "No custom words yet") : "No matching words").font(.system(size: 13, weight: .medium))
                        Text(query.isEmpty ? (possible ? (controller.learnWords ? "Correct a name or unfamiliar term after dictating to suggest it here." : "Turn learning on to suggest words from your corrections.") : "Add names, technical terms and phrases you use often.") : "Try another spelling.")
                            .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                }.padding(22).frame(maxWidth: .infinity, alignment: .leading)
                    .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.white.opacity(0.07)))
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
                }.background(Color.white.opacity(0.02), in: RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.white.opacity(0.08)))
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
