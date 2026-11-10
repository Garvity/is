import Foundation

public class APIClient {
    public static let shared = APIClient()
    private let baseURL = URL(string: "http://localhost:3000")!

    private init() {}

    public func login(email: String, password: String) async throws -> String {
        let url = baseURL.appendingPathComponent("/auth/login")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body = ["email": email, "password": password]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw NSError(domain: "APIClient", code: 401, userInfo: [NSLocalizedDescriptionKey: "Invalid credentials"])
        }

        let authResponse = try JSONDecoder().decode(AuthResponse.self, from: data)
        _ = KeychainService.shared.saveToken(authResponse.token)
        return authResponse.token
    }

    public func register(email: String, password: String) async throws -> String {
        let url = baseURL.appendingPathComponent("/auth/register")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body = ["email": email, "password": password]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 201 else {
            throw NSError(domain: "APIClient", code: 400, userInfo: [NSLocalizedDescriptionKey: "Registration failed"])
        }

        let authResponse = try JSONDecoder().decode(AuthResponse.self, from: data)
        _ = KeychainService.shared.saveToken(authResponse.token)
        return authResponse.token
    }

    public func fetchMe() async throws -> UserProfile {
        guard let token = KeychainService.shared.getToken() else {
            throw NSError(domain: "APIClient", code: 401, userInfo: [NSLocalizedDescriptionKey: "No token found"])
        }

        let url = baseURL.appendingPathComponent("/auth/me")
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw NSError(domain: "APIClient", code: 401, userInfo: [NSLocalizedDescriptionKey: "Unauthorized"])
        }

        return try JSONDecoder().decode(UserProfile.self, from: data)
    }

    public func fetchItems() async throws -> ItemListResponse {
        guard let token = KeychainService.shared.getToken() else {
            throw NSError(domain: "APIClient", code: 401, userInfo: [NSLocalizedDescriptionKey: "No token found"])
        }

        let url = baseURL.appendingPathComponent("/items")
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw NSError(domain: "APIClient", code: 401, userInfo: [NSLocalizedDescriptionKey: "Failed to fetch items"])
        }

        return try JSONDecoder().decode(ItemListResponse.self, from: data)
    }
}
