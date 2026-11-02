import SwiftUI

struct AccessibilitySetupView: View {
    @Bindable var controller: DictationController
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 9) {
                        Text("Accessibility").font(CodaStyle.rowTitleFont)
                        CodaStatusChip(readiness: controller.accessibility.trusted ? .ready : .blocked,
                                       text: controller.accessibility.trusted ? "Enabled" : "Not enabled")
                    }
                    Text(controller.accessibility.guidance).font(CodaStyle.secondaryFont).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                if !controller.accessibility.trusted {
                    Button("Review access…") { controller.enableAutomaticInsertion() }
                        .buttonStyle(CodaPrimaryButtonStyle())
                        .disabled(controller.lifecycle.busy)
                }
            }
            HStack(spacing: 12) {
                Button("Refresh access status") { controller.refreshAccessibility() }.buttonStyle(CodaQuietButtonStyle())
                Text("Coda " + (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "development") + " • process " + String(ProcessInfo.processInfo.processIdentifier))
                    .font(CodaStyle.captionFont).foregroundStyle(CodaStyle.muted)
            }
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
