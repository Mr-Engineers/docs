# Simulator API contract

**Status:** draft  
**UI:** Simulator (`/simulator`) — [`src/pages/SimulatorPage.tsx`](https://github.com/Mr-Engineers/one-frontend/blob/main/src/pages/SimulatorPage.tsx) (stub)  
**OpenAPI:** tag `Simulator` in [`openapi/openapi.json`](https://github.com/Mr-Engineers/one-frontend/blob/main/openapi/openapi.json)  
**Auth:** Bearer (Supabase session), org/tenant scoped

Page is a **stub** today (“Agent + role picker, scenario list, step timeline, open in audit”). Endpoints below are a proposed shape so OpenAPI/tags stay complete; treat as speculative until UI lands.

Frontend would call `/api/simulator/...` → backend `/api/v1/simulator/...`.

---

## Proposed endpoints (not wired in UI)

| Method | Path | Purpose |
| --- | --- | --- |
| `GET` | `/simulator/scenarios` | List canned scenarios |
| `POST` | `/simulator/runs` | Start a dry-run against agent + role |
| `GET` | `/simulator/runs/{runId}` | Run detail + step timeline |
| `GET` | `/simulator/runs/{runId}/audit-link` | Optional deep-link to synthetic audit event |

---

## Proposed shapes

### Scenario

| Field | Type |
| --- | --- |
| `id` | string |
| `label` | string |
| `tool` | string |
| `args` | object |
| `agentIdHint` | string \| null |

### Run request

```json
{
  "agentId": "agt_purchasing_01",
  "roleId": "role_purchasing_operator",
  "scenarioId": "scn_checkout_popup",
  "argsOverride": {}
}
```

### Run response

| Field | Type | Notes |
| --- | --- | --- |
| `id` | string | |
| `status` | `completed` \| `failed` | |
| `decision` | `allow` \| `caution` \| `deny` \| `rate_limited` | |
| `steps` | array | Mirror audit `decisionChain` |
| `auditEventId` | string \| null | If persisted |

---

## Errors

| Status | When |
| --- | --- |
| `400` | Invalid agent/role/scenario |
| `401` / `403` | Auth |
| `404` | Unknown run |
| `501` | Not implemented |
| `500` | Unexpected |

---

## Open questions for backend

1. Persist simulator runs into Audit vs ephemeral only?
2. Reuse rules dry-run (`POST /agents/{id}/rules/dry-run`) vs full pipeline simulation (RBAC → rules → specialist → rate limits)?
3. When UI is built, replace this brief with concrete fields from components/mocks.
