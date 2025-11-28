//
//  ImageTextRecognizer.swift
//  fortest
//
//  Created by Codex on 2025/3/14.
//

import Foundation
import Vision
import UIKit

enum ImageTextRecognizer {
    enum RecognizerError: Error {
        case noCGImage
        case noTextFound
    }

    static func recognizeText(from image: UIImage) async throws -> String {
        guard let cgImage = image.cgImage else { throw RecognizerError.noCGImage }

        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let observations = request.results as? [VNRecognizedTextObservation], !observations.isEmpty else {
                    continuation.resume(throwing: RecognizerError.noTextFound)
                    return
                }

                let lines: [RecognizedLine] = observations.compactMap { observation in
                    guard let candidate = observation.topCandidates(1).first else { return nil }
                    let box = observation.boundingBox
                    return RecognizedLine(text: candidate.string, x: box.origin.x, y: box.origin.y + box.height)
                }

                let ordered = lines
                    .sorted { lhs, rhs in
                        if abs(lhs.y - rhs.y) > 0.02 {
                            return lhs.y > rhs.y // y 越大越靠上
                        }
                        return lhs.x < rhs.x
                    }
                    .map { $0.text }

                let joined = ordered.joined(separator: "\n")
                continuation.resume(returning: joined)
            }

            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.minimumTextHeight = 0.01
            request.recognitionLanguages = ["zh-Hant", "zh-Hans", "en-US"]

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    private struct RecognizedLine {
        let text: String
        let x: CGFloat
        let y: CGFloat
    }
}
