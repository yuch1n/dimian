# Dimian 系統架構圖

從專案原始碼（`ContentView`, `EventDataManager`, `SQLiteManager`, `TextToEventParser`, `ImageTextRecognizer`, `AIImageEventRecognizer`, `SharedEventUploader` 等）萃取的整體資料流如下。

```mermaid
flowchart LR
    subgraph UI["SwiftUI 介面"]
        CV[ContentView\nCalendarView + EventListView]
        EV[EventEditView\n新增/編輯行程]
        AV[ExpenseAnalyticsView\n支出統計]
        TV[TextImportView\n貼上文字解析]
        IV[ImageImportView\n截圖/照片匯入]
        SH[ShareSheet + FileImporter\n匯出/匯入]
    end

    subgraph Data["資料層"]
        EDM[EventDataManager\nObservableObject，集中 CRUD/匯出匯入]
        SQL[(SQLiteManager\nSQLite events.db\n含 schema migrate)]
    end

    subgraph Import["辨識/解析管線"]
        TTP[TextToEventParser\nregex + heuristics]
        OCR[ImageTextRecognizer\nVision OCR]
        AI[AIImageEventRecognizer\nOpenRouter chat\nx-ai/grok-4.1-fast]
    end

    subgraph Network["對外服務"]
        OR[(OpenRouter API)]
        UPL[SharedEventUploader\nPOST JSON]
        EXT[(SharedEventsUploadURL\n自備後端)]
    end

    CV <--> EDM
    EV --> EDM
    AV --> EDM
    SH -->|匯入 JSON/CSV| EDM
    EDM -- 匯出 JSON/CSV --> SH
    EDM <--> SQL

    TV --> TTP --> EDM
    IV --> OCR --> TTP
    IV -. 可選 AI 解析 .-> AI --> OR
    AI --> TTP

    EDM -- 上傳共享 isShared 事件 --> UPL --> EXT
```

### 流程重點
- `ContentView` 聚合日曆、列表、圖表、匯入/匯出按鈕；所有操作都透過 `EventDataManager`。
- `EventDataManager` 封裝 CRUD、JSON/CSV 匯入匯出，並以 `SQLiteManager` 永久化至 `events.db`，啟動時載入資料或示例數據。
- 文字匯入：`TextImportView` 觸發 `TextToEventParser` 解析日期/時間/金額/類別，輸出 `Event` 寫回資料層。
- 圖像匯入：`ImageImportView` 先跑 Vision OCR（`ImageTextRecognizer`），再交給 `TextToEventParser`；可選用 `AIImageEventRecognizer` 走 OpenRouter 取得結構化 JSON 後與本地結果整併。
- 共享上傳：`EventDataManager` 抽取當日 `isShared` 事件，交給 `SharedEventUploader` 轉 JSON 並 POST 至 `SharedEventsUploadURL`。
- 匯出/分享：資料層可輸出單日 JSON、全部 CSV，再由 `ShareSheet` 分享；`FileImporter` 支援 JSON/CSV 回填資料庫。
