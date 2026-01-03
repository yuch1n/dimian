import Foundation
import SwiftUI

// MARK: - 數據模型
struct CategoryExpense {
    let category: Event.ExpenseCategory
    let amount: Double
    let count: Int
}

class EventDataManager: ObservableObject {
    @Published var events: [Event] = []
    
    private let sqliteManager = SQLiteManager.shared
    private let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    
    init() {
        loadEvents()
        print("初始化完成，載入事件數量: \(events.count)")
        // 如果沒有數據，載入示例數據
        if events.isEmpty {
            print("沒有現有數據，開始載入示例數據")
            loadSampleData()
        } else {
            print("發現現有數據，跳過示例數據載入")
        }
    }
    
    // MARK: - 數據操作
    
    @discardableResult
    func addEvent(_ event: Event) -> Event? {
        print("嘗試添加事件: \(event.title) - ID: \(event.id)")
        print("當前事件數量: \(events.count)")
        
        var newEvent = normalizeEvent(event)
        newEvent.updatedAt = Date()
        var attempt = 0
        let maxAttempts = 5
        
        while attempt < maxAttempts {
            if events.contains(where: { $0.id == newEvent.id }) {
                print("記憶體中事件ID衝突 (\(newEvent.id))，重新生成 UUID")
                newEvent.id = UUID()
                attempt += 1
                continue
            }

            switch sqliteManager.insertEvent(newEvent) {
            case .success:
                events.append(newEvent)
                print("事件添加成功，當前事件數量: \(events.count)")
                return newEvent
            case .constraint(let message):
                if message.contains("events.id") {
                    print("資料庫事件ID衝突 (\(newEvent.id))，重新生成 UUID")
                    newEvent.id = UUID()
                    attempt += 1
                } else {
                    print("事件插入違反約束: \(message)")
                    return nil
                }
            case .failure(let message):
                print("事件添加失敗: \(message)")
                return nil
            }
        }
        
        print("事件添加失敗：超過最大重試次數")
        return nil
    }
    
    func updateEvent(_ updatedEvent: Event, preserveTimestamp: Bool = false) {
        var sanitizedEvent = normalizeEvent(updatedEvent)
        if !preserveTimestamp {
            sanitizedEvent.updatedAt = Date()
        }
        if sqliteManager.updateEvent(sanitizedEvent) {
            if let index = events.firstIndex(where: { $0.id == sanitizedEvent.id }) {
                events[index] = sanitizedEvent
            }
        }
    }
    
    func deleteEvent(withId id: UUID) {
        if sqliteManager.deleteEvent(withId: id) {
            events.removeAll { $0.id == id }
        }
    }

    func removeEventLocally(withId id: UUID) {
        if sqliteManager.deleteEvent(withId: id) {
            events.removeAll { $0.id == id }
        }
    }

    /// 合併共享事件（本地最新優先）
    func mergeSharedEvent(_ incoming: Event) {
        guard incoming.isShared else { return }
        let sanitized = normalizeEvent(incoming)

        if let index = events.firstIndex(where: { $0.id == sanitized.id }) {
            if sanitized.updatedAt > events[index].updatedAt {
                if sqliteManager.updateEvent(sanitized) {
                    events[index] = sanitized
                }
            }
        } else {
            switch sqliteManager.insertEvent(sanitized) {
            case .success:
                events.append(sanitized)
            case .constraint(let message):
                print("合併共享事件失敗 (約束): \(message)")
            case .failure(let message):
                print("合併共享事件失敗: \(message)")
            }
        }
    }
    
    // MARK: - 數據持久化
    
    private func loadEvents() {
        events = sqliteManager.getAllEvents()
        print("載入事件數量: \(events.count)")
    }
    
    private func loadSampleData() {
        print("開始載入示例數據")
        // 先清空數據庫
        if sqliteManager.clearAllData() {
            events = []
            print("數據庫清空成功")
        } else {
            print("數據庫清空失敗")
            return
        }
        
        // 載入示例數據，為每個事件生成新的 UUID
        for var event in Event.sampleEvents {
            event.id = UUID() // 為每個示例事件生成新的 UUID
            let sanitizedEvent = normalizeEvent(event)
            print("載入示例事件: \(sanitizedEvent.title) - ID: \(sanitizedEvent.id)")
            switch sqliteManager.insertEvent(sanitizedEvent) {
            case .success:
                events.append(sanitizedEvent)
            case .constraint(let message):
                if message.contains("events.id") {
                    print("示例事件插入失敗 (ID重複): \(sanitizedEvent.title)")
                } else {
                    print("示例事件插入失敗: \(sanitizedEvent.title) - \(message)")
                }
            case .failure(let message):
                print("示例事件插入失敗: \(sanitizedEvent.title) - \(message)")
            }
        }
        print("示例數據載入完成，總共 \(events.count) 個事件")
    }
    
    // MARK: - 統計功能
    
    func getEventsForDate(_ date: Date) -> [Event] {
        return sqliteManager.getEventsForDate(date)
    }
    
    func getExpenseEventsForDate(_ date: Date) -> [Event] {
        return sqliteManager.getExpenseEventsForDate(date)
    }
    
    func getTotalExpenseForDate(_ date: Date) -> Double {
        return sqliteManager.getTotalExpenseForDate(date)
    }
    
    func getCategoryExpenses() -> [CategoryExpense] {
        return sqliteManager.getCategoryExpenses()
    }

    func uploadSharedEvents(for date: Date, completion: @escaping (Result<Int, SharedEventUploader.UploadError>) -> Void) {
        let sharedEvents = getEventsForDate(date).filter { $0.isShared }
        guard !sharedEvents.isEmpty else {
            completion(.failure(.noSharedEvents))
            return
        }
        SharedEventUploader.shared.uploadSharedEvents(sharedEvents, completion: completion)
    }

    @discardableResult
    func addEvent(from text: String, defaultDate: Date = Date()) -> Event? {
        guard let parsed = TextToEventParser.parse(text: text, defaultDate: defaultDate) else {
            print("Text parse failed: empty or invalid text")
            return nil
        }
        return addEvent(parsed)
    }

    func exportEvents(for date: Date) -> URL? {
        let eventsForDate = getEventsForDate(date)
        guard !eventsForDate.isEmpty else { return nil }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        do {
            let data = try encoder.encode(eventsForDate)
            let filename = "events-\(formatDateForFilename(date)).json"
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
            try data.write(to: tempURL, options: .atomic)
            return tempURL
        } catch {
            print("匯出指定日期事件失敗: \(error)")
            return nil
        }
    }
    
    // MARK: - 數據管理
    
    func clearAllData() {
        if sqliteManager.clearAllData() {
            events = []
        }
    }
    
    func resetToSampleData() {
        // 清空數據庫和內存
        if sqliteManager.clearAllData() {
            events = []
        }
        // 載入示例數據
        loadSampleData()
    }
    
    func exportData() -> Data? {
        let header = [
            "id",
            "title",
            "description",
            "date",
            "color",
            "amount",
            "category",
            "isExpense",
            "shareGroupSize",
            "splitMethod"
        ].joined(separator: ",")
        
        let rows = events.map { event in
            [
                event.id.uuidString,
                csvEscape(event.title),
                csvEscape(event.description),
                isoFormatter.string(from: event.date),
                event.color.rawValue,
                event.amount.map { String($0) } ?? "",
                event.category.rawValue,
                event.isExpense ? "1" : "0",
                String(max(1, event.shareGroupSize)),
                event.splitMethod.rawValue
            ].joined(separator: ",")
        }
        
        let csvString = ([header] + rows).joined(separator: "\n")
        return csvString.data(using: .utf8)
    }

    func exportDataToFile() -> URL? {
        guard let data = exportData() else { return nil }
        let filename = "events-all.csv"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            print("導出檔案失敗: \(error)")
            return nil
        }
    }
    
    func importData(from data: Data) -> Bool {
        do {
            // 嘗試解析 CSV
            if let csvString = String(data: data, encoding: .utf8),
               let importedEvents = parseCSV(csvString) {
                clearAllData()
                for event in importedEvents {
                    let sanitizedEvent = normalizeEvent(event)
                    switch sqliteManager.insertEvent(sanitizedEvent) {
                    case .success:
                        events.append(sanitizedEvent)
                    case .constraint(let message):
                        if message.contains("events.id") {
                            print("導入事件 ID 衝突: \(sanitizedEvent.id)")
                        } else {
                            print("導入事件違反約束: \(message)")
                        }
                    case .failure(let message):
                        print("導入事件失敗: \(message)")
                    }
                }
                return true
            }
            
            // Fallback JSON
            let importedEvents = try JSONDecoder().decode([Event].self, from: data)
            // 清空現有數據
            clearAllData()
            // 插入新數據
            for event in importedEvents {
                let sanitizedEvent = normalizeEvent(event)
                switch sqliteManager.insertEvent(sanitizedEvent) {
                case .success:
                    events.append(sanitizedEvent)
                case .constraint(let message):
                    if message.contains("events.id") {
                        print("導入事件 ID 衝突: \(sanitizedEvent.id)")
                    } else {
                        print("導入事件違反約束: \(message)")
                    }
                case .failure(let message):
                    print("導入事件失敗: \(message)")
                }
            }
            return true
        } catch {
            print("導入數據失敗: \(error)")
            return false
        }
    }
    
    // MARK: - 資料校正
    
    private func normalizeEvent(_ event: Event) -> Event {
        var normalized = event
        normalized.shareGroupSize = max(1, normalized.shareGroupSize)
        if normalized.shareGroupSize == 1 {
            normalized.splitMethod = .personal
        } else if normalized.splitMethod == .personal {
            normalized.splitMethod = .aa
        }
        let trimmedGroup = normalized.groupId?.trimmingCharacters(in: .whitespacesAndNewlines)
        normalized.groupId = (trimmedGroup?.isEmpty == true) ? nil : trimmedGroup
        let trimmedAuthor = normalized.author?.trimmingCharacters(in: .whitespacesAndNewlines)
        normalized.author = (trimmedAuthor?.isEmpty == true) ? "local" : (trimmedAuthor ?? "local")
        if normalized.updatedAt.timeIntervalSince1970 <= 0 {
            normalized.updatedAt = Date()
        }
        return normalized
    }

    private func formatDateForFilename(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd"
        return formatter.string(from: date)
    }

    private func csvEscape(_ value: String) -> String {
        var escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
        if escaped.contains(",") || escaped.contains("\"") || escaped.contains("\n") {
            escaped = "\"\(escaped)\""
        }
        return escaped
    }

    private func parseCSV(_ csv: String) -> [Event]? {
        let lines = csv.split(whereSeparator: \.isNewline).map { String($0) }
        guard !lines.isEmpty else { return [] }
        let dataLines = lines.dropFirst() // skip header
        var results: [Event] = []
        for line in dataLines {
            let columns = parseCSVLine(line)
            guard columns.count >= 10 else { continue }
            let id = UUID(uuidString: columns[0]) ?? UUID()
            let title = columns[1]
            let description = columns[2]
            let dateString = columns[3]
            guard let date = isoFormatter.date(from: dateString) else { continue }
            let color = Event.EventColor(rawValue: columns[4]) ?? .blue
            let amount = Double(columns[5])
            let category = Event.ExpenseCategory(rawValue: columns[6]) ?? .other
            let isExpense = columns[7] == "1" || columns[7].lowercased() == "true"
            let shareGroupSize = Int(columns[8]) ?? 1
            let splitMethod = Event.SplitMethod(rawValue: columns[9]) ?? .personal

            results.append(Event(
                id: id,
                title: title,
                description: description,
                date: date,
                color: color,
                amount: amount,
                category: category,
                isExpense: isExpense,
                shareGroupSize: shareGroupSize,
                splitMethod: splitMethod
            ))
        }
        return results
    }

    private func parseCSVLine(_ line: String) -> [String] {
        var result: [String] = []
        var current = ""
        var inQuotes = false
        var iterator = line.makeIterator()
        while let char = iterator.next() {
            if char == "\"" {
                if inQuotes {
                    if let next = iterator.next() {
                        if next == "\"" {
                            current.append("\"")
                        } else {
                            inQuotes = false
                            if next == "," {
                                result.append(current)
                                current = ""
                            } else {
                                current.append(next)
                            }
                        }
                    } else {
                        inQuotes = false
                    }
                } else {
                    inQuotes = true
                }
            } else if char == "," && !inQuotes {
                result.append(current)
                current = ""
            } else {
                current.append(char)
            }
        }
        result.append(current)
        return result
    }
}
