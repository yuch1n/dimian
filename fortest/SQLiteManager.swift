import Foundation
import SQLite3

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

class SQLiteManager {
    static let shared = SQLiteManager()
    
    private var db: OpaquePointer?
    private let dbPath: String
    private var hasShareColumns = false
    private var hasSyncColumns = false
    private let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    private let legacyISOFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
    
    private init() {
        let fileManager = FileManager.default
        let documentsPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        dbPath = documentsPath.appendingPathComponent("events.db").path
        
        openDatabase()
        createTable()
        migrateDatabaseIfNeeded()
    }
    
    deinit {
        closeDatabase()
    }
    
    // MARK: - 數據庫連接
    
    private func openDatabase() {
        if sqlite3_open(dbPath, &db) != SQLITE_OK {
            print("無法打開數據庫: \(String(cString: sqlite3_errmsg(db)))")
        } else {
            print("數據庫連接成功: \(dbPath)")
            sqlite3_busy_timeout(db, 2000)
            if sqlite3_exec(db, "PRAGMA encoding = 'UTF-8';", nil, nil, nil) != SQLITE_OK {
                print("設定 UTF-8 編碼失敗: \(String(cString: sqlite3_errmsg(db)))")
            }
            if sqlite3_exec(db, "PRAGMA journal_mode=WAL;", nil, nil, nil) != SQLITE_OK {
                print("設定 WAL 模式失敗: \(String(cString: sqlite3_errmsg(db)))")
            }
        }
    }
    
    private func closeDatabase() {
        if sqlite3_close(db) != SQLITE_OK {
            print("無法關閉數據庫: \(String(cString: sqlite3_errmsg(db)))")
        }
    }
    
    // MARK: - 表結構創建
    
    private func createTable() {
        let createTableSQL = """
            CREATE TABLE IF NOT EXISTS events (
                id TEXT PRIMARY KEY,
                title TEXT NOT NULL,
                description TEXT,
                date TEXT NOT NULL,
                color TEXT NOT NULL,
                amount REAL,
                category TEXT NOT NULL,
                isExpense INTEGER NOT NULL,
                share_group_size INTEGER NOT NULL DEFAULT 1,
                split_method TEXT NOT NULL DEFAULT 'personal',
                group_id TEXT,
                updated_at TEXT NOT NULL DEFAULT '',
                author TEXT,
                sync_status TEXT NOT NULL DEFAULT 'synced'
            );
        """
        
        if sqlite3_exec(db, createTableSQL, nil, nil, nil) != SQLITE_OK {
            print("創建表失敗: \(String(cString: sqlite3_errmsg(db)))")
        } else {
            print("表創建成功")
        }
    }

    private func migrateDatabaseIfNeeded() {
        let expectedColumns: [String: String] = [
            "amount": "ALTER TABLE events ADD COLUMN amount REAL;",
            "category": "ALTER TABLE events ADD COLUMN category TEXT NOT NULL DEFAULT '其他';",
            "isExpense": "ALTER TABLE events ADD COLUMN isExpense INTEGER NOT NULL DEFAULT 0;",
            "share_group_size": "ALTER TABLE events ADD COLUMN share_group_size INTEGER NOT NULL DEFAULT 1;",
            "split_method": "ALTER TABLE events ADD COLUMN split_method TEXT NOT NULL DEFAULT 'personal';",
            "group_id": "ALTER TABLE events ADD COLUMN group_id TEXT;",
            "updated_at": "ALTER TABLE events ADD COLUMN updated_at TEXT NOT NULL DEFAULT '';",
            "author": "ALTER TABLE events ADD COLUMN author TEXT;",
            "sync_status": "ALTER TABLE events ADD COLUMN sync_status TEXT NOT NULL DEFAULT 'synced';"
        ]

        var existingColumns = fetchColumnNames()

        for (column, alterSQL) in expectedColumns where !existingColumns.contains(column) {
            if sqlite3_exec(db, alterSQL, nil, nil, nil) == SQLITE_OK {
                print("資料庫遷移: 新增欄位 \(column)")
                existingColumns.insert(column)

                switch column {
                case "category":
                    let updateSQL = "UPDATE events SET category = '其他' WHERE category IS NULL OR TRIM(category) = '';"
                    if sqlite3_exec(db, updateSQL, nil, nil, nil) != SQLITE_OK {
                        print("更新預設類別失敗: \(String(cString: sqlite3_errmsg(db)))")
                    }
                case "isExpense":
                    let updateSQL = "UPDATE events SET isExpense = CASE WHEN amount IS NULL OR amount = 0 THEN 0 ELSE 1 END;"
                    if sqlite3_exec(db, updateSQL, nil, nil, nil) != SQLITE_OK {
                        print("更新預設支出標記失敗: \(String(cString: sqlite3_errmsg(db)))")
                    }
                case "updated_at":
                    let nowString = isoFormatter.string(from: Date())
                    let updateSQL = "UPDATE events SET updated_at = '\(nowString)' WHERE updated_at IS NULL OR TRIM(updated_at) = '';"
                    if sqlite3_exec(db, updateSQL, nil, nil, nil) != SQLITE_OK {
                        print("更新預設 updated_at 失敗: \(String(cString: sqlite3_errmsg(db)))")
                    }
                case "sync_status":
                    let updateSQL = "UPDATE events SET sync_status = 'synced' WHERE sync_status IS NULL OR TRIM(sync_status) = '';"
                    if sqlite3_exec(db, updateSQL, nil, nil, nil) != SQLITE_OK {
                        print("更新預設 sync_status 失敗: \(String(cString: sqlite3_errmsg(db)))")
                    }
                default:
                    break
                }
            } else {
                print("資料庫遷移失敗 (\(column)): \(String(cString: sqlite3_errmsg(db)))")
            }
        }
        
        hasShareColumns = existingColumns.contains("share_group_size") && existingColumns.contains("split_method")
        hasSyncColumns = existingColumns.contains("group_id") && existingColumns.contains("updated_at") && existingColumns.contains("sync_status")
    }
    
    // MARK: - 數據操作
    
    enum InsertResult {
        case success
        case constraint(String)
        case failure(String)
    }

    func insertEvent(_ event: Event) -> InsertResult {
        print("SQLite: 嘗試插入事件 - \(event.title)")
        ensureShareColumnStatus()
        let insertSQL: String
        if hasShareColumns && hasSyncColumns {
            insertSQL = """
            INSERT INTO events (id, title, description, date, color, amount, category, isExpense, share_group_size, split_method, group_id, updated_at, author, sync_status)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
        """
        } else if hasShareColumns {
            insertSQL = """
            INSERT INTO events (id, title, description, date, color, amount, category, isExpense, share_group_size, split_method)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
        """
        } else {
            insertSQL = """
            INSERT INTO events (id, title, description, date, color, amount, category, isExpense)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?);
        """
        }
        
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        
        guard sqlite3_prepare_v2(db, insertSQL, -1, &statement, nil) == SQLITE_OK else {
            let message = String(cString: sqlite3_errmsg(db))
            print("準備語句失敗: \(message)")
            return .failure(message)
        }
        
        var parameterIndex: Int32 = 1
        bindText(statement, index: parameterIndex, value: event.id.uuidString)
        parameterIndex += 1
        bindText(statement, index: parameterIndex, value: event.title)
        parameterIndex += 1
        bindText(statement, index: parameterIndex, value: event.description)
        parameterIndex += 1
        bindText(statement, index: parameterIndex, value: isoFormatter.string(from: event.date))
        parameterIndex += 1
        bindText(statement, index: parameterIndex, value: event.color.colorString)
        parameterIndex += 1
        
        if let amount = event.amount {
            sqlite3_bind_double(statement, parameterIndex, amount)
        } else {
            sqlite3_bind_null(statement, parameterIndex)
        }
        parameterIndex += 1
        
        bindText(statement, index: parameterIndex, value: event.category.rawValue)
        parameterIndex += 1
        sqlite3_bind_int(statement, parameterIndex, event.isExpense ? 1 : 0)
        parameterIndex += 1
        
        if hasShareColumns {
            sqlite3_bind_int(statement, parameterIndex, Int32(max(1, event.shareGroupSize)))
            parameterIndex += 1
            bindText(statement, index: parameterIndex, value: event.splitMethod.rawValue)
            parameterIndex += 1
        }
        if hasShareColumns && hasSyncColumns {
            bindText(statement, index: parameterIndex, value: event.groupId ?? "")
            parameterIndex += 1
            bindText(statement, index: parameterIndex, value: isoFormatter.string(from: event.updatedAt))
            parameterIndex += 1
            bindText(statement, index: parameterIndex, value: event.author ?? "")
            parameterIndex += 1
            bindText(statement, index: parameterIndex, value: event.syncStatus.rawValue)
            parameterIndex += 1
        }
        
        let stepResult = sqlite3_step(statement)
        switch stepResult {
        case SQLITE_DONE:
            print("SQLite: 事件插入成功 - \(event.title)")
            return .success
        case SQLITE_CONSTRAINT:
            let message = String(cString: sqlite3_errmsg(db))
            print("SQLite: 插入數據失敗 (約束): \(message)")
            return .constraint(message)
        default:
            let message = String(cString: sqlite3_errmsg(db))
            print("SQLite: 插入數據失敗: \(message) (code: \(stepResult))")
            return .failure(message)
        }
    }
    
    func updateEvent(_ event: Event) -> Bool {
        ensureShareColumnStatus()
        let updateSQL: String
        if hasShareColumns && hasSyncColumns {
            updateSQL = """
            UPDATE events 
            SET title = ?, description = ?, date = ?, color = ?, amount = ?, category = ?, isExpense = ?, share_group_size = ?, split_method = ?, group_id = ?, updated_at = ?, author = ?, sync_status = ?
            WHERE id = ?;
        """
        } else if hasShareColumns {
            updateSQL = """
            UPDATE events 
            SET title = ?, description = ?, date = ?, color = ?, amount = ?, category = ?, isExpense = ?, share_group_size = ?, split_method = ?
            WHERE id = ?;
        """
        } else {
            updateSQL = """
            UPDATE events 
            SET title = ?, description = ?, date = ?, color = ?, amount = ?, category = ?, isExpense = ?
            WHERE id = ?;
        """
        }
        
        var statement: OpaquePointer?
        if sqlite3_prepare_v2(db, updateSQL, -1, &statement, nil) == SQLITE_OK {
            var parameterIndex: Int32 = 1
            bindText(statement, index: parameterIndex, value: event.title)
            parameterIndex += 1
            bindText(statement, index: parameterIndex, value: event.description)
            parameterIndex += 1
            bindText(statement, index: parameterIndex, value: isoFormatter.string(from: event.date))
            parameterIndex += 1
            bindText(statement, index: parameterIndex, value: event.color.colorString)
            parameterIndex += 1
            
            if let amount = event.amount {
                sqlite3_bind_double(statement, parameterIndex, amount)
            } else {
                sqlite3_bind_null(statement, parameterIndex)
            }
            parameterIndex += 1
            
            bindText(statement, index: parameterIndex, value: event.category.rawValue)
            parameterIndex += 1
            sqlite3_bind_int(statement, parameterIndex, event.isExpense ? 1 : 0)
            parameterIndex += 1
            
            if hasShareColumns {
                sqlite3_bind_int(statement, parameterIndex, Int32(max(1, event.shareGroupSize)))
                parameterIndex += 1
                bindText(statement, index: parameterIndex, value: event.splitMethod.rawValue)
                parameterIndex += 1
            }

            if hasShareColumns && hasSyncColumns {
                bindText(statement, index: parameterIndex, value: event.groupId ?? "")
                parameterIndex += 1
                bindText(statement, index: parameterIndex, value: isoFormatter.string(from: event.updatedAt))
                parameterIndex += 1
                bindText(statement, index: parameterIndex, value: event.author ?? "")
                parameterIndex += 1
                bindText(statement, index: parameterIndex, value: event.syncStatus.rawValue)
                parameterIndex += 1
            }
            
            bindText(statement, index: parameterIndex, value: event.id.uuidString)
            
            if sqlite3_step(statement) == SQLITE_DONE {
                sqlite3_finalize(statement)
                return true
            } else {
                print("更新數據失敗: \(String(cString: sqlite3_errmsg(db)))")
            }
        } else {
            print("準備語句失敗: \(String(cString: sqlite3_errmsg(db)))")
        }
        
        sqlite3_finalize(statement)
        return false
    }
    
    func deleteEvent(withId id: UUID) -> Bool {
        let deleteSQL = "DELETE FROM events WHERE id = ?;"
        
        var statement: OpaquePointer?
        
        if sqlite3_prepare_v2(db, deleteSQL, -1, &statement, nil) == SQLITE_OK {
            bindText(statement, index: 1, value: id.uuidString)
            
            if sqlite3_step(statement) == SQLITE_DONE {
                sqlite3_finalize(statement)
                return true
            } else {
                print("刪除數據失敗: \(String(cString: sqlite3_errmsg(db)))")
            }
        } else {
            print("準備語句失敗: \(String(cString: sqlite3_errmsg(db)))")
        }
        
        sqlite3_finalize(statement)
        return false
    }
    
    func getAllEvents() -> [Event] {
        let querySQL = "SELECT * FROM events ORDER BY date DESC;"
        
        var statement: OpaquePointer?
        var events: [Event] = []
        
        if sqlite3_prepare_v2(db, querySQL, -1, &statement, nil) == SQLITE_OK {
            while sqlite3_step(statement) == SQLITE_ROW {
                if let event = parseEvent(from: statement) {
                    events.append(event)
                }
            }
        } else {
            print("查詢數據失敗: \(String(cString: sqlite3_errmsg(db)))")
        }
        
        sqlite3_finalize(statement)
        return events
    }

    func eventExists(withId id: UUID) -> Bool {
        let querySQL = "SELECT 1 FROM events WHERE id = ? LIMIT 1;"
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        
        if sqlite3_prepare_v2(db, querySQL, -1, &statement, nil) == SQLITE_OK {
            bindText(statement, index: 1, value: id.uuidString)
            let stepResult = sqlite3_step(statement)
            if stepResult == SQLITE_ROW {
                return true
            } else if stepResult == SQLITE_DONE {
                return false
            } else {
                if let errorPointer = sqlite3_errmsg(db) {
                    let message = String(cString: errorPointer)
                    print("檢查事件存在失敗: \(message)")
                } else {
                    print("檢查事件存在失敗: 未知錯誤")
                }
            }
        } else {
            if let errorPointer = sqlite3_errmsg(db) {
                let message = String(cString: errorPointer)
                print("準備存在查詢失敗: \(message)")
            } else {
                print("準備存在查詢失敗: 未知錯誤")
            }
        }
        
        return false
    }
    
    func getEventsForDate(_ date: Date) -> [Event] {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!
        
        let querySQL = """
            SELECT * FROM events 
            WHERE date >= ? AND date < ? 
            ORDER BY date ASC;
        """
        
        var statement: OpaquePointer?
        var events: [Event] = []
        
        if sqlite3_prepare_v2(db, querySQL, -1, &statement, nil) == SQLITE_OK {
            bindText(statement, index: 1, value: isoFormatter.string(from: startOfDay))
            bindText(statement, index: 2, value: isoFormatter.string(from: endOfDay))
            
            while sqlite3_step(statement) == SQLITE_ROW {
                if let event = parseEvent(from: statement) {
                    events.append(event)
                }
            }
        } else {
            print("查詢數據失敗: \(String(cString: sqlite3_errmsg(db)))")
        }
        
        sqlite3_finalize(statement)
        return events
    }
    
    func getExpenseEventsForDate(_ date: Date) -> [Event] {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!
        
        let querySQL = """
            SELECT * FROM events 
            WHERE date >= ? AND date < ? AND isExpense = 1 AND amount IS NOT NULL
            ORDER BY date ASC;
        """
        
        var statement: OpaquePointer?
        var events: [Event] = []
        
        if sqlite3_prepare_v2(db, querySQL, -1, &statement, nil) == SQLITE_OK {
            bindText(statement, index: 1, value: isoFormatter.string(from: startOfDay))
            bindText(statement, index: 2, value: isoFormatter.string(from: endOfDay))
            
            while sqlite3_step(statement) == SQLITE_ROW {
                if let event = parseEvent(from: statement) {
                    events.append(event)
                }
            }
        } else {
            print("查詢數據失敗: \(String(cString: sqlite3_errmsg(db)))")
        }
        
        sqlite3_finalize(statement)
        return events
    }
    
    func getTotalExpenseForDate(_ date: Date) -> Double {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!
        
        let querySQL = """
            SELECT SUM(amount) FROM events 
            WHERE date >= ? AND date < ? AND isExpense = 1 AND amount IS NOT NULL;
        """
        
        var statement: OpaquePointer?
        var total: Double = 0.0
        
        if sqlite3_prepare_v2(db, querySQL, -1, &statement, nil) == SQLITE_OK {
            bindText(statement, index: 1, value: isoFormatter.string(from: startOfDay))
            bindText(statement, index: 2, value: isoFormatter.string(from: endOfDay))
            
            if sqlite3_step(statement) == SQLITE_ROW {
                total = sqlite3_column_double(statement, 0)
            }
        } else {
            print("查詢數據失敗: \(String(cString: sqlite3_errmsg(db)))")
        }
        
        sqlite3_finalize(statement)
        return total
    }
    
    func getCategoryExpenses() -> [CategoryExpense] {
        let querySQL = """
            SELECT category, SUM(amount) as total, COUNT(*) as count
            FROM events 
            WHERE isExpense = 1 AND amount IS NOT NULL
            GROUP BY category
            ORDER BY total DESC;
        """
        
        var statement: OpaquePointer?
        var expenses: [CategoryExpense] = []
        
        if sqlite3_prepare_v2(db, querySQL, -1, &statement, nil) == SQLITE_OK {
            while sqlite3_step(statement) == SQLITE_ROW {
                let categoryString = String(cString: sqlite3_column_text(statement, 0))
                let total = sqlite3_column_double(statement, 1)
                let count = sqlite3_column_int(statement, 2)
                
                if let category = Event.ExpenseCategory(rawValue: categoryString) {
                    expenses.append(CategoryExpense(category: category, amount: total, count: Int(count)))
                }
            }
        } else {
            print("查詢數據失敗: \(String(cString: sqlite3_errmsg(db)))")
        }
        
        sqlite3_finalize(statement)
        return expenses
    }
    
    func clearAllData() -> Bool {
        let deleteSQL = "DELETE FROM events;"
        
        if sqlite3_exec(db, deleteSQL, nil, nil, nil) == SQLITE_OK {
            return true
        } else {
            print("清空數據失敗: \(String(cString: sqlite3_errmsg(db)))")
            return false
        }
    }
    
    // MARK: - 數據解析
    
    private func parseEvent(from statement: OpaquePointer?) -> Event? {
        guard let statement = statement else { return nil }
        
        guard let idString = stringColumn(statement, index: 0),
              let id = UUID(uuidString: idString) else { return nil }
        
        let title = stringColumn(statement, index: 1) ?? "未命名活動"
        let description = stringColumn(statement, index: 2) ?? ""
        
        guard let dateString = stringColumn(statement, index: 3) else {
            print("日期欄位為空，無法解析事件")
            return nil
        }
        guard let date = isoFormatter.date(from: dateString) ?? legacyISOFormatter.date(from: dateString) else {
            print("日期解析失敗: \(dateString)")
            return nil
        }
        
        let colorString = stringColumn(statement, index: 4) ?? Event.EventColor.blue.rawValue
        let color = Event.EventColor(rawValue: colorString) ?? .blue
        
        let amount: Double? = sqlite3_column_type(statement, 5) == SQLITE_NULL ? nil : sqlite3_column_double(statement, 5)
        
        let categoryString = stringColumn(statement, index: 6) ?? Event.ExpenseCategory.other.rawValue
        let category = Event.ExpenseCategory(rawValue: categoryString) ?? .other
        
        let isExpense = sqlite3_column_int(statement, 7) == 1
        
        var shareGroupSize = 1
        var splitMethod: Event.SplitMethod = .personal
        var groupId: String? = nil
        var author: String? = nil
        var updatedAt = date
        var syncStatus: Event.SyncStatus = .synced
        let columnCount = sqlite3_column_count(statement)
        if columnCount > 8 {
            shareGroupSize = max(1, Int(sqlite3_column_int(statement, 8)))
        }
        if columnCount > 9,
           sqlite3_column_type(statement, 9) != SQLITE_NULL,
           let splitMethodPointer = sqlite3_column_text(statement, 9) {
            let splitMethodString = String(cString: splitMethodPointer)
            splitMethod = Event.SplitMethod(rawValue: splitMethodString) ?? (shareGroupSize > 1 ? .aa : .personal)
        } else if shareGroupSize > 1 {
            splitMethod = .aa
        }
        if columnCount > 10 {
            groupId = stringColumn(statement, index: 10)
        }
        if columnCount > 11,
           let updatedAtString = stringColumn(statement, index: 11) {
            let fallbackFormatter = DateFormatter()
            fallbackFormatter.locale = Locale(identifier: "en_US_POSIX")
            fallbackFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
            updatedAt = isoFormatter.date(from: updatedAtString)
                ?? legacyISOFormatter.date(from: updatedAtString)
                ?? fallbackFormatter.date(from: updatedAtString)
                ?? date
        }
        if columnCount > 12 {
            author = stringColumn(statement, index: 12)
        }
        if columnCount > 13,
           let statusString = stringColumn(statement, index: 13),
           let status = Event.SyncStatus(rawValue: statusString) {
            syncStatus = status
        }
        
        return Event(
            id: id,
            title: title,
            description: description,
            date: date,
            color: color,
            amount: amount,
            category: category,
            isExpense: isExpense,
            shareGroupSize: shareGroupSize,
            splitMethod: splitMethod,
            groupId: groupId,
            author: author,
            updatedAt: updatedAt,
            syncStatus: syncStatus
        )
    }

    private func bindText(_ statement: OpaquePointer?, index: Int32, value: String) {
        guard let data = value.data(using: .utf8) else {
            sqlite3_bind_null(statement, index)
            return
        }
        if data.isEmpty {
            sqlite3_bind_text(statement, index, "", 0, SQLITE_TRANSIENT)
            return
        }
        data.withUnsafeBytes { buffer in
            let baseAddress = buffer.bindMemory(to: Int8.self).baseAddress
            sqlite3_bind_text(statement, index, baseAddress, Int32(data.count), SQLITE_TRANSIENT)
        }
    }
    
    private func stringColumn(_ statement: OpaquePointer, index: Int32) -> String? {
        guard index >= 0 && index < sqlite3_column_count(statement) else { return nil }
        guard sqlite3_column_type(statement, index) != SQLITE_NULL else { return nil }
        guard let pointer = sqlite3_column_text(statement, index) else { return nil }
        let length = Int(sqlite3_column_bytes(statement, index))
        let data = Data(bytes: pointer, count: length)
        if let string = String(data: data, encoding: .utf8) {
            return string
        } else {
            let rawPointer = UnsafeRawPointer(pointer).assumingMemoryBound(to: CChar.self)
            return String(cString: rawPointer)
        }
    }
    
    private func fetchColumnNames() -> Set<String> {
        var columns = Set<String>()
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        
        if sqlite3_prepare_v2(db, "PRAGMA table_info(events);", -1, &statement, nil) == SQLITE_OK {
            while sqlite3_step(statement) == SQLITE_ROW {
                if let columnNamePointer = sqlite3_column_text(statement, 1) {
                    let columnName = String(cString: columnNamePointer)
                    columns.insert(columnName)
                }
            }
        } else {
            print("讀取欄位資訊失敗: \(String(cString: sqlite3_errmsg(db)))")
        }
        
        return columns
    }
    
    private func ensureShareColumnStatus() {
        if hasShareColumns && hasSyncColumns { return }
        let columns = fetchColumnNames()
        hasShareColumns = columns.contains("share_group_size") && columns.contains("split_method")
        hasSyncColumns = columns.contains("group_id") && columns.contains("updated_at") && columns.contains("sync_status")
    }
}
