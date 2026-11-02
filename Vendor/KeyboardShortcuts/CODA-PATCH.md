Upstream: https://github.com/sindresorhus/KeyboardShortcuts
Version: 2.4.0
Revision: 1aef85578fdd4f9eaeeb8d53b7b4fc31bf08fe27
License: MIT; full text in license.

Compatibility modifications: remove three #Preview editor blocks at the end of Recorder.swift because the installed Command Line Tools lack the PreviewsMacros plugin. ViewModifiers.swift also aliases SwiftUI.State to select the stable property wrapper instead of the unavailable macOS 27 State macro. Runtime semantics are unchanged. This directory includes the upstream Package.swift, Sources, resources, and license.

Shortcut.isTakenBySystem is exposed as public (implementation unchanged) so Coda checks the suggested binding before assigning it.
