import Testing
@testable import CodaCore

@Test func spokenURLSpellingUsesExplicitSeparatorsOnly() {
    for (raw, expected) in [
        ("style.fyi slash style dash md", "style.fyi/style-md"),
        ("Style.fyi slash style dash md.", "style.fyi/style-md"),
        ("Style.fyi, slash style, dash md.", "style.fyi/style-md"),
        ("Use style.fyi slash style dash md and send it.", "Use style.fyi/style-md and send it."),
        ("example dot com slash docs slash README dot md", "example.com/docs/README.md"),
        ("https colon slash slash example dot com slash Docs", "https://example.com/Docs"),
        ("https://example.com slash Docs slash v2 dot html", "https://example.com/Docs/v2.html"),
        ("Open www dot example dot org forward slash my underscore file hyphen name", "Open www.example.org/my_file-name"),
        ("example.com slash search question mark q equals voice ampersand mode equals smart", "example.com/search?q=voice&mode=smart"),
        ("example.com slash docs hash intro", "example.com/docs#intro"),
        ("example.com slash docs hash sign intro", "example.com/docs#intro"),
        ("example.com slash docs. Hello there.", "example.com/docs. Hello there."),
        ("😀 example.com slash café dash md", "😀 example.com/café-md"),
        ("Visit example.com / docs / Readme.md", "Visit example.com/docs/Readme.md"),
        ("example.com slash docs and example.org slash about", "example.com/docs and example.org/about"),
        ("Visit example . com", "Visit example.com"),
        ("Visit use dot net slash docs", "Visit use.net/docs"),
    ] { #expect(SpokenURL.normalize(raw) == expected, "\(raw)") }
}

@Test func URLFormattingPreservesLiteralTextAndExistingURLs() {
    for raw in ["A slash separates alternatives and a dash separates clauses.",
                "Put a dot in the middle.", "Keep README.md slash docs unchanged.",
                "Say exactly style.fyi slash style dash md", "`style.fyi slash style dash md`",
                "\"example.com slash docs\"", "Keep https://Example.com/Docs/README.md?q=A%2FB#Top.",
                "Keep ‘example.com slash docs’ unchanged.",
                "Email user@example.com slash docs", "Visit example.com and send a dash of salt.",
                "example.com dash a useful site", "example.com slash", "3.14 slash two"] {
        #expect(SpokenURL.normalize(raw) == raw, "\(raw)")
    }
    for raw in ["We use dot net for this project.", "Learn dot net today.",
                "A cloud. Me too.", "Keep it. It is ready.", "1. AI is useful."] {
        #expect(SpokenURL.normalize(raw) == raw, "\(raw)")
    }
}
