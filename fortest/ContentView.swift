
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var dataManager = EventDataManager()
    @State private var selectedDate = Date()
    @State private var showingNewEvent = false
    @State private var editingEvent: Event? = nil
    @State private var showingAnalytics = false
    @State private var showingClearConfirmation = false
    @State private var showingShareSheet = false
    @State private var shareItems: [Any] = []
    @State private var showingShareAlert = false
    @State private var shareAlertMessage = ""
    @State private var isUploadingShared = false
    @State private var showingUploadAlert = false
    @State private var uploadAlertMessage = ""
    @State private var showingTextImport = false
    @State private var showingImageImport = false
    @State private var showingFileImporter = false
    @State private var importError: String?
    
    private let shareDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_TW")
        formatter.dateFormat = "yyyy/MM/dd (EEE)"
        return formatter
    }()

    private let shareTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_TW")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()
    
    var body: some View {
        NavigationView {
            GeometryReader { geometry in
                VStack(spacing: 0) {
                    headerSection
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                        .padding(.bottom, 6)
                        .background(Color(.systemBackground))
                    
                    // 日曆區域 (微縮高度讓下方列表露出更多)
                    VStack {
                        CalendarView(selectedDate: $selectedDate, events: dataManager.events)
                            .padding(.top, 0)
                    }
                    .frame(height: geometry.size.height * 0.58)
                    .background(Color(.systemBackground))
                    
                    // 分隔線
                    Divider()
                    .background(Color.gray.opacity(0.3))
                    
                    // 活動列表區域 (加大高度)
                    
                    EventListView(selectedDate: selectedDate, events: $dataManager.events, onEditEvent: editEvent, onDeleteEvent: deleteEvent)
                        .frame(height: geometry.size.height * 0.42)
                }
            }
            .navigationBarHidden(true)
            .sheet(isPresented: $showingNewEvent) {
                EventEditView(
                    editingEvent: nil,
                    defaultDate: selectedDate,
                    onSave: { event in
                        addNewEvent(event)
                    }
                )
            }
            .sheet(item: $editingEvent) { event in
                EventEditView(
                    editingEvent: event,
                    defaultDate: event.date,
                    onSave: { updated in
                        updateEvent(updated)
                    }
                )
            }
            .sheet(isPresented: $showingAnalytics) {
                ExpenseAnalyticsView(dataManager: dataManager)
            }
            .sheet(isPresented: $showingShareSheet) {
                ShareSheet(activityItems: shareItems)
            }
            .sheet(isPresented: $showingImageImport) {
                ImageImportView(defaultDate: selectedDate) { event in
                    addNewEvent(event)
                }
            }
            .sheet(isPresented: $showingTextImport) {
                TextImportView(defaultDate: selectedDate) { event in
                    addNewEvent(event)
                }
            }
            .fileImporter(isPresented: $showingFileImporter, allowedContentTypes: csvAllowedTypes) { result in
                switch result {
                case .success(let url):
                    importFromFile(url)
                case .failure(let error):
                    importError = error.localizedDescription
                }
            }
            .alert("確定要清除所有活動嗎？", isPresented: $showingClearConfirmation) {
                Button("刪除", role: .destructive) {
                    clearAllEvents()
                }
                Button("取消", role: .cancel) { }
            } message: {
                Text("此操作僅供開發除錯使用。所有已儲存的行程都會被刪除。")
            }
            .alert("無法分享", isPresented: $showingShareAlert) {
                Button("知道了", role: .cancel) { }
            } message: {
                Text(shareAlertMessage)
            }
            .alert("上傳結果", isPresented: $showingUploadAlert) {
                Button("好的", role: .cancel) { }
            } message: {
                Text(uploadAlertMessage)
            }
            .alert("匯入失敗", isPresented: Binding(get: { importError != nil }, set: { _ in importError = nil })) {
                Button("好的", role: .cancel) { importError = nil }
            } message: {
                Text(importError ?? "")
            }
        }
    }
    
    private func addNewEvent(_ event: Event) {
        guard let savedEvent = dataManager.addEvent(event) else {
            return
        }
        // 如果新活動的日期不是當前選中的日期，切換到該日期
        if !Calendar.current.isDate(savedEvent.date, inSameDayAs: selectedDate) {
            selectedDate = savedEvent.date
        }
    }
    
    private func editEvent(_ event: Event) {
        editingEvent = event
    }
    
    private func updateEvent(_ updatedEvent: Event) {
        dataManager.updateEvent(updatedEvent)
    }
    
    private func deleteEvent(withId id: UUID) {
        dataManager.deleteEvent(withId: id)
    }

    private func clearAllEvents() {
        dataManager.clearAllData()
        selectedDate = Date()
    }

    private func shareItinerary() {
        let eventsForDay = dataManager.getEventsForDate(selectedDate).sorted { $0.date < $1.date }
        guard !eventsForDay.isEmpty else {
            shareAlertMessage = "這一天沒有可分享的行程。"
            showingShareAlert = true
            return
        }

        var lines: [String] = []
        lines.append("Dimian 行程分享")
        lines.append(shareDateFormatter.string(from: selectedDate))
        lines.append("")

        for event in eventsForDay {
            let timeString = shareTimeFormatter.string(from: event.date)
            var parts: [String] = []
            parts.append("[\(timeString)] \(event.title)")
            if !event.description.isEmpty {
                parts.append(event.description)
            }
            if event.isExpense, let amount = event.amount {
                parts.append("NT$ \(String(format: "%.0f", amount)) • \(event.category.rawValue)")
            }
            if event.isShared {
                parts.append("\(event.shareGroupSize)人 \(event.splitMethod.displayName)")
            }
            lines.append(parts.joined(separator: " ｜ "))
        }

        lines.append("")
        lines.append("附上 JSON 匯出檔，可匯入還原行程。")

        var items: [Any] = [lines.joined(separator: "\n")]
        if let fileURL = dataManager.exportEvents(for: selectedDate) {
            items.append(fileURL)
        }

        shareItems = items
        showingShareSheet = true
    }

    private func uploadSharedEvents() {
        let sharedEvents = dataManager.getEventsForDate(selectedDate).filter { $0.isShared }
        guard !sharedEvents.isEmpty else {
            uploadAlertMessage = "這一天沒有共享行程，無需上傳。"
            showingUploadAlert = true
            return
        }

        isUploadingShared = true
        dataManager.uploadSharedEvents(for: selectedDate) { result in
            DispatchQueue.main.async {
                isUploadingShared = false
                switch result {
                case .success(let count):
                    uploadAlertMessage = "已上傳 \(count) 筆共享行程。"
                case .failure(let error):
                    uploadAlertMessage = uploadErrorMessage(error)
                }
                showingUploadAlert = true
            }
        }
    }

    private func uploadErrorMessage(_ error: SharedEventUploader.UploadError) -> String {
        switch error {
        case .missingEndpoint:
            return "請在 Info.plist 設定 SharedEventsUploadURL 以完成上傳。"
        case .encodingFailed:
            return "資料編碼失敗，請稍後再試。"
        case .network(let err):
            return "網路錯誤：\(err.localizedDescription)"
        case .server(let status, let body):
            if let body, !body.isEmpty {
                return "伺服器回應錯誤 (\(status))：\(body)"
            } else {
                return "伺服器回應錯誤，狀態碼 \(status)。"
            }
        case .noSharedEvents:
            return "沒有共享行程可上傳。"
        }
    }

    private func exportAllEvents() {
        guard let url = dataManager.exportDataToFile() else {
            uploadAlertMessage = "匯出失敗，請稍後再試。"
            showingUploadAlert = true
            return
        }
        shareItems = [url]
        showingShareSheet = true
    }

    private func importFromFile(_ url: URL) {
        do {
            let data = try Data(contentsOf: url)
            if dataManager.importData(from: data) {
                selectedDate = Date()
            } else {
                importError = "匯入失敗，檔案格式可能不正確。"
            }
        } catch {
            importError = "讀取檔案失敗：\(error.localizedDescription)"
        }
    }

    private var csvAllowedTypes: [UTType] {
        var types: [UTType] = [.json, .plainText]
        if let csv = UTType("public.comma-separated-values-text") {
            types.append(csv)
        }
        if let csvExt = UTType(filenameExtension: "csv") {
            types.append(csvExt)
        }
        return types
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Dimian")
                .font(.largeTitle)
                .fontWeight(.bold)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    Button(action: { 
                        editingEvent = nil
                        showingNewEvent = true 
                    }) {
                        Label("新增行程", systemImage: "plus")
                            .labelStyle(.titleAndIcon)
                    }
                    .buttonStyle(.borderedProminent)

                    Button(action: { showingAnalytics = true }) {
                        Label("分析", systemImage: "chart.bar.xaxis")
                            .labelStyle(.titleAndIcon)
                    }
                    .buttonStyle(.bordered)
                    
                    Button(action: { showingImageImport = true }) {
                        Label("圖像", systemImage: "photo.on.rectangle")
                            .labelStyle(.titleAndIcon)
                    }
                    .buttonStyle(.bordered)

                    Button(action: { exportAllEvents() }) {
                        Label("匯出", systemImage: "square.and.arrow.up")
                            .labelStyle(.titleAndIcon)
                    }
                    .buttonStyle(.bordered)
                    
                    Button(action: { showingFileImporter = true }) {
                        Label("匯入", systemImage: "tray.and.arrow.down")
                            .labelStyle(.titleAndIcon)
                    }
                    .buttonStyle(.bordered)
                    
                    Button(action: { showingClearConfirmation = true }) {
                        Label("刪除", systemImage: "trash")
                            .labelStyle(.titleAndIcon)
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }
}

#Preview {
    ContentView()
}

struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
