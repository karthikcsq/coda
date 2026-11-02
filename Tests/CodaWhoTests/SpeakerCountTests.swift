import Testing
@testable import CodaWho

@Test func knownCountMergesExtraVoiceClustersBySimilarity() {
    // Three voices, with two split into slightly different embeddings.
    let voices: [[Float]] = [[1, 0, 0], [0.98, 0.2, 0], [0, 1, 0], [0, 0.98, 0.2], [0, 0, 1]]
    let automatic = AverageLinkage.cluster(voices, cosine: 0.999)
    #expect(Set(automatic).count == 5)
    let labels = AverageLinkage.cluster(voices, cosine: 0.999, speakerCount: 3)
    #expect(labels == [0, 0, 1, 1, 2])
}

@Test func knownCountDoesNotMergePastTheRequestedNumberOrInventVoices() {
    let voices: [[Float]] = [[1, 0], [0.99, 0.1], [0, 1]]
    #expect(AverageLinkage.cluster(voices, cosine: 0.5, speakerCount: 3) == [0, 1, 2])
    #expect(AverageLinkage.cluster(voices, cosine: 0.5, speakerCount: 1) == [0, 0, 0])
    #expect(AverageLinkage.cluster([[1, 0]], cosine: 0.5, speakerCount: 3) == [0])
    #expect(AverageLinkage.cluster([], cosine: 0.5, speakerCount: 3).isEmpty)
    #expect(AverageLinkage.cluster(voices, cosine: 0.5) == [0, 0, 1])
}
