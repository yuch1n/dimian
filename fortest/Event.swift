//
//  Event.swift
//  fortest
//
//  Created by Yuchen Yeh on 2025/9/11.
//

import Foundation
import SwiftUI

struct Event: Identifiable, Codable {
    var id: UUID
    var title: String
    var description: String
    var date: Date
    var color: EventColor
    var amount: Double?
    var category: ExpenseCategory
    var isExpense: Bool
    var shareGroupSize: Int = 1
    var splitMethod: SplitMethod = .personal
    
    var isShared: Bool {
        shareGroupSize > 1
    }
    
    enum EventColor: String, CaseIterable, Codable {
        case red = "red"
        case blue = "blue"
        case green = "green"
        case orange = "orange"
        case purple = "purple"
        case yellow = "yellow"
        
        var color: Color {
            switch self {
            case .red: return .red
            case .blue: return .blue
            case .green: return .green
            case .orange: return .orange
            case .purple: return .purple
            case .yellow: return .yellow
            }
        }
        
        var colorString: String {
            switch self {
            case .red: return "red"
            case .blue: return "blue"
            case .green: return "green"
            case .orange: return "orange"
            case .purple: return "purple"
            case .yellow: return "yellow"
            }
        }
    }
    
    enum ExpenseCategory: String, CaseIterable, Codable {
        case food = "餐飲"
        case transport = "交通"
        case shopping = "購物"
        case entertainment = "娛樂"
        case health = "醫療"
        case education = "教育"
        case travel = "旅遊"
        case other = "其他"
        
        var icon: String {
            switch self {
            case .food: return "fork.knife"
            case .transport: return "car"
            case .shopping: return "bag"
            case .entertainment: return "tv"
            case .health: return "cross.case"
            case .education: return "book"
            case .travel: return "airplane"
            case .other: return "questionmark.circle"
            }
        }
    }
    
    enum SplitMethod: String, CaseIterable, Codable {
        case personal
        case aa
        case a0
        case custom
        
        var displayName: String {
            switch self {
            case .personal:
                return "個人"
            case .aa:
                return "AA制"
            case .a0:
                return "A0制"
            case .custom:
                return "自訂"
            }
        }
        
        var description: String {
            switch self {
            case .personal:
                return "不共享"
            case .aa:
                return "平均分攤"
            case .a0:
                return "一人請客"
            case .custom:
                return "自訂比例"
            }
        }
    }
}

// 示例數據
extension Event {
    static let sampleEvents: [Event] = [
        // 本週數據
        Event(id: UUID(), title: "早餐", description: "便利商店早餐", date: Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date(), color: .blue, amount: 85.0, category: .food, isExpense: true),
        Event(id: UUID(), title: "午餐", description: "公司附近餐廳", date: Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date(), color: .red, amount: 250.0, category: .food, isExpense: true),
        Event(id: UUID(), title: "咖啡", description: "下午茶時光", date: Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date(), color: .orange, amount: 120.0, category: .food, isExpense: true),
        
        // 今天的數據
        Event(id: UUID(), title: "捷運費", description: "通勤交通費", date: Date(), color: .green, amount: 40.0, category: .transport, isExpense: true),
        Event(id: UUID(), title: "午餐", description: "便當", date: Date(), color: .blue, amount: 95.0, category: .food, isExpense: true),
        Event(id: UUID(), title: "會議", description: "團隊會議", date: Date(), color: .purple, amount: nil, category: .other, isExpense: false),
        
        // 昨天的數據
        Event(id: UUID(), title: "購物", description: "生活用品", date: Calendar.current.date(byAdding: .day, value: -2, to: Date()) ?? Date(), color: .yellow, amount: 680.0, category: .shopping, isExpense: true),
        Event(id: UUID(), title: "計程車", description: "回家交通費", date: Calendar.current.date(byAdding: .day, value: -2, to: Date()) ?? Date(), color: .green, amount: 180.0, category: .transport, isExpense: true),
        
        // 本週稍早
        Event(id: UUID(), title: "看電影", description: "週末娛樂", date: Calendar.current.date(byAdding: .day, value: -3, to: Date()) ?? Date(), color: .purple, amount: 350.0, category: .entertainment, isExpense: true),
        Event(id: UUID(), title: "晚餐", description: "朋友聚餐", date: Calendar.current.date(byAdding: .day, value: -3, to: Date()) ?? Date(), color: .red, amount: 480.0, category: .food, isExpense: true, shareGroupSize: 4, splitMethod: .aa),
        
        // 上週數據
        Event(id: UUID(), title: "健身房", description: "月費", date: Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date(), color: .orange, amount: 1200.0, category: .health, isExpense: true),
        Event(id: UUID(), title: "書籍", description: "技術書籍", date: Calendar.current.date(byAdding: .day, value: -8, to: Date()) ?? Date(), color: .blue, amount: 450.0, category: .education, isExpense: true),
        Event(id: UUID(), title: "超市採購", description: "一週食材", date: Calendar.current.date(byAdding: .day, value: -9, to: Date()) ?? Date(), color: .green, amount: 850.0, category: .shopping, isExpense: true),
        
        // 更早的數據（上上週）
        Event(id: UUID(), title: "加油", description: "汽車加油", date: Calendar.current.date(byAdding: .day, value: -14, to: Date()) ?? Date(), color: .yellow, amount: 950.0, category: .transport, isExpense: true),
        Event(id: UUID(), title: "醫療", description: "看醫生", date: Calendar.current.date(byAdding: .day, value: -15, to: Date()) ?? Date(), color: .red, amount: 420.0, category: .health, isExpense: true),
        Event(id: UUID(), title: "服飾", description: "新衣服", date: Calendar.current.date(byAdding: .day, value: -16, to: Date()) ?? Date(), color: .purple, amount: 1680.0, category: .shopping, isExpense: true),
        
        // 本月較早數據
        Event(id: UUID(), title: "旅遊", description: "週末小旅行", date: Calendar.current.date(byAdding: .day, value: -20, to: Date()) ?? Date(), color: .blue, amount: 2500.0, category: .travel, isExpense: true, shareGroupSize: 3, splitMethod: .a0),
        Event(id: UUID(), title: "餐廳", description: "慶祝聚餐", date: Calendar.current.date(byAdding: .day, value: -21, to: Date()) ?? Date(), color: .red, amount: 720.0, category: .food, isExpense: true),
        Event(id: UUID(), title: "線上課程", description: "程式設計課程", date: Calendar.current.date(byAdding: .day, value: -22, to: Date()) ?? Date(), color: .green, amount: 990.0, category: .education, isExpense: true),
        
        // 上個月數據
        Event(id: UUID(), title: "房租", description: "月租費", date: Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date(), color: .orange, amount: 15000.0, category: .other, isExpense: true),
        Event(id: UUID(), title: "水電費", description: "公用事業費", date: Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date(), color: .blue, amount: 850.0, category: .other, isExpense: true),
        Event(id: UUID(), title: "手機費", description: "月租費", date: Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date(), color: .purple, amount: 699.0, category: .other, isExpense: true),
        
        // 更多多樣化的數據
        Event(id: UUID(), title: "咖啡廳", description: "工作咖啡", date: Calendar.current.date(byAdding: .day, value: -5, to: Date()) ?? Date(), color: .yellow, amount: 150.0, category: .food, isExpense: true),
        Event(id: UUID(), title: "Uber", description: "機場接送", date: Calendar.current.date(byAdding: .day, value: -12, to: Date()) ?? Date(), color: .green, amount: 320.0, category: .transport, isExpense: true),
        Event(id: UUID(), title: "藥局", description: "維他命", date: Calendar.current.date(byAdding: .day, value: -18, to: Date()) ?? Date(), color: .red, amount: 280.0, category: .health, isExpense: true),
        Event(id: UUID(), title: "電影院", description: "IMAX電影", date: Calendar.current.date(byAdding: .day, value: -25, to: Date()) ?? Date(), color: .purple, amount: 420.0, category: .entertainment, isExpense: true),
        
        // 一些非支出活動
        Event(id: UUID(), title: "工作會議", description: "專案討論", date: Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date(), color: .blue, amount: nil, category: .other, isExpense: false),
        Event(id: UUID(), title: "運動", description: "晨跑", date: Calendar.current.date(byAdding: .day, value: -3, to: Date()) ?? Date(), color: .green, amount: nil, category: .health, isExpense: false),
        Event(id: UUID(), title: "讀書", description: "學習時間", date: Calendar.current.date(byAdding: .day, value: -6, to: Date()) ?? Date(), color: .orange, amount: nil, category: .education, isExpense: false)
    ]
}
