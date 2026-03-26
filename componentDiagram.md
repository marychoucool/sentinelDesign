# Component Diagram (元件圖)

## 圖表位置
- **Backend API**: `/Users/mary/code/sentinel/backendApiComponent.mmd`
- **Chat Service**: `/Users/mary/code/sentinel/chatServiceComponent.mmd`

## 什麼是 Component Diagram？

**Component Diagram** 是 C4 模型的第三層，展開容器內部的元件（Components）及其互動關係。

### 適合對象
- 軟體架構師
- 開發團隊成員
- 技術主管

---

## 1. Backend API Component Diagram

### 架構層次

```
┌─────────────────────────────────────────────────────────┐
│                    Cross-cutting Concerns               │
│  (Auth Middleware, Validation, Exception, Logging)      │
└─────────────────────────────────────────────────────────┘
                            │
┌─────────────────────────────────────────────────────────┐
│                      API / Gateway Layer                │
│  Controllers + WebSocket Gateway                        │
└─────────────────────────────────────────────────────────┘
                            │
┌─────────────────────────────────────────────────────────┐
│                       Service Layer                     │
│  Business Logic Implementation                          │
└─────────────────────────────────────────────────────────┘
                            │
┌─────────────────────────────────────────────────────────┐
│                     Repository Layer                    │
│  Data Access Abstraction                                │
└─────────────────────────────────────────────────────────┘
                            │
┌─────────────────────────────────────────────────────────┐
│                   Infrastructure Layer                  │
│  External Service Clients + Storage                     │
└─────────────────────────────────────────────────────────┘
```

### 元件說明

#### API / Gateway Layer

| 元件 | 職責 |
|------|------|
| **AuthController** | 使用者認證、登入/登出、Token 管理 |
| **SessionController** | Session CRUD、錄音狀態管理 |
| **ScheduleController** | 會議預約、修改、取消、提醒 |
| **ReportController** | 會議報告查詢、匯出 |
| **ActionItemController** | Action Item CRUD、狀態更新 |
| **ChatController** | Chat 查詢請求轉發 |
| **AdminController** | 系統監控 API、統計數據 |
| **SettingsController** | 個人資料、偏好設定管理 |
| **WebSocketGateway** | 實時音訊串流 + Chat Streaming |

#### Service Layer

| 元件 | 職責 |
|------|------|
| **AuthService** | 使用者認證、授權邏輯 |
| **SessionService** | Session 生命週期管理、觸發 ASR 工作流 |
| **ScheduleService** | 預約邏輯、排程任務、提醒通知 |
| **ReportService** | 生成會議摘要、格式化輸出 |
| **ActionItemService** | 任務管理、指派邏輯 |
| **ChatProxyService** | 轉發 Chat 請求至 Chat Service |
| **StorageService** | 音檔存儲管理（上傳/下載/刪除） |
| **MonitorService** | 系統指標收集（CPU/Memory/Storage） |
| **NotificationService** | 處理完成通知推播 |
| **SettingsService** | 個人設定、偏好設定管理 |

#### Repository Layer

| 元件 | 職責 |
|------|------|
| **UserRepository** | 使用者資料存取 |
| **SessionRepository** | Session 元數據存取 |
| **ScheduleRepository** | 會議預約資料存取 |
| **TranscriptRepository** | 逐字稿內容存取 |
| **ActionItemRepository** | Action Item 存取 |
| **EmbeddingRepository** | 向量嵌入存取（pgvector） |

#### Infrastructure Layer

| 元件 | 職責 |
|------|------|
| **Database Connection Pool** | PostgreSQL 連線池管理 |
| **gRPC Client** | ASR Service 通訊客戶端 |
| **Temporal Client** | 工作流引擎客戶端 |
| **Chat Client** | Chat Service WebSocket 客戶端 |
| **Local File Storage** | 本地音檔存儲 |
| **Scheduler** | 排程引擎（Node-Cron / BullMQ） |

#### Cross-cutting Concerns

| 元件 | 職責 |
|------|------|
| **Auth Middleware** | JWT 驗證、權限檢查 |
| **Validation Pipe** | 請求參數驗證 |
| **Exception Filter** | 統一錯誤處理 |
| **Logger** | 日誌記錄與追蹤 |

---

## 2. Chat Service Component Diagram

### 架構層次

```
                    ┌──────────────────┐
                    │  Gateway Layer   │
                    │  (WebSocket)     │
                    └──────────────────┘
                            │
                    ┌──────────────────┐
                    │  Router Layer    │
                    │  (Plan-based)    │
                    └──────────────────┘
                      │              │
          ┌───────────┘              └───────────┐
          │                                      │
  ┌───────────────┐                    ┌─────────────────┐
  │  RAG Engine   │                    │  Agent Engine   │
  │  (Basic Plan) │                    │  (Mid Plan)     │
  └───────────────┘                    └─────────────────┘
          │                                      │
          │                              ┌───────┴────────┐
          │                              │                │
  ┌───────────────┐              ┌─────────────┐  ┌──────────────┐
  │   Database    │              │  MCP Server │  │  LLM Provider│
  │  (pgvector)   │              │  (Tools)    │  │              │
  └───────────────┘              └─────────────┘  └──────────────┘
```

### 元件說明

#### Gateway Layer

| 元件 | 職責 |
|------|------|
| **Chat WebSocket Gateway** | 接收 Chat 查詢、串流回應 |
| **Request Validator** | 驗證查詢格式、權限檢查 |

#### Router Layer

| 元件 | 職責 |
|------|------|
| **Plan-based Router** | 根據使用者 Plan 路由至不同引擎 |
| **Intent Classifier** | 識別查詢意圖（簡單查詢 vs 複雜任務） |

#### RAG Engine (Basic Plan)

| 元件 | 職責 |
|------|------|
| **Query Preprocessor** | 查詢預處理、改寫 |
| **Vector Search Service** | 向量相似度搜尋（pgvector） |
| **Context Builder** | 組裝檢索到的上下文 |
| **RAG LLM Client** | 基於上下文生成答案 |
| **Response Formatter** | 格式化串流回應 |

#### Agent Engine (Mid Plan)

| 元件 | 職責 |
|------|------|
| **Tool Registry** | 註冊可用的工具 |
| **Tool Executor** | 執行工具調用 |
| **Reasoning Engine** | 多步推理規劃 |
| **Conversation Memory** | 對話歷史管理 |
| **MCP Client** | 與 MCP Server 通訊 |
| **Agent LLM Client** | 支援 Tool Calling 的 LLM |

#### MCP Server

| 元件 | 職責 |
|------|------|
| **MCP Protocol Handler** | 處理 MCP 協議 |
| **MCP Tool Registry** | 註冊系統工具 |
| **System Tools** | CRUD Operations、Action Item 管理 |

---

## 主要資料流

### 1. 實時錄音流程
```
Frontend → WebSocketGateway → SessionService
                                   ↓
                            gRPC Client → ASR Service
                                   ↓
                            推送逐字稿片段
                                   ↓
                            WebSocketGateway → Frontend
```

### 2. 會議預約流程
```
Frontend → ScheduleController → ScheduleService
                                     ↓
                              ScheduleRepository (儲存預約)
                                     ↓
                              Scheduler (排程任務)
                                     ↓
                        到達預約時間 → NotificationService (提醒通知)
                                     ↓
                              Frontend (推播通知)
```

### 3. Chat 查詢流程 (Basic Plan)
```
Frontend → Backend API → ChatWSGateway → PlanBasedRouter
                                          ↓ (Basic Plan)
                                   RAG Engine
                                          ↓
                                   Vector Search → Database
                                          ↓
                                   RAG LLM Client → LLM Provider
                                          ↓
                                   RAGResponseFormatter → Frontend
```

### 4. Chat 查詢流程 (Mid Plan)
```
Frontend → Backend API → ChatWSGateway → PlanBasedRouter
                                          ↓ (Mid Plan)
                                   Agent Engine
                                          ↓
                                   Agent LLM Client → LLM Provider
                                          ↓ (需要工具)
                                   Reasoning Engine → Tool Executor
                                          ↓
                                   MCP Client → MCP Server → Database
                                          ↓
                                   回傳結果 → Frontend
```

---

## C4 層級對應

```
Level 1: System Context Diagram
    │
    │ 展開系統內部容器
    ▼
Level 2: Container Diagram
    │
    │ 展開容器內部元件
    ▼
Level 3: Component Diagram (本圖)
    │
    │ 展開類別與函數
    ▼
Level 4: Code / Class Diagram
```

---

## 設計模式應用

| 模式 | 應用位置 |
|------|----------|
| **Layered Architecture** | Backend API 分層結構 |
| **Repository Pattern** | Repository Layer 抽象資料存取 |
| **Dependency Injection** | NestJS 內建 DI 容器 |
| **Strategy Pattern** | Plan-based Router 選擇不同引擎 |
| **Chain of Responsibility** | Middleware 處理鏈 |
| **Observer Pattern** | WebSocket 事件推播 |

---

## 相關文檔
- [System Overview](./systemOverview.md) - 系統要求
- [Context Diagram](./contextDiagram.md) - 系統脈絡
- [Container Diagram](./containerDiagram.md) - 容器架構
- [Backend API Component](./backendApiComponent.mmd) - Backend API 元件圖
- [Chat Service Component](./chatServiceComponent.mmd) - Chat Service 元件圖
