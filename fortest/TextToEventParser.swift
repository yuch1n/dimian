//
//  TextToEventParser.swift
//  fortest
//
//  Created by Codex on 2025/3/14.
//

import Foundation
import SwiftUI

enum TextToEventParser {
    static func parse(text: String, defaultDate: Date = Date()) -> Event? {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return nil }

        let detectedDate = detectDate(in: cleaned, reference: defaultDate)
        let detectedTime = detectTime(in: cleaned)
        let finalDate = merge(date: detectedDate, time: detectedTime) ?? defaultDate

        let amount = detectAmount(in: cleaned)
        let category = detectCategory(in: cleaned)

        let title = detectTitle(in: cleaned) ?? cleaned
        let isExpense = amount != nil || cleaned.contains("消費") || cleaned.lowercased().contains("cost")

        let event = Event(
            id: UUID(),
            title: title,
            description: cleaned,
            date: finalDate,
            color: color(for: category),
            amount: amount,
            category: category,
            isExpense: isExpense,
            shareGroupSize: 1,
            splitMethod: .personal
        )
        return event
    }

    static func cleanRecognizedText(_ text: String) -> String {
        let rawLines = text.components(separatedBy: .newlines)
        var filtered: [(idx: Int, line: String)] = []

        let ignoreKeywords = [
            "line", "錢包", "message", "回覆", "自動回覆", "輸入訊息", "thanks for the message",
            "i'm sorry", "don't worry", "sending you more", "wifi", "4g", "<", "99+", "提醒",
            "已讀", "已讀取", "已讀訊息", "reply", "soon", "auto reply"
        ]

        let importantPattern = #"(\d{1,2}[:：]\d{2}|\d{1,2}[/-]\d{1,2}|\d{4}[/-]\d{1,2}[/-]\d{1,2}|今天|明天|後天|消費|元|\$)"#
        let importantRegex = try? NSRegularExpression(pattern: importantPattern, options: .caseInsensitive)

        let pureTimeRegex = try? NSRegularExpression(pattern: #"^\d{1,2}[:：]\d{2}$"#, options: [])

        for (index, line) in rawLines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            let lower = trimmed.lowercased()
            if ignoreKeywords.contains(where: { lower.contains($0) }) { continue }
            if trimmed.first == "<" || trimmed.first == "•" { continue }
            if trimmed.count <= 1 && !trimmed.contains(where: { $0.isNumber }) { continue }

            if let regex = importantRegex {
                let range = NSRange(trimmed.startIndex..<trimmed.endIndex, in: trimmed)
                if regex.firstMatch(in: trimmed, options: [], range: range) == nil {
                    // keep short text only if it's mostly letters/numbers
                    let letters = trimmed.filter { $0.isLetter }.count
                    let numbers = trimmed.filter { $0.isNumber }.count
                    if letters + numbers < 2 { continue }
                }
            }

            // Skip top-of-screen狀態列時間 (純時間而且出現在前幾行)
            if let pureTimeRegex,
               pureTimeRegex.firstMatch(in: trimmed, options: [], range: NSRange(trimmed.startIndex..<trimmed.endIndex, in: trimmed)) != nil,
               index < 3 {
                continue
            }

            filtered.append((index, trimmed))
        }

        guard !filtered.isEmpty else { return "" }

        // 移除主要為英文字母且無數字的行（常見英文自動回覆）
        filtered = filtered.filter { entry in
            let letters = entry.line.filter { $0.isLetter }.count
            let numbers = entry.line.filter { $0.isNumber }.count
            let total = entry.line.count
            if numbers == 0 && total > 0 && Double(letters) / Double(total) > 0.6 {
                return false
            }
            return true
        }

        // 如果有明確日期/金額行，截取自該行起的內容，避開前面的狀態列時間
        let strongPattern = #"(\d{1,2}[/-]\d{1,2}|\d{4}[/-]\d{1,2}[/-]\d{1,2}|消費|元|\$|NT)"#
        let strongRegex = try? NSRegularExpression(pattern: strongPattern, options: .caseInsensitive)
        if let strongRegex {
            if let firstStrongIndex = filtered.firstIndex(where: { entry in
                let range = NSRange(entry.line.startIndex..<entry.line.endIndex, in: entry.line)
                return strongRegex.firstMatch(in: entry.line, options: [], range: range) != nil
            }) {
                filtered = Array(filtered[firstStrongIndex...])
            }
        }

            // 優先保留包含日期/金額的行及其前後文
            var keepIndices = Set<Int>()
            if let regex = importantRegex {
                for (pos, entry) in filtered.enumerated() {
                    let range = NSRange(entry.line.startIndex..<entry.line.endIndex, in: entry.line)
                    if regex.firstMatch(in: entry.line, options: [], range: range) != nil {
                    keepIndices.insert(pos)
                    if pos > 0 { keepIndices.insert(pos - 1) }
                    if pos + 1 < filtered.count { keepIndices.insert(pos + 1) }
                }
            }
        }

        let finalLines: [String]
        if !keepIndices.isEmpty {
            finalLines = filtered.enumerated().compactMap { keepIndices.contains($0.offset) ? $0.element.line : nil }
        } else {
            // 如果沒有特別的關鍵行，仍避免純時間霸屏：僅保留最多一個時間行並需穿插文字
            var seenTime = false
            finalLines = filtered.compactMap { entry in
                if let pureTimeRegex,
                   pureTimeRegex.firstMatch(in: entry.line, options: [], range: NSRange(entry.line.startIndex..<entry.line.endIndex, in: entry.line)) != nil {
                    if seenTime { return nil }
                    seenTime = true
                }
                return entry.line
            }
        }

        return finalLines.joined(separator: "\n")
    }

    private static func detectTitle(in text: String) -> String? {
        let lines = text.components(separatedBy: .newlines)
        let datePrefix = try? NSRegularExpression(pattern: #"^\s*\d{1,2}[/-]\d{1,2}\s*"#)
        let timeOnly = try? NSRegularExpression(pattern: #"^\s*\d{1,2}[:：]\d{2}\s*$"#)
        let dateAnywhere = try? NSRegularExpression(pattern: #"\b\d{1,2}[/-]\d{1,2}\b"#)
        let timeAnywhere = try? NSRegularExpression(pattern: #"\b\d{1,2}[:：]\d{2}\b"#)

        let unwantedKeywords = ["已讀", "已讀取", "read", "reply", "message", "soon", "輸入訊息"]
        let leadingPronounPattern = try? NSRegularExpression(pattern: #"^(我們|大家|我|一起|想要|想|要)\s*"#)

        for raw in lines {
            var line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }
            let lower = line.lowercased()
            if unwantedKeywords.contains(where: { lower.contains($0) }) { continue }
            if let datePrefix, datePrefix.firstMatch(in: line, options: [], range: NSRange(line.startIndex..<line.endIndex, in: line)) != nil {
                line = datePrefix.stringByReplacingMatches(in: line, options: [], range: NSRange(line.startIndex..<line.endIndex, in: line), withTemplate: "").trimmingCharacters(in: .whitespaces)
            }
            if let dateAnywhere {
                line = dateAnywhere.stringByReplacingMatches(in: line, options: [], range: NSRange(line.startIndex..<line.endIndex, in: line), withTemplate: "").trimmingCharacters(in: .whitespaces)
            }
            if let timeAnywhere {
                line = timeAnywhere.stringByReplacingMatches(in: line, options: [], range: NSRange(line.startIndex..<line.endIndex, in: line), withTemplate: "").trimmingCharacters(in: .whitespaces)
            }
            if let leadingPronounPattern {
                line = leadingPronounPattern.stringByReplacingMatches(in: line, options: [], range: NSRange(line.startIndex..<line.endIndex, in: line), withTemplate: "").trimmingCharacters(in: .whitespaces)
            }
            if let timeOnly,
               timeOnly.firstMatch(in: line, options: [], range: NSRange(line.startIndex..<line.endIndex, in: line)) != nil {
                continue
            }
            // skip lines that are only digits
            if line.allSatisfy({ $0.isNumber }) { continue }
            if !line.isEmpty { return line }
        }

        // Fallback: use first segment before punctuation
        let separators = ["，", ",", "。", ".", "；", ";", "、"]
        for sep in separators {
            if let range = text.range(of: sep) {
                let prefix = text[..<range.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
                if !prefix.isEmpty { return String(prefix) }
            }
        }
        return nil
    }

    private static func detectDate(in text: String, reference: Date) -> Date {
        let lower = text.lowercased()
        let calendar = Calendar.current

        // 優先找明確日期字串
        let datePatterns = [
            #"(\d{4})[/-](\d{1,2})[/-](\d{1,2})"#,
            #"(\d{1,2})[/-](\d{1,2})"#
        ]

        var extractedDates: [Date] = []
        for pattern in datePatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
                let range = NSRange(text.startIndex..<text.endIndex, in: text)
                regex.enumerateMatches(in: text, options: [], range: range) { match, _, _ in
                    guard let match = match else { return }
                    if match.numberOfRanges == 4,
                       let yearRange = Range(match.range(at: 1), in: text),
                       let monthRange = Range(match.range(at: 2), in: text),
                       let dayRange = Range(match.range(at: 3), in: text),
                       let year = Int(text[yearRange]),
                       let month = Int(text[monthRange]),
                       let day = Int(text[dayRange]) {
                        var components = DateComponents()
                        components.year = year
                        components.month = month
                        components.day = day
                        if let date = calendar.date(from: components) {
                            extractedDates.append(calendar.startOfDay(for: date))
                        }
                    } else if match.numberOfRanges == 3,
                              let monthRange = Range(match.range(at: 1), in: text),
                              let dayRange = Range(match.range(at: 2), in: text),
                              let month = Int(text[monthRange]),
                              let day = Int(text[dayRange]) {
                        var components = calendar.dateComponents([.year], from: reference)
                        components.month = month
                        components.day = day
                        if let date = calendar.date(from: components) {
                            extractedDates.append(calendar.startOfDay(for: date))
                        }
                    }
                }
            }
        }

        if let explicit = extractedDates.last {
            return explicit
        }

        // 再用相對詞
        if lower.contains("今天") {
            return calendar.startOfDay(for: reference)
        }
        if lower.contains("明天") {
            return calendar.startOfDay(for: calendar.date(byAdding: .day, value: 1, to: reference) ?? reference)
        }
        if lower.contains("後天") {
            return calendar.startOfDay(for: calendar.date(byAdding: .day, value: 2, to: reference) ?? reference)
        }

        return calendar.startOfDay(for: reference)
    }

    private static func detectTime(in text: String) -> DateComponents? {
        let pattern = #"(\d{1,2})[:：](\d{2})"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        let matches = regex.matches(in: text, options: [], range: range)

        // 優先選在包含日期或金額行內的時間，否則選最後一個時間
        let lines = text.components(separatedBy: .newlines)
        for match in matches {
            if match.numberOfRanges == 3,
               let hourRange = Range(match.range(at: 1), in: text),
               let minuteRange = Range(match.range(at: 2), in: text),
               let hour = Int(text[hourRange]),
               let minute = Int(text[minuteRange]),
               hour >= 0, hour < 24, minute >= 0, minute < 60 {

                // confirm the line has date/amount keywords
                if let lineRange = Range(match.range(at: 0), in: text) {
                    let line = lineContaining(range: lineRange, in: lines, original: text)
                    let hasContext = line.range(of: #"(\d{1,2}[/-]\d{1,2}|\d{4}[/-]\d{1,2}[/-]\d{1,2}|消費|元|\$|NT|\d{3,})"#, options: .regularExpression) != nil
                    if hasContext {
                        return DateComponents(hour: hour, minute: minute)
                    }
                }
            }
        }

        if let last = matches.last,
           last.numberOfRanges == 3,
           let hourRange = Range(last.range(at: 1), in: text),
           let minuteRange = Range(last.range(at: 2), in: text),
           let hour = Int(text[hourRange]),
           let minute = Int(text[minuteRange]),
           hour >= 0, hour < 24, minute >= 0, minute < 60 {
            return DateComponents(hour: hour, minute: minute)
        }

        return nil
    }

    private static func lineContaining(range: Range<String.Index>, in lines: [String], original: String) -> String {
        var current = original.startIndex
        for line in lines {
            let next = original.index(current, offsetBy: line.count)
            if range.lowerBound >= current && range.upperBound <= next {
                return line
            }
            if next < original.endIndex {
                current = original.index(after: next)
            }
        }
        return lines.last ?? ""
    }

    private static func detectAmount(in text: String) -> Double? {
        let lines = text.components(separatedBy: .newlines)
        let amountPatterns = [
            #"(?<![:/])([0-9]{2,}(?:\.[0-9]+)?)\s*(?:元|塊|nt\$?)"#,
            #"消費\s*([0-9]{2,}(?:\.[0-9]+)?)"#
        ]

        // 先找有關鍵詞的行
        for line in lines {
            for pattern in amountPatterns {
                guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
                let range = NSRange(line.startIndex..<line.endIndex, in: line)
                if let match = regex.firstMatch(in: line, options: [], range: range),
                   match.numberOfRanges >= 2,
                   let amountRange = Range(match.range(at: 1), in: line) {
                    return Double(line[amountRange])
                }
            }
        }

        // 退而求其次：抓純數字但排除時間
        let pureNumber = try? NSRegularExpression(pattern: #"^\s*([0-9]{2,})\s*$"#)
        for line in lines {
            guard let pureNumber else { break }
            let range = NSRange(line.startIndex..<line.endIndex, in: line)
            if let match = pureNumber.firstMatch(in: line, options: [], range: range),
               match.numberOfRanges >= 2,
               let numRange = Range(match.range(at: 1), in: line) {
                let valueString = String(line[numRange])
                if let value = Double(valueString), value >= 10 {
                    // 避免時間：如果值小於等於 60 但未見冒號，判斷上下文
                    if value <= 60 {
                        continue
                    }
                    return value
                }
            }
        }
        return nil
    }

    private static func detectCategory(in text: String) -> Event.ExpenseCategory {
        let candidates: [(Event.ExpenseCategory, [String])] = [
            (.food, ["飯", "餐", "午餐", "早餐", "晚餐", "吃", "咖啡", "飲", "餐廳", "便當"]),
            (.transport, ["車", "捷運", "公車", "地鐵", "高鐵", "火車", "uber", "計程車", "油", "停車"]),
            (.shopping, ["買", "購物", "超市", "商店", "衣", "服", "鞋", "包", "日用品"]),
            (.entertainment, ["電影", "演唱會", "娛樂", "玩", "聚會", "酒吧", "電玩"]),
            (.health, ["醫", "藥", "牙", "診所", "健身", "運動", "體檢"]),
            (.education, ["課", "學", "書", "課程", "教育", "講座"]),
            (.travel, ["旅遊", "旅行", "出差", "機票", "飯店", "住宿", "住宿費"])
        ]

        let lower = text.lowercased()
        for (category, keywords) in candidates {
            if keywords.contains(where: { lower.contains($0.lowercased()) }) {
                return category
            }
        }
        return .other
    }

    private static func color(for category: Event.ExpenseCategory) -> Event.EventColor {
        switch category {
        case .food: return .red
        case .transport: return .green
        case .shopping: return .orange
        case .entertainment: return .purple
        case .health: return .yellow
        case .education: return .blue
        case .travel: return .green
        case .other: return .blue
        }
    }

    private static func merge(date: Date, time: DateComponents?) -> Date? {
        guard let time else { return date }
        var components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        components.hour = time.hour
        components.minute = time.minute
        return Calendar.current.date(from: components)
    }
}
