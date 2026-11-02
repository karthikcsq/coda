import Foundation

public struct MeetingAccessibilityNode: Sendable {
    public var role: String
    public var text: String
    public var url: String?
    public var children: [MeetingAccessibilityNode]
    public init(role: String = "", text: String = "", url: String? = nil, children: [Self] = []) {
        self.role = role; self.text = text; self.url = url; self.children = children
    }
    var flattened: [Self] { [self] + children.flatMap(\.flattened) }
}

public struct DetectedMeeting: Sendable, Equatable {
    public let id: String
    public let service: String
    /// Includes you. A participant is a hint, not proof of a distinct audible voice.
    public let participantCount: Int?
    public init(id: String, service: String, participantCount: Int?) {
        self.id = id; self.service = service; self.participantCount = participantCount
    }
}

public enum MeetingDetection {
    public static func service(for rawURL: String) -> String? {
        guard let url = URL(string: rawURL), url.scheme == "https", let host = url.host?.lowercased() else { return nil }
        if host == "meet.google.com", url.path.range(of: #"^/[a-z]{3}-[a-z]{4}-[a-z]{3}/?$"#, options: .regularExpression) != nil { return "Google Meet" }
        if host == "teams.microsoft.com" || host == "teams.live.com" || host == "teams.cloud.microsoft" { return "Teams" }
        if (host == "zoom.us" || host.hasSuffix(".zoom.us")), url.path.hasPrefix("/wc/") { return "Zoom" }
        return nil
    }
    public static func nativeService(bundleID: String) -> String? {
        switch bundleID {
        case "us.zoom.xos": "Zoom"
        case "com.microsoft.teams2", "com.microsoft.teams": "Teams"
        default: nil
        }
    }
    public static func detect(_ root: MeetingAccessibilityNode, nativeService: String? = nil, identity: String = "") -> DetectedMeeting? {
        if let nativeService { return active(root, service: nativeService, id: identity) }
        // Scope both the hang-up control and count to one web document, never another tab/window.
        if let url = root.url, let service = service(for: url) {
            return active(root, service: service, id: url.components(separatedBy: "?")[0].components(separatedBy: "#")[0])
        }
        return root.children.lazy.compactMap { detect($0, identity: identity) }.first
    }
    private static func active(_ root: MeetingAccessibilityNode, service: String, id: String) -> DetectedMeeting? {
        let nodes = root.flattened
        let activeLabels = ["leave call", "leave meeting", "leave", "hang up", "end call", "end meeting"]
        guard nodes.contains(where: { node in
            node.role == "AXButton" && activeLabels.contains(where: { label in
                let text = node.text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
                return text == label || text.hasPrefix(label + " (")
            })
        }) else { return nil }
        let counts = Set(nodes.filter { $0.role == "AXButton" }.compactMap { node -> Int? in
            let text = node.text.lowercased()
            guard ["people", "participants", "show everyone"].contains(where: text.contains) else { return nil }
            // Only numbers in the participant control or its badge; never a timer/chat count elsewhere.
            let values = [node.text] + node.children.flatMap(\.flattened).map(\.text)
            let matches = values.flatMap { value -> [Int] in
                value.matches(of: /\b[0-9]{1,3}\b/).compactMap { Int($0.output) }
            }
            let unique = Set(matches.filter { $0 > 0 })
            return unique.count == 1 ? unique.first : nil
        })
        return DetectedMeeting(id: id, service: service, participantCount: counts.count == 1 ? counts.first : nil)
    }
}

public enum SpeakerCountSelection {
    /// Manual always wins; a missing/out-of-range automatic hint falls back to audio discovery.
    public static func resolve(manual: Int?, detected: Int?, useDetected: Bool) -> Int? {
        if let manual, (1...4).contains(manual) { return manual }
        if useDetected, let detected, (1...4).contains(detected) { return detected }
        return nil
    }
}
