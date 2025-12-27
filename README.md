# Dimian 專案說明

## 專案特色
- 行事曆＋記帳整合：`CalendarView` 搭配 `EventListView` 讓行程、支出、共享資訊同步呈現，支援編輯、滑動刪除與色彩標記。
- 支出/共享場景：`Event` 支援金額、類別、多人分帳（AA/A0/自訂），並可透過 `SharedEventUploader` 依 Info.plist 端點上傳共享行程。
- 匯入匯出與分享：單日 JSON 匯出、全量 CSV 匯出（`exportEvents` / `exportDataToFile`），支援 JSON/CSV 匯入、iOS ShareSheet 行程分享。
- 文字/圖片快速轉行程：`TextImportView` 使用 `TextToEventParser` 將文字轉成行程；`ImageImportView` 結合 Vision OCR（`ImageTextRecognizer`）與可選 AI 解析（`AIImageEventRecognizer`）從聊天截圖生成行程。
- 消費分析：`ExpenseAnalyticsView`（Charts）提供總覽卡片、類別環圖、趨勢折線/面積圖及類別排行，並可一鍵載入示例資料。
- 內建示例與清除：首次啟動自動匯入 `Event.sampleEvents` 至 SQLite，亦可在 UI 端重置或清除所有資料。
- 多人同步模型（本地版）：`Event` 新增 `groupId`（協作 ID）、`author`、`updatedAt`、`syncStatus` 欄位；SQLite 同步遷移。衝突策略採最新更新時間優先（`EventDataManager.mergeSharedEvent`），現階段以本地 `LocalSyncEngine` 模擬雙向同步。
- 協作 UI：主畫面工具列提供協作設定（協作 ID / 協作者名稱），活動列顯示協作者名稱與同步狀態；若多人行程沒有作者，更新時會要求補填協作者。
- 多人協作流程（本地模擬）：以協作 ID 作為群組識別，僅同步 `isShared == true` 事件；建立/編輯/刪除後會標記 `pendingUpload` 並觸發同步。
- 衝突策略：以 `updatedAt` 判斷最新版本，較新的事件覆蓋較舊版本；刪除會被記錄並在同步時清理對應事件。
- 同步狀態提示：事件列顯示 `已同步/同步中`，協作者名稱顯示於共享事件底部，便於追蹤來源。
- 即時模擬：`LocalSyncEngine` 以本地 JSON 檔做為共享儲存，模擬雙向同步與刪除傳播，後續可替換為伺服器 API。

## 本系統使用的架構與技術
- 架構：SwiftUI MVVM（View + ObservableObject DataManager）搭配 SQLite 持久化與本地同步引擎。
- 資料層：`SQLiteManager` 以 SQLite3 C API 處理 CRUD、遷移與彙總查詢。
- 同步層：`LocalSyncEngine` 以本地 JSON 儲存模擬雙向同步、刪除傳播與衝突合併（`updatedAt` 最新優先）。
- 解析與匯入：文字解析 `TextToEventParser`、Vision OCR（`VNRecognizeTextRequest`）、CSV/JSON 匯入匯出。
- 視覺化與 UI：SwiftUI、Charts（iOS 16+）與 iOS 15 fallback，搭配 PhotosPicker / FileImporter / ShareSheet。

## 檔案與功能導覽（逐檔分析）
### App 入口與總體流程
- `fortest/fortestApp.swift`：App 入口，直接載入 `ContentView`，讓所有功能統一在單一主畫面入口啟動。
- `fortest/ContentView.swift`：主頁控制中心，整合「行事曆＋列表＋工具列」，提供新增、分析、圖片匯入、匯出、匯入、清除、協作 ID 設定等入口；同時整合多種 Sheet、Alert、ShareSheet、FileImporter 互動流程。

### UI 核心畫面
- `fortest/CalendarView.swift`：月曆格狀檢視、固定 6 行高度（避免跳動），支援月切換與日期選取，並以顏色圓點視覺化當天事件分佈。
- `fortest/EventListView.swift`：顯示選中日期清單，含當日總支出統計卡、無資料空態提示；單筆支援 swipe 編輯/刪除、context menu、共享分攤顯示、AA 每人金額計算。
- `fortest/EventEditView.swift`：新增/編輯表單，支援日期時間拆選、支出與類別切換、色彩標記、共享人數與分攤模式；切換共享狀態時自動調整合理值。
- `fortest/ExpenseAnalyticsView.swift`：分析頁含時間範圍選擇、總覽卡片、類別環圖（iOS 16 Charts）、趨勢折線與面積圖、類別排行與詳細頁入口；iOS 15 有列表與簡易趨勢 fallback。

### 文字/圖片匯入與解析
- `fortest/TextImportView.swift`：即時文字解析 UI，邊輸入邊解析，顯示解析出的標題、日期、金額、類別與支出狀態。
- `fortest/ImageImportView.swift`：PhotosPicker 選圖 → OCR →（可選 AI）→ 事件解析流程；提供即時狀態、辨識結果與解析預覽。
- `fortest/ImageTextRecognizer.swift`：Vision OCR，支援中英文、多行排序（依 y/x 位置重排），優先完整保留對話順序。
- `fortest/AIImageEventRecognizer.swift`：OpenRouter Chat Completions，支援文字解析與圖片解析，具備 JSON 回傳解析與備援模型。
- `fortest/TextToEventParser.swift`：文字規則解析引擎，具備日期/時間/金額/類別偵測、標題抽取、行清洗與噪音過濾（狀態列時間、已讀、英文自動回覆等），並提供 `cleanRecognizedText` 強化 OCR 結果品質。

### 資料模型與資料層
- `fortest/Event.swift`：核心資料模型（Codable + Identifiable），定義事件顏色、類別、分攤模式、同步狀態，並內建大量示例資料 `sampleEvents`。
- `fortest/EventDataManager.swift`：資料中樞（ObservableObject），封裝 SQLite CRUD、樣本載入、分攤與同步欄位校正、CSV/JSON 匯入匯出、共享上傳、文字解析新增等功能。
- `fortest/SQLiteManager.swift`：SQLite3 封裝層，負責資料庫連線、WAL/UTF-8 設定、欄位遷移（分享與同步欄位）、事件 CRUD、分類統計與每日統計。

### 共享與上傳
- `fortest/SharedEventUploader.swift`：共享行程上傳器（Info.plist 設定 `SharedEventsUploadURL`），以 ISO8601 生成 payload，處理網路與伺服器錯誤，回傳上傳筆數。

### 專案設定與資源
- `fortest/Assets.xcassets/*`：App Icon、AccentColor 等資源配置。
- `fortest/sample-import.csv`：CSV 匯入示例，包含支出與非支出樣本，方便測試解析與匯入流程。
- `fortest.xcodeproj/project.pbxproj`：Xcode 專案設定與建置配置。
- `fortest.xcodeproj/project.xcworkspace/contents.xcworkspacedata`：工作區描述檔。
- `fortest.xcodeproj/xcuserdata/.../xcschememanagement.plist`：個人 Scheme 管理檔（本機用）。
- `fortest.xcodeproj/xcuserdata/.../Breakpoints_v2.xcbkptlist`：本機斷點設定。
- `fortest.xcodeproj/project.xcworkspace/xcuserdata/.../UserInterfaceState.xcuserstate`：Xcode UI 狀態記錄。
- `swiftui-general-rules.mdc`：Swift/SwiftUI 開發規範（維護性、最新文件、描述簡潔）。

### 測試檔案
- `fortestTests/fortestTests.swift`：單元測試樣板（目前為空白範例）。
- `fortestUITests/fortestUITests.swift`：UI 測試樣板與啟動效能測試。
- `fortestUITests/fortestUITestsLaunchTests.swift`：啟動畫面截圖測試樣板。

## 使用技術與架構
- 前端：SwiftUI（NavigationView/Form/Sheet/Picker/SwipeActions）打造 iOS 行程/記帳介面，支援 PhotosPicker、FileImporter、ShareSheet。
- 數據層：自建 `SQLiteManager`（SQLite3 C API）負責事件 CRUD、欄位遷移、查詢彙總（每日、類別）；`EventDataManager` 作為 ObservableObject 封裝同步、CSV/JSON 匯入匯出與示例載入。
- 解析管線：`TextToEventParser` 進行日期/時間/金額/類別抽取與文字清洗；Vision OCR (`VNRecognizeTextRequest`) 取得行內位置排序；AI 解析透過 OpenRouter（需設定 API Key，建議模型 `openai/gpt-4o-mini`）。
- 網路：`SharedEventUploader` 以 `SharedEventsUploadURL` POST JSON 上傳共享事件。
- 視覺化：Charts (iOS 16+) 的 SectorMark、LineMark、AreaMark；提供 iOS 15 fallback。

## 專案成果
- 實作一個整合行程、記帳、分帳與分析的 iOS App 範例，附完整 UI 流程（新增/編輯/刪除/分享/上傳）。
- 落地化資料持久化與遷移邏輯，首次啟動即可載入示例資料並在 SQLite 永續保存。
- 多模匯入能力：文字、CSV/JSON 檔案、聊天截圖（本地 OCR 或 AI 模型）皆可轉成結構化行程。
- 產出可直接試用的樣本檔（`fortest/sample-import.csv`）與分析畫面，方便展示與測試。
