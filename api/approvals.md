# Approvals API contract

**Status:** draft  
**UI:** Approvals queue (`/approvals`, `/approvals/:approvalId`) — [`src/pages/ApprovalsPage.tsx`](https://github.com/Mr-Engineers/one-frontend/blob/main/src/pages/ApprovalsPage.tsx)  
**OpenAPI:** tag `Approvals` in [`openapi/openapi.json`](https://github.com/Mr-Engineers/one-frontend/blob/main/openapi/openapi.json)  
**Auth:** Bearer (Supabase session), org/tenant scoped

Pending human decisions after specialist `caution → human`. List + detail panel with Allow / Deny / Allow temporarily.

Frontend calls `/api/approvals` → backend `/api/v1/approvals`.

---

## Endpoints

| Method | Path | Purpose |
| --- | --- | --- |
| `GET` | `/approvals` | List open approvals |
| `GET` | `/approvals/{approvalId}` | Detail (same shape as list item) |
| `POST` | `/approvals/{approvalId}/allow` | Allow once (forward call) |
| `POST` | `/approvals/{approvalId}/deny` | Deny |
| `POST` | `/approvals/{approvalId}/allow-temporary` | Allow with short TTL override |

Resolved items leave the queue (UI removes row). Default TTL for waiting approvals comes from workspace settings (`defaultApprovalTtlSeconds`).

---

## `GET /approvals`

### Query parameters

| Param | Default | Purpose |
| --- | --- | --- |
| `search` | — | Match `tool`, `agentName` |
| `agent_id` | — | Filter by agent |
| `sort` | `age` | `tool` \| `agent` \| `age` \| `ttl` \| `created_at` |
| `sort_dir` | `desc` | `asc` \| `desc` |
| `limit` | `50` | Max 200 |
| `cursor` | — | Next page |

Only **pending** items are listed. Historical resolutions appear in Audit.

### Response item (`ApprovalRequest`)

| Field | Type | Notes |
| --- | --- | --- |
| `id` | string | e.g. `apr_01` |
| `tool` | string | Tool name |
| `agentId` | string | |
| `agentName` | string | Display |
| `specialist` | string | Model/route id, e.g. `local/purchasing` |
| `allowProb` | number | 0–1 specialist P(allow) |
| `denyProb` | number | 0–1 specialist P(deny) |
| `ageSeconds` | int | Seconds waiting (point-in-time; or derive from `createdAt`) |
| `ttlSeconds` | int | Seconds until auto-deny |
| `matchedRules` | string[] | Human-readable rule refs that escalated |
| `modelChoice` | string | e.g. `caution → human` |
| `argsRedacted` | object | Sensitive fields masked (`***`) |
| `createdAt` | datetime | |

Prefer also returning `expiresAt` (absolute) so UI need not poll-derived TTL; MVP UI uses `ttlSeconds`.

```json
{
  "items": [
    {
      "id": "apr_01",
      "tool": "shop.checkout",
      "agentId": "agt_purchasing_01",
      "agentName": "Purchasing",
      "specialist": "local/purchasing",
      "allowProb": 0.41,
      "denyProb": 0.38,
      "ageSeconds": 42,
      "ttlSeconds": 300,
      "matchedRules": ["elevated spend or non-HQ"],
      "modelChoice": "caution → human",
      "argsRedacted": {
        "sku": "NB-A4-80",
        "qty": 24,
        "total_eur": "***",
        "shop_location": "popup"
      },
      "createdAt": "2026-10-03T11:54:00Z"
    }
  ],
  "nextCursor": null
}
```

---

## Resolve actions

All three return `204` or `{ "id", "decision": "allow"|"deny", "mode": "once"|"temporary"|"deny" }` and remove from pending queue. Also write an Audit event.

### `POST .../allow`

Empty body. Forward the original tool call.

### `POST .../deny`

Optional body: `{ "reason"?: string }`.

### `POST .../allow-temporary`

**Body:** `{ "ttlSeconds"?: number }` — if omitted, use a short default (e.g. 15m) or workspace default. UI button is “Allow temporarily” without a picker today.

---

## Errors

| Status | When |
| --- | --- |
| `400` | Invalid TTL |
| `401` / `403` | Auth |
| `404` | Unknown or already resolved |
| `409` | Expired / already decided (race) |
| `500` | Unexpected |

---

## Open questions for backend

1. Emit `ageSeconds`/`ttlSeconds` server-side each fetch vs absolute `createdAt`/`expiresAt` only?
2. Temporary allow: scope (this call vs tool+agent window) and exact TTL semantics?
3. Polling interval / push for queue freshness — UI has no websocket today; poll is fine.
4. Should list include specialist display name separately from `specialist` route id?
