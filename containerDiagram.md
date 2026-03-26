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
| **Mobile App** | iOS / Android | 錄音、上傳、Chat 查詢 |
| **Laptop App** | Web / Desktop | 錄音、上傳、Chat 查詢 |
| **Admin Dashboard** | Web | 監控系統、查看統計 |

### 後端容器 (Sentinel Server)

| 容器 | 技術 | 職責 |
|------|------|------|
| **Backend API** | NestJS / REST API | 中央 API 閘道，處理所有請求 |
| **ASR Service** | - | 語音轉文字 |
| **LLM Batch Service** | - | 批次處理：摘要、Action Items、嵌入 |
| **Chat Module** | - | Chat 查詢處理 (RAG / Agent) |
| **Monitoring Service** | - | 系統監控與指標收集 |

### 資料儲存 (Data Stores)

| 容器 | 技術 | 職責 |
|------|------|------|
| **Database** | PostgreSQL + pgvector | 儲存會議資料、逐字稿、向量 |
| **Local Storage** | File System | 暫存音訊檔案 |
| **Job Queue** | Redis / Bull | 非同步任務排程 |

---

## 容器間通訊

### 通訊協定

| 連結 | 協定 | 用途 |
|------|------|------|
| Frontend → Backend API | HTTPS / REST API | 使用者請求 |
| Backend API → ASR Service | gRPC / HTTP | ASR 請求 |
| Backend API → Job Queue | Job Event | 放入非同步任務 |
| Job Queue → LLM Batch Service | Job Event | 消費任務 |
| Service → Database | SQL (TCP/Connection Pool) | 資料存取 |
| Service → Local Storage | File I/O | 音檔讀寫 |
| Monitoring → Dashboard | WebSocket | 實時推送 |

---

## 主要資料流

### 1. 音訊處理流程
```
Mobile App → Backend API → Local Storage (儲存音檔)
                            ↓
                         Job Queue
                            ↓
                        ASR Service
                            ↓
                    Database (儲存逐字稿)
                            ↓
                         Job Queue
                            ↓
                    LLM Batch Service
                            ↓
                    Database (儲存摘要、Action Items、嵌入)
```

### 2. Chat 查詢流程
```
Mobile App → Backend API → Chat Module → Database (向量搜尋)
                                         ↓
                                     LLM 回應
                                         ↓
                                    Backend API
                                         ↓
                                    Mobile App
```

### 3. 監控流程
```
Admin Dashboard → Backend API → Monitoring Service
                                          ↓
                                    (WebSocket 推送)
                                          ↓
                                  Admin Dashboard
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
| **Job Queue 處理非同步任務** | ASR/LLM 耗時較長，避免阻塞使用者請求 |
| **PostgreSQL + pgvector** | 支援關聯式資料與語意搜尋 |
| **WebSocket 推送監控數據** | 實時更新，無需輪詢 |

---

## 相關文檔
- [Sytem overview](./systemOverview.md) - 系統要求
- [Context Diagram](./contextDiagram.md) - 上一層：系統脈絡
- [Container Diagram](./containerDiagram.md) - 下一層：系統內部容器架構
- [System Architecture](./systemArch.md) - 完整系統架構說明
- [Data Flow](./dataflow.md) - 詳細資料流程
