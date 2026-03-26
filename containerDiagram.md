# Container Diagram (容器圖)

## 圖表位置
`/Users/mary/code/sentinel/containerDiagram.mmd`

## 什麼是 Container Diagram？

**Container Diagram** 是 C4 模型的第二層，展示系統內部的「容器」及其互動關係。

> ⚠️ **注意**: 這裡的「Container」指的是 **邏輯容器**（應用程式、資料庫、訊息佇列等），不是 Docker 容器！

### 適合對象
- 軟體架構師
- 技術主管
- 開發團隊成員

---



## 容器說明

### 前端容器 (Client Applications)

| 容器 | 技術 | 職責 |
|------|------|------|
| **Frontend App** | Desktop / iOS / Android | 錄音、上傳、Chat 查詢 |


### 後端容器 (Sentinel Server)

| 容器 | 技術 | 職責 |
|------|------|------|
| **Backend API** | NestJS + Local Storage | REST API、WebSocket、音檔儲存、系統監控 |
| **ASR Service** | gRPC Streaming + Job Worker | 語音轉文字（實時 + 批次） |
| **LLM Batch Service** | - | 批次處理：摘要、Action Items、嵌入 |
| **Chat Module** | - | Chat 查詢處理 (RAG / Agent) |

### 資料儲存 (Data Stores)

| 容器 | 技術 | 職責 |
|------|------|------|
| **Database** | PostgreSQL + pgvector | 儲存會議資料、逐字稿、向量 |
| **Workflow Engine** | Temporal.io / BullMQ | 工作流編排與非同步任務排程 |

---

## 容器間通訊

### 通訊協定

| 連結 | 協定 | 用途 |
|------|------|------|
| Frontend → Backend API | **WebSocket** | 實時音訊串流 + Chat Streaming |
| Frontend → Backend API | **HTTPS / REST API** | 其他請求（錄音/上傳/查詢） |
| Backend API → Frontend App | **WebSocket** | 推送監控數據（Admin Dashboard） |
| Backend API → Chat Module | **WebSocket Streaming** | Chat 查詢串流 |
| Backend API → ASR Service | **gRPC Streaming** | 實時 ASR（錄音中） |
| ASR Service → Backend API | gRPC Streaming | 推送逐字稿片段 |
| Backend API → Workflow Engine | Start Workflow | 啟動 ASR → LLM 工作流 |
| Workflow Engine → ASR Service | Activity | ASR 批次處理 |
| Workflow Engine → LLM Batch Service | Activity | LLM 批次處理 |
| ASR Service → Workflow Engine | Workflow Signal | ASR 完成，觸發 LLM |
| ASR Service → Backend API | HTTP | 讀取音檔 |
| Service → Database | SQL (TCP/Connection Pool) | 資料存取 |

---

## 主要資料流

### 1. 音訊處理流程

#### 階段 1: 錄音中（實時串流）
```
Frontend App ──WebSocket──→ Backend API ──gRPC Streaming──→ ASR Service
       ↑                                                                   │
       └───────────── WebSocket 推送逐字稿片段 ─────────────────────────────┘
```

#### 階段 2: 錄音完成（批次處理）
```
Backend API ──Workflow Engine──→ ASR Service (讀取音檔、完整處理)
                                   ↓
                           Database (儲存逐字稿)
                                   ↓
                             Workflow Signal (ASR 完成)
                                   ↓
                             LLM Batch Service
                                   ↓
                           Database (儲存摘要、Action Items、嵌入)
```

### 2. Chat 查詢流程 (Streaming)
```
Mobile App ←WebSocket→ Backend API ←WebSocket→ Chat Module → Database (向量搜尋)
                                            ↓
                                        LLM Streaming Tokens
                                            ↓
                                         Backend API
                                            ↓
                                         Mobile App
```

### 3. 監控流程
```
Frontend App ←─────────────────────────→ Backend API
     ↑                                         ↓
     └──────── WebSocket 推送系統狀態 ──────────┘
                                  (CPU / Memory / Storage / Active Sessions)
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
| **ASR Service 支援 Streaming + Batch** | 單一容器同時支援實時反饋與完整處理 |
| **Workflow Engine 處理多步驟任務** | ASR → LLM 工作流編排，避免阻塞使用者請求 |
| **PostgreSQL + pgvector** | 支援關聯式資料與語意搜尋 |

---

## 相關文檔
- [Sytem overview](./systemOverview.md) - 系統要求
- [Context Diagram](./contextDiagram.md) - 上一層：系統脈絡
- [Container Diagram](./containerDiagram.md) - 下一層：系統內部容器架構
- [System Architecture](./systemArch.md) - 完整系統架構說明
- [Data Flow](./dataflow.md) - 詳細資料流程
