// Importers/Callers: ContentView.swift
// Affected API: Combine @Published, NWPathMonitor
// User's instruction: Implement multi-device sync and offline support

import Foundation
import Combine
import Network

enum SyncStatus: String {
    case synced
    case syncing
    case offline
    case error
}

class SyncStateManager: ObservableObject {
    static let shared = SyncStateManager()
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.clouddrive.SyncStateManager")
    private let appGroupIdentifier = "group.com.example.clouddrive"

    @Published var status: SyncStatus = .synced
    @Published var isOnline: Bool = true
    @Published var registeredDeviceId: String = UUID().uuidString

    private var lastSyncTime: Date = Date()

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                self?.isOnline = path.status == .satisfied
                self?.updateStatus()
            }
        }
        monitor.start(queue: queue)
        registerDevice()
    }

    func registerDevice() {
        let userDefaults = UserDefaults(suiteName: appGroupIdentifier)
        if let existingDeviceId = userDefaults?.string(forKey: "device_id") {
            registeredDeviceId = existingDeviceId
        } else {
            registeredDeviceId = UUID().uuidString
            userDefaults?.set(registeredDeviceId, forKey: "device_id")
        }
    }

    func setStatus(_ status: SyncStatus) {
        self.status = status
        UserDefaults(suiteName: appGroupIdentifier)?.set(status.rawValue, forKey: "sync_status")
    }

    func updateLastSyncTime() {
        lastSyncTime = Date()
        UserDefaults(suiteName: appGroupIdentifier)?.set(lastSyncTime.timeIntervalSince1970, forKey: "last_sync_time")
    }

    var lastSyncTimeFormatted: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: lastSyncTime)
    }

    private func updateStatus() {
        if !isOnline {
            setStatus(.offline)
        } else if status == .offline {
            setStatus(.synced)
        }
    }
}
