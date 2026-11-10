import SwiftUI
import Combine
import FileProvider

struct ContentView: View {
    @StateObject private var authViewModel = AuthViewModel()
    
    var body: some View {
        Group {
            if authViewModel.isAuthenticated {
                AuthenticatedView(viewModel: authViewModel)
            } else {
                LoginView(viewModel: authViewModel)
            }
        }
        .onAppear {
            authViewModel.restoreSession()
        }
    }
}

struct LoginView: View {
    @ObservedObject var viewModel: AuthViewModel
    @State private var email = ""
    @State private var password = ""
    @State private var isRegistering = false
    @State private var errorMessage: String?
    @State private var showingRecoveryFlow = false
    @State private var showingMnemonicSheet = false
    @State private var recoveryMnemonic = ""

    var body: some View {
        VStack(spacing: 20) {
            Text(isRegistering ? "Register" : "Login")
                .font(.largeTitle)
                .bold()

            TextField("Email", text: $email)
                .textFieldStyle(.roundedBorder)
                .disableAutocorrection(true)

            SecureField("Password", text: $password)
                .textFieldStyle(.roundedBorder)

            if let error = errorMessage {
                Text(error)
                    .foregroundColor(.red)
                    .font(.caption)
            }

            Button(isRegistering ? "Register" : "Login") {
                Task {
                    do {
                        if isRegistering {
                            try await viewModel.register(email: email, password: password)
                        } else {
                            try await viewModel.login(email: email, password: password)
                        }
                        errorMessage = nil
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(email.isEmpty || password.isEmpty)

            Button(isRegistering ? "Already have an account? Login" : "Don't have an account? Register") {
                isRegistering.toggle()
                errorMessage = nil
            }
            .buttonStyle(.plain)

            // Recovery flow button
            if !isRegistering {
                Divider()
                    .padding(.vertical, 8)

                Button("Recover Account") {
                    showingRecoveryFlow = true
                }
                .buttonStyle(.bordered)
                .foregroundColor(.secondary)
            } else {
                // Show recovery setup after registration
                VStack(spacing: 12) {
                    Divider()
                        .padding(.vertical, 8)

                    Button("Set up Recovery") {
                        showingMnemonicSheet = true
                    }
                    .buttonStyle(.borderedProminent)
                    .foregroundColor(.blue)

                    Text("Generate a 24-word recovery phrase")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .frame(width: 300)
        .sheet(isPresented: $showingRecoveryFlow) {
            RecoveryView(viewModel: viewModel, onRecoveryComplete: {
                showingRecoveryFlow = false
            })
        }
        .sheet(isPresented: $showingMnemonicSheet) {
            RecoverySetupView(onComplete: { mnemonic in
                recoveryMnemonic = mnemonic
                // Store mnemonic temporarily for user to save
                showingMnemonicSheet = false
                // Could show save dialog here
            })
        }
    }
}

struct AuthenticatedView: View {
    @ObservedObject var viewModel: AuthViewModel
    @AppStorage("sync_status", store: UserDefaults(suiteName: "group.com.example.clouddrive")) var syncStatus: String = "synced"

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Text("CloudDrive")
                    .font(.title)
                    .bold()
                Spacer()
                Text("Sync: \(syncStatus.capitalized)")
                    .font(.caption)
                    .padding(5)
                    .background(Color.secondary.opacity(0.2))
                    .cornerRadius(5)
                Button("Logout") {
                    viewModel.logout()
                }
                .buttonStyle(.bordered)
            }

            
            if let user = viewModel.currentUser {
                Text("Logged in as: \(user.email)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            Divider()
            
            if viewModel.items.isEmpty {
                Text("No files or folders yet")
                    .foregroundColor(.secondary)
            } else {
                List(viewModel.items) { item in
                    HStack {
                        Image(systemName: item.isDirectory ? "folder" : "doc")
                        Text(item.name)
                        Spacer()
                        Text(item.isDirectory ? "Folder" : "File")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .listStyle(.inset)
            }
            
            Button("Refresh") {
                Task {
                    try? await viewModel.refreshItems()
                }
            }
            .buttonStyle(.bordered)
        }
        .padding()
        .frame(minWidth: 400, minHeight: 300)
    }
}

@MainActor
class AuthViewModel: ObservableObject {
    @Published var isAuthenticated = false
    @Published var currentUser: UserProfile?
    @Published var items: [CloudDriveItem] = []
    
    private let apiClient = APIClient.shared
    private let database = Database.shared
    private let keychain = KeychainService.shared
    
    func restoreSession() {
        guard keychain.getToken() != nil else { return }
        
        Task {
            do {
                let user = try await apiClient.fetchMe()
                let items = try await apiClient.fetchItems()
                
                let allItems: [CloudDriveItem] = items.folders.map { folder in
                    CloudDriveItem(
                        id: folder.id,
                        userId: folder.userId,
                        parentId: folder.parentId,
                        name: folder.name,
                        mimeType: nil,
                        size: 0,
                        r2Key: nil,
                        isDirectory: true,
                        createdAt: folder.createdAt,
                        updatedAt: folder.updatedAt
                    )
                } + items.files.map { file in
                    CloudDriveItem(
                        id: file.id,
                        userId: file.userId,
                        parentId: file.folderId,
                        name: file.name,
                        mimeType: file.mimeType,
                        size: file.size,
                        r2Key: file.r2Key,
                        isDirectory: false,
                        createdAt: file.createdAt,
                        updatedAt: file.updatedAt
                    )
                }
                
                try database.insertOrUpdate(allItems)
                
                await MainActor.run {
                    self.currentUser = user
                    self.items = allItems
                    self.isAuthenticated = true
                    self.registerFileProviderDomain()
                }
            } catch {
                _ = keychain.deleteToken()
                await MainActor.run {
                    self.isAuthenticated = false
                }
            }
        }
    }
    
    func login(email: String, password: String) async throws {
        _ = try await apiClient.login(email: email, password: password)
        await restoreSession()
    }
    
    func register(email: String, password: String) async throws {
        _ = try await apiClient.register(email: email, password: password)
        await restoreSession()
    }
    
    func logout() {
        _ = keychain.deleteToken()
        do {
            if let user = currentUser {
                try database.deleteAll(for: user.id)
            }
        } catch {
            print("Failed to delete local data: \(error)")
        }
        isAuthenticated = false
        currentUser = nil
        items = []
    }
    
    func refreshItems() async throws {
        let items = try await apiClient.fetchItems()
        
        let allItems: [CloudDriveItem] = items.folders.map { folder in
            CloudDriveItem(
                id: folder.id,
                userId: folder.userId,
                parentId: folder.parentId,
                name: folder.name,
                mimeType: nil,
                size: 0,
                r2Key: nil,
                isDirectory: true,
                createdAt: folder.createdAt,
                updatedAt: folder.updatedAt
            )
        } + items.files.map { file in
            CloudDriveItem(
                id: file.id,
                userId: file.userId,
                parentId: file.folderId,
                name: file.name,
                mimeType: file.mimeType,
                size: file.size,
                r2Key: file.r2Key,
                isDirectory: false,
                createdAt: file.createdAt,
                updatedAt: file.updatedAt
            )
        }
        
        if let user = currentUser {
            try database.deleteAll(for: user.id)
            try database.insertOrUpdate(allItems)
        }
        
        await MainActor.run {
            self.items = allItems
        }
    }

    func registerFileProviderDomain() {
        let domainIdentifier = NSFileProviderDomainIdentifier(rawValue: "com.garv.CloudDriveProject.domain")
        let domain = NSFileProviderDomain(identifier: domainIdentifier, displayName: "Cloud Drive")

        NSFileProviderManager.add(domain) { error in
            if let error = error {
                print("Failed to add File Provider domain: \(error)")
            } else {
                print("Successfully registered File Provider domain: \(domainIdentifier.rawValue)")
            }
        }
    }
}
