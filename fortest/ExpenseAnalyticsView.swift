//
//  ExpenseAnalyticsView.swift
//  fortest
//
//  Created by Yuchen Yeh on 2025/9/11.
//

import SwiftUI
import Charts

struct ExpenseAnalyticsView: View {
    @ObservedObject var dataManager: EventDataManager
    @State private var selectedTimeRange: TimeRange = .thisMonth
    @State private var showingDetailView = false
    @State private var selectedCategory: Event.ExpenseCategory?
    
    enum TimeRange: String, CaseIterable {
        case thisWeek = "本週"
        case thisMonth = "本月"
        case last3Months = "近3個月"
        case thisYear = "今年"
    }
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // 時間範圍選擇器
                    timeRangeSelector
                    
                    // 總覽卡片
                    overviewCards
                    
                    // 類別分析圖表
                    categoryChart
                    
                    // 趨勢分析圖表
                    trendChart
                    
                    // 詳細類別表格
                    categoryTable
                }
                .padding()
            }
            .navigationTitle("消費分析")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("載入示例") {
                        dataManager.resetToSampleData()
                    }
                    .font(.caption)
                }
            }
        }
    }
    
    // MARK: - 時間範圍選擇器
    private var timeRangeSelector: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("時間範圍")
                .font(.headline)
                .foregroundColor(.primary)
            
            Picker("時間範圍", selection: $selectedTimeRange) {
                ForEach(TimeRange.allCases, id: \.self) { range in
                    Text(range.rawValue).tag(range)
                }
            }
            .pickerStyle(SegmentedPickerStyle())
        }
    }
    
    // MARK: - 總覽卡片
    private var overviewCards: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: 16) {
            OverviewCard(
                title: "總支出",
                value: "NT$ \(String(format: "%.0f", totalExpense))",
                icon: "creditcard",
                color: .red
            )
            
            OverviewCard(
                title: "交易筆數",
                value: "\(expenseEvents.count) 筆",
                icon: "list.number",
                color: .blue
            )
            
            OverviewCard(
                title: "平均單筆",
                value: "NT$ \(String(format: "%.0f", averageExpense))",
                icon: "chart.bar.horizontal",
                color: .green
            )
            
            OverviewCard(
                title: "最高類別",
                value: topCategory?.rawValue ?? "無",
                icon: "crown",
                color: .orange
            )
        }
    }
    
    // MARK: - 類別分析圖表
    private var categoryChart: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("類別分析")
                .font(.title2)
                .fontWeight(.semibold)
            
            if #available(iOS 16.0, *) {
                Chart(categoryExpenses, id: \.category) { data in
                    SectorMark(
                        angle: .value("金額", data.amount),
                        innerRadius: .ratio(0.6),
                        angularInset: 2
                    )
                    .foregroundStyle(by: .value("類別", data.category.rawValue))
                }
                .frame(height: 300)
                .chartLegend(position: .bottom, alignment: .leading)
            } else {
                // iOS 15 fallback
                VStack(spacing: 12) {
                    ForEach(categoryExpenses, id: \.category) { data in
                        HStack {
                            Image(systemName: data.category.icon)
                                .foregroundColor(.blue)
                                .frame(width: 20)
                            
                            Text(data.category.rawValue)
                                .font(.body)
                            
                            Spacer()
                            
                            Text("NT$ \(String(format: "%.0f", data.amount))")
                                .font(.body)
                                .fontWeight(.medium)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color(.systemGray6))
                        .cornerRadius(8)
                    }
                }
                .frame(height: 300)
            }
        }
    }
    
    // MARK: - 趨勢分析圖表
    private var trendChart: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("支出趨勢")
                .font(.title2)
                .fontWeight(.semibold)
            
            if #available(iOS 16.0, *) {
                Chart(dailyExpenses, id: \.date) { data in
                    LineMark(
                        x: .value("日期", data.date),
                        y: .value("金額", data.amount)
                    )
                    .foregroundStyle(.blue)
                    
                    AreaMark(
                        x: .value("日期", data.date),
                        y: .value("金額", data.amount)
                    )
                    .foregroundStyle(.blue.opacity(0.3))
                }
                .frame(height: 200)
                .chartXAxis {
                    AxisMarks(values: .automatic) { _ in
                        AxisGridLine()
                        AxisValueLabel(format: .dateTime.month().day())
                    }
                }
                .chartYAxis {
                    AxisMarks { _ in
                        AxisGridLine()
                        AxisValueLabel()
                    }
                }
            } else {
                // iOS 15 fallback
                VStack(spacing: 8) {
                    Text("近期支出趨勢")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(dailyExpenses, id: \.date) { data in
                                VStack(spacing: 4) {
                                    Text("NT$ \(String(format: "%.0f", data.amount))")
                                        .font(.caption2)
                                        .fontWeight(.medium)
                                    
                                    Rectangle()
                                        .fill(Color.blue)
                                        .frame(width: 30, height: max(data.amount / 100, 10))
                                    
                                    Text(DateFormatter.dayFormatter.string(from: data.date))
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        .padding(.horizontal)
                    }
                }
                .frame(height: 200)
                .background(Color(.systemGray6))
                .cornerRadius(12)
            }
        }
    }
    
    // MARK: - 詳細類別表格
    private var categoryTable: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("詳細分析")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Button("查看詳情") {
                    showingDetailView = true
                }
                .font(.caption)
                .foregroundColor(.blue)
            }
            
            VStack(spacing: 12) {
                ForEach(categoryExpenses, id: \.category) { data in
                    CategoryRow(
                        category: data.category,
                        amount: data.amount,
                        percentage: data.amount / totalExpense * 100,
                        transactionCount: data.count
                    )
                }
            }
        }
        .sheet(isPresented: $showingDetailView) {
            ExpenseDetailView(dataManager: dataManager, timeRange: selectedTimeRange)
        }
    }
}

// MARK: - 支援視圖
struct OverviewCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(color)
                    .font(.title3)
                
                Spacer()
            }
            
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            
            Text(value)
                .font(.headline)
                .fontWeight(.semibold)
                .foregroundColor(.primary)
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

struct CategoryRow: View {
    let category: Event.ExpenseCategory
    let amount: Double
    let percentage: Double
    let transactionCount: Int
    
    var body: some View {
        HStack(spacing: 12) {
            // 類別圖標
            Image(systemName: category.icon)
                .foregroundColor(.blue)
                .frame(width: 24, height: 24)
            
            // 類別信息
            VStack(alignment: .leading, spacing: 2) {
                Text(category.rawValue)
                    .font(.body)
                    .fontWeight(.medium)
                
                Text("\(transactionCount) 筆交易")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // 金額和百分比
            VStack(alignment: .trailing, spacing: 2) {
                Text("NT$ \(String(format: "%.0f", amount))")
                    .font(.body)
                    .fontWeight(.semibold)
                
                Text("\(String(format: "%.1f", percentage))%")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(.systemBackground))
        .cornerRadius(8)
        .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
}

// MARK: - 數據處理
extension ExpenseAnalyticsView {
    private var dateRange: (start: Date, end: Date) {
        let calendar = Calendar.current
        let now = Date()
        
        switch selectedTimeRange {
        case .thisWeek:
            let startOfWeek = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? now
            return (startOfWeek, now)
        case .thisMonth:
            let startOfMonth = calendar.dateInterval(of: .month, for: now)?.start ?? now
            return (startOfMonth, now)
        case .last3Months:
            let threeMonthsAgo = calendar.date(byAdding: .month, value: -3, to: now) ?? now
            return (threeMonthsAgo, now)
        case .thisYear:
            let startOfYear = calendar.dateInterval(of: .year, for: now)?.start ?? now
            return (startOfYear, now)
        }
    }
    
    private var expenseEvents: [Event] {
        let range = dateRange
        return dataManager.events.filter { event in
            event.isExpense && 
            event.amount != nil && 
            event.date >= range.start && 
            event.date <= range.end
        }
    }
    
    private var totalExpense: Double {
        expenseEvents.compactMap { $0.amount }.reduce(0, +)
    }
    
    private var averageExpense: Double {
        guard !expenseEvents.isEmpty else { return 0 }
        return totalExpense / Double(expenseEvents.count)
    }
    
    private var topCategory: Event.ExpenseCategory? {
        categoryExpenses.max(by: { $0.amount < $1.amount })?.category
    }
    
    private var categoryExpenses: [CategoryExpense] {
        return dataManager.getCategoryExpenses()
    }
    
    private var dailyExpenses: [DailyExpense] {
        let calendar = Calendar.current
        let range = dateRange
        let grouped = Dictionary(grouping: expenseEvents) { event in
            calendar.startOfDay(for: event.date)
        }
        
        var dailyData: [DailyExpense] = []
        var currentDate = range.start
        
        while currentDate <= range.end {
            let dayStart = calendar.startOfDay(for: currentDate)
            let dayEvents = grouped[dayStart] ?? []
            let dayTotal = dayEvents.compactMap { $0.amount }.reduce(0, +)
            
            dailyData.append(DailyExpense(date: dayStart, amount: dayTotal))
            currentDate = calendar.date(byAdding: .day, value: 1, to: currentDate) ?? currentDate
        }
        
        return dailyData
    }
}

// MARK: - 數據模型
struct DailyExpense {
    let date: Date
    let amount: Double
}

// MARK: - 詳細視圖
struct ExpenseDetailView: View {
    @ObservedObject var dataManager: EventDataManager
    let timeRange: ExpenseAnalyticsView.TimeRange
    @Environment(\.presentationMode) var presentationMode
    
    var body: some View {
        NavigationView {
            List {
                // 這裡可以添加更詳細的分析內容
                Text("詳細分析功能開發中...")
                    .foregroundColor(.secondary)
            }
            .navigationTitle("詳細分析")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") {
                        presentationMode.wrappedValue.dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - 日期格式化器
extension DateFormatter {
    static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "M/d"
        return formatter
    }()
}

#Preview {
    ExpenseAnalyticsView(dataManager: EventDataManager())
}
