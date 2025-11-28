//
//  EventEditView.swift
//  fortest
//
//  Created by Yuchen Yeh on 2025/9/11.
//

import SwiftUI

struct EventEditView: View {
    @Environment(\.presentationMode) var presentationMode
    @State private var title = ""
    @State private var description = ""
    @State private var selectedDate = Date()
    @State private var selectedTime = Date()
    @State private var selectedColor: Event.EventColor = .blue
    @State private var amount = ""
    @State private var selectedCategory: Event.ExpenseCategory = .other
    @State private var isExpense = false
    @State private var isShared = false
    @State private var shareGroupSize = 1
    @State private var selectedSplitMethod: Event.SplitMethod = .personal
    
    let editingEvent: Event?
    let defaultDate: Date
    let onSave: (Event) -> Void
    
    private let dateFormatter = DateFormatter()
    
    init(editingEvent: Event? = nil, defaultDate: Date, onSave: @escaping (Event) -> Void) {
        self.editingEvent = editingEvent
        self.defaultDate = defaultDate
        self.onSave = onSave
        dateFormatter.locale = Locale(identifier: "zh_TW")

        if let event = editingEvent {
            _title = State(initialValue: event.title)
            _description = State(initialValue: event.description)
            _selectedDate = State(initialValue: event.date)
            _selectedTime = State(initialValue: event.date)
            _selectedColor = State(initialValue: event.color)
            _amount = State(initialValue: event.amount.map { String(format: "%.0f", $0) } ?? "")
            _selectedCategory = State(initialValue: event.category)
            _isExpense = State(initialValue: event.isExpense)
            _shareGroupSize = State(initialValue: event.shareGroupSize)
            _selectedSplitMethod = State(initialValue: event.splitMethod)
            _isShared = State(initialValue: event.isShared)
        } else {
            _title = State(initialValue: "")
            _description = State(initialValue: "")
            _selectedDate = State(initialValue: defaultDate)
            _selectedTime = State(initialValue: Date())
            _selectedColor = State(initialValue: .blue)
            _amount = State(initialValue: "")
            _selectedCategory = State(initialValue: .food)
            _isExpense = State(initialValue: true)
            _shareGroupSize = State(initialValue: 1)
            _selectedSplitMethod = State(initialValue: .personal)
            _isShared = State(initialValue: false)
        }
    }
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("活動詳情")) {
                    TextField("活動標題", text: $title)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                    
                    TextField("活動描述", text: $description, axis: .vertical)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .lineLimit(3...6)
                }
                
                Section(header: Text("日期和時間")) {
                    DatePicker("日期", selection: $selectedDate, displayedComponents: .date)
                        .datePickerStyle(CompactDatePickerStyle())
                    
                    DatePicker("時間", selection: $selectedTime, displayedComponents: .hourAndMinute)
                        .datePickerStyle(CompactDatePickerStyle())
                }
                
                Section(header: Text("記帳設定")) {
                    Toggle("這是支出項目", isOn: $isExpense)
                    
                    if isExpense {
                        HStack {
                            Text("金額")
                            Spacer()
                            TextField("0", text: $amount)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                            Text("元")
                                .foregroundColor(.secondary)
                        }
                        
                        Picker("類別", selection: $selectedCategory) {
                            ForEach(Event.ExpenseCategory.allCases, id: \.self) { category in
                                HStack {
                                    Image(systemName: category.icon)
                                    Text(category.rawValue)
                                }
                                .tag(category)
                            }
                        }
                        .pickerStyle(MenuPickerStyle())
                    }
                }
                
                Section(header: Text("顏色標記")) {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 16) {
                        ForEach(Event.EventColor.allCases, id: \.self) { color in
                            ColorOptionView(
                                color: color,
                                isSelected: selectedColor == color,
                                onTap: { selectedColor = color }
                            )
                        }
                    }
                    .padding(.vertical, 8)
                }
                
                Section(header: Text("共享設定")) {
                    Toggle("多人共享", isOn: $isShared.animation())
                    
                    if isShared {
                        Stepper(value: $shareGroupSize, in: 2...20) {
                            HStack {
                                Text("參與人數")
                                Spacer()
                                Text("\(shareGroupSize) 人")
                                    .foregroundColor(.secondary)
                            }
                        }
                        Picker("均攤機制", selection: $selectedSplitMethod) {
                            ForEach(sharedSplitMethods, id: \.self) { method in
                                Text(method.displayName).tag(method)
                            }
                        }
                        .pickerStyle(SegmentedPickerStyle())
                    } else {
                        HStack {
                            Text("模式")
                            Spacer()
                            Text(Event.SplitMethod.personal.displayName)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .navigationTitle(editingEvent == nil ? "新增活動" : "編輯活動")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                if let event = editingEvent {
                    print("編輯模式 - 載入事件: \(event.title)")
                } else {
                    print("新增模式 - 初始化默認值，預設日期: \(defaultDate)")
                }
            }
            .onChange(of: isShared) { newValue in
                if newValue {
                    if shareGroupSize < 2 { shareGroupSize = 2 }
                    if selectedSplitMethod == .personal {
                        selectedSplitMethod = .aa
                    }
                } else {
                    shareGroupSize = 1
                    selectedSplitMethod = .personal
                }
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") {
                        presentationMode.wrappedValue.dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("儲存") {
                        saveEvent()
                    }
                    .disabled(title.isEmpty)
                }
            }
        }
    }
    
    private func saveEvent() {
        // 合併日期和時間
        let calendar = Calendar.current
        let dateComponents = calendar.dateComponents([.year, .month, .day], from: selectedDate)
        let timeComponents = calendar.dateComponents([.hour, .minute], from: selectedTime)
        
        var finalDateComponents = dateComponents
        finalDateComponents.hour = timeComponents.hour
        finalDateComponents.minute = timeComponents.minute
        
        guard let finalDate = calendar.date(from: finalDateComponents) else {
            return
        }
        
        // 處理金額
        let eventAmount: Double? = isExpense ? Double(amount) : nil
        
        let eventId = editingEvent?.id ?? UUID()
        print("創建事件 - editingEvent: \(editingEvent?.title ?? "nil"), 使用ID: \(eventId)")
        
        let finalShareGroupSize = isShared ? max(2, shareGroupSize) : 1
        let finalSplitMethod = isShared ? selectedSplitMethod : .personal
        
        let newEvent = Event(
            id: eventId,
            title: title,
            description: description,
            date: finalDate,
            color: selectedColor,
            amount: eventAmount,
            category: selectedCategory,
            isExpense: isExpense,
            shareGroupSize: finalShareGroupSize,
            splitMethod: finalSplitMethod
        )
        
        onSave(newEvent)
        presentationMode.wrappedValue.dismiss()
    }
    
    private var sharedSplitMethods: [Event.SplitMethod] {
        Event.SplitMethod.allCases.filter { $0 != .personal }
    }
}

struct ColorOptionView: View {
    let color: Event.EventColor
    let isSelected: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            ZStack {
                Circle()
                    .fill(color.color)
                    .frame(width: 50, height: 50)
                
                if isSelected {
                    Circle()
                        .stroke(Color.primary, lineWidth: 3)
                        .frame(width: 50, height: 50)
                }
            }
        }
        .buttonStyle(PlainButtonStyle())
    }
}

#Preview {
    EventEditView(defaultDate: Date(), onSave: { _ in })
}

#Preview("編輯活動") {
    EventEditView(
        editingEvent: Event.sampleEvents.first,
        defaultDate: Event.sampleEvents.first?.date ?? Date(),
        onSave: { _ in }
    )
}
