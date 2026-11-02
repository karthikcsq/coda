import SwiftUI

struct AccessibilitySetupView: View {
    @Bindable var controller: DictationController
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            if controller.accessibility.trusted {
                Label("Accessibility enabled", systemImage: "checkmark.circle").foregroundStyle(.secondary)
            } else {
                Button("Review automatic insertion access…") { controller.enableAutomaticInsertion() }
                    .buttonStyle(.borderedProminent)
                    .disabled(controller.lifecycle.busy)
            }
            Text("Coda " + (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "development") + " • process " + String(ProcessInfo.processInfo.processIdentifier)).font(.caption2).foregroundStyle(.secondary)
            Button("Refresh access status") { controller.refreshAccessibility() }.buttonStyle(.link)
            Text(controller.accessibility.guidance).font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .task {
            // Read-only while this help is visible; no prompt or Settings opening on refresh.
            while !Task.isCancelled {
                controller.refreshAccessibility()
                do { try await Task.sleep(for: .seconds(2)) } catch { return }
            }
        }
    }
}
