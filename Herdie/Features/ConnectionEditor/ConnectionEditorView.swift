import SwiftUI
import UniformTypeIdentifiers

struct ConnectionEditorView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var draft: ConnectionDraft
    @State private var errorMessage: String?
    @State private var importingKey = false
    @FocusState private var focusedField: ConnectionField?

    let onSave: (ConnectionDraft) throws -> Void

    init(draft: ConnectionDraft, onSave: @escaping (ConnectionDraft) throws -> Void) {
        _draft = State(initialValue: draft)
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            ZStack {
                HerdieTheme.background.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        field("Name", focus: .name) {
                            TextField("My Mac", text: $draft.name)
                                .textContentType(.name)
                                .accessibilityLabel("Connection name")
                                .accessibilityIdentifier("connection-name")
                        }

                        HStack(alignment: .top, spacing: 12) {
                            field("Host", focus: .host) {
                                TextField("192.168.1.100", text: $draft.host)
                                    .textContentType(.URL)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                                    .accessibilityIdentifier("connection-host")
                            }
                            .frame(maxWidth: .infinity)
                            field("Port", focus: .port) {
                                TextField("22", text: $draft.port)
                                    .keyboardType(.numberPad)
                                    .accessibilityIdentifier("connection-port")
                            }
                            .frame(width: 104)
                        }

                        field("Username", focus: .username) {
                            TextField("your-username", text: $draft.username)
                                .textContentType(.username)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .accessibilityIdentifier("connection-username")
                        }

                        VStack(alignment: .leading, spacing: 10) {
                            Text("Authentication")
                                .font(.headline)
                            Picker("Authentication", selection: $draft.authentication) {
                                ForEach(AuthenticationMethod.allCases) { method in
                                    Text(method.title).tag(method)
                                }
                            }
                            .pickerStyle(.segmented)
                        }

                        credentialFields

                        Button {
                            save()
                        } label: {
                            Text(draft.isEditing ? "Save" : "Connect")
                                .font(.headline)
                                .foregroundStyle(HerdieTheme.onAccent)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 17)
                                .background(HerdieTheme.accent, in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(draft.isEditing ? "Save" : "Connect")

                        Label(
                            "Credentials are encrypted in iOS Keychain and never synced by Herdie.",
                            systemImage: "lock.shield"
                        )
                        .font(.footnote)
                        .foregroundStyle(HerdieTheme.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                    }
                    .padding(20)
                }
            }
            .navigationTitle(draft.isEditing ? "Edit Connection" : "New Connection")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", systemImage: "checkmark") { save() }
                }
            }
        }
        .fileImporter(
            isPresented: $importingKey,
            allowedContentTypes: [.data, .plainText],
            allowsMultipleSelection: false
        ) { result in
            importPrivateKey(result)
        }
        .alert("Connection", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    @ViewBuilder
    private var credentialFields: some View {
        switch draft.authentication {
        case .none:
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "network")
                    .foregroundStyle(HerdieTheme.accent)
                Text("Use this for Tailscale SSH or hosts that deliberately allow SSH none authentication.")
                    .font(.subheadline)
                    .foregroundStyle(HerdieTheme.secondary)
            }
            .padding(16)
            .herdieCard(cornerRadius: 16)
        case .password:
            field("Password", focus: .password) {
                SecureField(
                    draft.canKeepExistingCredential
                        ? "Leave blank to keep saved password"
                        : "Password",
                    text: $draft.password
                )
                    .textContentType(.password)
                    .privacySensitive()
                    .accessibilityIdentifier("connection-password")
            }
        case .privateKey:
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("OpenSSH Private Key")
                        .font(.headline)
                    Spacer()
                    Button("Import File", systemImage: "doc.badge.plus") {
                        importingKey = true
                    }
                    .font(.subheadline)
                }
                TextEditor(text: $draft.privateKey)
                    .font(.system(.caption, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 130)
                    .padding(10)
                    .background(HerdieTheme.raisedSurface, in: RoundedRectangle(cornerRadius: 16))
                    .privacySensitive()
                    .accessibilityLabel("Private key")
                    .focused($focusedField, equals: .privateKey)
                    .contentShape(Rectangle())
                    .simultaneousGesture(TapGesture().onEnded {
                        focusedField = .privateKey
                    })
                field("Passphrase (optional)", focus: .passphrase) {
                    SecureField("Passphrase", text: $draft.passphrase)
                        .privacySensitive()
                }
                if draft.canKeepExistingCredential {
                    Text("Leave the key blank to keep the existing Keychain item.")
                        .font(.footnote)
                        .foregroundStyle(HerdieTheme.secondary)
                }
            }
        }
    }

    private func field<Content: View>(
        _ label: String,
        focus: ConnectionField,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(label)
                .font(.headline)
            content()
                .focused($focusedField, equals: focus)
                .padding(.horizontal, 15)
                .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
                .background(HerdieTheme.raisedSurface, in: RoundedRectangle(cornerRadius: 16))
                .contentShape(Rectangle())
                .simultaneousGesture(TapGesture().onEnded {
                    focusedField = focus
                })
        }
    }

    private func save() {
        do {
            try onSave(draft)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func importPrivateKey(_ result: Result<[URL], Error>) {
        do {
            let url = try result.get().first
            guard let url else { return }
            let didAccess = url.startAccessingSecurityScopedResource()
            defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
            draft.privateKey = try String(contentsOf: url, encoding: .utf8)
        } catch {
            errorMessage = "The selected private key could not be read."
        }
    }
}

private enum ConnectionField: Hashable {
    case name
    case host
    case port
    case username
    case password
    case privateKey
    case passphrase
}
