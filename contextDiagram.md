# Context Diagram (系統脈絡圖)

## 圖表位置
`/Users/mary/code/sentinel/contextDiagram.mmd`

## 什麼是 Context Diagram？

**Context Diagram** 是 C4 模型的第一層，展示軟體系統在整個環境中的位置。它回答「這個系統與誰互動？」的問題。

### 適合對象
- 專案經理、產品經理
- 非技術利害關係人
- 新加入團隊的成員（快速理解系統邊界）

---



| 元素類型 | 說明 | 圖中對應 |
|---------|------|---------|
| **Person (使用者)** | 與系統互動的人員 | Normal User, Admin User, Root User |
| **Software System (軟體系統)** | 正在設計的系統本身 | Sentinel Server |
| **Arrow (箭頭)** | 使用者與系統之間的互動 | 錄音、上傳、Chat、監控、Debug |

---

## 使用者角色說明

| 角色 | 設備 | 主要用途 | 互動內容 |
|------|------|---------|---------|
| **Normal User** | Mobile / Laptop | 會議錄音、查詢報告、Chat 查詢 | **外網**: 透過 Relay 錄音 / Chat<br>**區網**: 直連 Sentinel Server |
| **Admin User** | Dashboard | 監控系統狀態、設定管理 | **外網**: 透過 Relay 監控 / 設定<br>**區網**: 直連 Sentinel Server (同網段時) |
| **Root User** | 任何 | Debug 和開發 | Debug / 全權限存取 |

---

## 系統說明

### 外部雲端系統 (Cloud Infrastructure)

#### Relay Service
- **部署位置**: Cloud (SaaS)
- **功能**: 純 TCP 轉發（不做認證）
- **用途**: 解決 On-Premise Server 位於 NAT 後方、無固定 IP 的連線問題
- **路由方式**: 根據 email 查找 tenant_id，轉發到對應 Tunnel

#### Device Registry
- **部署位置**: Cloud (SaaS)
- **功能**: Email → Tenant 映射、使用者註冊
- **用途**: Sentinel 註冊使用者時，記錄 email 與 tenant_id 的對應關係

### On-Premise 系統

#### Sentinel Server
- **部署位置**: On-Premise (客戶端 PC)
- **功能**: 會議錄音、ASR 轉寫、AI 分析、Chat 查詢、**用戶認證**
- **特點**: 完全處理用戶認證邏輯，日常使用不依賴 SaaS Auth

---

## 關鍵觀察

1. **Relay 模式**: 系統使用 Relay Service 進行 NAT 穿透，解決 On-Premise Server 無固定 IP 的連線問題
2. **區網直連**: Normal User 和 Admin User 在同一區網時，可直接連接 Sentinel Server（不經 Relay）
3. **Sentinel 負責 Auth**: 所有認證邏輯由 Sentinel Server 處理，Relay 只做純 TCP 轉發
4. **Email 路由**: 用戶連 Relay 時提供 email，Relay 查找對應的 tenant_id 並路由
5. **Device Registry**: Sentinel 註冊使用者時同步到 SaaS，記錄 email → tenant_id 映射
6. **使用者權限分層**: 三種使用者角色有明確的權限區分
7. **互動簡潔**: Context 層級只展示「誰與系統互動」，不涉及內部實作細節

---

## C4 層級對應

```
Level 1: System Context Diagram (本圖)
    │
    │ 展開系統內部結構
    ▼
Level 2: Container Diagram
    │
    │ 展開容器內部組件
    ▼
Level 3: Component Diagram
    │
    │ 展開部署結構
    ▼
Level 4: Deployment Diagram
```

---

## 相關文檔
- [Sytem overview](./systemOverview.md) - 系統要求
- [Container Diagram](./containerDiagram.md) - 下一層：系統內部容器架構
- [Context Diagram](./contextDiagram.md) - 上一層：系統脈絡
- [System Architecture](./systemArch.md) - 完整系統架構說明
- [Data Flow](./dataflow.md) - 詳細資料流程