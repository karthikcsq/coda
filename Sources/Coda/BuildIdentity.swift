import Foundation
import CodaCore

enum BuildIdentity {
    static let channel: AppChannel = {
        let environment = ProcessInfo.processInfo.environment
        // Only synthetic UI renders may override bundle identity.
        if environment["CODA_RENDER_DOCS"] == "1", let raw = environment["CODA_UI_CHANNEL"], let channel = AppChannel(rawValue: raw) { return channel }
        return AppChannel(rawValue: Bundle.main.object(forInfoDictionaryKey: "CodaChannel") as? String ?? "development") ?? .development
    }()
    static var isDevelopment: Bool { channel == .development }
    static var name: String { channel.appName }
    static var dataRoot: URL { channel.dataRoot() }
    static var revision: String { String((Bundle.main.object(forInfoDictionaryKey: "CodaSourceRevision") as? String ?? "unpackaged").prefix(8)) }
}
