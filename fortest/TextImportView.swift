import SwiftUI

struct TextImportView: View {
    @Environment(\.presentationMode) private var presentationMode

    let defaultDate: Date
    let onAdd: (Event) -> Void

    @State private var rawText: String = ""
    @State private var parsedEvent: Event?
    @State private var parseError: String?

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
                Section(header: Text("辨識文字")) {
                    TextEditor(text: $rawText)
                        .frame(minHeight: 160)
                        .onChange(of: rawText) { _ in
                            parseText()
                        }
                    Text("貼上辨識結果（例：\"3/16 19:30 西門町吃晚餐 420元\"），系統會自動解析日期、時間、金額與類別。")
                        .font(.footnote)
                        .foregroundColor(.secondary)
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
                                    .font(.body)
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
                            if !event.description.isEmpty {
                                Text(event.description)
                                    .font(.callout)
                                    .foregroundColor(.secondary)
                                    .padding(.top, 4)
                            }
                        }
                    } else if let parseError {
                        Text(parseError)
                            .foregroundColor(.secondary)
                    } else {
                        Text("輸入後會自動解析。")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("文字轉行程")
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
            .onAppear {
                parseText()
            }
        }
    }

    private func parseText() {
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            parsedEvent = nil
            parseError = "請輸入文字供解析。"
            return
        }

        if let event = TextToEventParser.parse(text: trimmed, defaultDate: defaultDate) {
            parsedEvent = event
            parseError = nil
        } else {
            parsedEvent = nil
            parseError = "無法解析，請確認格式。"
        }
    }

    private func save() {
        guard let event = parsedEvent else { return }
        onAdd(event)
        presentationMode.wrappedValue.dismiss()
    }
}
