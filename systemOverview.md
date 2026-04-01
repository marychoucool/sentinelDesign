# 系統描述

系統會部署在客戶的 **on-premise PC**（作為 server）。

使用者透過 **mobile device**（laptop / iOS / Android）連線至 server，進行即時語音傳輸（session），session內容為會議討論（meeting）。

Server 端會執行兩個模型：
- **ASR**（語音轉文字）
- **LLM**（語意理解 / 回答）

系統功能：
- 將 audio 轉為文字並儲存
- 將內容向量化存入 **pgvector**（支援語意搜尋）
- 提供 chat 介面讓使用者透過 RAG 查詢會議內容
- 根據會議內容產出：
  - **Report**（會議摘要）
  - **Action Items**（任務指派，類似 Jira ticket）

---

# 系統目標

- 自動整理會議內容（session）
- 自動產出任務並指派負責人
- 提供 LLM chat 查詢歷史會議
- 提升企業會議效率與資訊可追蹤性

---

# 使用者角色

- **系統部署者 / IT 人員**（Deployer）
  - 負責初次系統設定與網路配置
- **公司員工**（Normal User）
  - **Basic Plan**: 使用 RAG Chat 查詢會議內容
  - **Mid Plan**: 使用 Agent with MCP Chat，支援更複雜的任務執行
- **管理者**（Admin User）
  - 系統監控、使用者管理、首次初始化設定
- **Root**（Super User for Dev and Debug）
  - 全系統存取權限，用於開發與排錯  

---

# Terminology

- **Session**: 等同於 truley companion meeting
- **Action Item**: 類似 Jira ticket，包括具體任務、指派人與截止日期

---

# User Story

## Initial Setup & First-Time Configuration
- 作為 **系統部署者**，我希望在首次啟動 Sentinel Server 時能夠設定網路連線（支援 Static IP 或 DHCP），以便 Server 能夠在客戶環境中正確運作。
- 作為 **系統部署者**，我希望系統能提供設定網路的命令範例，以便快速完成網路配置。
- 作為 **系統部署者**，我希望在首次啟動時輸入 License Key 以啟用 Sentinel 服務，確保授權合法。
- 作為 **管理者**（Admin User），我希望在首次設定完成後，能透過直連 IP 訪問 Sentinel Server 的初始化頁面。
- 作為 **管理者**，我希望透過初始化頁面能夠創建 Normal User 帳號，並查看系統基本資訊（包含音訊檔管理）。
- 作為 **管理者**，我希望查看 License 狀態與到期時間，以便提前續約。
- 作為 **管理者**，我希望系統能在 License 即將到期時發出通知。
- 作為 **管理者**，我希望系統能夠在**完全離線**（無外網連線）的環境下進行使用者認證，確保資料安全與隱私。

## Session Recording
- 作為使用者，我希望可以建立會議即時 Session，錄製會議內容（streaming upload）。
- 作為使用者，我希望可以預約會議 Session，時間到的時候前端提醒使用者，並可以在 calendar page 查看。
- 作為使用者，我希望在離線時錄製 Session，連線後自動上傳至 server。
- 作為使用者，我希望在 Session 處理完成後收到通知，以便盡快查看報告。

## Report
- 作為使用者，我希望完成 session 後系統能自動產生會議摘要。
- 作為使用者，我希望可以將會議報告匯出為 PDF、Word 或 Markdown 格式。

## Action Item
- 作為使用者，我希望系統能自動從會議中產生任務。
- 作為使用者，我希望可以查看被指派的任務及其狀態（未完成/已完成/逾期）。
- 作為使用者，我希望可以更改 Action Item 內容，使工作更具體明確。

## Chat
- 作為 **Basic Plan** 使用者，我希望可以用自然語言查詢過去會議內容（RAG 模式）。
- 作為 **Mid Plan** 使用者，我希望 Chat 能協助我執行複雜任務，如修改 Action Items、建立會議等（Agent with MCP 模式）。

## Dashboard
- 作為管理者，我希望可以監控伺服器資源（CPU、記憶體、儲存空間）。
- 作為管理者，我希望可以查看目前活躍會議 Session 及任務數量。

## Calendar
- 作為使用者，我希望可以在 calendar page 當中看到我所預約的 session。

## Settings
- 作為使用者，我希望可以更改個人資訊。

## Debug and Dev
- 作為 Root，我希望能夠存取系統中的所有內容以進行除錯與開發。

---

# Use Case

## 1. 建立與同步會議錄音 (Session Recording & Sync)
**Actor**: Normal User  
**Precondition**: Normal user is logged in

### 主要流程
1. 使用者在 Mobile Device 點擊「開始錄製」。
2. 系統在本地建立 Session 並開始錄音。
3. 使用者結束錄音，系統詢問是否上傳至 Server。
4. 系統將音檔上傳至 On-premise Server。
5. Server 接收完成，進入 ASR 與 LLM 分析。

### 替代流程（離線/排程）
- **離線錄製**：音檔暫存在 Mobile Device，待連線後手動上傳。
- **預約錄製**：使用者預設會議時間，系統在指定時間提醒或自動開啟錄製介面。

---

## 2. 查看與管理會議報告 (View & Manage Meeting Report)
**Actor**: Normal User  
**Precondition**: Session 已上傳且 Server 已完成 ASR 與 LLM 批次處理

### 主要流程
1. 使用者收到系統通知（處理完成）。
2. 使用者進入 App 的「會議列表」點擊該 Session。
3. 系統呈現 **會議摘要 (Report)**，包含關鍵討論點。
4. 系統同步列出由 LLM 自動識別並指派的 **待辦事項 (Action Items)**。
5. 使用者檢閱報告內容與逐字稿 (Transcript, timestamp)。
6. 使用者點擊「匯出」，選擇格式（PDF/Word/Markdown）下載。

---

## 3. 自動化會議處理與任務指派 (Batch AI Processing)
**Actor**: 系統 (System / AI Engine)  
**觸發條件**: Session 音檔上傳完成

### 主要流程
1. **ASR 轉寫**：音檔轉文字。
2. **向量化儲存**：切片逐字稿並存入 pgvector，支援 RAG 檢索。
3. **LLM 分析**：生成會議摘要 (Report) 與待辦事項 (Action Items)。
4. **自動指派**：LLM 識別對話中的人名，指派給使用者。
5. **通知發送**：處理完成後通知與會者。

---

## 4. Chat Intelligence
**Actor**: Normal User

**Precondition**: Normal user logged in 且至少有一個完成的 session

### 主要流程（Basic Plan - RAG 模式）
1. 使用者開啟 Chat 介面，輸入自然語言查詢。
2. 系統透過 RAG 檢索 pgvector 並由 LLM 回答。
3. 使用者查看 Session Report 或 Action Items（可篩選狀態）。

### 主要流程（Mid Plan - Agent with MCP 模式）
1. 使用者開啟 Chat 介面，輸入複雜任務指令（如「幫我建立下週三的團隊會議」）。
2. 系統透過 Agent Engine 進行任務規劃與工具調用。
3. Agent 透過 MCP Server 呼叫系統工具（如建立 Session、修改 Action Item）。
4. 系統回傳執行結果與狀態更新。

---

## 5. 系統監控與 Debug (Admin & Root)
**Actor**: Admin User / Root

**Precondition**: Admin User / Root logged in

### 主要流程（Admin User）
1. 查看伺服器硬體狀態（CPU/Memory/Storage）及系統活躍指標（Active Sessions）。
2. 查看使用者列表與系統統計資訊。
3. 管理使用者帳號（創建、修改、停用）。

### 主要流程（Root）
1. 擁有 Admin User 的所有權限。
2. 可查看特定會議逐字稿、摘要內容（用於除錯）。
3. 可存取系統日誌與錯誤追蹤資訊。
4. 可執行系統維護操作（如重新索引、清理快取）。

---

## 6. 查看與管理預約會議 (Calendar)
**Actor**: Normal User / Admin User

**Precondition**: User logged in

### 主要流程
1. 使用者進入 Calendar 介面。
2. 系統呈現已預約的 Session（標題、時間、參與者）。
3. 使用者可以點擊特定 Session 查看詳情或進行修改/取消。

---

## 7. 初次系統設定與網路配置 (Initial Setup & Network Configuration)
**Actor**: 系統部署者 / IT 人員

**Precondition**: Sentinel Server 硬體已就緒，尚未進行網路設定

### 主要流程
1. 系統部署者將 Sentinel Server 連接至客戶網路。
2. 系統部署者執行初次設定命令。
3. 系統提供網路設定選項：
   - **DHCP 模式**（推薦）：自動從 DHCP Server 取得 IP
   - **Static IP 模式**：手動輸入 IP、Netmask、Gateway、DNS
4. 系統套用網路設定並回報設定成功與分配的 IP 位址。
5. 系統啟動 Web Server（預設連接埠 80/443）。

### 替代流程
- **Static IP 設定**：系統提供設定命令範例，部署者複製並修改參數後執行。
- **設定失敗**：系統提供錯誤訊息與診斷建議（如檢查網路線、IP 衝突等）。

---

## 8. 首次管理者登入與使用者初始化 (First-Time Admin Login & User Initialization)
**Actor**: Admin User (首次登入)

**Precondition**: 網路設定完成，Admin 透過 IP 直連 Sentinel Server

### 主要流程
1. Admin 開啟瀏覽器，輸入 Sentinel Server 的 IP 位址（如 `http://192.168.1.100`）。
2. 系統呈現**初始化設定頁面**（首次訪問限定）。
3. 系統顯示基本資訊：
   - 系統版本與狀態
   - 硬體資源概況（CPU、Memory、Storage）
   - 音訊檔儲存位置與容量
   - 目前網路設定資訊（IP、Gateway、DNS）
4. Admin 輸入預設管理者憑證或設定新的管理者密碼。
5. 系統驗證成功後，進入**使用者管理頁面**。
6. Admin 創建第一個 Normal User 帳號（輸入使用者名稱、Email、初始密碼）(登入使用Email、初始密碼)。
7. 系統將使用者資訊儲存至本地資料庫（**無需外網連線**）。
8. Admin 可繼續創建更多 Normal User 或完成初始化。

### 安全考量
- **離線認證機制**：所有認證資訊（密碼 hash、session token）均儲存在本地資料庫，不依賴外部 OAuth 或雲端服務。
- **預設連接埠**：初始化頁面僅在首次訪問時顯示，之後需登入才能存取。
- **HTTPS 支援**：系統支援自簽憑證或上傳客戶提供憑證，確保加密傳輸。

---

## 9. Sentinel License Activation
**Actor**: 系統部署者 / IT 人員

**Precondition**: Sentinel Server 網路設定完成，具備外網連線（用於 License 驗證）

### 主要流程
1. 系統部署者完成網路設定後，系統提示進行 License Activation。
2. 系統部署者輸入 License Key。
3. Sentinel Server 連線至 SaaS 服務進行 License 驗證。
4. SaaS 驗證 License Key 有效後，回傳授權資訊（到期日、功能等級）。
5. 系統儲存授權資訊並啟用 Sentinel 服務。
6. 系統顯示啟用成功與 License 到期日。

### 替代流程
- **License 無效**：系統顯示錯誤訊息（無效、過期、已使用），允許重新輸入。
- **無外網連線**：系統提供離線啟用流程（生成 request file，上傳至 SaaS portal 取得 response file，匯入後啟用）。
- **License 即將到期**：系統提前 30 天通知管理員，可透過 SaaS 續約並更新 License Key。

### 備註
- **License 與 Relay Tunnel 註冊分離**：License Activation 是產品授權驗證；Relay Tunnel 註冊是建立反向隧道連線，兩者為獨立功能。
- **授權資訊儲存**：License 資訊（Key、到期日、等級）儲存於本地資料庫，定期與 SaaS 同步狀態。

---

# Infra
- **OS**: Linux
- **Container**: Docker
- **Database**: PostgreSQL + pgvector
- **Relay Endpoint**: Rust (自建)
- **Backend API**: NestJS
- **Job Processing**: Database Jobs Table Polling (ASR/LLM Services)