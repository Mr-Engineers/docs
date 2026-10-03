# Audit API contract

**Status:** draft  
**UI:** Audit log (`/audit`, `/audit/:eventId`) — [`src/pages/AuditPage.tsx`](https://github.com/Mr-Engineers/one-frontend/blob/main/src/pages/AuditPage.tsx)  
**OpenAPI:** tag `Audit` in [`openapi/openapi.json`](https://github.com/Mr-Engineers/one-frontend/blob/main/openapi/openapi.json)  
**Auth:** Bearer (Supabase session), org/tenant scoped

Read-only decision history: table + detail with decision chain and redacted args.

Frontend calls `/api/audit` → backend `/api/v1/audit`.

---

## Endpoints

| Method | Path | Purpose |
| --- | --- | --- |
| `GET` | `/audit` | List events (filter/sort/paginate) |
| `GET` | `/audit/{eventId}` | Single event detail |

No mutations on this page.

---

## `GET /audit`

### Query parameters

| Param | Default | Purpose |
| --- | --- | --- |
| `search` | — | Match `tool` (and optionally redacted arg text — backend choice) |
| `agent_id` | — | Filter by agent id |
| `agent_name` | — | Demo UI filters by display name enum; prefer `agent_id` |
| `decision` | — | `allow` \| `caution` \| `deny` \| `rate_limited` (multi) |
| `from` / `to` | — | ISO-8601 time range on `timestamp` |
| `tool` | — | Exact or prefix match |
| `sort` | `time` | `time` \| `tool` \| `agent` \| `decision` |
| `sort_dir` | `desc` | |
| `limit` | `50` | Max 200 |
| `cursor` | — | |

Retention governed by workspace `auditRetentionDays` (Settings).

### Response item (`AuditEvent`)

| Field | Type | Notes |
| --- | --- | --- |
| `id` | string | e.g. `aud_01` |
| `timestamp` | datetime | When decided / recorded |
| `tool` | string | |
| `agentId` | string | |
| `agentName` | string | |
| `decision` | enum | `allow` \| `caution` \| `deny` \| `rate_limited` (not `pending`) |
| `decisionChain` | array | Ordered pipeline stages |
| `argsRedacted` | object | Masked request payload |

### `decisionChain[]` step

| Field | Type | Notes |
| --- | --- | --- |
| `stage` | enum | `rbac` \| `rules` \| `specialist` \| `human` |
| `outcome` | string | Freeform: `pass`, `allow`, `deny`, `needs_ai`, `caution`, `skipped`, `pending`, … |
| `detail` | string | Human-readable explanation |

UI humanizes stage/outcome labels client-side.

```json
{
  "items": [
    {
      "id": "aud_01",
      "timestamp": "2026-10-03T11:40:12Z",
      "tool": "shop.search",
      "agentId": "agt_purchasing_01",
      "agentName": "Purchasing",
      "decision": "allow",
      "decisionChain": [
        {
          "stage": "rbac",
          "outcome": "pass",
          "detail": "Role purchasing-operator"
        },
        {
          "stage": "rules",
          "outcome": "allow",
          "detail": "search allow"
        },
        {
          "stage": "specialist",
          "outcome": "skipped",
          "detail": "Rule short-circuit"
        },
        {
          "stage": "human",
          "outcome": "skipped",
          "detail": "Not required"
        }
      ],
      "argsRedacted": { "query": "notebook A4", "limit": 20 }
    }
  ],
  "nextCursor": null
}
```

---

## Errors

| Status | When |
| --- | --- |
| `400` | Invalid range / decision filter |
| `401` / `403` | Auth |
| `404` | Unknown event |
| `500` | Unexpected |

---

## Open questions for backend

1. Normalize `decisionChain.outcome` to a closed enum vs free string?
2. Export endpoint (CSV/JSON) for retention window — not in UI yet.
3. Link from rate-limited rows to quota id — mock has `auditEventId` on hits; optional enrichment.
4. Include `approvalId` when human stage was involved?
