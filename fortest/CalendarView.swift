import SwiftUI

struct CalendarView: View {
    @Binding var selectedDate: Date
    let events: [Event]
    
    private let calendar = Calendar.current
    private let dateFormatter = DateFormatter()
    
    init(selectedDate: Binding<Date>, events: [Event]) {
        self._selectedDate = selectedDate
        self.events = events
        dateFormatter.locale = Locale(identifier: "zh_TW")
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // 月份標題和導航按鈕
            HStack {
                Button(action: previousMonth) {
                    Image(systemName: "chevron.left")
                        .font(.title2)
                        .foregroundColor(.blue)
                }
                
                Spacer()
                
                Text(monthYearString)
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Button(action: nextMonth) {
                    Image(systemName: "chevron.right")
                        .font(.title2)
                        .foregroundColor(.blue)
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 4)
            
            // 星期標題
            HStack {
                ForEach(weekdaySymbols, id: \.self) { weekday in
                    Text(weekday)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 2)
            
            // 日曆網格 - 固定6行高度
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 6) {
                ForEach(0..<42, id: \.self) { index in
                    if index < daysInMonth.count, let date = daysInMonth[index] {
                        DayView(
                            date: date,
                            isSelected: calendar.isDate(date, inSameDayAs: selectedDate),
                            isToday: calendar.isDateInToday(date),
                            eventColors: eventColors(on: date),
                            onTap: { selectedDate = date }
                        )
                    } else {
                        // 空白格子，保持固定高度
                        Rectangle()
                            .fill(Color.clear)
                            .frame(height: 40)
                    }
                }
            }
            .padding(.horizontal)
            .frame(height: 260) // 固定高度：6行 × 40px + 5個間距 × 4px = 260px
        }
    }
    
    private var monthYearString: String {
        dateFormatter.dateFormat = "yyyy年MM月"
        return dateFormatter.string(from: selectedDate)
    }
    
    private var weekdaySymbols: [String] {
        dateFormatter.shortWeekdaySymbols
    }
    
    private var daysInMonth: [Date?] {
        guard let monthInterval = calendar.dateInterval(of: .month, for: selectedDate),
              let monthFirstWeek = calendar.dateInterval(of: .weekOfYear, for: monthInterval.start),
              let monthLastWeek = calendar.dateInterval(of: .weekOfYear, for: monthInterval.end - 1) else {
            return []
        }
        
        let firstDate = monthFirstWeek.start
        let lastDate = monthLastWeek.end
        
        var days: [Date?] = []
        var currentDate = firstDate
        
        while currentDate < lastDate {
            if calendar.isDate(currentDate, equalTo: monthInterval.start, toGranularity: .month) {
                days.append(currentDate)
            } else {
                days.append(nil)
            }
            currentDate = calendar.date(byAdding: .day, value: 1, to: currentDate) ?? currentDate
        }
        
        return days
    }
    
    private func eventColors(on date: Date) -> [Event.EventColor] {
        events
            .filter { calendar.isDate($0.date, inSameDayAs: date) }
            .map { $0.color }
    }
    
    private func previousMonth() {
        if let newDate = calendar.date(byAdding: .month, value: -1, to: selectedDate) {
            selectedDate = newDate
        }
    }
    
    private func nextMonth() {
        if let newDate = calendar.date(byAdding: .month, value: 1, to: selectedDate) {
            selectedDate = newDate
        }
    }
}

struct DayView: View {
    let date: Date
    let isSelected: Bool
    let isToday: Bool
    let eventColors: [Event.EventColor]
    let onTap: () -> Void
    
    private let calendar = Calendar.current
    private let dateFormatter = DateFormatter()
    
    init(date: Date, isSelected: Bool, isToday: Bool, eventColors: [Event.EventColor], onTap: @escaping () -> Void) {
        self.date = date
        self.isSelected = isSelected
        self.isToday = isToday
        self.eventColors = eventColors
        self.onTap = onTap
        dateFormatter.dateFormat = "d"
    }
    
    var body: some View {
        Button(action: onTap) {
            ZStack {
                Circle()
                    .fill(isSelected ? Color.blue : (isToday ? Color.blue.opacity(0.3) : Color.clear))
                    .frame(width: 40, height: 40)
                
                VStack(spacing: 2) {
                    Text(dateFormatter.string(from: date))
                        .font(.system(size: 16, weight: isSelected ? .bold : .medium))
                        .foregroundColor(isSelected ? .white : (isToday ? .blue : .primary))
                    
                    if !eventColors.isEmpty {
                        HStack(spacing: 2) {
                            ForEach(Array(eventColors.prefix(3).enumerated()), id: \.offset) { _, color in
                                Circle()
                                    .fill(color.color)
                                    .frame(width: 6, height: 6)
                            }
                        }
                    }
                }
            }
        }
        .buttonStyle(PlainButtonStyle())
    }
}

#Preview {
    CalendarView(selectedDate: .constant(Date()), events: Event.sampleEvents)
        .padding()
}
