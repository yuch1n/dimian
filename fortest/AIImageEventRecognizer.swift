//
//  AIImageEventRecognizer.swift
//  fortest
//
//  Created by Codex on 2025/3/14.
//

import Foundation
import UIKit

final class AIImageEventRecognizer {
    static let shared = AIImageEventRecognizer()

    struct ParsedResult {
        let recognizedText: String
        let event: Event?
    }

    enum RecognizerError: Error {
        case missingConfig
        case imageEncodingFailed
        case network(Error)
        case invalidResponse
        case server(status: Int, body: String?)
    }

    // MARK: - Config

    private var endpoint: URL? {
        if let value = Bundle.main.object(forInfoDictionaryKey: "AIImageParseURL") as? String {
            return URL(string: value)
        }
        // 預設走 OpenRouter chat completions
        return URL(string: "https://openrouter.ai/api/v1/chat/completions")
    }

    private var apiKey: String? {
        if let key = Bundle.main.object(forInfoDictionaryKey: "AIImageParseKey") as? String, !key.isEmpty {
            return key
        }
        // fallback: hardcoded key provided by user (建議改放 Info.plist)
        let fallback = "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"
        return fallback.isEmpty ? nil : fallback
    }

    private var model: String {
        (Bundle.main.object(forInfoDictionaryKey: "AIImageParseModel") as? String) ?? "x-ai/grok-4.1-fast"
    }

    // MARK: - Public

    func parseRecognizedText(_ text: String, defaultDate: Date) async throws -> ParsedResult {
        guard let endpoint = endpoint, let apiKey = apiKey, !apiKey.isEmpty else {
            throw RecognizerError.missingConfig
        }

        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else {
            throw RecognizerError.invalidResponse
        }

        let systemPrompt = """
        你是一個行程與記帳解析助手。從給定的文字中擷取單一事件資訊，並回傳純 JSON（不要多餘文字）：
        {
          "recognizedText": "與事件相關的簡短文字（不要包含狀態列時間或已讀）",
          "event": {
            "title": "...", // 不要包含日期/時間
            "description": "...",
            "date": "ISO8601",
            "time": "HH:mm 可選",
            "amount": 2000,
            "category": "餐飲|交通|購物|娛樂|醫療|教育|旅遊|其他",
            "isExpense": true,
            "shareGroupSize": 1,
            "splitMethod": "personal"
          }
        }
        無法確定的欄位設為 null 或省略，請確保輸出可被 JSON 解碼。
        """

        let userMessage = "以下為辨識文字，請解析為行程 JSON，避免使用狀態列時間:\n\(cleaned)"

        let messages = [
            Message(role: "system", content: [.text(systemPrompt)]),
            Message(role: "user", content: [.text(userMessage)])
        ]

        let request = ChatRequest(
            model: model,
            messages: messages,
            max_tokens: 800,
            extra_body: ExtraBody(reasoning: Reasoning(enabled: true))
        )

        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let encoder = JSONEncoder()
        guard let body = try? encoder.encode(request) else {
            throw RecognizerError.imageEncodingFailed
        }
        urlRequest.httpBody = body

        do {
            let (data, response) = try await URLSession.shared.data(for: urlRequest)
            guard let http = response as? HTTPURLResponse else {
                throw RecognizerError.invalidResponse
            }
            guard (200...299).contains(http.statusCode) else {
                let body = String(data: data, encoding: .utf8)
                throw RecognizerError.server(status: http.statusCode, body: body)
            }

            let decoded = try JSONDecoder().decode(ChatResponse.self, from: data)
            guard let content = decoded.choices.first?.message.content else {
                throw RecognizerError.invalidResponse
            }

            let jsonString: String = {
                switch content {
                case .string(let text): return text
                case .parts(let parts):
                    return parts.compactMap { part in
                        switch part {
                        case .text(let t): return t
                        default: return nil
                        }
                    }.joined(separator: "\n")
                }
            }()

            if let eventResponse = try? JSONDecoder().decode(APIResponse.self, from: Data(jsonString.utf8)) {
                let recognizedText = eventResponse.recognizedText ?? cleaned
                if let ev = eventResponse.event {
                    let aiEvent = ev.toEvent(defaultDate: defaultDate)
                    let fallbackEvent = TextToEventParser.parse(text: recognizedText, defaultDate: defaultDate)
                    let merged = reconcileEvent(primary: aiEvent, fallback: fallbackEvent)
                    return ParsedResult(
                        recognizedText: recognizedText,
                        event: merged
                    )
                }
                let localClean = TextToEventParser.cleanRecognizedText(recognizedText)
                let event = TextToEventParser.parse(text: localClean.isEmpty ? recognizedText : localClean, defaultDate: defaultDate)
                return ParsedResult(recognizedText: localClean.isEmpty ? recognizedText : localClean, event: event)
            }

            let localClean = TextToEventParser.cleanRecognizedText(jsonString)
            let event = TextToEventParser.parse(text: localClean.isEmpty ? jsonString : localClean, defaultDate: defaultDate)
            return ParsedResult(recognizedText: localClean.isEmpty ? jsonString : localClean, event: event)
        } catch let error as RecognizerError {
            throw error
        } catch {
            throw RecognizerError.network(error)
        }
    }

    func recognize(image: UIImage, defaultDate: Date) async throws -> ParsedResult {
        guard let endpoint = endpoint, let apiKey = apiKey, !apiKey.isEmpty else {
            throw RecognizerError.missingConfig
        }
        guard let jpegData = image.jpegData(compressionQuality: 0.7) else {
            throw RecognizerError.imageEncodingFailed
        }

        let base64Image = "data:image/jpeg;base64,\(jpegData.base64EncodedString())"

        let systemPrompt = """
        你是一個行程與記帳解析助手。請從聊天截圖或照片中擷取單一事件資訊，並回傳純 JSON（不要有多餘文字）：
        {
          "recognizedText": "與事件相關的簡短文字（不要包含狀態列時間或已讀）",
          "event": {
            "title": "...", // 不要包含日期/時間，簡短描述，如「去吃飯」
            "description": "...", // 允許為空
            "date": "ISO8601", // 優先使用圖片中的日期（如 11/30），若無則用今天
            "time": "HH:mm 可選", // 若無時間，可省略
            "amount": 2000, // 沒有則 null
            "category": "餐飲|交通|購物|娛樂|醫療|教育|旅遊|其他",
            "isExpense": true,
            "shareGroupSize": 1,
            "splitMethod": "personal"
          }
        }
        如無法確定某欄位，設為 null 或省略，請確保輸出可被 JSON 解析。
        """

        let userText = "請解析這張圖片中的行程/消費資訊，並輸出上述 JSON 結構。避免使用狀態列時間。"

        let systemMessage = Message(role: "system", content: [.text(systemPrompt)])
        let userMessage = Message(
            role: "user",
            content: [
                .text(userText),
                .imageURL(ImageURL(url: base64Image))
            ]
        )

        let request = ChatRequest(
            model: model,
            messages: [systemMessage, userMessage],
            max_tokens: 800,
            extra_body: ExtraBody(reasoning: Reasoning(enabled: true))
        )

        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let encoder = JSONEncoder()
        guard let body = try? encoder.encode(request) else {
            throw RecognizerError.imageEncodingFailed
        }
        urlRequest.httpBody = body

        do {
            let (data, response) = try await URLSession.shared.data(for: urlRequest)
            guard let http = response as? HTTPURLResponse else {
                throw RecognizerError.invalidResponse
            }
            guard (200...299).contains(http.statusCode) else {
                let body = String(data: data, encoding: .utf8)
                throw RecognizerError.server(status: http.statusCode, body: body)
            }

            let decoded = try JSONDecoder().decode(ChatResponse.self, from: data)
            guard let content = decoded.choices.first?.message.content else {
                throw RecognizerError.invalidResponse
            }

            let jsonString: String
            switch content {
            case .string(let text):
                jsonString = text
            case .parts(let parts):
                jsonString = parts.compactMap { part in
                    switch part {
                    case .text(let t): return t
                    default: return nil
                    }
                }.joined(separator: "\n")
            }

            if let eventResponse = try? JSONDecoder().decode(APIResponse.self, from: Data(jsonString.utf8)) {
                let recognizedText = eventResponse.recognizedText ?? ""
                if let ev = eventResponse.event {
                    let aiEvent = ev.toEvent(defaultDate: defaultDate)
                    let fallbackEvent = TextToEventParser.parse(text: recognizedText, defaultDate: defaultDate)
                    let merged = reconcileEvent(primary: aiEvent, fallback: fallbackEvent)
                    return ParsedResult(
                        recognizedText: recognizedText,
                        event: merged
                    )
                }
                let cleaned = TextToEventParser.cleanRecognizedText(recognizedText)
                let event = TextToEventParser.parse(text: cleaned.isEmpty ? recognizedText : cleaned, defaultDate: defaultDate)
                return ParsedResult(recognizedText: cleaned.isEmpty ? recognizedText : cleaned, event: event)
            }

            // fallback to local parser if JSON decode fails
            let cleaned = TextToEventParser.cleanRecognizedText(jsonString)
            let event = TextToEventParser.parse(text: cleaned.isEmpty ? jsonString : cleaned, defaultDate: defaultDate)
            return ParsedResult(recognizedText: cleaned.isEmpty ? jsonString : cleaned, event: event)
        } catch let error as RecognizerError {
            throw error
        } catch {
            throw RecognizerError.network(error)
        }
    }
}

// MARK: - Request DTO

private struct ChatRequest: Encodable {
    let model: String
    let messages: [Message]
    let max_tokens: Int?
    let extra_body: ExtraBody?
}

private struct Message: Encodable {
    let role: String
    let content: [Content]
}

private enum Content: Encodable {
    case text(String)
    case imageURL(ImageURL)

    enum CodingKeys: String, CodingKey {
        case type
        case text
        case image_url
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .text(let value):
            try container.encode("text", forKey: .type)
            try container.encode(value, forKey: .text)
        case .imageURL(let url):
            try container.encode("image_url", forKey: .type)
            try container.encode(url, forKey: .image_url)
        }
    }
}

private struct ImageURL: Encodable {
    let url: String
}

private struct ExtraBody: Encodable {
    let reasoning: Reasoning
}

private struct Reasoning: Encodable {
    let enabled: Bool
}

// MARK: - Response DTO

private struct ChatResponse: Decodable {
    let choices: [Choice]
}

private struct Choice: Decodable {
    let message: ChatMessage
}

private struct ChatMessage: Decodable {
    let content: ChatContent
}

private enum ChatContent: Decodable {
    case string(String)
    case parts([Part])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let str = try? container.decode(String.self) {
            self = .string(str)
        } else if let parts = try? container.decode([Part].self) {
            self = .parts(parts)
        } else {
            self = .string("")
        }
    }
}

private enum Part: Decodable {
    case text(String)
    case other

    enum CodingKeys: String, CodingKey {
        case type
        case text
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        if type == "text" {
            let text = try container.decode(String.self, forKey: .text)
            self = .text(text)
        } else {
            self = .other
        }
    }
}

private struct APIResponse: Decodable {
    let recognizedText: String?
    let event: EventPayload?
}

private struct EventPayload: Decodable {
    let title: String
    let description: String?
    let date: String?
    let time: String?
    let amount: Double?
    let category: String?
    let isExpense: Bool?
    let shareGroupSize: Int?
    let splitMethod: String?

    func toEvent(defaultDate: Date) -> Event {
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let legacyISO = ISO8601DateFormatter()
        legacyISO.formatOptions = [.withInternetDateTime]

        var parsedDate = date.flatMap { isoFormatter.date(from: $0) ?? legacyISO.date(from: $0) } ?? defaultDate
        if let time = time, let timeDate = isoFormatter.date(from: "1970-01-01T\(time)Z") {
            let calendar = Calendar.current
            var comps = calendar.dateComponents([.year, .month, .day], from: parsedDate)
            comps.hour = calendar.component(.hour, from: timeDate)
            comps.minute = calendar.component(.minute, from: timeDate)
            parsedDate = calendar.date(from: comps) ?? parsedDate
        }

        let cat = Event.ExpenseCategory(rawValue: category ?? "") ?? .other
        let split = Event.SplitMethod(rawValue: splitMethod ?? "personal") ?? .personal

        let shareSize = max(1, shareGroupSize ?? 1)

        return Event(
            id: UUID(),
            title: title,
            description: description ?? "",
            date: parsedDate,
            color: .blue,
            amount: amount,
            category: cat,
            isExpense: isExpense ?? (amount != nil),
            shareGroupSize: shareSize,
            splitMethod: shareSize == 1 ? .personal : split
        )
    }
}

// MARK: - Merge Helpers

private func reconcileEvent(primary: Event, fallback: Event?) -> Event {
    guard let fallback = fallback else { return primary }
    var merged = primary
    let calendar = Calendar.current

    if !calendar.isDate(primary.date, inSameDayAs: fallback.date) {
        merged.date = fallback.date
    }
    if merged.amount == nil, let altAmount = fallback.amount {
        merged.amount = altAmount
    }
    if merged.isExpense == false, fallback.isExpense {
        merged.isExpense = true
    }
    // Keep title from AI to avoid over-trimming; but if empty use fallback
    if merged.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        merged.title = fallback.title
    }
    return merged
}
