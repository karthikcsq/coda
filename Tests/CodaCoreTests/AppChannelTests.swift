import Foundation
import Testing
@testable import CodaCore

@Test func developmentCannotResolveProductionStorageOrIdentity() {
    let home = URL(fileURLWithPath: "/test/home")
    #expect(AppChannel.production.bundleIdentifier == "app.coda.notebook")
    #expect(AppChannel.production.dataRoot(home: home).path == "/test/home/Library/Application Support/Coda")
    #expect(AppChannel.development.bundleIdentifier == "app.coda.notebook.dev")
    #expect(AppChannel.development.dataRoot(home: home).path == "/test/home/Library/Application Support/Coda Dev")
    #expect(AppChannel.development.appName != AppChannel.production.appName)
}
