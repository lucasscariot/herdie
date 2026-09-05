import SwiftUI

struct AgentSheet: View {
    @Environment(\.dismiss) private var dismiss
    let model: TerminalViewModel

    var body: some View {
        NavigationStack {
            content
                .background(HerdieTheme.background)
                .navigationTitle("Running agents")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { toolbar }
        }
        .task { model.refreshAgents() }
    }

    @ViewBuilder
    private var content: some View {
        if model.agents.isEmpty, model.isLoadingAgents {
            ProgressView("Loading agents…")
        } else if model.agents.isEmpty {
            ContentUnavailableView(
                "No running agents",
                systemImage: "person.2.slash",
                description: Text("Herdr has not detected an active agent on this host.")
            )
        } else {
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(model.agents.filter { $0.status == .blocked }) { agent in
                        agentButton(agent)
                    }
                    ForEach(model.agents.filter { $0.status != .blocked }) { agent in
                        agentButton(agent)
                    }
                }
                .padding(16)
            }
            .refreshable { model.refreshAgents() }
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button {
                model.refreshAgents()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .disabled(model.isLoadingAgents)
            .accessibilityLabel("Refresh agents")
        }
        ToolbarItem(placement: .confirmationAction) {
            Button("Done") { dismiss() }
        }
    }

    private func agentButton(_ agent: RunningAgent) -> some View {
        Button {
            model.focusAgent(agent)
            dismiss()
        } label: {
            HStack(spacing: 13) {
                Circle()
                    .fill(agent.status.color)
                    .frame(width: 10, height: 10)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text(agent.title)
                            .font(.system(.headline, design: .monospaced))
                            .lineLimit(1)
                        Spacer()
                        Text(agent.status.label)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(agent.status.color)
                    }

                    if let usage = agent.usageLabel {
                        Text(usage)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(HerdieTheme.secondary)
                            .lineLimit(1)
                    }

                    HStack(spacing: 8) {
                        if let context = agent.context {
                            Text(context)
                        }
                        Text("\(agent.workspaceID) · \(agent.tabID)")
                        if agent.focused {
                            Label("Current", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(HerdieTheme.accent)
                        }
                    }
                    .font(.caption2)
                    .foregroundStyle(HerdieTheme.secondary.opacity(0.85))
                    .lineLimit(1)
                }

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(HerdieTheme.secondary)
            }
            .padding(15)
            .herdieCard(cornerRadius: 18)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(agent.title), \(agent.status.label)")
        .accessibilityHint("Moves the Herdr terminal to this agent")
    }
}

private extension RunningAgent {
    var usageLabel: String? {
        [provider ?? agent, limit]
            .compactMap { $0 }
            .joined(separator: " · ")
    }
}

private extension RunningAgentStatus {
    var label: String {
        switch self {
        case .unknown: "Unknown"
        case .idle: "Idle"
        case .working: "Working"
        case .blocked: "Needs input"
        case .done: "Done"
        }
    }

    var color: Color {
        switch self {
        case .unknown: HerdieTheme.secondary
        case .idle: HerdieTheme.blue
        case .working: HerdieTheme.accent
        case .blocked: .orange
        case .done: HerdieTheme.blue
        }
    }
}
