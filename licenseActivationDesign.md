# License Activation Design

## Overview

Sentinel 採用 License-based 授權機制，客戶需在首次啟動時輸入 License Key 並通過 SaaS 驗證以啟用服務。

**設計假設**：目標客戶為一般企業環境，啟用時具備外網連線。


---

## License Key Format

### 短碼格式（19 字元）
```
SENT-XXXX-XXXX-XXXX
```

**範例**: `SENT-A3B7-K9X2-Y4P8`

**欄位說明**:
- `SENT`: 固定前綴
- `XXXX-XXXX-XXXX`: 8 字元簽章碼（Base32 編碼，移除易混淆字元 0/O, 1/I/l）

### 簽章生成
```
SIGNATURE = BASE32(HMAC-SHA256(SECRET_KEY, PLAN + CUSTOMER_ID + TIMESTAMP))[0:8]
```

**安全性**:
- 8 字元 = 16^8 ≈ 43 億組合
- 配合 API Rate Limiting（5 次/分鐘）防止暴力破解

---

## Machine ID 生成

為防止同一 License 被多台機器使用，需綁定 Machine ID。

### 採用持久化 + Fallback 方案

傳統硬體特徵（CPU ID、MAC、Disk Serial）在 VM/雲端環境不穩定。

**改進方案**：首次啟動時生成並持久化

```
優先順序：
1. 讀取 /var/lib/sentinel/.machine-id（已存在則使用）
2. dmidecode system-uuid（實體機）
3. /etc/machine-id（systemd 系統）
4. 生成隨機 UUID 並儲存
```

**儲存位置**：`/var/lib/sentinel/.machine-id`

**特性**：
- 生成後永久不變（除非刪除檔案）
- 實體機用硬體 UUID，VM/雲端用持久化 ID
- VM 克隆會有相同 ID，SaaS 可偵測並拒絕

---

## SaaS 端：Key 生成與驗證

### Key 生成流程

```mermaid
flowchart TD
    A[客戶購買 License] --> B[建立資料庫記錄]
    B --> C[生成唯一 Customer ID]
    C --> D[決定 Plan 與到期日]
    D --> E[計算 HMAC 簽章]
    E --> F[Base32 編碼取前 8 字元]
    F --> G[組合成 SENT-XXXX-XXXX-XXXX]
    G --> H[儲存至資料庫]
    H --> I[發送 Key 給客戶]
```

### 資料庫 Schema

```sql
CREATE TABLE licenses (
    id UUID PRIMARY KEY,
    license_key VARCHAR(19) UNIQUE NOT NULL,
    customer_id VARCHAR(50) NOT NULL,
    plan VARCHAR(20) NOT NULL,
    expires_at TIMESTAMP NOT NULL,
    machine_id VARCHAR(50),
    activated_at TIMESTAMP,
    created_at TIMESTAMP DEFAULT NOW()
);
```

### 驗證邏輯

```
1. 解析 License Key 格式
   └─ 檢查前綴 "SENT" 與格式

2. 從資料庫查詢 License
   └─ SELECT * FROM licenses WHERE license_key = ?

3. 驗證 License 狀態
   ├─ License 不存在 → LICENSE_NOT_FOUND
   ├─ 已過期 → LICENSE_EXPIRED
   └─ 已被啟用且 machine_id 不同 → ALREADY_ACTIVATED

4. 綁定 Machine ID
   └─ UPDATE licenses SET machine_id = ?, activated_at = NOW()

5. 生成回應簽章
   └─ Ed25519.Sign(PRIVATE_KEY, plan + expires_at + machine_id)

6. 返回授權資訊
```

---

## Activation Flow

### 線上啟用 (Online Activation)

```mermaid
sequenceDiagram
    participant Deployer as 系統部署者
    participant Sentinel as Sentinel Server
    participant SaaS as License SaaS

    Note over Deployer,SaaS: 啟用階段（需外網連線）
    Deployer->>Sentinel: 輸入 License Key
    Note over Deployer: SENT-A3B7-K9X2-Y4P8
    Sentinel->>Sentinel: 生成 Machine ID
    Sentinel->>SaaS: POST /api/v1/license/validate
    Note over Sentinel,SaaS: {<br/>  license_key: "SENT-...",<br/>  machine_id: "A1:B2:C3",<br/>  version: "1.0.0"<br/>}
    SaaS->>SaaS: 驗證 Key 簽章
    SaaS->>SaaS: 檢查 License 狀態
    SaaS->>SaaS: 紀錄 Machine ID 綁定
    SaaS-->>Sentinel: 200 OK
    Note over SaaS,Sentinel: {<br/>  valid: true,<br/>  plan: "basic",<br/>  expires_at: "2027-04-01",<br/>  features: [...],<br/>  signature: "..."<br/>}
    Sentinel->>Sentinel: 驗證 SaaS 簽章
    Sentinel->>Sentinel: 儲存授權資訊（加密）
    Sentinel-->>Deployer: 啟用成功
    Note over Deployer: License 有效期限: 1 年

    Note over Sentinel: 日常使用（完全離線也可）
    Sentinel->>Sentinel: 本地驗證授權
    Note over Sentinel: 檢查到期日 + Machine ID
```

---

## Local Storage

### 授權資訊儲存

```json
{
  "license_key": "SENT-A3B7-K9X2-Y4P8",
  "plan": "basic",
  "customer_id": "acme",
  "customer_name": "Acme Corp",
  "machine_id": "A1:B2:C3:D4:E5:F6",
  "activated_at": "2026-04-01T10:00:00Z",
  "expires_at": "2027-04-01T10:00:00Z",
  "features": ["rag_chat", "session_recording", "report"],
  "saas_signature": "Ed25519 簽章 (64 bytes base64)"
}
```

**儲存位置**: `/var/lib/sentinel/.license`

**儲存格式**: 明文 JSON + 簽章驗證

---

## 為什麼簽章驗證就夠了？

### 安全需求分析

| 威脅 | 簽章驗證是否防護 | 加密是否額外幫助 |
|------|------------------|------------------|
| 篡改授權資訊 | ✅ 簽章驗證失敗 | ❌ 不需要 |
| 複製檔案到另一台機器 | ✅ Machine ID 不匹配 | ❌ 不需要 |
| 偽造授權檔案 | ✅ 無法偽造簽章 | ❌ 不需要 |
| 讀取授權資訊 | ❌ 明文可讀 | ⚠️ 可隱藏 |

### 簽章如何防護篡改

```
SaaS 生成回應時（私鑰簽章）：
  回應資料 + PRIVATE_KEY → Ed25519 簽章 → signature

Sentinel 驗證時（公鑰驗證）：
  儲存的資料 + signature + PUBLIC_KEY → Ed25519 驗證
  結果：有效 / 無效
    ✅ 有效 → 資料未被篡改
    ❌ 無效 → 資料被修改，拒絕啟動
```

**關鍵**：私鑰只有 SaaS 知道，公鑰內嵌在 Sentinel
- Sentinel 能驗證簽章，但無法偽造（沒有私鑰）
- 攻擊者修改任何欄位 → 簽章驗證失敗

### 簽章如何防護檔案複製

```
攻擊者複製 /var/lib/sentinel/.license 到新機器：

1. 檔案中的 machine_id: "A1:B2:C3:D4:E5:F6"
2. 新機器的 machine_id: "X9:Y8:Z7:W6:V5:U4"
3. Sentinel 比較：A1:B2:C3... != X9:Y8:Z7...
4. 結果：機器 ID 不匹配，啟動失敗
```

### 為什麼不需要加密

1. **簽章已保護完整性**：任何修改都會被偵測
2. **Machine ID 已綁定機器**：複製檔案無效
3. **授權資訊非敏感**：plan、到期日不是機密
4. **簡化實作**：不需要管理加密金鑰、salt 等
5. **降低複雜度**：減少潛在的加密相關 bug

### Ed25519 公私鑰簽章

```
SaaS 端（私鑰）：
  PRIVATE_KEY → Ed25519.Sign(資料) → signature

Sentinel 端（公鑰）：
  PUBLIC_KEY + signature → Ed25519.Verify(資料) → 有效/無效
```

**特性**：
- 私鑰簽章，公鑰驗證
- 私鑰外洩 = 系統被攻破
- 公鑰公開 = 無風險（只能驗證，不能偽造）

---

## License Validation

### Sentinel 端：啟動時驗證邏輯

```mermaid
flowchart TD
    A[Sentinel 啟動] --> B{讀取 .license}
    B -->|不存在| C[顯示未啟用頁面]
    B -->|存在| D[解析 JSON 檔案]
    D -->|失敗| E[檔案格式錯誤<br/>需重新啟用]
    D -->|成功| F[驗證 SaaS 簽章]
    F -->|無效| G[授權被篡改<br/>需重新啟用]
    F -->|有效| H{檢查 Machine ID}
    H -->|不匹配| I[硬體變更<br/>需重新綁定]
    H -->|匹配| J{檢查到期日}
    J -->|已過期| K[License 過期<br/>請續約]
    J -->|未過期| L[正常啟動]

```

### 驗證步驟詳解

```
1. 讀取授權檔案
   └─ /var/lib/sentinel/.license

2. 解析 JSON 檔案
   └─ 解析失敗 → 檔案格式錯誤

3. 驗證 SaaS 簽章
   └─ Ed25519.Verify(PUBLIC_KEY, 資料, signature)
   └─ 確保授權資訊未被篡改
   └─ 簽章無效 → 授權被篡改

4. 檢查 Machine ID
   └─ 比較儲存的 machine_id 與當前機器
   └─ 不匹配 → 硬體變更或克隆

5. 檢查到期日
   └─ expires_at > NOW()
   └─ 已過期 → 需續約

6. 載入授權配置
   └─ plan, features
   └─ 啟動服務
```

### 錯誤處理

| 錯誤 | 處理方式 | 使用者體驗 |
|------|----------|------------|
| 未啟用 | 顯示啟用頁面 | 輸入 License Key |
| 檔案格式錯誤 | 刪除錯誤檔案 | 重新輸入 License Key |
| 簽章無效 | 刪除檔案 | 授權被篡改，重新啟用 |
| Machine ID 不匹配 | 提示重新綁定 | 聯絡 SaaS 支援 |
| License 過期 | 顯示續約提示 | 輸入新 License Key |

**無需聯網**：所有驗證在本地完成

---

## API Definition

### SaaS License Validation API

**Endpoint**:
```http
POST /api/v1/license/validate
```

**Request**:
```http
Content-Type: application/json

{
  "license_key": "SENT-A3B7-K9X2-Y4P8",
  "machine_id": "A1:B2:C3:D4:E5:F6",
  "version": "1.0.0"
}
```

**Response (Success)**:
```http
200 OK

{
  "valid": true,
  "plan": "basic",
  "customer_id": "acme",
  "customer_name": "Acme Corp",
  "expires_at": "2027-04-01T10:00:00Z",
  "features": ["rag_chat", "session_recording", "report"],
  "signature": "Ed25519 簽章 (base64, 64 bytes)"
}
```

**Response (Error)**:
```http
400 Bad Request

{
  "valid": false,
  "error": "LICENSE_EXPIRED",
  "message": "License expired on 2026-03-01"
}
```

**錯誤代碼**:
| Code | 說明 |
|------|------|
| `INVALID_KEY` | Key 格式錯誤 |
| `INVALID_SIGNATURE` | Key 簽章無效（偽造） |
| `LICENSE_EXPIRED` | License 已過期 |
| `ALREADY_ACTIVATED` | License 已被其他機器啟用 |
| `LICENSE_NOT_FOUND` | License 不存在 |
| `RATE_LIMITED` | 請求過於頻繁 |

**Rate Limiting**:
- 限制：每 IP 每 5 次請求
- 視窗：60 秒
- 超限回傳 429 Too Many Requests

---

## Renewal Flow

### License 續約

```mermaid
sequenceDiagram
    participant SaaS as License SaaS
    participant Admin as 管理者
    participant Sentinel as Sentinel Server

    Note over SaaS,Admin: 續約階段
    SaaS->>Admin: 到期前 30 天發送 Email 通知
    Admin->>SaaS: 登入 SaaS Portal 完成續約
    SaaS->>SaaS: 生成新 License Key
    SaaS->>Admin: 提供新 License Key
    Note over Admin: SENT-X9Y2-M4K7-P3Q6

    Note over Admin,Sentinel: 啟用新 License
    Admin->>Sentinel: 輸入新 License Key
    Sentinel->>SaaS: POST /api/v1/license/validate
    SaaS-->>Sentinel: 驗證成功（返回新到期日）
    Sentinel->>Sentinel: 更新本地授權資訊
    Sentinel-->>Admin: 續約成功
    Note over Admin: 新到期日: 2028-04-01
```

---

## Security Considerations

1. **傳輸加密**: 所有 API 通信必須使用 HTTPS (TLS 1.3+)
2. **Key 保護**: License Key 不以明文顯示於日誌或錯誤訊息
3. **Rate Limiting**: 驗證 API 實作 IP-based throttling
4. **Audit Log**: SaaS 端記錄所有啟用/驗證請求
5. **簽章驗證**: Ed25519 公私鑰機制
   - SaaS 用私鑰簽章（絕不外洩）
   - Sentinel 用公鑰驗證（內嵌於程式）
6. **Machine ID 綁定**: 防止同一 License 被多台機器使用

---

## Error Handling

### 常見錯誤場景

| 錯誤 | 顯示訊息 | 解決方式 |
|------|----------|----------|
| Key 格式錯誤 | 「License Key 格式不正確，應為 SENT-XXXX-XXXX-XXXX」 | 檢查輸入 |
| License 過期 | 「License 已於 2026-03-01 過期，請聯絡 SaaS 續約」 | 聯絡 SaaS |
| 已被啟用 | 「此 License 已被其他機器啟用」 | 聯絡 SaaS 重新綁定 |
| Machine ID 變更 | 「硬體識別碼變更，需重新綁定」 | 聯絡 SaaS 重新綁定 |
| 網路錯誤 | 「無法連線至 SaaS，請檢查網路連線」 | 檢查網路 |

---

## Apeendix: 完整 Activation 流程演示

### 概念說明：License vs License Key

| License (授權) | License Key (金鑰) |
|----------------|-------------------|
| 完整的授權記錄 | 短字串標識符 |
| 存在 SaaS 資料庫 | 給客戶的「票據」 |
| 包含所有資訊 | 用來查找 License |

```
License Key (SENT-XXXX-XXXX-XXXX) → 查找資料庫 → License (完整記錄)
```

### 階段 1：客戶購買，SaaS 生成 License Key

```mermaid
sequenceDiagram
    participant Customer as 客戶
    participant SaaS as SaaS
    participant DB as 資料庫

    Customer->>SaaS: 購買 Basic Plan (1年)
    SaaS->>SaaS: 生成 Customer ID: "acme"
    SaaS->>SaaS: 決定到期日: "2027-04-01"
    SaaS->>SaaS: 組合資料: "BASIC" + "acme" + "1743497600"

    Note over SaaS: 計算 HMAC 簽章
    SaaS->>SaaS: HMAC-SHA256(SECRET, "BASICacme1743497600")
    SaaS->>SaaS: 雜湊結果: a3b7c9d8e2f1a1b2...
    SaaS->>SaaS: Base32 編碼: A3B7K9X2Y4P8M4Q6...
    SaaS->>SaaS: 取前 8 字元: A3B7K9X2

    SaaS->>SaaS: 組裝 Key: SENT-A3B7-K9X2-Y4P8

    SaaS->>DB: INSERT INTO licenses
    Note over DB: license_key: "SENT-A3B7-K9X2-Y4P8"<br/>plan: "basic"<br/>customer_id: "acme"<br/>expires_at: "2027-04-01"<br/>machine_id: NULL

    SaaS->>Customer: 發送 License Key<br/>(Email / SaaS Portal)
    Note over Customer: 收到: SENT-A3B7-K9X2-Y4P8
```

### 階段 2：部署者輸入 Key，Sentinel 驗證

```mermaid
sequenceDiagram
    participant Deployer as 部署者
    participant Sentinel as Sentinel Server
    participant SaaS as SaaS
    participant DB as 資料庫

    Note over Deployer,Sentinel: 首次啟動
    Deployer->>Sentinel: 輸入 License Key
    Note over Deployer: SENT-A3B7-K9X2-Y4P8

    Sentinel->>Sentinel: 解析 Key 格式
    Note over Sentinel: 前綴: SENT ✓<br/>格式: XXXX-XXXX-XXXX ✓

    Sentinel->>Sentinel: 生成 Machine ID
    Note over Sentinel: 讀取 /var/lib/sentinel/.machine-id<br/>不存在，則生成新 ID

    Sentinel->>SaaS: POST /api/v1/license/validate
    Note over Sentinel,SaaS: {<br/>  "license_key": "SENT-A3B7-K9X2-Y4P8",<br/>  "machine_id": "A1:B2:C3:D4:E5:F6",<br/>  "version": "1.0.0"<br/>}

    Note over SaaS,DB: SaaS 驗證
    SaaS->>DB: SELECT * FROM licenses WHERE license_key = ?
    DB-->>SaaS: 返回 License 記錄

    SaaS->>SaaS: 檢查狀態
    Note over SaaS: ✓ Key 存在<br/>✓ 未過期 (2027-04-01 > 今天)<br/>✓ machine_id = NULL (首次啟用)

    SaaS->>SaaS: 生成回應簽章
    Note over SaaS: Ed25519.Sign(PRIVATE_KEY,<br/>  "basic2027-04-01A1:B2:C3...")<br/>  = signature (64 bytes)

    SaaS->>DB: UPDATE licenses SET machine_id = ?, activated_at = NOW()

    SaaS-->>Sentinel: 200 OK
    Note over SaaS,Sentinel: {<br/>  "valid": true,<br/>  "plan": "basic",<br/>  "customer_id": "acme",<br/>  "customer_name": "Acme Corp",<br/>  "expires_at": "2027-04-01T10:00:00Z",<br/>  "features": ["rag_chat", "session_recording", "report"],<br/>  "signature": "Ed25519 簽章"<br/>}
```

### 階段 3：Sentinel 儲存並啟用

```mermaid
sequenceDiagram
    participant SaaS as SaaS
    participant Sentinel as Sentinel Server
    participant Deployer as 部署者
    participant Storage as 本地儲存

    Note over Sentinel,SaaS: 收到驗證回應
    Sentinel->>Sentinel: 驗證 SaaS 簽章
    Note over Sentinel: Ed25519.Verify(PUBLIC_KEY,<br/>  資料, signature)<br/>  ✓ 有效

    Sentinel->>Storage: 儲存 /var/lib/sentinel/.license
    Note over Storage: {<br/>  "license_key": "SENT-A3B7-K9X2-Y4P8",<br/>  "plan": "basic",<br/>  ...<br/>  "saas_signature": "Ed25519 簽章"<br/>}

    Sentinel-->>Deployer: 啟用成功！
    Note over Deployer: License 有效期限: 1 年<br/>到期日: 2027-04-01

    Sentinel->>Sentinel: 啟動服務
    Note over Sentinel:載入 Basic Plan 功能<br/>✓ RAG Chat<br/>✓ Session Recording<br/>✓ Report
```

### 階段 4：日常開機驗證（完全離線）

```mermaid
sequenceDiagram
    participant Sentinel as Sentinel Server
    participant Storage as 本地儲存

    Sentinel->>Storage: 讀取 /var/lib/sentinel/.license
    Storage-->>Sentinel: 授權檔案 (JSON)

    Sentinel->>Sentinel: 解析 JSON
    Sentinel->>Sentinel: 驗證 SaaS 簽章
    Note over Sentinel: ✓ 簽章有效

    Sentinel->>Sentinel: 檢查 Machine ID
    Note over Sentinel: 當前: A1:B2:C3:D4:E5:F6<br/>儲存: A1:B2:C3:D4:E5:F6<br/>✓ 匹配

    Sentinel->>Sentinel: 檢查到期日
    Note over Sentinel: 到期: 2027-04-01<br/>今天: 2026-04-01<br/>✓ 未過期

    Sentinel->>Sentinel: 載入授權配置
    Note over Sentinel: plan: basic<br/>features: [...]

    Sentinel->>Sentinel: 正常啟動 ✓
```

### 階段 5：有人嘗試複製 Key 到另一台機器

```mermaid
sequenceDiagram
    participant Attacker as 攻擊者
    participant Sentinel2 as 新機器 Sentinel
    participant SaaS as SaaS
    participant DB as 資料庫

    Note over Attacker: 偷到 License Key<br/>SENT-A3B7-K9X2-Y4P8
    Attacker->>Sentinel2: 輸入 Key

    Sentinel2->>Sentinel2: 生成新 Machine ID
    Note over Sentinel2: ID: X9:Y8:Z7:W6:V5:U4 (不同！)

    Sentinel2->>SaaS: POST /api/v1/license/validate
    Note over Sentinel2,SaaS: {<br/>  license_key: "SENT-A3B7-K9X2-Y4P8",<br/>  machine_id: "X9:Y8:Z7:W6:V5:U4"<br/>}

    SaaS->>DB: SELECT * FROM licenses WHERE license_key = ?
    DB-->>SaaS: 返回記錄<br/>machine_id: "A1:B2:C3:D4:E5:F6"

    SaaS->>SaaS: 比較 Machine ID
    Note over SaaS: 已綁定: A1:B2:C3...<br/>當前請求: X9:Y8:Z7...<br/>✗ 不同！

    SaaS-->>Sentinel2: 400 Bad Request
    Note over SaaS,Sentinel2: {<br/>  "valid": false,<br/>  "error": "ALREADY_ACTIVATED",<br/>  "message": "此 License 已被其他機器啟用"<br/>}

    Sentinel2-->>Attacker: 啟用失敗
    Note over Attacker: 顯示錯誤<br/>「此 License 已被其他機器啟用」
```

### 流程總結

| 階段 | 需要聯網 | 說明 |
|------|----------|------|
| 1. 生成 Key | - | SaaS 端完成 |
| 2. 驗證 Key | ✅ 需要 | Sentinel 連線 SaaS |
| 3. 儲存啟用 | ✅ 需要 | 儲存授權資訊 |
| 4. 日常驗證 | ❌ 不需要 | 完全本地驗證 |
| 5. 防複製 | ✅ 需要 | SaaS 綁定 Machine ID |
