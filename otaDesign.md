# OTA (Over-The-Air) Update Design

## Overview

Sentinel 採用 **分層 OTA 更新機制**，支援兩層更新：
1. **OS 層** (Linux): 系統核心更新，使用 A/B 分區避免設備磚化
2. **容器層** (Docker): 應用程式更新，包含 Backend API、ASR、LLM、Chat 服務及模型

系統支援三種更新模式：
- **自動更新**: 設備定期檢查並下載更新
- **手動更新**: 管理員主動觸發更新
- **離線更新**: 透過 USB 傳輸更新套件（氣隔環境）

---

## Update Scope

| 層級 | 更新內容 | 更新頻率 | 風險等級 |
|------|----------|----------|----------|
| **OS 層** | Linux kernel、系統套件、安全修補 | 低頻 (季度/年度) | 高 - 失敗可能導致無法開機 |
| **容器層** | Backend API、ASR、LLM、Chat 服務、模型映像 | 高頻 (週/月) | 中 - 服務可回滾 |


---

## Architecture Components

### System Architecture

```mermaid
flowchart TD
    subgraph SaaS ["SaaS Cloud"]
        subgraph OTA_Server ["OTA Server"]
            VersionDB["版本資料庫<br/>manifest, changelog"]
            DeviceDB["設備資料庫<br/>ID, version, group"]
            GroupMgr["群組管理器<br/>Canary/Beta/Full"]
            Signer["簽章服務<br/>Ed25519 私鑰"]
            ReleaseCtrl["推出控制器<br/>決定誰能看到更新"]
            StatusTracker["狀態追蹤器<br/>更新進度"]
        end

        CDN["CDN Storage<br/>簽章套件儲存"]
        Telemetry["Telemetry Service<br/>更新狀態回報"]
    end

    %% OTA Server internal flow
    VersionDB --> ReleaseCtrl
    DeviceDB --> ReleaseCtrl
    GroupMgr --> ReleaseCtrl
    ReleaseCtrl -->|"有新版本"| Agent
    Signer -->|"簽章套件"| CDN

    %% Agent interactions
    Agent -->|"查詢更新<br/>(設備ID, 目前版本)"| ReleaseCtrl
    Agent -->|"下報狀態"| StatusTracker
    Agent -->|"下載套件"| CDN
    Agent -->|"上報更新結果"| Telemetry

    subgraph OnPrem ["Sentinel On-Premise Server"]
        Agent["OTA Agent<br/>更新管理器"]

        subgraph OS ["OS Layer"]
            A_Partition["分區 A<br/>目前啟動系統"]
            B_Partition["分區 B<br/>備用/更新系統"]
            Bootloader["Bootloader<br/>分區切換控制"]
        end

        subgraph Containers ["Container Layer"]
            Runtime["Container Runtime<br/>(Docker)"]
            Registry["Local Registry<br/>映像快取"]
        end

        subgraph Services ["Application Services"]
            Backend["Backend API"]
            ASR["ASR Service"]
            LLM["LLM Service"]
            Chat["Chat Service"]
        end

        Storage["Local Storage<br/>備份、暫存"]
    end

    subgraph Manual ["Manual Update"]
        USB["USB Drive<br/>離線套件"]
    end

    %% Online Flow
    OTA -->|"版本查詢、套件下載"| Agent
    CDN -->|"簽章套件"| Agent

    %% Offline Flow
    Portal -->|"下載"| USB
    USB -->|"上傳"| Agent

    %% OS Layer Update
    Agent -->|"OS 映像寫入"| B_Partition
    Agent -->|"切換啟動分區"| Bootloader

    %% Container Layer Update
    Agent -->|"映像驗證、載入"| Runtime
    Agent -->|"映像快取"| Registry
    Runtime -->|"啟動/重啟"| Services

    %% Monitoring
    Agent -->|"更新狀態、健康指標"| Monitor
    Services -->|"健康狀態"| Agent

    %% Storage
    Agent -->|"備份、暫存"| Storage
```

### Component Responsibilities

#### SaaS Cloud Components

| Component | Responsibility |
|-----------|----------------|
| **OTA Server** | 版本管理、設備群組管理、簽章套件生成、推出控制 |
| **CDN Storage** | 儲存簽章後的更新套件 |
| **Telemetry Service** | 接收設備更新狀態回報、記錄成功/失敗 |

### OTA Server 具體職責

| 功能 | 說明 |
|------|------|
| **版本管理** | 儲存每個版本的 manifest、changelog、套件位置 |
| **設備註冊** | 維護設備清單（設備 ID、目前版本、硬體型號、群組） |
| **群組管理** | 將設備分群（Canary 5%、Beta 25%、Full 100%） |
| **簽章** | 將套件 manifest 用私鑰簽章，產生 signature.sig |
| **推出控制** | 根據群組、版本兼容性決定哪些設備能看到更新 |
| **狀態追蹤** | 記錄每台設備的更新狀態（idle/downloading/installing/success/failed） |
| **推出暫停** | 當 Canary 失敗率超過閾值，停止推送到後續群組 |

#### On-Premise Components

| Component | Responsibility |
|-----------|----------------|
| **OTA Agent** | 檢查更新、下載套件、驗證簽章、執行更新、健康檢查、回滾決策 |
| **Bootloader** | A/B 分區切換控制 |
| **Container Runtime** | 映像載入、容器生命週期管理 |
| **Local Registry** | 映像快取、版本管理 |
| **Local Storage** | 備份映像、資料庫快照、暫存檔案 |

---

## Update Package Design

### Package Types

| 類型 | 格式 | 內容 | 大小 |
|------|------|------|------|
| **OS Update Package** | `.img.tar.gz` | 完整 OS 映像、kernel、bootloader | 1-2 GB |
| **Container Update Package** | `.tar.gz` | Docker images (含 ASR/LLM 模型)、migrations、config | 2-15GB |
| **Offline Package** | `.tar.gz` | 包含 OS + Container 套件 | 3-20GB |

### Package Manifest

每個更新套件包含以下資訊：

| 欄位 | 用途 |
|------|------|
| **version** | 目標版本號 (遵循 Semantic Versioning) |
| **package_type** | OS / Container |
| **previous_version** | 上一版本號 (用於驗證升級路徑) |
| **release_date** | 發布日期 |
| **build_number** | 建置編號 |
| **changelog** | 更新內容說明 |
| **total_size** | 套件總大小 |
| **requires_migration** | 是否需要資料庫遷移 |
| **estimated_downtime** | 預估停機時間 |
| **min_compatible_version** | 最低相容版本 |
| **signature_algorithm** | 簽章演算法 |
| **checksums** | 各檔案的雜湊值 |

### Package Components

```
sentinel-release-v{VERSION}.tar.gz
├── manifest.json              # 套件資訊
├── signature.sig              # 數位簽章
├── checksums.sha256           # 檔案完整性驗證
│
├── [OS Layer - 僅 OS 套件]
│   └── os-image.img           # OS 映像
│
├── [Container Layer]
│   ├── images/                # Docker images (含模型)
│   │   ├── sentinel-backend.tar
│   │   ├── sentinel-asr.tar      # 含 ASR 模型
│   │   ├── sentinel-llm.tar      # 含 LLM 模型
│   │   └── sentinel-chat.tar
│   └── migrations/            # Database migrations
│       └── *.sql
```

---

## Security Design

### Security Layers

```mermaid
flowchart LR
    subgraph Download ["下載階段"]
        A1["HTTPS + TLS"]
        A2["Certificate Pinning"]
    end

    subgraph Verify ["驗證階段"]
        B1["數位簽章驗證<br/>(Ed25519)"]
        B2["雜湊值校驗<br/>(SHA256)"]
        B3["版本路徑檢查"]
    end

    subgraph Install ["安裝階段"]
        C1["最小權限執行"]
        C2["自動備份"]
    end

    subgraph Runtime ["執行階段"]
        D1["健康檢查"]
        D2["自動回滾"]
    end

    Download --> Verify
    Verify --> Install
    Install --> Runtime
```

### Security Mechanisms

| 威脅 | 防護措施 |
|------|----------|
| **惡意套件** | Ed25519 數位簽章驗證 |
| **傳輸竄改** | HTTPS + Certificate Pinning |
| **重放攻擊** | 版本檢查 + monotonic 版本號 |
| **權限提升** | OTA Agent 以最小權限執行 |
| **資料遺失** | 更新前自動備份 (映像 + 資料庫) |
| **回滾失敗** | 保留多版本備份 |

### Signature Verification Flow

```mermaid
flowchart LR
    A[下載套件] --> B[提取 signature.sig]
    A --> C[提取 manifest.json]
    C --> D[計算 SHA256]
    B --> E[使用公鑰驗證]
    D --> E
    E -->|有效| F[驗證檔案 checksums]
    E -->|無效| G[拒絕套件<br/>通知管理員]
    F -->|全部符合| H[載入映像]
    F -->|不符合| G
```

### Key Management

| 金鑰類型 | 位置 | 用途 |
|----------|------|------|
| **私鑰** | SaaS (HSM/加密儲存) | 簽署更新套件 |
| **公鑰** | OTA Agent (建置時內建) | 驗證套件簽章 |
| **金鑰版本** | SaaS + Agent | 支援金鑰輪換 |

---

## Update Flow Design

### Update Modes

| 模式 | 觸發方式 | 網路需求 | 適用場景 |
|------|----------|----------|----------|
| **自動更新** | 定期檢查 | 需外網 | 一般設備，維持最新版本 |
| **手動更新** | 管理員觸發 | 需外網 | 控制更新時機 |
| **離線更新** | USB 上傳 | 無需外網 | 氣隔環境 |

### Generic Update Flow

```mermaid
sequenceDiagram
    participant Agent as OTA Agent
    participant SaaS as OTA Server
    participant Admin as Admin Dashboard
    participant OS as OS Layer
    participant Container as Container Layer

    Note over Agent,SaaS: 1. 查詢更新
    Agent->>SaaS: 查詢更新 (設備 ID、目前版本)
    alt 有新版本且在推出群組
        SaaS-->>Agent: 回傳更新資訊

        Note over Agent,SaaS: 2. 下載套件
        Agent->>SaaS: 下載套件
        Agent->>Agent: 驗證簽章與 checksums
        Agent->>Admin: 通知更新可用

        Note over Agent,OS: 3. 執行更新
        Agent->>Admin: 請求批准 (自動/手動模式)
        Agent->>OS: OS 更新 (寫入 B 分區、切換 bootloader)
        Agent->>Container: 容器更新 (載入新映像、重啟服務)

        Note over Agent,Admin: 4. 健康檢查
        Agent->>Agent: 健康檢查
        alt 健康
            Agent-->>Admin: 更新成功
            Agent->>SaaS: 回報成功
        else 失敗
            Agent->>OS: 自動回滾
            Agent->>Container: 恢復舊映像
            Agent-->>Admin: 更新失敗，已回滾
            Agent->>SaaS: 回報失敗
        end
    end
```

### Mode-Specific Differences

| 步驟 | 自動更新 | 手動更新 | 離線更新 |
|------|----------|----------|----------|
| **觸發** | 定期檢查 | 管理員點擊 | USB 上傳 |
| **套件來源** | SaaS CDN | SaaS CDN | 本地上傳 |
| **批准方式** | 維護時段內自動/需批准 | 每次需批准 | 上傳即執行 |
| **通訊** | 與 SaaS 雙向 | 與 SaaS 雙向 | 本地驗證，僅回報結果 |

### Canary Rollout Strategy

```mermaid
flowchart TD
    A[發布新版本] --> B[建立 Canary 群組<br/>5% 設備]
    B --> C{Canary 成功率 >= 95%<br/>且運行 24 小時?}
    C -->|否| D[暫停推出<br/>通知團隊]
    C -->|是| E[擴大到 Beta 群組<br/>25% 設備]
    E --> F{Beta 成功率 >= 95%<br/>且運行 48 小時?}
    F -->|否| D
    F -->|是| G[全面推出<br/>100% 設備]
    G --> H[監控全域健康狀態]
    H --> I{失敗率 > 閾值?}
    I -->|是| J[自動暫停推出]
    I -->|否| K[推出完成]
```

**分群條件**：硬體版本、地理區域、客戶類型、網路環境

---

## Data Persistence in A/B Partition

### Disk Layout

```
┌─────────────────────────────────────────────────────────────┐
│ Boot Partition (共享)                                       │
│ - bootloader configuration                                 │
│ - kernel (A/B)                                             │
├─────────────────────────────────────────────────────────────┤
│ Partition A (/) ← OS 系統檔 (rootfs)                       │
│ - /bin, /lib, /usr...                                      │
├─────────────────────────────────────────────────────────────┤
│ Partition B (/) ← OS 系統檔 (rootfs, 備用)                 │
│ - /bin, /lib, /usr...                                      │
├─────────────────────────────────────────────────────────────┤
│ Data Partition (/var) ← 共享資料，不會被 OS 更新覆蓋        │
│ ├─ /var/lib/docker/     ← Docker 映像、容器               │
│ ├─ /var/lib/postgresql/ ← 資料庫檔案                      │
│ └─ /var/lib/sentinel/   ← 應用程式資料、音訊檔           │
├─────────────────────────────────────────────────────────────┤
│ Config Partition (/etc) ← 共享設定，不會被 OS 更新覆蓋      │
│ - docker-compose.yml                                       │
│ - application configs                                      │
└─────────────────────────────────────────────────────────────┘
```

### Data Safety During OS Update

| 資料類型 | 位置 | OS 更新時 |
|----------|------|-----------|
| Docker 映像 | `/var/lib/docker` | ✅ 保留 (在 Data 分區) |
| 資料庫 | `/var/lib/postgresql` | ✅ 保留 (在 Data 分區) |
| 音訊檔 | `/var/lib/sentinel` | ✅ 保留 (在 Data 分區) |
| 應用設定 | `/etc` | ✅ 保留 (在 Config 分區) |
| OS 系統檔 | `/` (分區 A/B) | ❌ 被覆蓋 (這是預期) |

### OS Update Flow with Data Preservation

```mermaid
flowchart TD
    A[系統在分區 A 運行] --> B[下載新 OS 映像]
    B --> C[寫入分區 B]
    C --> D{Data 分區完整?}
    D -->|是| E[更新 bootloader 配置]
    D -->|否| F[中止更新<br/>通知管理員]
    E --> G[重啟]
    G --> H{分區 B 啟動成功?}
    H -->|是| I[運行新 OS<br/>Data 分區內容不變]
    H -->|否| J[Bootloader 自動切回分區 A<br/>Data 分區內容不變]
```

---

## Rollback Design

### Rollback Trigger Conditions

| 條件 | 觸發動作 |
|------|----------|
| **健康檢查失敗** | 連續 N 次失敗 |
| **服務無法啟動** | 重啟 M 次後仍失敗 |
| **資料庫遷移失敗** | 遷移腳本回傳錯誤 |
| **手動觸發** | 管理員主動回滾 |

### Rollback Decision Flow

```mermaid
flowchart TD
    A[更新套用] --> B[啟動健康檢查循環]
    B --> C{檢查間隔<br/>30s}

    C --> D[查詢健康端點]
    D --> E{全部健康?}

    E -->|是| F[成功計數 +1]
    E -->|否| G[失敗計數 +1]

    F --> H{成功計數 >= 10?}
    H -->|是| I[標記更新成功]
    H -->|否| C

    G --> J{失敗計數 >= 閾值?}
    J -->|否| C
    J -->|是| K[觸發回滾]

    K --> L[停止目前服務]
    L --> M{層級?}

    M -->|OS 層| N[Bootloader 切換回 A 分區]
    M -->|容器層| O[恢復備份映像]
    M -->|資料庫| P[還原 Snapshot]

    N --> Q[重啟系統]
    O --> Q
    P --> Q

    Q --> R[驗證回滾成功]
    R --> S[通知管理員並記錄日誌]
```

### Rollback Strategies by Layer

| 層級 | 回滾機制 | 恢復時間 |
|------|----------|----------|
| **OS 層** | Bootloader 切換至 A 分區 | 系統重啟時間 |
| **容器層** | 恢復備份映像標籤 | 30-60 秒 |
| **資料庫** | 從 snapshot 還原 | 視資料量 |
| **設定檔** | 恢復備份設定 | 即時 |

### Rollback Fallback

```mermaid
flowchart TD
    A[回滾失敗] --> B{嘗試次數 < 3?}
    B -->|是| C[嘗試其他備份版本]
    B -->|否| D[進入安全模式]

    D --> E[僅啟動最小服務]
    E --> F[通知管理員介入]
    F --> G[收集診斷日誌]
    G --> H[上傳至 SaaS 分析]
```

---

## Versioning & Compatibility

### Semantic Versioning

```
MAJOR.MINOR.PATCH
  │     │     └─ Bug fixes, hotfixes
  │     └────── New features, config changes
  └──────────── Breaking changes, migration required
```

### Update Impact Matrix

| 版本變更 | 自動安裝 | 停機時間 | 需要遷移 | 回滾複雜度 |
|----------|----------|----------|----------|------------|
| PATCH (1.0.x → 1.0.y) | ✅ 是 | ~0s | 否 | 低 |
| MINOR (1.0.x → 1.1.z) | ⚠️ 需批准 | ~30s | 可能 | 中 |
| MAJOR (1.x → 2.0) | ❌ 手動 | 計劃停機 | 是 | 高 |

### Compatibility & Migration

| 檢查項目 | 說明 |
|----------|------|
| **min_compatible_version** | 目前版本必須 >= 最低相容版本 |
| **previous_version** | 跳過版本升級時發出警告 |
| **requires_migration** | 需要遷移時：備份 → 停止服務 → 執行遷移 → 驗證 |

---

---

## Health Check Design

### Health Check Architecture

```mermaid
flowchart LR
    subgraph Services ["Sentinel Services"]
        Backend["Backend API<br/>/health"]
        ASR["ASR Service<br/>/health"]
        LLM["LLM Service<br/>/health"]
        Chat["Chat Service<br/>/health"]
    end

    subgraph OTA_Agent ["OTA Agent"]
        Monitor["Health Monitor"]
        Decision["Rollback Decision"]
    end

    Backend --> Monitor
    ASR --> Monitor
    LLM --> Monitor
    Chat --> Monitor

    Monitor -->|Health Status| Decision
    Decision -->|Failure Threshold| Rollback["觸發回滾"]
```

**健康檢查回應**：status (healthy/unhealthy/degraded)、version、timestamp、各組件狀態

---

## Monitoring & Telemetry

### Telemetry Data Flow

```mermaid
flowchart TD
    subgraph OnPrem ["Sentinel On-Prem"]
        Agent["OTA Agent"]
        Events["更新事件日誌"]
    end

    subgraph SaaS ["SaaS Cloud"]
        Telemetry["遙測服務"]
    end

    Agent -->|"更新狀態、健康指標<br/>定期上報"| Telemetry
    Events -->|"錯誤日誌<br/>失敗時上報"| Telemetry

    Telemetry -->|"資料儲存"| Storage["資料庫/日誌系統"]
    Storage -->|"分析與告警"| Team["SaaS 團隊"]
```

### Telemetry Data Points

| 類別 | 資料點 | 用途 |
|------|--------|------|
| **更新狀態** | 設備 ID、版本、更新狀態、時間戳 | 追蹤更新進度 |
| **健康指標** | CPU、記憶體、磁碟、服務狀態 | 判斷是否回滾 |
| **錯誤日誌** | 錯誤類型、堆疊、相關日誌 | 失敗分析 |
| **更新統計** | 成功率、失敗率、平均時間 | 漸進式推出決策 |

### Alert Conditions

| 條件 | 嚴等級 | 動作 |
|------|--------|------|
| Canary 群組失敗率 > 5% | 高 | 暫停推出 |
| 單一設備更新失敗 | 中 | 記錄、可選通知 |
| 健康檢查連續失敗 | 高 | 自動回滾 |
| 更新時間超過預期 | 中 | 記錄 |

> 通知機制不在本設計範圍，可由客戶自行決定是否啟用

---

## Error Handling

### Error Categories

| 類別 | 範例 | 恢復策略 |
|------|------|----------|
| **下載錯誤** | 網路逾時、空間不足 | 重試 (3x)、建議離線更新 |
| **驗證錯誤** | 簽章無效、checksum 不符 | 拒絕套件、通知管理員 |
| **安裝錯誤** | 映像載入失敗、遷移錯誤 | 自動回滾 |
| **執行時錯誤** | 服務崩潰、健康檢查失敗 | 自動回滾 |

### Error Recovery Flow

```mermaid
flowchart TD
    A[偵測到錯誤] --> B{錯誤類型}
    B -->|下載| C[重試下載<br/>最多 3 次]
    B -->|驗證| D[拒絕套件<br/>通知管理員]
    B -->|安裝/執行時| E[自動回滾<br/>通知管理員]

    C -->|成功| F[繼續更新]
    C -->|全部失敗| G[建議離線套件]

    E --> H[上報錯誤至 SaaS]
    D --> H
```

---

## Special Considerations

### Large Container Images

ASR/LLM 容器包含模型檔案，映像大小可達 10GB+，需考量：

| 考量 | 說明 |
|------|------|
| **傳輸時間** | 支援斷點續傳 |
| **儲存空間** | 更新前檢查可用空間 |
| **暫存策略** | 下載後驗證，再載入映像 |
| **回滾** | 保留舊映像版本 |

### Configuration Drift

| 情境 | 處理方式 |
|------|----------|
| 新增欄位 | 使用預設值，提示管理員檢查 |
| 移除欄位 | 忽略舊欄位 |
| 欄位改名 | 自動轉換 |
| 結構變更 | 執行 migration script |

### Multi-Instance Coordination

| 情境 | 處理方式 |
|------|----------|
| 單一設備 | 獨立更新 |
| 多設備 (同客戶) | 交錯更新，避免全體離線 |
| 全域推出 | Canary → Beta → 全面 |

---

## Related Diagrams

- [Container Diagram](./containerDiagram.md) - OTA Agent 在容器架構中的位置
- [System Architecture](./systemArch.md) - 完整系統架構
