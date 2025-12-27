//
//  LocalSyncEngine.swift
//  fortest
//
//
//

import Foundation

final class LocalSyncEngine {
    static let shared = LocalSyncEngine()

    private let storeURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    private init() {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        storeURL = documents.appendingPathComponent("local_shared_store.json")
        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    func recordDeletion(eventId: UUID, groupId: String) {
        let key = deletedKey(for: groupId)
        var deleted = loadDeletedIds(key: key)
        deleted.insert(eventId.uuidString)
        saveDeletedIds(deleted, key: key)
    }

    func sync(groupId rawGroupId: String, author rawAuthor: String, dataManager: EventDataManager) -> Date? {
        let groupId = rawGroupId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !groupId.isEmpty else { return nil }
        let author = rawAuthor.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "local" : rawAuthor

        var store = loadStore()
        var group = store.groups[groupId] ?? GroupStore(events: [], deletedIds: [], updatedAt: Date())

        let deletedKey = deletedKey(for: groupId)
        let localDeleted = loadDeletedIds(key: deletedKey)
        if !localDeleted.isEmpty {
            group.deletedIds.formUnion(localDeleted)
            group.events.removeAll { localDeleted.contains($0.id.uuidString) }
        }

        var storeById: [UUID: Event] = [:]
        for event in group.events {
            storeById[event.id] = event
        }

        let localShared = dataManager.events.filter { $0.isShared && (($0.groupId ?? groupId) == groupId) }
        for var event in localShared {
            if event.groupId == nil {
                event.groupId = groupId
                dataManager.updateEvent(event, preserveTimestamp: true)
            }
            if event.author == nil || event.author?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true {
                event.author = author
                dataManager.updateEvent(event, preserveTimestamp: true)
            }

            event.syncStatus = .synced
            if let stored = storeById[event.id] {
                if event.updatedAt > stored.updatedAt {
                    storeById[event.id] = event
                }
            } else {
                storeById[event.id] = event
            }
        }

        for deletedId in group.deletedIds {
            if let uuid = UUID(uuidString: deletedId) {
                storeById.removeValue(forKey: uuid)
            }
        }

        group.events = Array(storeById.values)
        group.updatedAt = Date()
        store.groups[groupId] = group
        saveStore(store)

        for event in group.events {
            var incoming = event
            incoming.groupId = groupId
            incoming.syncStatus = .synced
            dataManager.mergeSharedEvent(incoming)
        }

        if !group.deletedIds.isEmpty {
            for deletedId in group.deletedIds {
                if let uuid = UUID(uuidString: deletedId) {
                    dataManager.removeEventLocally(withId: uuid)
                }
            }
        }

        let toSync = dataManager.events.filter { $0.isShared && $0.groupId == groupId && $0.syncStatus != .synced }
        for var event in toSync {
            event.syncStatus = .synced
            dataManager.updateEvent(event, preserveTimestamp: true)
        }

        saveDeletedIds([], key: deletedKey)
        let syncDate = Date()
        setLastSyncDate(syncDate, for: groupId)
        return syncDate
    }

    func lastSyncDate(for groupId: String) -> Date? {
        let key = lastSyncKey(for: groupId)
        let timestamp = UserDefaults.standard.double(forKey: key)
        return timestamp > 0 ? Date(timeIntervalSince1970: timestamp) : nil
    }

    private func loadStore() -> SharedStore {
        guard let data = try? Data(contentsOf: storeURL) else {
            return SharedStore(groups: [:])
        }
        if let store = try? decoder.decode(SharedStore.self, from: data) {
            return store
        }
        return SharedStore(groups: [:])
    }

    private func saveStore(_ store: SharedStore) {
        guard let data = try? encoder.encode(store) else { return }
        try? data.write(to: storeURL, options: .atomic)
    }

    private func deletedKey(for groupId: String) -> String {
        "local_sync_deleted_\(groupId)"
    }

    private func lastSyncKey(for groupId: String) -> String {
        "local_sync_last_\(groupId)"
    }

    private func loadDeletedIds(key: String) -> Set<String> {
        let stored = UserDefaults.standard.array(forKey: key) as? [String] ?? []
        return Set(stored)
    }

    private func saveDeletedIds(_ deleted: Set<String>, key: String) {
        UserDefaults.standard.set(Array(deleted), forKey: key)
    }

    private func setLastSyncDate(_ date: Date, for groupId: String) {
        UserDefaults.standard.set(date.timeIntervalSince1970, forKey: lastSyncKey(for: groupId))
    }
}

private struct SharedStore: Codable {
    var groups: [String: GroupStore]
}

private struct GroupStore: Codable {
    var events: [Event]
    var deletedIds: Set<String>
    var updatedAt: Date
}
