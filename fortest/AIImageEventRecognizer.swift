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

    private init() {}

    private var endpoint: URL? {
        if let value = UserDefaults.standard.string(forKey: "AIImageParseURL"),
           let url = URL(string: value) {
            return url
        }
        if let value = Bundle.main.object(forInfoDictionaryKey: "AIImageParseURL") as? String,
           let url = URL(string: value) {
            return url
        }
        return URL(string: "https://openrouter.ai/api/v1/chat/completions")
    }

    private var apiKey: String? {
        if let stored = UserDefaults.standard.string(forKey: "AIImageParseKey"), !stored.isEmpty {
            return stored
        }
        if let key = Bundle.main.object(forInfoDictionaryKey: "AIImageParseKey") as? String, !key.isEmpty {
            return key
        }
        if let env = ProcessInfo.processInfo.environment["OPENROUTER_API_KEY"], !env.isEmpty {
            return env
        }
        return nil
    }

    private var model: String {
        if let stored = UserDefaults.standard.string(forKey: "AIImageParseModel"), !stored.isEmpty {
            return stored
        }
        return (Bundle.main.object(forInfoDictionaryKey: "AIImageParseModel") as? String) ?? "openai/gpt-4o-mini"
    }

    private var fallbackModel: String? {
        if let stored = UserDefaults.standard.string(forKey: "AIImageParseFallbackModel"), !stored.isEmpty {
            return stored
        }
        return Bundle.main.object(forInfoDictionaryKey: "AIImageParseFallbackModel") as? String
    }

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

        let content = try await requestContent(endpoint: endpoint, apiKey: apiKey) { candidate in
            if supportsSystemRole(for: candidate) {
                return [
                    Message(role: "system", content: [.text(systemPrompt)]),
                    Message(role: "user", content: [.text(userMessage)])
                ]
            }
            let combined = "\(systemPrompt)\n\n\(userMessage)"
            return [Message(role: "user", content: [.text(combined)])]
        }

        let jsonString = contentText(from: content)
        return parseResult(from: jsonString, defaultDate: defaultDate, fallbackText: cleaned)
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

        let content = try await requestContent(endpoint: endpoint, apiKey: apiKey) { candidate in
            if supportsSystemRole(for: candidate) {
                let systemMessage = Message(role: "system", content: [.text(systemPrompt)])
                let userMessage = Message(
                    role: "user",
                    content: [
                        .text(userText),
                        .imageURL(ImageURL(url: base64Image))
                    ]
                )
                return [systemMessage, userMessage]
            }
            let combined = "\(systemPrompt)\n\n\(userText)"
            let userMessage = Message(
                role: "user",
                content: [
                    .text(combined),
                    .imageURL(ImageURL(url: base64Image))
                ]
            )
            return [userMessage]
        }

        let jsonString = contentText(from: content)
        return parseResult(from: jsonString, defaultDate: defaultDate, fallbackText: "")
    }
}

private extension AIImageEventRecognizer {
    func requestContent(endpoint: URL, apiKey: String, buildMessages: (String) -> [Message]) async throws -> ChatContent {
        let candidates = modelCandidates
        var lastError: RecognizerError?

        for candidate in candidates {
            do {
                let messages = buildMessages(candidate)
                return try await send(messages: messages, model: candidate, endpoint: endpoint, apiKey: apiKey)
            } catch let error as RecognizerError {
                lastError = error
                if case .server(let status, _) = error, (400...499).contains(status) {
                    continue
                }
                throw error
            }
        }
        throw lastError ?? RecognizerError.invalidResponse
    }

    func send(messages: [Message], model: String, endpoint: URL, apiKey: String) async throws -> ChatContent {
        let request = ChatRequest(
            model: model,
            messages: messages,
            max_tokens: 800
        )

        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")
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
            return content
        } catch let error as RecognizerError {
            throw error
        } catch {
            throw RecognizerError.network(error)
        }
    }

    func parseResult(from jsonString: String, defaultDate: Date, fallbackText: String) -> ParsedResult {
        if let eventResponse = try? JSONDecoder().decode(APIResponse.self, from: Data(jsonString.utf8)) {
            let recognizedText = eventResponse.recognizedText ?? fallbackText
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
    }

    func contentText(from content: ChatContent) -> String {
        switch content {
        case .string(let text):
            return text
        case .parts(let parts):
            return parts.compactMap { part in
                switch part {
                case .text(let t): return t
                default: return nil
                }
            }.joined(separator: "\n")
        }
    }

    var modelCandidates: [String] {
        var candidates = [model]
        if let fallback = fallbackModel, !fallback.isEmpty, fallback != model {
            candidates.append(fallback)
        }
        return candidates
    }

    func supportsSystemRole(for model: String) -> Bool {
        let lower = model.lowercased()
        if lower.contains("gemma-3-4b-it") {
            return false
        }
        return true
    }
}

extension AIImageEventRecognizer.RecognizerError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .missingConfig:
            return "缺少 AI 設定，請輸入 OpenRouter API Key。"
        case .imageEncodingFailed:
            return "圖片編碼失敗。"
        case .network(let error):
            return "網路錯誤：\(error.localizedDescription)"
        case .invalidResponse:
            return "回應格式無效。"
        case .server(let status, let body):
            if let body, !body.isEmpty {
                return "伺服器錯誤 (\(status))：\(body)"
            }
            return "伺服器錯誤，狀態碼 \(status)。"
        }
    }
}

private struct ChatRequest: Encodable {
    let model: String
    let messages: [Message]
    let max_tokens: Int?
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
    if merged.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        merged.title = fallback.title
    }
    return merged
}
