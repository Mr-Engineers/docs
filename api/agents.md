# Agents API contract

**Status:** draft  
**UI:** Agents hub (`/agents`, `/agents/:agentId`) — [`src/pages/AgentsPage.tsx`](https://github.com/Mr-Engineers/one-frontend/blob/main/src/pages/AgentsPage.tsx)  
**OpenAPI:** tag `Agents` (+ nested `Rules`, `Quotas`) in [`openapi/openapi.json`](https://github.com/Mr-Engineers/one-frontend/blob/main/openapi/openapi.json)  
**Auth:** Bearer (Supabase session), org/tenant scoped

List + squash-reveal detail with tabs: **Overview · Access · Rules · Limits · Keys**. Rules and quotas are agent-scoped resources; MCP attach and role binding live on the agent.

Frontend calls `/api/...` → backend `/api/v1/...`.

---

## Endpoints

| Method | Path | Purpose |
| --- | --- | --- |
| `GET` | `/agents` | List agents (table) |
| `GET` | `/agents/{agentId}` | Agent detail (+ posture summary optional) |
| `PATCH` | `/agents/{agentId}` | Update role binding / metadata |
| `POST` | `/agents/{agentId}/revoke` | Revoke API key (status → `revoked`) |
| `GET` | `/agents/{agentId}/overview` | Overview tab metrics (windowed) |
| `GET` | `/agents/{agentId}/posture` | Effective grants ∩ attached MCPs |
| `POST` | `/agents/{agentId}/mcp/{serverId}` | Attach org MCP (may require auth) |
| `DELETE` | `/agents/{agentId}/mcp/{serverId}` | Detach MCP |
| `POST` | `/agents/{agentId}/mcp/{serverId}/auth` | Start/complete per-agent MCP OAuth |
| `GET` | `/agents/{agentId}/rules` | List policy rules |
| `POST` | `/agents/{agentId}/rules` | Create rule |
| `PUT` | `/agents/{agentId}/rules/{ruleId}` | Update rule |
| `DELETE` | `/agents/{agentId}/rules/{ruleId}` | Delete rule |
| `GET` | `/agents/{agentId}/rules/meta` | Editor enums: tools, fields, dry-run samples |
| `POST` | `/agents/{agentId}/rules/dry-run` | Evaluate rules against sample args |
| `GET` | `/agents/{agentId}/quotas` | Rate-limit caps |
| `POST` | `/agents/{agentId}/quotas` | Create cap (wizard) |
| `PATCH` | `/quotas/{quotaId}` | Enable/disable (and future edit) |

---

## `GET /agents`

### Query parameters

| Param | Default | Purpose |
| --- | --- | --- |
| `search` | — | Match `name`, `apiKeyHint`, role display name |
| `status` | — | `active` \| `revoked` \| `disabled` (repeatable or comma-separated) |
| `role_id` | — | Filter by bound role |
| `sort` | `last_seen` | `name` \| `role` \| `status` \| `api_key` \| `last_seen` |
| `sort_dir` | `desc` | `asc` \| `desc` |
| `limit` | `50` | Page size (max 200) |
| `cursor` | — | Opaque cursor for next page |

UI currently filters client-side; query params document the server contract when wired.

### Response item (`AgentListItem`)

| Field | Type | Notes |
| --- | --- | --- |
| `id` | string | e.g. `agt_purchasing_01` |
| `name` | string | Display name |
| `roleId` | string \| null | FK to role template |
| `roleName` | string \| null | Denormalized for table |
| `status` | enum | `active` \| `revoked` \| `disabled` |
| `apiKeyHint` | string | Masked hint only (`gw_live_••••a91c`) |
| `mcpServerIds` | string[] | Attached org MCP ids |
| `createdAt` | datetime | ISO-8601 |
| `lastSeenAt` | datetime | ISO-8601 |

```json
{
  "items": [
    {
      "id": "agt_purchasing_01",
      "name": "Purchasing",
      "roleId": "role_purchasing_operator",
      "roleName": "purchasing-operator",
      "status": "active",
      "apiKeyHint": "gw_live_••••a91c",
      "mcpServerIds": ["mcp_shop", "mcp_magazine"],
      "createdAt": "2026-09-12T10:00:00Z",
      "lastSeenAt": "2026-10-03T11:42:00Z"
    }
  ],
  "nextCursor": null
}
```

---

## `GET /agents/{agentId}`

Full agent row plus optional embedded posture (or call `/posture` separately).

Same fields as list item. Prefer including `roleName` for header subtitle.

---

## `PATCH /agents/{agentId}`

**Body**

| Field | Required | Notes |
| --- | --- | --- |
| `roleId` | no | `string \| null` — bind grant template; `null` = no grants |
| `name` | no | Display rename (if product allows) |
| `status` | no | `active` \| `disabled` (not revoke — use revoke endpoint) |

---

## `POST /agents/{agentId}/revoke`

Sets `status` to `revoked`, rotates/invalidates gateway key, returns updated agent with new `apiKeyHint` (revoked form). Irreversible for that key material.

---

## `GET /agents/{agentId}/overview`

Per-agent Overview tab. Reuse org Overview window query params (`range`, `from`/`to`, `tz`, `bucket`, `top_limit`) where applicable. See [overview.md](./overview.md).

### Response (`AgentOverviewResponse`)

| Field | Meaning |
| --- | --- |
| `window` | Same shape as org Overview `window` |
| `calls` | Calls by this agent in window |
| `callsDeltaPct` | vs previous period; `null` if previous = 0 |
| `pendingApprovals` | Point-in-time queue count for this agent |
| `denyRatePct` / `cautionRatePct` | Of audited decisions for this agent |
| `rateLimited` | Count of `rate_limited` in window |
| `clearToday` / `cautionToday` | Allow count vs caution+deny (UI labels “clear” / “pressure”) — prefer windowed names `clear` / `flagged` in API; UI can map copy |
| `decisionSplit` | `allow`, `caution`, `deny`, `rate_limited` |
| `callsOverTime` | Dense buckets |
| `topTools` | `{ tool, count }[]` |
| `budget` | Primary daily quota snapshot or `null` (`id`, `label`, `used`, `cap`, `unit`) |

---

## `GET /agents/{agentId}/posture`

| Field | Meaning |
| --- | --- |
| `role` | Full role summary or `null` |
| `callable` | Granted **and** MCP attached — `{ serverId, serverName, tool, via }` |
| `unreachable` | Granted but MCP not attached |
| `attachedWithoutGrants` | Attached server ids with zero role grants |

`via`: `server` \| `tool`.

---

## MCP attach / detach

**MVP:** attach/detach + OAuth for **remote** catalog servers that set `requiresAuth: true` must work. See [mcp.md](./mcp.md) § MVP implementation scope. UI `AttachMcpAuthFlow` is still a staged mock today — backend should return a real `authorizationUrl`.

### `POST /agents/{agentId}/mcp/{serverId}`

Attach catalog server. If `requiresAuth`, return `409` or `202` with `authRequired: true` and UI must call auth flow.

**Success:** `{ "agentId", "mcpServerIds": [...] }`

### `POST /agents/{agentId}/mcp/{serverId}/auth`

Start OAuth (or complete with callback token). Demo UI is staged prompt → redirect → done.

**Response (start):** `{ "authorizationUrl": "...", "state": "..." }`  
**Response (complete):** `{ "attached": true, "serverId": "..." }`

### `DELETE /agents/{agentId}/mcp/{serverId}`

Detach; does not delete org catalog entry.

---

## Rules (Access tab sibling)

Rules evaluate **after** RBAC. First matching enabled rule wins. Outcomes: `allow` \| `deny` \| `needs_ai`.

### Rule shape (`PolicyRule`)

| Field | Type |
| --- | --- |
| `id` | string |
| `name` | string |
| `agentId` | string |
| `tool` | string (exact tool name) |
| `when` | condition tree (groups + leaves) |
| `then` | `allow` \| `deny` \| `needs_ai` |
| `enabled` | boolean |

**Condition leaf:** `{ id, field, op, value }`  
**Condition group:** `{ id, combinator: "and"|"or", children: [...] }`

**Ops:** `eq` \| `neq` \| `gt` \| `gte` \| `lt` \| `lte` \| `in` \| `not_in` \| `is_empty` \| `not_empty`  
(`is_empty` / `not_empty` need no value.)

**Fields (demo catalog):** `shop_location`, `total_eur`, `vendor`, `qty`, `delta`, `abs_delta`, `reason`, `sku`, `priority`, `audience` — each with type `enum` \| `number` \| `text` and tool globs.

### `GET /agents/{agentId}/rules/meta`

```json
{
  "tools": [
    { "serverId": "mcp_shop", "serverName": "Shop Catalog", "tools": ["shop.search", "shop.checkout"] }
  ],
  "fields": [
    {
      "id": "total_eur",
      "label": "total_eur",
      "type": "number",
      "tools": ["shop.checkout", "shop.order_create"]
    }
  ],
  "dryRunSamples": [
    {
      "id": "sample_1",
      "label": "HQ checkout €40",
      "tool": "shop.checkout",
      "args": { "total_eur": 40, "shop_location": "hq" }
    }
  ]
}
```

### `POST /agents/{agentId}/rules/dry-run`

**Body:** `{ "tool": "...", "args": { }, "rules"?: PolicyRule[] }`  
If `rules` omitted, evaluate persisted rules.

**Response:** `{ "matchedRuleId": "..." | null, "outcome": "allow"|"deny"|"needs_ai"|null, "detail": "..." }`

---

## Quotas (Limits tab)

### Quota shape

| Field | Type | Notes |
| --- | --- | --- |
| `id` | string | |
| `name` | string | |
| `agentId` / `agentName` | string | |
| `window` | `1m` \| `1h` \| `1d` | |
| `cap` | int | Steady cap |
| `used` | int | Point-in-time usage |
| `unit` | `"calls"` | |
| `enabled` | boolean | |
| `burst` | int | Token-bucket headroom |
| `updatedAt` | datetime | |

### `POST /agents/{agentId}/quotas`

**Body:** `{ "name": "...", "window": "...", "cap": 0, "burst": 0 }` — creates enabled quota with `used: 0`.

### `PATCH /quotas/{quotaId}`

**Body:** `{ "enabled"?: boolean, "name"?: string, "cap"?: int, "burst"?: int }`

---

## Keys tab

Rendered from agent fields (`status`, `apiKeyHint`, `createdAt`, `lastSeenAt`) + revoke action. No separate list of historical keys in MVP UI.

---

## Errors

| Status | When |
| --- | --- |
| `400` | Invalid body, window, condition tree |
| `401` | Missing/invalid auth |
| `403` | Not allowed for org |
| `404` | Unknown agent / rule / quota / MCP |
| `409` | Attach needs auth; duplicate quota window (if enforced) |
| `500` | Unexpected |

Body: `{ "detail": "..." }`.

---

## Example requests

```
GET /agents?status=active&sort=last_seen&sort_dir=desc
GET /agents/agt_purchasing_01/overview?range=today&tz=Europe/Warsaw
PATCH /agents/agt_purchasing_01  { "roleId": "role_purchasing_readonly" }
POST /agents/agt_purchasing_01/mcp/mcp_tickets
POST /agents/agt_purchasing_01/quotas  { "name": "Hourly cap", "window": "1h", "cap": 100, "burst": 10 }
```

---

## Open questions for backend

1. Should `/agents/{id}` embed posture + linked MCP summaries, or keep separate round-trips?
2. Full key plaintext returned once on create/rotate — UI has no rotate yet, only revoke.
3. Rule ordering: explicit `priority` field vs array order?
4. Per-agent overview: reuse identical `window` semantics as org Overview (recommended).
5. Rate-limit hit history (`mockRateLimitHits`) — not shown in agent UI; defer or expose under `/agents/{id}/rate-limit-hits`?
