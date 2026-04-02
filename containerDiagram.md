# Container Diagram (容器圖)

## 圖表位置
`/Users/mary/code/sentinel/containerDiagram.mmd`

## 什麼是 Container Diagram？

**Container Diagram** 是 C4 模型的第二層，展示系統內部的「容器」及其互動關係。

> ⚠️ **注意**: 這裡的「Container」指的是 **邏輯容器**（應用程式、資料庫、訊息佇列等），不是 Docker 容器！


---



## 容器說明

### 前端容器 (Client Applications)

| 容器 | 技術 | 職責 |
|------|------|------|
| **Frontend App** | Desktop / iOS / Android | 錄音、上傳、Chat 查詢（Normal User / Admin User 使用） |

> **Root User**: 不使用 Frontend App，透過 shell 直連 Backend API 進行開發調試

### 雲端基礎設施 (Cloud Infrastructure - SaaS)

| 容器 | 技術 | 職責 |
|------|------|------|
| **Relay Endpoint** | 自建 Relay Server (Rust) | 純 TCP 轉發（不做認證） |
| **Device Registry** | Database + API | Email → Tenant 映射、使用者註冊 |
| **OTA Server** | 版本管理服務 | 版本管理、推出控制、簽章服務、狀態追蹤 |

### 後端容器 (Sentinel Server - On-Premise)

| 容器 | 技術 | 職責 |
|------|------|------|
| **Tunnel Client** | 自建 agent | 維持 outbound tunnel 連線 |
| **Backend API** | NestJS + Local JWT Validation | REST API、WebSocket（僅 Chat）、音檔儲存、系統監控 |
| **ASR Service** | HTTP API | 語音轉文字（批次處理） |
| **LLM Batch Service** | - | 批次處理：摘要、Action Items、嵌入 |
| **Chat Service** | WebSocket Streaming | Chat 查詢處理 (RAG / Agent)，串流回應 |
| **OTA Agent** | **Rust**/Go | 系統更新管理：查詢更新、下載套件、驗證簽章、執行更新、健康檢查、回滾 |

### 資料儲存 (Data Stores)

| 容器 | 技術 | 職責 |
|------|------|------|
| **Database** | PostgreSQL + pgvector | 儲存會議資料、逐字稿、向量、jobs 表 |

> **Jobs 表輪詢機制**：ASR Service 和 LLM Batch Service 分別輪詢自己的 jobs，無需額外 Worker |

---

## 容器間通訊

### 通訊協定

| 連結 | 協定 | 用途 |
|------|------|------|
| Frontend → Relay Endpoint | **TCP** | 上傳音檔、Chat 串流（外網，帶 email 路由） |
| Relay Endpoint ↔ Tunnel Client | **TCP** | 純流量轉發 |
| Root User → Backend API | **Shell 直連** | 開發調試（Debug / Dev Access） |
| Tunnel Client → Backend API | **Local TCP** | 本地轉發請求 |
| Backend API → Device Registry | **HTTPS** | 註冊使用者 |
| Relay Endpoint → Device Registry | **HTTPS** | 查詢 tenant_id（按需路由） |
| OTA Agent ↔ OTA Server | **HTTPS** | 查詢更新、下載套件、回報狀態 |
| Backend API → Chat Service | **WebSocket** | Chat 查詢串流回應 |
| OTA Agent → Backend API | **HTTP** | 健康檢查、更新狀態查詢 |
| OTA Agent → ASR/LLM/Chat Services | **HTTP** | 健康檢查 |
| Backend API → Database | SQL | 讀寫資料、新增 Job |
| ASR Service → Database | SQL (Poll + Write) | 輪詢 ASR Jobs、寫入逐字稿 |
| LLM Batch Service → Database | SQL (Poll + Write) | 輪詢 LLM Jobs、寫入處理結果 |
| Chat Service → Database | SQL | 查詢/寫入 |
| OTA Agent → Database | SQL | 儲存更新狀態、版本資訊 |

---

## 主要資料流

### 1. 音訊處理流程（經過 Relay）

#### 錄音完成 → 批次處理

```mermaid
sequenceDiagram
    participant FE as Frontend App
    participant Relay as Relay Endpoint
    participant API as Backend API
    participant DB as Database
    participant ASR as ASR Service
    participant LLM as LLM Batch Service

    FE->>Relay: TCP POST 音檔 (帶 email)
    Relay->>Relay: 查 email → tenant_id，路由
    Relay->>API: 轉發
    API->>API: 驗證用戶認證
    API->>DB: INSERT ASR Job (status=pending)

    Note over ASR: 輪詢 jobs 表
    ASR->>DB: SELECT * FROM jobs WHERE type='asr' AND status='pending'
    ASR->>DB: UPDATE Job (status=processing)
    ASR->>DB: 儲存逐字稿
    ASR->>DB: INSERT LLM Job (status=pending)

    Note over LLM: 輪詢 jobs 表
    LLM->>DB: SELECT * FROM jobs WHERE type='llm' AND status='pending'
    LLM->>DB: UPDATE Job (status=processing)
    LLM->>DB: 儲存摘要、Action Items、嵌入
    LLM->>DB: UPDATE Job (status=completed)
```

### 2. Chat 查詢流程 (TCP Streaming，經過 Relay)

```mermaid
sequenceDiagram
    participant App as Mobile App
    participant Relay as Relay Endpoint
    participant Tunnel as Tunnel Client
    participant API as Backend API
    participant Chat as Chat Service
    participant DB as Database
    participant LLM as LLM Service

    App->>Relay: TCP 連線 (帶 email)
    Relay->>Relay: 查 email → tenant_id，路由
    Relay->>Tunnel: 轉發
    Tunnel->>API: Local TCP
    API->>API: 驗證用戶認證
    API->>Chat: TCP 串流

    Chat->>DB: 向量搜尋
    Chat->>LLM: LLM Streaming Tokens
    LLM-->>Chat: Tokens
    Chat-->>API: TCP 回傳
    API-->>Tunnel: 回傳路徑相同
    Tunnel-->>Relay: 轉發
    Relay-->>App: TCP 推送
```

### 3. 監控流程（TCP 輪詢，經過 Relay）

```mermaid
sequenceDiagram
    participant FE as Frontend App
    participant Relay as Relay Endpoint
    participant API as Backend API

    FE->>Relay: TCP GET 監控數據 (帶 email)
    Relay->>Relay: 查 email → tenant_id，路由
    Relay->>API: 轉發

    Note over API: 驗證用戶認證<br/>收集系統狀態<br/>CPU / Memory / Storage / Active Sessions

    API-->>Relay: TCP 回應系統狀態
    Relay-->>FE: TCP 回應
```

### 4. 使用者註冊與路由流程

#### 初始化階段（系統部署者新增使用者）

```mermaid
sequenceDiagram
    participant Deployer as 系統部署者
    participant API as Backend API
    participant Registry as Device Registry (SaaS)

    Deployer->>API: 新增使用者 (alice@acme.com)
    API->>Registry: 註冊使用者 (email, tenant_id)
    Registry-->>API: 確認
    API-->>Deployer: 使用者創建成功
```

#### 運行階段（Relay 按需查詢路由）

```mermaid
sequenceDiagram
    participant FE as Frontend App
    participant Relay as Relay Endpoint
    participant Registry as Device Registry (SaaS)
    participant Tunnel as Tunnel Client
    participant API as Backend API

    FE->>Relay: TCP 連線 (帶 email)
    Relay->>Relay: 檢查本地路由快取

    alt 未找到 email
        Relay->>Registry: 查詢 tenant_id
        Registry-->>Relay: 返回 tenant_id
        Relay->>Relay: 更新本地快取
    end

    Relay->>Tunnel: 轉發請求
    Tunnel->>API: 本地轉發
```

---

## C4 層級對應

```
Level 1: System Context Diagram
    │
    │ 展開系統內部結構
    ▼
Level 2: Container Diagram (本圖)
    │
    │ 展開 Chat Module 內部組件
    ▼
Level 3: Component Diagram
    │
    │ 展開部署結構
    ▼
Level 4: Deployment Diagram
```

---

## 關鍵設計決策

| 決策 | 原因 |
|------|------|
| **Backend API 作為中央閘道** | 統一請求入口、易於管理認證授權 |
| **監控功能集成於 Backend API** | 功能簡單、數據源在內部、降低部署複雜度 |
| **ASR Service 採用 HTTP** | 簡化通訊，批次處理即可，無需 gRPC 複雜度 |
| **WebSocket 僅用於 Chat** | Chat 需要串流 LLM 回應，其他功能用 HTTP 即可 |
| **資料庫即 Job Queue** | 用 jobs 表存任務，各 Service 自己輪詢處理，無需額外依賴 |
| **PostgreSQL + pgvector** | 支援關聯式資料與語意搜尋 |
| **分層 OTA 更新** | OS 層使用 A/B 分區避免磚化，容器層獨立更新降低風險 |
| **OTA Agent 獨立於 Backend API** | 更新過程中 Backend API 可能重啟，Agent 需獨立運作以處理回滾 |
| **自建 Relay vs ngrok** | 詳見 [Relay Server 設計](./relayServerDesign.md#0-技術選型-ngrok-vs-自建) |

---

## 相關文檔
- [Sytem overview](./systemOverview.md) - 系統要求
- [Context Diagram](./contextDiagram.md) - 上一層：系統脈絡
- [Container Diagram](./containerDiagram.md) - 下一層：系統內部容器架構
- [System Architecture](./systemArch.md) - 完整系統架構說明
- [Data Flow](./dataflow.md) - 詳細資料流程
