```mermaid
flowchart TD

%% System Context Diagram for Sentinel
%% Users
A["Normal User<br>(Mobile / Laptop)"]
B["Admin User<br>(Dashboard)"]
C["Root User<br>(Debuㄕ / Dev)"]

%% Server
D["Sentinel Server<br>(On-Premise)"]

%% Services (Context level)
E["ASR Service<br>(Speech to Text)"]
F1["LLM Batch Service<br>(Summary / Action Items / Embedding)"]
F2["Chat Module"]
G["Database<br>(PostgreSQL + pgvector)"]
H["Local Storage<br>(Audio Files)"]
I["Job Queue"]
J["Monitoring Service<br>(Metrics)"]

%% Chat Module 內部
K["Chat Router<br>(Plan-based)"]
L["RAG Engine<br>(Vector Search + LLM)"]
M["Agent Engine<br>(Tool Calling + Reasoning)"]
N["MCP Server<br>(System Tools)"]

%% ===== User Interactions =====
A -->|錄音 / 上傳 / Chat| D
B -->|監控系統、查看統計| D
C -->|全系統存取、Debug| D

%% ===== Server Context =====
D --> E
D --> F1
D --> F2
D --> G
D --> H
D --> I
D --> J

%% ===== Chat Module 內部 Flow =====
F2 --> K
K -->|Basic Plan| L
K -->|Mid Plan| M
L --> G
M --> N
N -->|工具調用| G

%% ===== External Flow =====
E -.-> F1
F1 -.->|產生 Report & Action Items| A
F2 -.->|Chat 回應| A
J -.->|系統狀態| B
```

# 元件說明 (Component Description / Legend)

| 元件 | 說明 |
|------|------|
| **Normal User** | 使用 Mobile / Laptop App 建立會議、錄音、查詢報告、修改 Action Items、使用 Chat 查詢過去會議 |
| **Admin User** | 管理者透過 Dashboard 監控系統資源與活躍 Session，但無法查看逐字稿或摘要內容 |
| **Root User** | 系統開發 / Debug 用戶，擁有全部存取權限，用於排錯和開發 |
| **Sentinel Server** | 核心服務，部署在 on-premise PC，負責接收音訊、執行模型分析、存取資料庫及提供 API |
| **ASR Service** | 語音轉文字服務，把錄音 Session 轉成逐字稿 |
| **LLM Batch Service** | 負責批次處理：生成會議摘要 (Report)、自動產生 Action Items、向量化嵌入 |
| **Chat Module** | 處理使用者 Chat 查詢，內含 Router、RAG Engine、Agent Engine，根據使用者 Plan 決定處理模式 |
| **Chat Router** | 根據使用者 Plan 路由：Basic Plan 使用 RAG，Mid Plan 使用 Agent |
| **RAG Engine** | 向量搜尋 + LLM 回答，提供給 Basic Plan 使用者 |
| **Agent Engine** | 工具調用 + 多步推理，提供給 Mid Plan 使用者 |
| **MCP Server** | 將系統能力暴露為 MCP 工具，供 Agent 調用 |
| **Database (PostgreSQL + pgvector)** | 儲存 Session、Transcript、向量化文字及 Action Items，支援語意搜尋 |
| **Local Storage** | 存放暫存的音訊檔案，支援離線錄製及上傳同步 |
| **Job Queue** | 排程批次作業（ASR Job / LLM Job）以非同步處理音訊及生成報告 |
| **Monitoring Service** | 收集系統資源使用狀態 (CPU / Memory / Storage) 及活躍 Session，用於 Admin 查看 |