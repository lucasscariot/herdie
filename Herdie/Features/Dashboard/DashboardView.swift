import SwiftUI

struct DashboardView: View {
    let environment: AppEnvironment

    @State private var showingConnectionEditor = false
    @State private var editingConnection: SavedConnection?
    @State private var showingSettings = false
    @State private var showingMaker = false
    @State private var showingConnectionManager = false
    @State private var activeConnection: SavedConnection?
    @State private var recentSession: RecentSession?

    private var model: DashboardViewModel { environment.dashboard }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            HerdieBackground()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 28) {
                    header
                    sessions
                    connections
                    if environment.preferences.showsMakerCard {
                        makerCard
                    }
                    privacyFooter
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 120)
            }
            addButton
                .padding(.trailing, 24)
                .padding(.bottom, 24)
        }
        .sheet(isPresented: $showingConnectionEditor) {
            ConnectionEditorView(draft: ConnectionDraft()) { draft in
                let saved = try model.save(draft)
                activeConnection = saved
            }
        }
        .sheet(item: $editingConnection) { connection in
            ConnectionEditorView(draft: ConnectionDraft(connection: connection)) { draft in
                _ = try model.save(draft)
            }
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView(preferences: environment.preferences)
        }
        .sheet(isPresented: $showingMaker) {
            NavigationStack {
                AboutView()
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { showingMaker = false }
                        }
                    }
            }
        }
        .sheet(isPresented: $showingConnectionManager) {
            ConnectionManagerView(model: model)
        }
        .fullScreenCover(item: $activeConnection) { connection in
            TerminalScreen(
                connection: connection,
                environment: environment,
                onSessionEnded: { frame in
                    recentSession = RecentSession(
                        connection: connection,
                        preview: frame.text,
                        lastUsed: .now
                    )
                }
            )
        }
        .alert("Herdie", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button("OK") { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    private var header: some View {
        HStack {
            Image("HerdieLogo")
                .resizable()
                .frame(width: 54, height: 54)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Herdie")
                    .font(.title2.bold())
                Text("Your Herdr sessions, anywhere")
                    .font(.caption)
                    .foregroundStyle(HerdieTheme.secondary)
            }
            Spacer()
            RoundIconButton(
                systemImage: "gearshape",
                accessibilityLabel: "Settings"
            ) {
                showingSettings = true
            }
        }
        .padding(.top, 12)
    }

    private var makerCard: some View {
        HStack(alignment: .top, spacing: 8) {
            Button {
                showingMaker = true
            } label: {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Enjoying Herdie?").font(.headline)
                    Text("I’m Lucas, the maker. Discover my other projects and follow what I’m building.")
                        .font(.subheadline)
                        .foregroundStyle(HerdieTheme.secondary)
                    Label("Meet the maker", systemImage: "arrow.up.right")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(HerdieTheme.accent)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Button {
                environment.preferences.dismissMakerCard()
            } label: {
                Image(systemName: "xmark")
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Dismiss maker card")
        }
        .padding(16)
        .herdieCard()
    }

    @ViewBuilder
    private var sessions: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionLabel(title: "Sessions")
            if let recentSession {
                Button {
                    activeConnection = recentSession.connection
                } label: {
                    RecentSessionCard(session: recentSession)
                }
                .buttonStyle(.plain)
            } else {
                HStack(spacing: 14) {
                    Image(systemName: "rectangle.stack.badge.play")
                        .font(.title2)
                        .foregroundStyle(HerdieTheme.accent)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("No recent session")
                            .font(.headline)
                        Text("Connect to a host to attach to Herdr.")
                            .font(.subheadline)
                            .foregroundStyle(HerdieTheme.secondary)
                    }
                    Spacer()
                }
                .padding(18)
                .herdieCard()
            }
        }
    }

    private var connections: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                SectionLabel(title: "Connections", trailing: nil)
                if !model.connections.isEmpty {
                    Button("Manage") {
                        showingConnectionManager = true
                    }
                    .font(.caption.weight(.medium))
                }
            }
            if model.connections.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "server.rack")
                        .font(.system(size: 30))
                        .foregroundStyle(HerdieTheme.secondary)
                    Text("Add your first SSH host")
                        .font(.headline)
                    Text("Passwords and private keys stay in Keychain on this device.")
                        .font(.subheadline)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(HerdieTheme.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 34)
                .padding(.horizontal, 24)
                .herdieCard()
            } else {
                ForEach(model.connections) { connection in
                    ConnectionRow(
                        connection: connection,
                        onOpen: { activeConnection = connection },
                        onEdit: { editingConnection = connection },
                        onDelete: { delete(connection) }
                    )
                }
            }
        }
    }

    private var privacyFooter: some View {
        VStack(spacing: 2) {
            Label("Direct SSH · no Herdie account or relay", systemImage: "lock.shield")
                .foregroundStyle(HerdieTheme.secondary)
            Button {
                showingMaker = true
            } label: {
                Text("Made by Lucas Scariot · About")
                    .foregroundStyle(HerdieTheme.accent)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("home-maker-link")
        }
        .font(.caption)
        .frame(maxWidth: .infinity)
    }

    private var addButton: some View {
        Button {
            showingConnectionEditor = true
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(HerdieTheme.onAccent)
                .frame(width: 72, height: 72)
                .background(HerdieTheme.accent, in: Circle())
                .shadow(color: HerdieTheme.accent.opacity(0.3), radius: 24)
        }
        .accessibilityLabel("Add connection")
    }

    private func delete(_ connection: SavedConnection) {
        do {
            try model.delete(connection)
        } catch {
            model.errorMessage = error.localizedDescription
        }
    }
}

private struct ConnectionRow: View {
    let connection: SavedConnection
    let onOpen: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            Button(action: onOpen) {
                HStack(spacing: 16) {
                    Image(systemName: "server.rack")
                        .font(.title2)
                        .foregroundStyle(HerdieTheme.secondary)
                        .frame(width: 42)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(connection.name)
                            .font(.headline)
                            .foregroundStyle(.primary)
                        Text(connection.destination)
                            .font(.system(.subheadline, design: .monospaced))
                            .foregroundStyle(HerdieTheme.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    Text("SSH")
                        .font(.caption.bold())
                        .foregroundStyle(.blue)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.blue.opacity(0.15), in: Capsule())
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Menu {
                Button("Edit", systemImage: "pencil", action: onEdit)
                Button("Delete", systemImage: "trash", role: .destructive, action: onDelete)
            } label: {
                Image(systemName: "ellipsis")
                    .font(.headline)
                    .foregroundStyle(HerdieTheme.secondary)
                    .frame(width: 36, height: 44)
            }
            .accessibilityLabel("Connection options")
        }
        .padding(18)
        .herdieCard()
    }
}

private struct ConnectionManagerView: View {
    @Environment(\.dismiss) private var dismiss
    let model: DashboardViewModel

    var body: some View {
        NavigationStack {
            List {
                ForEach(model.connections) { connection in
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(connection.name)
                            Text(connection.destination)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(HerdieTheme.secondary)
                        }
                        Spacer()
                        Button(role: .destructive) {
                            delete(connection)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Delete \(connection.name)")
                    }
                    .padding(.vertical, 4)
                }
                .onMove(perform: model.move)
                .onDelete(perform: delete)
            }
            .environment(\.editMode, .constant(.active))
            .scrollContentBackground(.hidden)
            .background(HerdieTheme.background)
            .navigationTitle("Manage Connections")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .alert("Herdie", isPresented: Binding(
                get: { model.errorMessage != nil },
                set: { if !$0 { model.errorMessage = nil } }
            )) {
                Button("OK") { model.errorMessage = nil }
            } message: {
                Text(model.errorMessage ?? "")
            }
        }
    }

    private func delete(at offsets: IndexSet) {
        let selected = offsets.compactMap { index in
            model.connections.indices.contains(index) ? model.connections[index] : nil
        }
        do {
            for connection in selected {
                try model.delete(connection)
            }
        } catch {
            model.errorMessage = error.localizedDescription
        }
    }

    private func delete(_ connection: SavedConnection) {
        do {
            try model.delete(connection)
        } catch {
            model.errorMessage = error.localizedDescription
        }
    }
}

private struct RecentSessionCard: View {
    let session: RecentSession

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Circle()
                    .fill(HerdieTheme.accent)
                    .frame(width: 8, height: 8)
                Text(session.connection.name)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(HerdieTheme.secondary)
                Spacer()
                Text("SSH")
                    .font(.caption.bold())
                    .foregroundStyle(.blue)
            }
            .padding(12)
            Divider().overlay(.white.opacity(0.08))
            Text(session.preview.isEmpty ? "Herdr is ready to reattach." : session.preview)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(8)
                .frame(maxWidth: .infinity, minHeight: 106, alignment: .topLeading)
                .padding(12)
            Divider().overlay(.white.opacity(0.08))
            HStack {
                Label("Herdr", systemImage: "rectangle.stack.fill")
                    .foregroundStyle(HerdieTheme.accent)
                Spacer()
                Text(session.lastUsed, style: .relative)
                    .foregroundStyle(HerdieTheme.secondary)
            }
            .font(.caption)
            .padding(12)
        }
        .herdieCard()
    }
}
