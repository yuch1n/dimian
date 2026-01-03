import SwiftUI

struct EventListView: View {
    let selectedDate: Date
    @Binding var events: [Event]
    let onEditEvent: (Event) -> Void
    let onDeleteEvent: (UUID) -> Void
    
    private let calendar = Calendar.current
    private let dateFormatter = DateFormatter()
    
    init(selectedDate: Date, events: Binding<[Event]>, onEditEvent: @escaping (Event) -> Void, onDeleteEvent: @escaping (UUID) -> Void) {
        self.selectedDate = selectedDate
        self._events = events
        self.onEditEvent = onEditEvent
        self.onDeleteEvent = onDeleteEvent
        dateFormatter.locale = Locale(identifier: "zh_TW")
        dateFormatter.dateFormat = "yyyy年MM月dd日 EEEE"
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 選中日期標題和支出統計
            VStack(spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("選中的日期")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Text(dateFormatter.string(from: selectedDate))
                            .font(.title3)
                            .fontWeight(.semibold)
                    }
                    
                    Spacer()
                    
                    Text("\(eventsForSelectedDate.count) 個活動")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.gray.opacity(0.2))
                        .cornerRadius(12)
                }
                
                // 每日支出統計
                if !expenseEvents.isEmpty {
                    HStack {
                        Image(systemName: "creditcard")
                            .foregroundColor(.red)
                        Text("今日支出")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Spacer()
                        Text("NT$ \(String(format: "%.0f", totalExpense))")
                            .font(.title3)
                            .fontWeight(.bold)
                            .foregroundColor(.red)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Color.red.opacity(0.1))
                    .cornerRadius(8)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 6)
            
            Divider()
            
            // 活動列表
            if eventsForSelectedDate.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "calendar.badge.plus")
                        .font(.system(size: 48))
                        .foregroundColor(.gray.opacity(0.6))
                    
                    Text("這一天沒有活動")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    
                    Text("點擊 + 按鈕添加新活動")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.top, 6)
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(eventsForSelectedDate) { event in
                            EventRowView(
                                event: event,
                                onEdit: { editEvent(event) },
                                onDelete: { deleteEvent(event) }
                            )
                            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                Button("刪除", role: .destructive) {
                                    deleteEvent(event)
                                }
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button("編輯") {
                                    editEvent(event)
                                }
                                .tint(.blue)
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                }
            }
        }
        .background(Color(.systemBackground))
    }
    
    private var eventsForSelectedDate: [Event] {
        events.filter { event in
            calendar.isDate(event.date, inSameDayAs: selectedDate)
        }.sorted { $0.date < $1.date }
    }
    
    private var expenseEvents: [Event] {
        eventsForSelectedDate.filter { $0.isExpense && $0.amount != nil }
    }
    
    private var totalExpense: Double {
        expenseEvents.compactMap { $0.amount }.reduce(0, +)
    }
    
    private func deleteEvent(_ eventToDelete: Event) {
        onDeleteEvent(eventToDelete.id)
    }
    
    private func editEvent(_ event: Event) {
        onEditEvent(event)
    }
}

struct EventRowView: View {
    let event: Event
    let onEdit: () -> Void
    let onDelete: () -> Void
    
    private let timeFormatter = DateFormatter()
    
    init(event: Event, onEdit: @escaping () -> Void, onDelete: @escaping () -> Void) {
        self.event = event
        self.onEdit = onEdit
        self.onDelete = onDelete
        timeFormatter.locale = Locale(identifier: "zh_TW")
        timeFormatter.dateFormat = "HH:mm"
    }
    
    var body: some View {
        HStack(spacing: 12) {
            // 時間標籤
            VStack(alignment: .leading, spacing: 2) {
                Text(timeFormatter.string(from: event.date))
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
            }
            .frame(width: 50, alignment: .leading)
            
            // 類別圖標或顏色指示器
            if event.isExpense {
                Image(systemName: event.category.icon)
                    .foregroundColor(event.color.color)
                    .frame(width: 20, height: 20)
            } else {
                Circle()
                    .fill(event.color.color)
                    .frame(width: 12, height: 12)
            }
            
            // 活動內容
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(event.title)
                        .font(.headline)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                    
                    Spacer()
                    
                    if event.isExpense, let amount = event.amount {
                        Text("NT$ \(String(format: "%.0f", amount))")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.red)
                    }
                }
                
                if !event.description.isEmpty {
                    Text(event.description)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
                
                if event.isExpense {
                    Text(event.category.rawValue)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color.gray.opacity(0.2))
                        .cornerRadius(4)
                }
                
                if event.isShared {
                    HStack(spacing: 8) {
                        Label("\(event.shareGroupSize) 人", systemImage: "person.2")
                            .font(.caption)
                            .foregroundColor(.blue)
                        
                        Text(event.splitMethod.displayName)
                            .font(.caption)
                            .foregroundColor(.blue)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Color.blue.opacity(0.1))
                            .cornerRadius(4)
                        
                        if event.splitMethod == .aa, let amount = event.amount {
                            let perPerson = amount / Double(max(event.shareGroupSize, 1))
                            Text("每人 NT$ \(String(format: "%.0f", perPerson))")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(Color.yellow.opacity(0.4))
                                .cornerRadius(4)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 4)
                                        .stroke(Color.yellow.opacity(0.6), lineWidth: 0.5)
                                )
                        }
                    }
                }
            }
            
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(.systemGray6))
        .cornerRadius(12)
        .contextMenu {
            Button(action: onEdit) {
                Label("編輯", systemImage: "pencil")
            }
            
            Button(action: onDelete) {
                Label("刪除", systemImage: "trash")
            }
            .foregroundColor(.red)
        }
    }
}

#Preview {
    EventListView(selectedDate: Date(), events: .constant(Event.sampleEvents), onEditEvent: { _ in }, onDeleteEvent: { _ in })
        .frame(height: 300)
}
