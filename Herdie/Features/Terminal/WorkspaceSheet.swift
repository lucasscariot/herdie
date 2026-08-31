import SwiftUI

struct WorkspaceSheet: View {
    @Environment(\.dismiss) private var dismiss
    let model: TerminalViewModel

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                HStack(spacing: 12) {
                    workspaceAction("Previous", symbol: "chevron.up") {
                        model.switchWorkspacePrevious()
                    }
                    workspaceAction("Next", symbol: "chevron.down") {
                        model.switchWorkspaceNext()
                    }
                    workspaceAction("New", symbol: "plus") {
                        model.createWorkspace()
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    Label("Herdr terminal navigation", systemImage: "rectangle.3.group")
                        .font(.headline)
                        .foregroundStyle(HerdieTheme.accent)
                    Text("Herdie is using Herdr’s portable key interface for this host. Previous, Next, and New workspaces act on the currently attached Herdr session without opening another SSH connection.")
                        .font(.subheadline)
                        .foregroundStyle(HerdieTheme.secondary)
                    Text("Structured workspace names will appear here when the remote Herdr API exposes them to mobile clients.")
                        .font(.footnote)
                        .foregroundStyle(HerdieTheme.secondary.opacity(0.8))
                }
                .padding(18)
                .herdieCard()
                Spacer()
            }
            .padding(20)
            .background(HerdieTheme.background)
            .navigationTitle("Workspaces")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func workspaceAction(
        _ title: String,
        symbol: String,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            action()
            dismiss()
        } label: {
            VStack(spacing: 9) {
                Image(systemName: symbol)
                    .font(.title3)
                    .foregroundStyle(HerdieTheme.accent)
                Text(title)
                    .font(.caption.weight(.medium))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .herdieCard(cornerRadius: 18)
        }
        .buttonStyle(.plain)
    }
}
