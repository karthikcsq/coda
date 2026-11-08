import SwiftUI
import AppKit
import UniformTypeIdentifiers
import CodaCore

private typealias PersonalState<Value> = SwiftUI.State<Value>

struct PersonalizationPage: View {
    @Bindable var model: AppModel
    @Bindable var controller: DictationController
    @PersonalState private var appError: String?
    @PersonalState private var editingSnippet: UUID?
    @PersonalState private var trigger = ""
    @PersonalState private var expansion = ""
    @PersonalState private var tab = "Writing style"
    init(model: AppModel, controller: DictationController, initialTab: String = "Writing style") {
        self.model = model; self.controller = controller
        _tab = PersonalState(initialValue: initialTab)
    }
    private var preferences: DictationPreferences { controller.preferences }
    private var locked: Bool { model.settingsChangesLocked || !preferences.isEditable }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                CodaPageHeader(icon: "slider.horizontal.3", title: "Make it yours", subtitle: "Writing preferences and reusable phrases, stored on this Mac.")
                Picker("Personalization", selection: $tab) {
                    Text("Writing style").tag("Writing style")
                    Text("Voice snippets").tag("Voice snippets")
                }.pickerStyle(.segmented).frame(maxWidth: 380)
                if let appError { CodaNotice(kind: .caution, text: appError) }
                if let error = preferences.error {
                    CodaNotice(kind: .caution, text: error)
                    if !preferences.isEditable {
                        Button("Reset settings and preserve original file") { preferences.resetPreservingFile() }
                            .buttonStyle(CodaSecondaryButtonStyle()).disabled(model.settingsChangesLocked)
                    }
                }
                if let notice = preferences.notice { CodaNotice(kind: .info, text: notice) }
                if controller.cleanupMode == .none {
                    CodaNotice(kind: .info, text: "Raw mode is on. Styles and snippets apply with Light or Smart cleanup. Choose a cleanup mode in Settings to use them.")
                }
                if tab == "Writing style" { styles; appRules }
                else { snippetEditor; snippetList }
            }.codaPageInsets()
        }
    }
    private var styles: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Default writing style").font(CodaStyle.sectionFont)
            Text("Only spacing, capitals and punctuation change. Your words stay in their original order. Choose an override below for apps that need a different style.")
                .font(CodaStyle.bodyFont).foregroundStyle(CodaStyle.muted).fixedSize(horizontal: false, vertical: true)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(DictationWritingStyle.allCases) { style in
                    Button { preferences.setGlobalStyle(style) } label: {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text(style.title).font(CodaStyle.sectionFont)
                                Spacer()
                                Image(systemName: preferences.globalStyle == style ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(preferences.globalStyle == style ? CodaStyle.mint : CodaStyle.muted)
                            }
                            Text(style.summary).font(CodaStyle.secondaryFont).foregroundStyle(CodaStyle.muted)
                                .fixedSize(horizontal: false, vertical: true).frame(minHeight: 34, alignment: .top)
                            Text(example(style)).font(.system(size: 13, design: .monospaced)).foregroundStyle(CodaStyle.mint)
                                .lineLimit(2).frame(minHeight: 34, alignment: .topLeading)
                        }.padding(18).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                            .background(preferences.globalStyle == style ? CodaStyle.mint.opacity(0.06) : CodaStyle.raised, in: RoundedRectangle(cornerRadius: 12))
                            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(preferences.globalStyle == style ? CodaStyle.mint.opacity(0.45) : CodaStyle.hairline))
                    }.buttonStyle(.plain).disabled(locked).accessibilityAddTraits(preferences.globalStyle == style ? .isSelected : [])
                }
            }
        }
    }
    private func example(_ style: DictationWritingStyle) -> String {
        DictationStyleFormatter.apply("Okay, i can send it today.", style: style)
    }
    private var appRules: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Per-app preferences").font(CodaStyle.sectionFont)
                Spacer()
                Button { chooseApp() } label: { Label("Add app", systemImage: "plus") }
                    .buttonStyle(CodaSecondaryButtonStyle()).disabled(locked || model.isVisualReview)
            }
            if preferences.appRules.isEmpty {
                CodaEmptyState(icon: "app.badge", title: "A different style for a different app", message: "Choose an app, then set its style. Everything else follows your default.")
            } else {
                VStack(spacing: 0) {
                    ForEach(preferences.appRules) { rule in
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(rule.appName ?? rule.bundleID).font(CodaStyle.rowTitleFont)
                                Text(rule.bundleID).font(CodaStyle.captionFont).foregroundStyle(CodaStyle.muted)
                            }
                            Spacer(minLength: 10)
                            Picker("Style for " + (rule.appName ?? rule.bundleID), selection: Binding(get: { rule.style }, set: { preferences.updateRule(rule.id, style: $0) })) {
                                ForEach(DictationWritingStyle.allCases) { Text($0.title).tag($0) }
                            }.labelsHidden().frame(width: 160).disabled(locked)
                            Button { preferences.removeRule(rule.id) } label: { Image(systemName: "minus.circle") }
                                .buttonStyle(CodaIconButtonStyle()).disabled(locked).accessibilityLabel("Remove preference for " + (rule.appName ?? rule.bundleID))
                        }.padding(14)
                        if rule.id != preferences.appRules.last?.id { Divider().opacity(0.4) }
                    }
                }.background(CodaStyle.raised, in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(CodaStyle.hairline))
            }
        }
    }
    private var snippetEditor: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(editingSnippet == nil ? "Create a voice snippet" : "Edit voice snippet").font(CodaStyle.sectionFont)
                Spacer()
                if editingSnippet != nil { Button("Cancel edit") { clearEditor() }.buttonStyle(CodaQuietButtonStyle()) }
            }
            Text("Say the trigger as a whole dictation to insert your saved text. For example, “my sign off” can insert your full email signature.")
                .font(CodaStyle.bodyFont).foregroundStyle(CodaStyle.muted).fixedSize(horizontal: false, vertical: true)
            TextField("Trigger, e.g. my sign off", text: $trigger).textFieldStyle(.roundedBorder).disabled(locked)
                .accessibilityLabel("Spoken snippet trigger")
            TextEditor(text: $expansion).font(.system(size: 14)).scrollContentBackground(.hidden)
                .padding(10).frame(minHeight: 100, maxHeight: 160)
                .background(CodaStyle.sunken, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(CodaStyle.strongEdge))
                .accessibilityLabel("Text to insert for this snippet").disabled(locked)
            HStack {
                Text("Inserted as plain text. Nothing is executed.").font(CodaStyle.secondaryFont).foregroundStyle(CodaStyle.muted)
                Spacer()
                Button(editingSnippet == nil ? "Add snippet" : "Save changes") { saveSnippet() }
                    .buttonStyle(CodaPrimaryButtonStyle()).disabled(locked || preferences.problem(trigger: trigger, expansion: expansion, editing: editingSnippet) != nil)
            }
            if !trigger.isEmpty, let problem = preferences.problem(trigger: trigger, expansion: expansion, editing: editingSnippet) {
                Text(problem).font(CodaStyle.secondaryFont).foregroundStyle(CodaStyle.caution)
            }
        }.codaCard()
    }
    private var snippetList: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack { Text("Your snippets").font(CodaStyle.sectionFont); CodaCountBadge(count: preferences.snippets.count) }
            if preferences.snippets.isEmpty {
                CodaEmptyState(icon: "text.badge.plus", title: "Keep your useful phrases close", message: "Add a signature, address, introduction or any text you type often.")
            } else {
                ForEach(preferences.snippets) { snippet in
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("“" + snippet.trigger + "”").font(CodaStyle.sectionFont).foregroundStyle(CodaStyle.mint)
                            Spacer()
                            Button("Edit") { editingSnippet = snippet.id; trigger = snippet.trigger; expansion = snippet.expansion }
                                .buttonStyle(CodaQuietButtonStyle()).disabled(locked)
                            Button { preferences.removeSnippet(snippet.id); if editingSnippet == snippet.id { clearEditor() } } label: { Image(systemName: "trash") }
                                .buttonStyle(CodaIconButtonStyle()).disabled(locked).accessibilityLabel("Delete snippet " + snippet.trigger)
                        }
                        Text(snippet.expansion).font(CodaStyle.bodyFont).foregroundStyle(CodaStyle.muted).lineLimit(4).textSelection(.enabled)
                    }.codaCard(padding: 18)
                }
            }
        }
    }
    private func clearEditor() { editingSnippet = nil; trigger = ""; expansion = ""; preferences.clearError() }
    private func saveSnippet() {
        let saved: Bool
        if let id = editingSnippet { saved = preferences.updateSnippet(id, trigger: trigger, expansion: expansion) }
        else { saved = preferences.addSnippet(trigger: trigger, expansion: expansion) }
        if saved { clearEditor() }
    }
    private func chooseApp() {
        guard !locked, !model.isVisualReview else { return }
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.applicationBundle]; panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications"); panel.message = "Choose an app to give it its own writing style."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let bundle = Bundle(url: url), let id = bundle.bundleIdentifier else {
            appError = "This app has no usable identifier. Choose another app."; return
        }
        appError = nil
        let name = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? url.deletingPathExtension().lastPathComponent
        preferences.setStyle(preferences.globalStyle, forBundleID: id, appName: name)
    }
}
