import AppKit
import Testing
@testable import Coda

@Test @MainActor func guardedPasteRestoresAllRepresentations() throws {
    let board = NSPasteboard.withUniqueName()
    defer { board.releaseGlobally() }
    let original = NSPasteboardItem()
    original.setString("synthetic original", forType: .string)
    original.setData(Data([1, 2, 3]), forType: .png)
    original.setString("file:///tmp/synthetic-only", forType: .fileURL)
    board.writeObjects([original])
    let transaction = GuardedPaste(board: board)
    #expect(transaction.publish("synthetic dictation"))
    #expect(transaction.ownsClipboard)
    #expect(board.string(forType: .string) == "synthetic dictation")
    #expect(transaction.readAt != nil)
    transaction.restore()
    #expect(!transaction.ownsClipboard)
    #expect(board.string(forType: .string) == "synthetic original")
    #expect(board.data(forType: .png) == Data([1, 2, 3]))
    #expect(board.string(forType: .fileURL) == "file:///tmp/synthetic-only")
    transaction.restore()
    #expect(board.string(forType: .string) == "synthetic original")
}

@Test @MainActor func guardedPasteNeverOverwritesNewCopy() {
    let board = NSPasteboard.withUniqueName()
    defer { board.releaseGlobally() }
    board.setString("old", forType: .string)
    let transaction = GuardedPaste(board: board)
    #expect(transaction.publish("dictation"))
    board.clearContents(); board.setString("new user copy", forType: .string)
    #expect(!transaction.ownsClipboard)
    transaction.restore()
    #expect(board.string(forType: .string) == "new user copy")
}

@Test @MainActor func guardedPasteKeepsTheFirstConsumptionReceipt() throws {
    let board = NSPasteboard.withUniqueName()
    defer { board.releaseGlobally() }
    let transaction = GuardedPaste(board: board)
    #expect(transaction.publish("synthetic only"))
    defer { transaction.restore() }
    let item = try #require(board.pasteboardItems?.first)
    transaction.pasteboard(board, item: item, provideDataForType: .string)
    let first = try #require(transaction.readAt)
    transaction.pasteboard(board, item: item, provideDataForType: .string)
    #expect(transaction.readAt == first)
    #expect(board.string(forType: .string) == "synthetic only")
}
