import Foundation
import Testing
@testable import CodaCore

private func styled(_ text: String, _ style: DictationWritingStyle) -> String { DictationStyleFormatter.apply(text, style: style) }

// MARK: Styles

@Test func preserveStyleReturnsExactInput() {
    for text in ["  hello   world ", "ok.", "i think so", "\n\n", "", "Line one\n\n\n\nline two  "] {
        #expect(styled(text, .preserve) == text)
    }
}

@Test func formalCapitalizesAndClosesWithoutRewording() {
    #expect(styled("  hello there.  how are you   ", .formal) == "Hello there. How are you.")
    #expect(styled("i think i'm ready and i've checked", .formal) == "I think I'm ready and I've checked.")
    #expect(styled("is it ready?", .formal) == "Is it ready?")
    #expect(styled("send it , please", .formal) == "Send it, please.")
    // Contractions and abbreviations stay; no grammar is invented.
    #expect(styled("we can't go, etc. and so on", .formal) == "We can't go, etc. and so on.")
    #expect(styled("first line\nsecond line", .formal) == "First line\nSecond line.")
}

@Test func promptTidiesWithoutAddingPunctuation() {
    #expect(styled("  write a function   that sorts a list ", .prompt) == "Write a function that sorts a list")
    #expect(styled("explain this. then i want tests", .prompt) == "Explain this. Then I want tests")
}

@Test func casualDropsOnlyALoneFinalPeriod() {
    #expect(styled("Okay sounds good.", .casual) == "okay sounds good")
    #expect(styled("Karthik will call.", .casual) == "Karthik will call")
    #expect(styled("I will call.", .casual) == "I will call")
    #expect(styled("Done. Thanks.", .casual) == "Done. Thanks.")
    #expect(styled("Wait...", .casual) == "Wait...")
    #expect(styled("Really?", .casual) == "Really?")
}

@Test func stylesLeaveProtectedSyntaxUntouched() {
    let cases = [
        "run `npm  test` now", "open https://example.com/a  b", "email me at karth@example.com",
        "edit file.swift  later", "he said \"i  am here\" yesterday", "see ~/Code/app now",
        "use snake_case names", "```\nlet x  = 1\n```"
    ]
    for text in cases {
        for style in DictationWritingStyle.allCases {
            let output = styled(text, style)
            for part in DictationStyleFormatter.segments(text) where part.protected {
                #expect(output.contains(part.text), Comment(rawValue: "\(style): \(text) -> \(output)"))
            }
        }
    }
    #expect(styled("file.swift is broken", .formal) == "file.swift is broken.")
    #expect(styled("go to https://example.com", .formal) == "Go to https://example.com")
}

@Test func stylesNeverLoseOrReorderWords() {
    let samples = [
        "um so i think we should, like, ship it tomorrow", "no no no", "The the cat", "Hello. hello. HELLO",
        "  call   Ana at 5 pm  ", "i.e. this is fine", "why? because! ok.", "naïve café résumé", "100 % done",
        "first\n\n\n\nsecond", "- bullet one\n- bullet two", "(aside) ok", "dear sir , i write"
    ]
    for text in samples {
        for style in DictationWritingStyle.allCases {
            let output = styled(text, style)
            #expect(DictationStyleFormatter.words(output) == DictationStyleFormatter.words(text), Comment(rawValue: "\(style): \(output)"))
            #expect(!output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }
    let long = String(repeating: "a ", count: DictationStyleFormatter.characterLimit)
    #expect(styled(long, .formal) == long)
    #expect(styled("   ", .formal) == "   ")
}

@Test func preserveCopyDescribesCleanupFormatting() {
    #expect(DictationWritingStyle.preserve.title == "Keep formatting")
    #expect(DictationWritingStyle.preserve.summary == "Keep the formatting produced by your cleanup mode.")
    #expect(Set(DictationWritingStyle.allCases.map(\.title)).count == DictationWritingStyle.allCases.count)
}

// MARK: Snippets

@Test func snippetsMatchOnlyTheWholeUtterance() throws {
    var settings = DictationPreferenceSettings()
    let snippet = try settings.addSnippet(trigger: "  My   Address ", expansion: "1 Infinite Loop\nCupertino").get()
    #expect(snippet.trigger == "My Address")
    for spoken in ["my address", "My address.", "  MY ADDRESS!  ", "my   address?", "“my address”"] {
        #expect(DictationSnippets.match(spoken, in: settings.snippets)?.id == snippet.id, Comment(rawValue: spoken))
    }
    for spoken in ["send my address", "my address please", "my addresses", "myaddress", "my-address", "", "  .  "] {
        #expect(DictationSnippets.match(spoken, in: settings.snippets) == nil, Comment(rawValue: spoken))
    }
    let result = DictationPersonalization.apply("My address.", bundleID: nil, settings: settings)
    #expect(result.text == "1 Infinite Loop\nCupertino")
    #expect(result.snippet?.id == snippet.id)
    // Expansions are inserted as text, never formatted or executed.
    _ = settings.addSnippet(trigger: "shell", expansion: "rm -rf $HOME  ")
    settings.globalStyle = .formal
    #expect(DictationPersonalization.apply("Shell.", bundleID: nil, settings: settings).text == "rm -rf $HOME  ")
    #expect(DictationPersonalization.apply("run shell", bundleID: nil, settings: settings).text == "Run shell.")
}

@Test func snippetValidationAndDeterministicEditing() throws {
    var settings = DictationPreferenceSettings()
    #expect(settings.addSnippet(trigger: "   ", expansion: "x") == .failure(.emptyTrigger))
    #expect(settings.addSnippet(trigger: "?!", expansion: "x") == .failure(.emptyTrigger))
    #expect(settings.addSnippet(trigger: "a", expansion: "x") == .failure(.triggerNeedsLetters))
    #expect(settings.addSnippet(trigger: "one\ntwo", expansion: "x") == .failure(.triggerHasLineBreak))
    #expect(settings.addSnippet(trigger: "a b c d e f g h i", expansion: "x") == .failure(.triggerTooLong))
    #expect(settings.addSnippet(trigger: String(repeating: "x", count: 61), expansion: "x") == .failure(.triggerTooLong))
    #expect(settings.addSnippet(trigger: "sign off", expansion: " \n ") == .failure(.emptyExpansion))
    #expect(settings.addSnippet(trigger: "sign off", expansion: String(repeating: "x", count: 5_001)) == .failure(.expansionTooLong))
    #expect(settings.snippets.isEmpty)

    let first = try settings.addSnippet(trigger: "Sign off", expansion: "Best,\nK").get()
    #expect(settings.addSnippet(trigger: "sign OFF.", expansion: "other") == .failure(.duplicateTrigger(existing: "Sign off")))
    let second = try settings.addSnippet(trigger: "calendar link", expansion: "https://cal.example/k").get()
    #expect(settings.updateSnippet(second.id, trigger: "sign off") == .failure(.duplicateTrigger(existing: "Sign off")))
    // Editing a snippet's own trigger casing is not a duplicate.
    #expect(try settings.updateSnippet(first.id, trigger: "SIGN OFF").get().trigger == "SIGN OFF")
    #expect(try settings.updateSnippet(first.id, expansion: "Thanks,\nK").get().expansion == "Thanks,\nK")
    #expect(settings.updateSnippet(UUID(), expansion: "x") == .failure(.notFound))
    #expect(settings.snippets.map(\.id) == [first.id, second.id])
    let removed = settings.removeSnippet(first.id), removedAgain = settings.removeSnippet(first.id)
    #expect(removed && !removedAgain)
    #expect(DictationSnippets.match("sign off", in: settings.snippets) == nil)

    var full = DictationPreferenceSettings()
    for index in 0..<DictationSnippets.snippetLimit { _ = full.addSnippet(trigger: "phrase \(index)", expansion: "x") }
    #expect(full.snippets.count == DictationSnippets.snippetLimit)
    #expect(full.addSnippet(trigger: "one more", expansion: "x") == .failure(.tooManySnippets))
}

// MARK: Per-app rules

@Test func perAppRulesFallBackToGlobalStyle() throws {
    var settings = DictationPreferenceSettings(globalStyle: .formal)
    let rule = try settings.setRule(bundleID: " com.tinyspeck.slackmacgap ", appName: "Slack", style: .casual).get()
    #expect(rule.bundleID == "com.tinyspeck.slackmacgap")
    #expect(settings.style(forBundleID: "com.tinyspeck.slackmacgap") == .casual)
    #expect(settings.style(forBundleID: "COM.TinySpeck.SlackMacGap") == .casual)
    #expect(settings.style(forBundleID: "com.tinyspeck") == .formal)
    #expect(settings.style(forBundleID: "com.apple.mail") == .formal)
    #expect(settings.style(forBundleID: nil) == .formal)
    #expect(settings.style(forBundleID: "") == .formal)

    // Setting an existing app again updates in place rather than duplicating.
    _ = settings.setRule(bundleID: "COM.tinyspeck.slackmacgap", style: .prompt)
    #expect(settings.appRules.count == 1)
    #expect(settings.appRules[0].appName == "Slack")
    #expect(settings.style(forBundleID: "com.tinyspeck.slackmacgap") == .prompt)

    #expect(settings.setRule(bundleID: "not a bundle", style: .casual) == .failure(.invalidBundleID("not a bundle")))
    #expect(settings.setRule(bundleID: "slack", style: .casual) == .failure(.invalidBundleID("slack")))
    let mail = try settings.setRule(bundleID: "com.apple.mail", style: .formal).get()
    #expect(settings.updateRule(mail.id, bundleID: "com.tinyspeck.slackmacgap") == .failure(.duplicateApp("Slack")))
    #expect(try settings.updateRule(mail.id, style: .preserve).get().style == .preserve)
    let removedRule = settings.removeRule(rule.id)
    #expect(removedRule)
    #expect(settings.style(forBundleID: "com.tinyspeck.slackmacgap") == .formal)

    settings.globalStyle = .preserve
    #expect(DictationPersonalization.apply("hi there", bundleID: "com.apple.mail", settings: settings).text == "hi there")
}

// MARK: Decoding and persistence

@Test func decodingKeepsValidEntriesAndReportsInvalidOnes() throws {
    let json = """
    {"globalStyle": "shouty",
     "appRules": [
       {"bundleID": "com.apple.mail", "style": "formal"},
       {"bundleID": "COM.APPLE.MAIL", "style": "casual"},
       {"bundleID": "bad id", "style": "casual"},
       {"bundleID": "com.apple.notes", "style": "unknown"},
       42
     ],
     "snippets": [
       {"trigger": "sign off", "expansion": "Best"},
       {"trigger": "Sign Off!", "expansion": "dup"},
       {"trigger": "", "expansion": "empty"},
       {"trigger": "no expansion"}
     ],
     "futureField": true}
    """
    let loaded = try DictationPreferenceSettings.decode(Data(json.utf8))
    #expect(loaded.settings.globalStyle == .preserve)
    #expect(loaded.settings.appRules.map(\.bundleID) == ["com.apple.mail"])
    #expect(loaded.settings.snippets.map(\.trigger) == ["sign off"])
    #expect(loaded.issues.count == 8)
    #expect(loaded.issues.contains(.unknownGlobalStyle("shouty")))
    #expect(loaded.issues.contains(.duplicateRule(bundleID: "COM.APPLE.MAIL")))
    #expect(loaded.issues.contains(.unreadableRule(index: 4)))
    #expect(loaded.issues.contains(.unreadableSnippet(index: 3)))

    // Older files with missing keys take defaults without issues.
    let empty = try DictationPreferenceSettings.decode(Data("{}".utf8))
    #expect(empty.settings == DictationPreferenceSettings())
    #expect(empty.issues.isEmpty)
    #expect(throws: DictationPreferenceSettings.LoadFailure.newerVersion(9)) { try DictationPreferenceSettings.decode(Data(#"{"version": 9}"#.utf8)) }
    #expect(throws: (any Error).self) { try DictationPreferenceSettings.decode(Data("[1, 2]".utf8)) }
    #expect(throws: (any Error).self) { try DictationPreferenceSettings.decode(Data("not json".utf8)) }
}

@Test func storeRoundTripsWithOwnerOnlyAtomicFiles() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("Coda-DictationPreferences-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: root) }
    let store = try DictationPreferenceStore(root: root)
    #expect(try store.load() == nil)

    var settings = DictationPreferenceSettings(globalStyle: .casual)
    _ = settings.setRule(bundleID: "com.apple.mail", appName: "Mail", style: .formal)
    _ = settings.addSnippet(trigger: "sign off", expansion: "Best,\n  K ")
    try store.save(settings)
    let loaded = try #require(try store.load())
    #expect(loaded.settings == settings)
    #expect(loaded.issues.isEmpty)

    let permissions = { (url: URL) in (try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber)?.intValue }
    #expect(try permissions(store.file) == 0o600)
    #expect(try permissions(root) == 0o700)
    let leftovers = try FileManager.default.contentsOfDirectory(atPath: root.path).filter { $0.hasSuffix(".tmp") }
    #expect(leftovers.isEmpty)

    let copy = try #require(try store.preserveCurrentFile(now: Date(timeIntervalSince1970: 100)))
    let second = try #require(try store.preserveCurrentFile(now: Date(timeIntervalSince1970: 100)))
    #expect(copy != second)
    #expect(try Data(contentsOf: copy) == Data(contentsOf: store.file))
    #expect(try permissions(copy) == 0o600)
}
