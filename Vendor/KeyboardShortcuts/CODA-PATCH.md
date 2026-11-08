Upstream: https://github.com/sindresorhus/KeyboardShortcuts
Version: 2.4.0
Revision: 1aef85578fdd4f9eaeeb8d53b7b4fc31bf08fe27
License: MIT; full text in license.

Compatibility modifications: remove three #Preview editor blocks at the end of Recorder.swift because the installed Command Line Tools lack the PreviewsMacros plugin. ViewModifiers.swift also aliases SwiftUI.State to select the stable property wrapper instead of the unavailable macOS 27 State macro. Runtime semantics are unchanged. This directory includes the upstream Package.swift, Sources, resources, and license.

Shortcut.isTakenBySystem is exposed as public (implementation unchanged) so Coda checks the suggested binding before assigning it.

# Coda patch: menu event tracking

The tracking-mode keyboard monitor previously dequeued every application event
and reposted unrelated events, including menu pointer events. On the installed
macOS 27 build, Dev menus opened and closed but mouse selection never reached
menu actions.

The monitor now peeks at the event queue and only dequeues a leading sequence of
matching keyboard events. A mouse or other unrelated event stops interception
and remains untouched for AppKit. Unhandled leading keys are restored at the
front in their original order. Polling uses the actual run-loop mode and a
nonblocking deadline.

Coda also suspends registered keyboard shortcuts during its status-menu tracking
scope and restores the previous state afterward. Regression tests cover leaving
mouse events untouched, preserving unhandled key order, and restoring shortcut
state on cancellation. No license or public shortcut API changes.
