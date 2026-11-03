import Foundation

/// Explicit URL spelling only. Ordinary prose is never joined into a path.
public enum SpokenURL {
    private static let commonTLDs = Set("com org net edu gov mil int io ai app dev co fyi info biz me tv xyz tech us uk ca de fr in au nz eu it es nl ch se no fi dk jp br za ly sh gg cc site online cloud link page wiki social studio news email live store pro name world tools design software space today blog club digital academy network systems solutions".split(separator: " ").map(String.init))
    private static let label = #"[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?"#
    private static let separator = #"(?:[ \t]*\.[ \t]*|[ \t]+dot[ \t]+)"#
    private static let scheme = #"(?:https?://|https?[ \t]+colon[ \t]+(?:forward[ \t]+)?slash[ \t]+(?:forward[ \t]+)?slash[ \t]+)"#
    private static let hosts = try! NSRegularExpression(pattern:
        #"(?<![A-Za-z0-9_@./-])("# + scheme + #")?("# + label + #"(?:"# + separator + label + #"){1,4})(?![A-Za-z0-9_-])"#,
        options: [.caseInsensitive])
    private static let operation = try! NSRegularExpression(pattern:
        #"^[ \t]*(?:,[ \t]*)?(?:(forward[ \t]+slash|slash|dash|hyphen|dot|underscore|question[ \t]+mark|equals|equal[ \t]+sign|ampersand|hash[ \t]+sign|hash)[ \t]+|([/._?=&#-])[ \t]*)"#,
        options: [.caseInsensitive])
    private static let atom = try! NSRegularExpression(pattern: #"^[\p{L}\p{N}][\p{L}\p{N}._~%+-]*"#)

    public static func normalize(_ raw: String) -> String {
        guard raw.utf16.count <= 4000,
              raw.range(of: #"["“”`{}\\]|‘[^’\n]+’|(?<!\w)'[^'\n]+'(?!\w)|\b(?:say exactly|verbatim|literally|literal)\b"#,
                        options: [.regularExpression, .caseInsensitive]) == nil else { return raw }
        let source = raw as NSString
        var edits: [(NSRange, String)] = []
        var consumed = 0
        for match in hosts.matches(in: raw, range: NSRange(location: 0, length: source.length)) {
            guard match.range.location >= consumed else { continue }
            let host = source.substring(with: match.range(at: 2))
            let compactHost = host.replacingOccurrences(of: #"[ \t]+dot[ \t]+|[ \t]*\.[ \t]*"#,
                with: ".", options: [.regularExpression, .caseInsensitive]).lowercased()
            guard let tld = compactHost.split(separator: ".").last else { continue }
            let prefixRange = match.range(at: 1)
            let prefix = prefixRange.location == NSNotFound ? "" : source.substring(with: prefixRange)
            // A scheme makes an unfamiliar suffix unambiguous. Without one,
            // avoid turning code members, filenames and ordinary 'a dot in' into URLs.
            guard !prefix.isEmpty || commonTLDs.contains(String(tld)) else { continue }
            let context = source.substring(to: match.range.location)
            let explicitContext = !prefix.isEmpty || context.range(of: #"\b(?:visit|open|website|url|link)[ \t]+$"#,
                options: [.regularExpression, .caseInsensitive]) != nil
            let hostHasSpaces = host.rangeOfCharacter(from: .whitespaces) != nil
            if hostHasSpaces, !explicitContext {
                let first = String(compactHost.split(separator: ".")[0])
                let ambiguous = ["a", "an", "the", "this", "that", "it", "we", "he", "she", "they", "you", "i", "us", "me",
                                 "use", "using", "learn", "learning", "study", "studying", "about", "with", "in", "to", "for", "on", "is"]
                guard !ambiguous.contains(first), !first.allSatisfy(\.isNumber) else { continue }
                if host.range(of: #"[ \t]+dot[ \t]+"#, options: [.regularExpression, .caseInsensitive]) == nil {
                    let following = source.substring(from: NSMaxRange(match.range))
                    guard following.range(of: #"^[ \t]*(?:/|(?:forward[ \t]+)?slash\b)"#,
                        options: [.regularExpression, .caseInsensitive]) != nil else { continue }
                }
            }
            let spokenScheme = prefix.range(of: "colon", options: .caseInsensitive) != nil
            var url = (spokenScheme ? (prefix.lowercased().hasPrefix("https") ? "https://" : "http://") : prefix) + compactHost
            var changed = spokenScheme || host != compactHost && host.rangeOfCharacter(from: .whitespaces) != nil
            var end = NSMaxRange(match.range)
            var hasPath = false
            var hasQuery = false
            while end < source.length {
                let rest = source.substring(from: end) as NSString
                guard let op = operation.firstMatch(in: rest as String, range: NSRange(location: 0, length: rest.length)) else { break }
                let spoken = op.range(at: 1).location != NSNotFound
                let token = rest.substring(with: op.range(at: spoken ? 1 : 2)).lowercased()
                    .replacingOccurrences(of: #"[ \t]+"#, with: " ", options: .regularExpression)
                let symbols = ["forward slash": "/", "slash": "/", "dash": "-", "hyphen": "-", "dot": ".",
                               "underscore": "_", "question mark": "?", "equals": "=", "equal sign": "=",
                               "ampersand": "&", "hash": "#", "hash sign": "#"]
                let symbol = symbols[token] ?? token
                guard hasPath || ["/", "?", "#"].contains(symbol) else { break }
                guard !["=", "&"].contains(symbol) || hasQuery else { break }
                let atomStart = NSMaxRange(op.range)
                let remainder = rest.substring(from: atomStart) as NSString
                guard let valueMatch = atom.firstMatch(in: remainder as String, range: NSRange(location: 0, length: remainder.length)) else { break }
                var value = remainder.substring(with: valueMatch.range)
                // Sentence punctuation remains outside the URL replacement.
                while value.hasSuffix(".") { value.removeLast() }
                guard !value.isEmpty else { break }
                let used = atomStart + (value as NSString).length
                if symbol == "?", spoken {
                    let following = rest.substring(from: used)
                    guard following.range(of: #"^(?:[ \t]+(?:equals|equal[ \t]+sign)[ \t]+|[ \t]*=)"#,
                        options: [.regularExpression, .caseInsensitive]) != nil else { break }
                }
                let originalPiece = rest.substring(to: used)
                url += symbol + value
                changed = changed || spoken || originalPiece != symbol + value
                end += used
                hasPath = true
                hasQuery = hasQuery || symbol == "?"
                if (value as NSString).length < valueMatch.range.length { break }
            }
            if changed {
                var replacementEnd = end
                // A dictated URL by itself should not acquire an ASR sentence dot.
                // In prose, sentence punctuation remains outside the URL.
                if source.substring(to: match.range.location).trimmingCharacters(in: .whitespaces).isEmpty,
                   source.substring(from: end).range(of: #"^\.[ \t]*$"#, options: .regularExpression) != nil {
                    replacementEnd += 1
                }
                edits.append((NSRange(location: match.range.location, length: replacementEnd - match.range.location), url))
                consumed = replacementEnd
            }
        }
        let output = NSMutableString(string: raw)
        for (range, replacement) in edits.reversed() { output.replaceCharacters(in: range, with: replacement) }
        return output as String
    }
}
