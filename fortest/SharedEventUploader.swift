import Foundation

final class SharedEventUploader {
    static let shared = SharedEventUploader()

    enum UploadError: Error {
        case missingEndpoint
        case encodingFailed
        case network(Error)
        case server(status: Int, body: String?)
        case noSharedEvents
    }

    private let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private var endpointURL: URL? {
        if let value = Bundle.main.object(forInfoDictionaryKey: "SharedEventsUploadURL") as? String {
            return URL(string: value)
        }
        return nil
    }

    func uploadSharedEvents(_ events: [Event], completion: @escaping (Result<Int, UploadError>) -> Void) {
        let sharedEvents = events.filter { $0.isShared }
        guard !sharedEvents.isEmpty else {
            completion(.failure(.noSharedEvents))
            return
        }

        guard let endpoint = endpointURL else {
            completion(.failure(.missingEndpoint))
            return
        }

        let payload = SharedEventUploadPayload(
            generatedAt: isoFormatter.string(from: Date()),
            events: sharedEvents.map { SharedEventPayload(event: $0, formatter: isoFormatter) }
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]

        guard let body = try? encoder.encode(payload) else {
            completion(.failure(.encodingFailed))
            return
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(.network(error)))
                return
            }

            guard let httpResponse = response as? HTTPURLResponse else {
                completion(.failure(.server(status: -1, body: nil)))
                return
            }

            guard (200...299).contains(httpResponse.statusCode) else {
                let bodyString = data.flatMap { String(data: $0, encoding: .utf8) }
                completion(.failure(.server(status: httpResponse.statusCode, body: bodyString)))
                return
            }

            completion(.success(sharedEvents.count))
        }
        task.resume()
    }

    private struct SharedEventUploadPayload: Encodable {
        let generatedAt: String
        let events: [SharedEventPayload]
    }

    private struct SharedEventPayload: Encodable {
        let id: UUID
        let title: String
        let description: String
        let date: String
        let amount: Double?
        let category: String
        let isExpense: Bool
        let shareGroupSize: Int
        let splitMethod: String

        init(event: Event, formatter: ISO8601DateFormatter) {
            id = event.id
            title = event.title
            description = event.description
            date = formatter.string(from: event.date)
            amount = event.amount
            category = event.category.rawValue
            isExpense = event.isExpense
            shareGroupSize = max(1, event.shareGroupSize)
            splitMethod = event.splitMethod.rawValue
        }
    }
}
