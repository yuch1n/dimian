//
//  ImageImportView.swift
//  fortest
//
//  Created by Codex on 2025/3/14.
//

import SwiftUI
import PhotosUI

struct ImageImportView: View {
    @Environment(\.presentationMode) private var presentationMode

    let defaultDate: Date
    let onAdd: (Event) -> Void

    @State private var pickerItem: PhotosPickerItem?
    @State private var selectedImage: UIImage?
    @State private var recognizedText: String = ""
    @State private var rawRecognizedText: String = ""
    @State private var parsedEvent: Event?
    @State private var statusMessage: String = "請選擇聊天截圖，系統會自動辨識文字。"
    @State private var isProcessing = false
    @State private var usingAI = true

    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_TW")
        formatter.dateFormat = "yyyy/MM/dd (EEE)"
        return formatter
    }()

    private let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_TW")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("選擇截圖")) {
                    PhotosPicker(selection: $pickerItem, matching: .images, preferredItemEncoding: .automatic) {
                        HStack {
                            Image(systemName: "photo.on.rectangle")
                            Text("從相簿選擇圖片")
                        }
                    }
                    if let image = selectedImage {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 240)
                            .cornerRadius(12)
                    }
                    Toggle("使用 AI 解析", isOn: $usingAI)
                        .toggleStyle(SwitchToggleStyle(tint: .blue))
                }

                Section(header: Text("辨識狀態")) {
                    if isProcessing {
                        HStack {
                            ProgressView()
                            Text("辨識中...")
                        }
                    } else {
                        Text(statusMessage)
                            .foregroundColor(.secondary)
                    }
                }

                Section(header: Text("辨識文字")) {
                    if recognizedText.isEmpty {
                        Text("尚未辨識文字")
                            .foregroundColor(.secondary)
                    } else {
                        Text(recognizedText)
                            .font(.body)
                    }
                }

                Section(header: Text("解析結果")) {
                    if let event = parsedEvent {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("標題")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text(event.title)
                            }
                            HStack {
                                Text("時間")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text("\(dateFormatter.string(from: event.date)) \(timeFormatter.string(from: event.date))")
                            }
                            HStack {
                                Text("金額")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                Spacer()
                                if let amount = event.amount {
                                    Text("NT$ \(String(format: "%.0f", amount))")
                                        .foregroundColor(.red)
                                } else {
                                    Text("未偵測")
                                        .foregroundColor(.secondary)
                                }
                            }
                            HStack {
                                Text("類別")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text(event.category.rawValue)
                            }
                            HStack {
                                Text("支出/收入")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text(event.isExpense ? "支出" : "非支出")
                            }
                        }
                    } else {
                        Text("等待截圖辨識後解析。")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("截圖轉行程")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") {
                        presentationMode.wrappedValue.dismiss()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("加入") {
                        save()
                    }
                    .disabled(parsedEvent == nil)
                }
            }
            .onChange(of: pickerItem) { newItem in
                if let newItem = newItem {
                    Task {
                        await loadImage(from: newItem)
                    }
                }
            }
        }
    }

    @MainActor
    private func loadImage(from item: PhotosPickerItem) async {
        isProcessing = true
        defer { isProcessing = false }
        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data) else {
                statusMessage = "載入圖片失敗，請重試。"
                return
            }
            selectedImage = image
            statusMessage = usingAI ? "文字辨識中..." : "辨識中..."

            let text = try await ImageTextRecognizer.recognizeText(from: image)
            rawRecognizedText = text
            let cleanedForDisplay = TextToEventParser.cleanRecognizedText(text)
            recognizedText = cleanedForDisplay.isEmpty ? text : cleanedForDisplay

            if usingAI {
                statusMessage = "AI 解析中..."
                do {
                    let result = try await AIImageEventRecognizer.shared.parseRecognizedText(rawRecognizedText, defaultDate: defaultDate)
                    recognizedText = result.recognizedText
                    parsedEvent = result.event
                    statusMessage = "AI 解析完成"
                    if parsedEvent == nil {
                        parseText(rawRecognizedText)
                    }
                } catch {
                    statusMessage = "AI 解析失敗：\(error.localizedDescription)，改用內建解析。"
                    parseText(rawRecognizedText)
                }
            } else {
                parseText(rawRecognizedText)
                statusMessage = "辨識完成"
            }
        } catch {
            statusMessage = "辨識失敗：\(error.localizedDescription)"
            recognizedText = ""
            parsedEvent = nil
        }
    }

    private func parseText(_ text: String) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            parsedEvent = nil
            return
        }
        parsedEvent = TextToEventParser.parse(text: text, defaultDate: defaultDate)
    }

    private func handleLocalParse(_ text: String) {
        let cleaned = TextToEventParser.cleanRecognizedText(text)
        recognizedText = cleaned.isEmpty ? text : cleaned
        parseText(recognizedText)
    }

    private func save() {
        guard let event = parsedEvent else { return }
        onAdd(event)
        presentationMode.wrappedValue.dismiss()
    }
}
