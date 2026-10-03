# Specialists API contract

**Status:** draft  
**UI:** Specialists catalog (`/specialists`, `/specialists/:specialistId`) — [`src/pages/SpecialistsPage.tsx`](https://github.com/Mr-Engineers/one-frontend/blob/main/src/pages/SpecialistsPage.tsx)  
**OpenAPI:** tag `Specialists` in [`openapi/openapi.json`](https://github.com/Mr-Engineers/one-frontend/blob/main/openapi/openapi.json)  
**Auth:** Bearer (Supabase session), org/tenant scoped

Local Jev-style evaluate workers (one per demo agent). Card grid + read-only detail. Thresholds are **read-only in MVP UI**.

Deep-link only (not in side nav). Also summarized on Agents → Rules tab.

Frontend calls `/api/specialists` → backend `/api/v1/specialists`.

---

## Endpoints

| Method | Path | Purpose |
| --- | --- | --- |
| `GET` | `/specialists` | List specialists |
| `GET` | `/specialists/{specialistId}` | Detail |

No create/update in current UI. Future: patch thresholds / reload artifact.

---

## `GET /specialists`

### Query parameters

| Param | Default | Purpose |
| --- | --- | --- |
| `agent_id` | — | Filter by bound agent |
| `health` | — | `healthy` \| `degraded` \| `down` \| `circuit_open` |
| `limit` | `50` | |
| `cursor` | — | |

### Response item (`Specialist`)

| Field | Type | Notes |
| --- | --- | --- |
| `id` | string | e.g. `spc_purchasing` |
| `name` | string | Display |
| `agentId` | string | Bound agent |
| `modelId` | string | Gateway route key, e.g. `local/purchasing` |
| `version` | string | Pinned artifact / checkpoint |
| `health` | enum | `healthy` \| `degraded` \| `down` \| `circuit_open` |
| `latencyP95Ms` | number | Rolling p95 |
| `latencyBudgetMs` | number | Timeout budget → escalate |
| `errorRatePct` | number | |
| `falseClearRatePct` | number | Golden-set / live false-clear % |
| `evaluatesToday` | int | Windowed “today” (org tz) — or rename to windowed later |
| `clearToday` | int | Auto-cleared |
| `cautionToday` | int | Escalated to human |
| `clearThreshold` | number | Min P(clear) to auto-allow |
| `onFailure` | enum | MVP: `escalate_human` only (UI also labels `deny`) |
| `circuitBreaker` | object | See below |
| `criteriaSummary` | string | What it looks for |
| `loadedAt` | datetime | Artifact load time |
| `lastEvaluateAt` | datetime | Last review |

### `circuitBreaker`

| Field | Type |
| --- | --- |
| `open` | boolean |
| `failures` | int |
| `threshold` | int |
| `cooldownSeconds` | int |

```json
{
  "items": [
    {
      "id": "spc_purchasing",
      "name": "Purchasing specialist",
      "agentId": "agt_purchasing_01",
      "modelId": "local/purchasing",
      "version": "purchase-risk-v2",
      "health": "healthy",
      "latencyP95Ms": 186,
      "latencyBudgetMs": 800,
      "errorRatePct": 0.4,
      "falseClearRatePct": 1.2,
      "evaluatesToday": 312,
      "clearToday": 248,
      "cautionToday": 64,
      "clearThreshold": 0.82,
      "onFailure": "escalate_human",
      "circuitBreaker": {
        "open": false,
        "failures": 0,
        "threshold": 5,
        "cooldownSeconds": 60
      },
      "criteriaSummary": "Spend limits, vendor allowlists, role (intern vs manager), cart/checkout/payment risk.",
      "loadedAt": "2026-10-03T08:01:12Z",
      "lastEvaluateAt": "2026-10-03T11:54:02Z"
    }
  ],
  "nextCursor": null
}
```

---

## Point-in-time vs windowed

- Health, circuit breaker, latency, thresholds, version: **point-in-time**
- `evaluatesToday` / `clearToday` / `cautionToday`: **calendar today** (prefer explicit `tz` + `window` later, matching Overview)

---

## Errors

| Status | When |
| --- | --- |
| `401` / `403` | Auth |
| `404` | Unknown specialist |
| `500` | Unexpected |

---

## Open questions for backend

1. Mutating `clearThreshold` / reloading version — product wants API later; omit write endpoints until UI has forms.
2. Align “today” counters with Overview `range=today&tz=...`.
3. One specialist per agent enforced?
