# Relay Server 設計文檔

設計自建 Relay Server，實現 NAT 穿透，讓 Mobile Client 能連接到客戶 On-Premise 的 Sentinel Server。

**架構**：Nginx + Rust + Redis
**目標讀者**：後端工程師、系統架構師
**最後更新**：2026-03-30

---

## 0. 技術選型：ngrok vs 自建

| 比較項目 | ngrok (SaaS) | 自建 Relay Server |
|---------|--------------|-------------------|
| **部署複雜度** | ⭐ 極簡 | ⭐⭐⭐ 需自行開發 |
| **成本** | 💰 ~$216/月/連線 | 💰 ~$50/月（統一） |
| **多租戶隔離** | ❌ 需用 subdomain 區分 | ✅ 原生支援 |
| **與 Auth API 整合** | ❌ 需額外整合 | ✅ 深度整合 |
| **資料隱私** | ⚠️ 流量經 ngrok | ✅ 流量經我們自己的 IDC |

**結論**：選擇自建，成本在規模化後更低、可與現有服務深度整合。

---

## 1. 核心架構

### 1.1 系統架構圖

```mermaid
flowchart TB
    subgraph Clients["Mobile Clients (外網)"]
        Client1["Client A<br/>(Tenant: acme)"]
        Client2["Client B<br/>(Tenant: beta)"]
    end

    subgraph IDC["IDC 落地機器<br/>固定 IP"]
        subgraph NginxLayer["Nginx<br/>:443"]
            TLS["TLS 終結"]
            Proxy["WebSocket 代理"]
        end

        subgraph Relay["Relay Server (Rust)<br/>:8443"]
            WSS["WebSocket Server"]
            Router["Tenant Router"]
            TunnelMgr["Tunnel Manager"]
        end

        subgraph Storage["Redis<br/>:6379"]
            TunnelTable["Tunnel Registry<br/>tenant_id → tunnel_id"]
            QuotaTable["Quota Counters"]
        end

        subgraph SaaS["SaaS Control Plane (雲端)"]
            AuthSvc["Auth API"]
        end
    end

    subgraph CustomerA["客戶 A On-Prem"]
        ServerA["Sentinel Server<br/>+ Tunnel Client"]
    end

    subgraph CustomerB["客戶 B On-Prem"]
        ServerB["Sentinel Server<br/>+ Tunnel Client"]
    end

    Client1 --> TLS
    Client2 --> TLS
    TLS --> Proxy
    Proxy --> WSS
    WSS --> Router
    Router --> TunnelTable
    Router --> AuthSvc
    Router --> QuotaTable
    TunnelMgr --> ServerA
    TunnelMgr --> ServerB

    style NginxLayer fill:#e8f5e9,stroke:#4caf50
    style Relay fill:#fff3e0,stroke:#ff9800
    style Storage fill:#f3e5f5,stroke:#9c27b0
```

### 1.2 連線流向

```
Mobile (外網) → Nginx (TLS) → Relay (Rust) → On-Prem Sentinel Server (NAT 後方)
```

**核心設計**：
1. 所有 Client 連到 `wss://relay.sentinel.com`
2. JWT 中帶有 `tenant_id`
3. Relay 根據 `tenant_id` 查 Redis，路由到對應的 Tunnel
4. 客戶 Server 主動建立 outbound 連線到 Relay

### 1.3 核心元件

| 元件 | 職責 |
|------|------|
| **Nginx** | TLS 終結、限流、WebSocket 轉發 |
| **WebSocket Server** | 接受 Client 和 Tunnel 連線 |
| **Tenant Router** | 根據 JWT tenant_id 路由 |
| **Tunnel Manager** | 管理 Tunnel 連線、心跳 |
| **Redis** | Tunnel 註冊、連線狀態、配額 |

---

## 2. 資料流設計

### 2.1 Tunnel 註冊與連接流程

```mermaid
sequenceDiagram
    participant Server as On-Prem Server
    participant Relay as Relay Server
    participant Redis as Redis
    participant Client as Mobile Client

    Note over Server,Redis: 階段 1: Server 主動連接
    Server->>Relay: 1. WebSocket (Outbound)
    Server->>Relay: 2. Tunnel 註冊 {tunnel_id, tenant_id}
    Relay->>Redis: 3. HSET tunnel:registry:{tenant_id}
    Relay-->>Server: 4. 連線成功

    Note over Server,Redis: 階段 2: Mobile 連接
    Client->>Relay: 5. WebSocket 連線
    Client->>Relay: 6. Auth message (JWT with tenant_id)
    Relay->>Relay: 7. 驗證 JWT
    Relay->>Redis: 8. HGET tunnel:registry:{tenant_id}
    Redis-->>Relay: 9. 返回 tunnel_id
    Relay-->>Client: 10. Auth OK
```

### 2.2 訊息轉發

```
Client → Relay → Server (On-Prem)
       ←        ←
```

---

## 3. 多租戶隔離

### 3.1 路由機制

**所有 Client 連到同一個 domain**：
```
wss://relay.sentinel.com
```

**Relay 根據 JWT 中的 tenant_id 路由**：
```rust
let tenant_id = verify_jwt(jwt)?.tenant_id;  // "acme"
let tunnel = redis.get(format!("tunnel:registry:{}", tenant_id))?;
forward(websocket, tunnel);
```

### 3.2 隔離保證

- ✅ Tenant A 的流量無法訪問 Tenant B 的 Tunnel
- ✅ 每個 Tenant 獨立的配額限制
- ✅ 租戶間的連線計數隔離

---

## 4. 通訊協議

### 4.1 連接方式

| 來源 | URL | 認證 |
|------|-----|------|
| **Mobile Client** | `wss://relay.sentinel.com` | JWT (第一條訊息) |
| **On-Prem Server** | `wss://relay.sentinel.com/tunnel` | Tunnel Token |

### 4.2 訊息格式

```json
{
  "type": "auth|data|heartbeat|close",
  "tenant_id": "acme",
  "tunnel_id": "...",
  "payload": "base64_data",
  "sequence": 123
}
```

---

## 5. 連線管理

### 5.1 心跳機制

| 方向 | 間隔 | 超時 |
|------|------|------|
| Relay → Tunnel | 30s | 90s |
| Client → Relay | 45s | 120s |

### 5.2 重連策略

```
指數退避: 1s → 2s → 4s → 8s (max)
最多重試: 10 次
```

---

## 6. 技術棧

| 組件 | 技術選擇 |
|------|---------|
| **反向代理** | Nginx |
| **核心服務** | Rust + tokio |
| **WebSocket** | tokio-tungstenite |
| **狀態存儲** | Redis |

---

## 7. Redis 數據結構

```
# Tunnel 註冊表
HSET tunnel:registry:{tenant_id} tunnel_id "xxx" status "active" last_heartbeat 1735689600

# 配額計數器
INCR quota:connections:acme
EXPIRE quota:connections:acme 3600
```

---

## 8. 相關文檔

- [Container Diagram](./containerDiagram.md)
- [Context Diagram](./contextDiagram.md)
- [System Architecture](./systemArch.md)
- [Connectivity Architecture](./connectivityArch.md)
