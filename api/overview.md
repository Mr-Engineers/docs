# Overview API contract

**Status:** draft  
**UI:** org Overview dashboard (`/`) — [`src/pages/OverviewPage.tsx`](https://github.com/Mr-Engineers/one-frontend/blob/main/src/pages/OverviewPage.tsx)  
**OpenAPI:** `GET /overview` in [`openapi/openapi.json`](https://github.com/Mr-Engineers/one-frontend/blob/main/openapi/openapi.json)  
**Auth:** Bearer (Supabase session), org/tenant scoped

One aggregated response hydrates the whole page. Frontend calls `/api/overview` → backend `/api/v1/overview`.

> Follow-up (not in this contract): per-agent Overview tab as `GET /agents/{agentId}/overview` reusing the same schemas.

---

## Query parameters

| Param | Default | Purpose |
| --- | --- | --- |
| `range` | `today` | Preset: `today` \| `24h` \| `7d` \| `30d`. Calendar-aware (`today`) uses `tz`; rolling (`24h`, `7d`, `30d`) are relative to `now`. |
| `from` / `to` | — | Custom ISO-8601 interval (inclusive start, exclusive end). Max span: 90 days. Reject if `to <= from`. |
| `tz` | org default (e.g. `Europe/Warsaw`) | IANA timezone for `today` boundaries and label formatting. |
| `bucket` | auto | Override: `5m` \| `15m` \| `1h` \| `1d`. If omitted, use the auto-bucket table. |
| `top_limit` | `5` | Cap for `topAgents` / `topTools`. |

**Preset vs custom:** if `range` is sent with `from`/`to`, **preset wins**. Custom requires both `from` and `to`.

### Auto-bucket by range

| Range | Default bucket |
| --- | --- |
| `today`, `24h` | `5m` |
| `7d` | `1h` |
| `30d` | `1d` |
| custom | Coarsest that keeps ≤ ~300 points (`5m` → `15m` → `1h` → `1d`) |

### Previous period (for `callsDeltaPct`)

Same duration immediately before `window.start`:

- `today` → previous calendar day in `tz`
- `24h` / `7d` / `30d` → prior equal rolling window
- `custom` → equal-length interval ending at `from`

---

## Response fields

Field names are **window-agnostic**. UI copy (“Calls today”, “vs yesterday”) comes from `window.preset` / `window.compareLabel`.

### Point-in-time (ignore selected range)

| Field | Meaning |
| --- | --- |
| `pendingApprovals` | Open approval queue count |
| `activeAgents` | Agents with `status === active` |
| `budgets` | Current quota usage (curated subset — e.g. daily + burst for busiest agents, not every quota row) |

### Windowed

| Field | Meaning |
| --- | --- |
| `calls` | Gateway tool invocations in `[start, end)` |
| `callsDeltaPct` | `((current - previous) / previous) * 100`, rounded int; `null` if previous period has 0 calls |
| `denyRatePct` / `cautionRatePct` | % of **audited decisions** in the window (not all HTTP traffic) |
| `rateLimited` | Count of `rate_limited` decisions in the window |
| `decisionSplit` | Prefer fixed order: `allow`, `caution`, `deny`, `rate_limited` |
| `agentSplit` | Per agent: `clear` = allow count; `flagged` = caution + deny (**not** rate_limited) |
| `callsOverTime` | Dense buckets covering the full window; include empty buckets (`count: 0`) |
| `topAgents` / `topTools` | Sorted desc, length ≤ `top_limit`. Tool name: use a single convention (prefer server-qualified if available) and stick to it |

### `window` (always resolved)

Echo the absolute interval so the UI does not re-derive rules:

```json
{
  "preset": "7d",
  "start": "2026-09-26T21:00:00+02:00",
  "end": "2026-10-03T21:00:00+02:00",
  "previousStart": "2026-09-19T21:00:00+02:00",
  "previousEnd": "2026-09-26T21:00:00+02:00",
  "timezone": "Europe/Warsaw",
  "bucket": "1h",
  "compareLabel": "vs prior 7 days"
}
```

`preset` is `today` \| `24h` \| `7d` \| `30d` \| `custom`.  
`compareLabel` is backend-owned (keeps delta copy consistent).

---

## Errors

| Status | When |
| --- | --- |
| `400` | Invalid range (`from`/`to` missing pair, inverted, or span > 90 days); invalid `bucket` / `tz` |
| `401` | Missing/invalid auth |
| `403` | Authenticated but not allowed for this org |
| `500` | Unexpected server error |

Body shape: `{ "detail": "..." }` (`ErrorResponse`).

---

## Example requests

### Today (5-minute buckets)

```
GET /overview?range=today&tz=Europe/Warsaw
```

### Last 7 days (hourly buckets)

```
GET /overview?range=7d&tz=Europe/Warsaw
```

### Custom range

```
GET /overview?from=2026-09-01T00:00:00%2B02:00&to=2026-09-15T00:00:00%2B02:00&tz=Europe/Warsaw
```

### Example response (`today`)

```json
{
  "window": {
    "preset": "today",
    "start": "2026-10-03T00:00:00+02:00",
    "end": "2026-10-03T21:00:00+02:00",
    "previousStart": "2026-10-02T00:00:00+02:00",
    "previousEnd": "2026-10-03T00:00:00+02:00",
    "timezone": "Europe/Warsaw",
    "bucket": "5m",
    "compareLabel": "vs yesterday"
  },
  "calls": 1842,
  "callsDeltaPct": 12,
  "pendingApprovals": 3,
  "activeAgents": 4,
  "denyRatePct": 8,
  "cautionRatePct": 15,
  "rateLimited": 2,
  "decisionSplit": [
    { "decision": "allow", "count": 120 },
    { "decision": "caution", "count": 24 },
    { "decision": "deny", "count": 12 },
    { "decision": "rate_limited", "count": 2 }
  ],
  "agentSplit": [
    {
      "agentId": "agt_purchasing",
      "agentName": "Purchasing",
      "clear": 80,
      "flagged": 18
    }
  ],
  "callsOverTime": [
    {
      "start": "2026-10-03T08:00:00+02:00",
      "end": "2026-10-03T08:05:00+02:00",
      "count": 12
    }
  ],
  "topAgents": [
    { "agentId": "agt_purchasing", "agentName": "Purchasing", "count": 98 }
  ],
  "topTools": [{ "tool": "create_po", "count": 40 }],
  "budgets": [
    {
      "id": "purchasing_day",
      "agentId": "agt_purchasing",
      "label": "Purchasing · daily",
      "used": 1280,
      "cap": 3000,
      "unit": "calls"
    }
  ]
}
```

---

## Open questions for backend

1. Tool identity: bare name vs `server/tool` — pick one for `topTools.tool`.
2. `agentSplit`: all active agents, or only agents with activity in the window?
3. Budget curation rule: top N by utilization, or fixed set of quota windows (daily + burst)?
