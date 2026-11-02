import Testing
@testable import CodaCore

@Test @MainActor func accessibilityRefreshNeverPromptsOrOpensSettings() {
    var prompts = 0; var opens = 0; var allowed = false
    let access = AccessibilityAccess(check: { allowed }, prompt: { prompts += 1 }, openSettings: { opens += 1; return true })
    access.refresh(); access.refresh()
    #expect(!access.trusted); #expect(prompts == 0); #expect(opens == 0)
    allowed = true; access.refresh()
    #expect(access.trusted); #expect(prompts == 0); #expect(opens == 0)
    allowed = false; access.refresh()
    #expect(!access.trusted); #expect(prompts == 0)
}
@Test @MainActor func explicitRequestPromptsOnceAndReopensPaneWithoutSpam() {
    var prompts = 0; var opens = 0
    let access = AccessibilityAccess(check: { false }, prompt: { prompts += 1 }, openSettings: { opens += 1; return true })
    access.requestFromUserAction(); access.requestFromUserAction(); access.refresh()
    #expect(prompts == 1); #expect(opens == 2); #expect(!access.trusted)
    #expect(access.guidance.contains("Only you"))
}
@Test @MainActor func grantedAccessDoesNotRequestAgain() {
    var effects = 0
    let access = AccessibilityAccess(check: { true }, prompt: { effects += 1 }, openSettings: { effects += 1; return true })
    access.requestFromUserAction()
    #expect(access.trusted); #expect(effects == 0)
}
@Test @MainActor func settingsFailureProvidesManualFallbackWithoutAssumingTrust() {
    let access = AccessibilityAccess(check: { false }, prompt: {}, openSettings: { false })
    access.requestFromUserAction()
    #expect(!access.trusted); #expect(access.guidance.contains("could not open"))
}
