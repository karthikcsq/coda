import Foundation

/// Finalize every writer even when capture stop or a sibling writer fails.
/// Files are only removed by the caller after all finalization and mixing succeeds.
@MainActor public enum CaptureFinalization {
    public static func finish<Track>(stop: () async throws -> Void,
        detach: () async -> Void, writers: [() async throws -> Track?]) async throws -> [Track] {
        var failure: Error?
        do { try await stop() } catch { failure = error }
        await detach()
        var tracks: [Track] = []
        for writer in writers {
            do { if let track = try await writer() { tracks.append(track) } }
            catch { if failure == nil { failure = error } }
        }
        if let failure { throw failure }
        return tracks
    }
}
