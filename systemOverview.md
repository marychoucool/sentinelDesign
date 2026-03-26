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

- **公司員工**（Normal User）
  - **Basic Plan**: 使用 RAG Chat 查詢會議內容
  - **Mid Plan**: 使用 Agent with MCP Chat，支援更複雜的任務執行
- **管理者**（Admin User）
- **Root**（Super User for Dev and Debug）  

---

# Terminology

- **Session**: 等同於 truley companion meeting
- **Action Item**: 類似 Jira ticket，包括具體任務、指派人與截止日期

---

# User Story

## Session Recording
- 作為使用者，我希望可以建立會議即時 Session，錄製會議內容（streaming upload）。
- 作為使用者，我希望可以預約會議 Session。
- 作為使用者，我希望在離線時錄製 Session，連線後自動上傳至 server。
- As a user, I want to be notified when a session is processed successfully, so that I can check report ASAP.

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

## Settings
- 作為使用者，我希望可以更改個人資訊。

## Debug and Dev
- As a root, I want to access everything in the system to debug and develop.

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

### 主要流程
1. 使用者開啟 Chat 介面，輸入自然語言查詢。
2. 系統透過 RAG 檢索 pgvector 並由 LLM 回答。
3. 使用者查看 Session Report 或 Action Items（可篩選狀態）。
4. 使用者修改 Action Item 內容以確保明確性。

---

## 5. 系統監控與 Debug (Admin & Root)
**Actor**: Admin User / Root  
**Precondition**: Admin User / Root logged in

### 主要流程
1. 查看伺服器硬體狀態（CPU/Memory/Storage）及系統活躍指標（Active Sessions）。
2. **權限限制**：Admin 無法查看特定會議逐字稿或摘要內容。

---

# Infra
- Linux
- Docker
- pgvector