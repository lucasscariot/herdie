import SwiftUI

struct WorkspaceSheet: View {
    @Environment(\.dismiss) private var dismiss
    let model: TerminalViewModel

    var body: some View {
        NavigationStack {
            List {
                Section {
                    workspaceAction("Previous workspace", symbol: "chevron.up", action: model.switchWorkspacePrevious)
                    workspaceAction("Next workspace", symbol: "chevron.down", action: model.switchWorkspaceNext)
                    workspaceAction("New workspace", symbol: "plus", action: model.createWorkspace)
                } header: {
                    Text(model.connection.name)
                } footer: {
                    Text("Switch workspaces in your current Herdr session.")
                }
            }
            .disabled(model.state != .attached)
            .navigationTitle("Workspaces")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func workspaceAction(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button {
            action()
            if model.errorMessage == nil {
                UISelectionFeedbackGenerator().selectionChanged()
                dismiss()
            }
        } label: {
            Label(title, systemImage: symbol).padding(.vertical, 6)
        }
    }
}
