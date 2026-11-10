import SwiftUI
import Combine

// MARK: - Recovery View

struct RecoveryView: View {
    @ObservedObject var viewModel: AuthViewModel
    let onRecoveryComplete: () -> Void
    @State private var mnemonic = ""
    @State private var errorMessage: String?
    @State private var isRecovering = false

    var body: some View {
        VStack(spacing: 20) {
            Text("Account Recovery")
                .font(.largeTitle)
                .bold()

            Text("Enter your 24-word recovery phrase")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            TextField("Recovery phrase", text: $mnemonic)
                .textFieldStyle(.roundedBorder)
                .disableAutocorrection(true)
                .textSelection(.enabled)
                .font(.caption)
                .lineLimit(3)

            if let error = errorMessage {
                Text(error)
                    .foregroundColor(.red)
                    .font(.caption)
            }

            Button("Recover Account") {
                Task {
                    isRecovering = true
                    errorMessage = nil

                    do {
                        let success = try await recoverWithMnemonic(mnemonic)
                        if success {
                            onRecoveryComplete()
                        } else {
                            errorMessage = "Recovery failed. Please check your recovery phrase."
                        }
                    } catch {
                        errorMessage = error.localizedDescription
                    }

                    isRecovering = false
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(mnemonic.isEmpty || isRecovering)

            Button("Cancel") {
                onRecoveryComplete()
            }
            .buttonStyle(.plain)
        }
        .padding()
        .frame(width: 400)
    }

    private func recoverWithMnemonic(_ mnemonic: String) async throws -> Bool {
        // Validate mnemonic format
        let words = mnemonic.split(separator: " ").map(String.init)
        guard words.count == 24 else {
            throw NSError(domain: "Recovery", code: 1, userInfo: [NSLocalizedDescriptionKey: "Recovery phrase must be 24 words"])
        }

        // Derive recovery wrap key from mnemonic
        let keyManager = KeyManager.shared
        let recovered = keyManager.recoverFromMnemonic(mnemonic)

        if recovered {
            // TODO: Server verification of recovery_key_hash
            // API call to verify recovery_key_hash matches stored hash
            // and recovery_salt matches
        }

        return recovered
    }
}

// MARK: - Recovery Setup View

struct RecoverySetupView: View {
    @State private var mnemonic = ""
    @State private var isGenerating = false
    @State private var showingConfirmDialog = false
    let onComplete: (String) -> Void

    var body: some View {
        VStack(spacing: 20) {
            Text("Setup Recovery")
                .font(.largeTitle)
                .bold()

            Text("Your 24-word recovery phrase will be generated below. Write it down and store it securely.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            if mnemonic.isEmpty {
                VStack {
                    Button("Generate Recovery Phrase") {
                        generateMnemonic()
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding()
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Recovery Phrase:")
                        .font(.headline)

                    ScrollView {
                        Text(mnemonic)
                            .font(.system(.caption, design: .monospaced))
                            .padding()
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(8)
                    }
                    .frame(maxHeight: 150)

                    Text("⚠️ Important: Save this phrase securely. It cannot be recovered if lost.")
                        .font(.caption)
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                }
                .padding()

                HStack {
                    Button("Regenerate") {
                        mnemonic = ""
                    }
                    .buttonStyle(.bordered)

                    Button("Save") {
                        showingConfirmDialog = true
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding()
        .frame(width: 500, height: 400)
        .alert("Save Recovery Phrase", isPresented: $showingConfirmDialog) {
            Button("I've saved it") {
                onComplete(mnemonic)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Make sure you've written down your recovery phrase securely before continuing.")
        }
    }

    private func generateMnemonic() {
        isGenerating = true
        // Simulate generation
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            let keyManager = KeyManager.shared
            Task {
                do {
                    let phrase = try await keyManager.setupRecoveryFlow()
                    mnemonic = phrase
                } catch {
                    mnemonic = "error generating mnemonic"
                }
                isGenerating = false
            }
        }
    }
}
