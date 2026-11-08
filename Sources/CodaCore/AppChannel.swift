import Foundation

public enum AppChannel: String, Sendable {
    case production, development
    public var appName: String { self == .development ? "Coda Dev" : "Coda" }
    public var bundleIdentifier: String { self == .development ? "app.coda.notebook.dev" : "app.coda.notebook" }
    public var dataDirectory: String { self == .development ? "Coda Dev" : "Coda" }
    public func dataRoot(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        home.appendingPathComponent("Library/Application Support").appendingPathComponent(dataDirectory)
    }
}
