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

@Test func knownCountFoldsMinorVoicesBeforeJoiningDistinctSpeakers() {
    // Three real voices with a lot of speech each, plus two short, unrecognizable scraps.
    // The second and third voices are partly alike (cosine ~0.6), as two real voices often are.
    let voices: [[Float]] = [[1, 0, 0, 0, 0], [0.99, 0.1, 0, 0, 0], [0, 0.95, 0.31, 0, 0], [0, 0.97, 0.24, 0, 0],
                             [0, 0.31, 0.95, 0, 0], [0, 0.24, 0.97, 0, 0], [0, 0, 0, 1, 0], [0, 0, 0, 0, 1]]
    let solo: [Float] = [200, 200, 80, 80, 90, 90, 6, 3]
    // Unweighted, the scraps are farthest from everyone, so two real speakers are merged instead.
    #expect(Set(AverageLinkage.cluster(voices, cosine: 0.65, speakerCount: 3).prefix(6)).count < 3)
    let labels = AverageLinkage.cluster(voices, cosine: 0.65, speakerCount: 3, weights: solo)
    #expect(Set(labels).count == 3)
    #expect(labels[0] == labels[1] && labels[2] == labels[3] && labels[4] == labels[5])
    #expect(Set([labels[0], labels[2], labels[4]]).count == 3)
}

@Test func knownCountStillMergesSplitVoicesWhenEveryGroupHasRealSpeech() {
    // One speaker split in two large clusters plus a quiet but substantial third voice: similarity wins.
    let voices: [[Float]] = [[1, 0, 0], [0.6, 0.8, 0], [0, 0, 1]]
    #expect(AverageLinkage.cluster(voices, cosine: 0.9, speakerCount: 2, weights: [300, 300, 60]) == [0, 0, 1])
}
