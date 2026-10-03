# Webhooks API contract

**Status:** draft  
**UI:** Webhooks (`/webhooks`, `/webhooks/:webhookId`) — [`src/pages/WebhooksPage.tsx`](https://github.com/Mr-Engineers/one-frontend/blob/main/src/pages/WebhooksPage.tsx)  
**OpenAPI:** tag `Webhooks` in [`openapi/openapi.json`](https://github.com/Mr-Engineers/one-frontend/blob/main/openapi/openapi.json) *(add when implementing)*  
**Auth:** Bearer (Supabase session), org/tenant scoped; mutate likely **admin/owner**

Outbound HTTPS endpoints subscribed to runtime / incident events. Operators define *what* to notify now; delivery workers can land later.

Frontend calls `/api/webhooks` → backend `/api/v1/webhooks`.

---

## Endpoints

| Method | Path | Purpose |
| --- | --- | --- |
| `GET` | `/webhooks` | List endpoints |
| `GET` | `/webhooks/{webhookId}` | Detail (+ recent deliveries) |
| `POST` | `/webhooks` | Create endpoint + event subscriptions |
| `PATCH` | `/webhooks/{webhookId}` | Update name, URL, description, events, status |
| `DELETE` | `/webhooks/{webhookId}` | Remove endpoint |
| `POST` | `/webhooks/{webhookId}/rotate-secret` | Issue new signing secret (optional MVP+) |
| `GET` | `/webhooks/{webhookId}/deliveries` | Paginated delivery log (optional if embedded on detail) |
| `POST` | `/webhooks/{webhookId}/test` | Send a synthetic ping event (optional MVP+) |

UI today: list + squash detail (toggle events, pause/resume, remove) and an add overlay. No rotate/test buttons yet — safe to stub or omit until wired.

---

## Event catalog

Closed set of subscription keys. Emit when the corresponding control-plane incident occurs.

| Event | When to fire |
| --- | --- |
| `approval.escalated` | Specialist escalated a tool call into the human approval queue |
| `decision.deny` | Gateway recorded a `deny` decision |
| `decision.caution` | Gateway recorded a `caution` decision (or caution path entered) |
| `mcp.health_degraded` | Org MCP server health → `degraded` |
| `mcp.down` | Org MCP server health → `down` |
| `rate_limit.hit` | A quota blocked a call (`rate_limited`) |
| `specialist.circuit_open` | Specialist circuit breaker opened |
| `agent.revoked` | Agent API key / agent status revoked |

UI groups these as approvals / decisions / infra / agents for display only — storage is a flat `events: WebhookEvent[]`.

---

## `GET /webhooks`

### Query parameters

| Param | Default | Purpose |
| --- | --- | --- |
| `search` | — | Match `name`, `url` |
| `status` | — | `active` \| `paused` \| `failing` (multi) |
| `event` | — | Filter hooks that subscribe to this event key |
| `sort` | `name` | `name` \| `url` \| `status` \| `last` (`lastDeliveryAt`) |
| `sort_dir` | `asc` | |
| `limit` | `50` | Max 200 |
| `cursor` | — | |

### Response item (`Webhook`)

| Field | Type | Notes |
| --- | --- | --- |
| `id` | string | e.g. `wh_01` |
| `name` | string | Display label |
| `url` | string | Must be `https://` |
| `status` | enum | `active` \| `paused` \| `failing` |
| `events` | string[] | Subset of event catalog |
| `secretHint` | string | Masked hint only (`whsec_••••abcd`) — never full secret on list/get |
| `description` | string | Optional |
| `createdAt` | datetime | |
| `lastDeliveryAt` | datetime \| null | |
| `successRatePct` | number | Rolling window (backend-defined; UI shows 1 decimal) |
| `recentDeliveries` | array | Optional on list; **required** (or via nested GET) on detail — last ~10 |

`failing` = active subscription with sustained delivery failures (backend threshold TBD). Pause is operator-driven (`paused`); resume → `active` (or `failing` if still unhealthy).

```json
{
  "items": [
    {
      "id": "wh_01",
      "name": "PagerDuty incidents",
      "url": "https://hooks.pagerduty.com/integration/modus/enqueue",
      "status": "active",
      "events": [
        "approval.escalated",
        "decision.deny",
        "mcp.down",
        "specialist.circuit_open"
      ],
      "secretHint": "whsec_••••7a2c",
      "description": "Pages on-call when the control plane escalates or fails closed.",
      "createdAt": "2026-09-12T09:00:00Z",
      "lastDeliveryAt": "2026-10-03T11:36:05Z",
      "successRatePct": 99.2,
      "recentDeliveries": [
        {
          "id": "del_01",
          "event": "approval.escalated",
          "status": "delivered",
          "statusCode": 202,
          "attemptAt": "2026-10-03T11:36:05Z",
          "latencyMs": 184
        }
      ]
    }
  ],
  "nextCursor": null
}
```

---

## `POST /webhooks`

**Body:**

| Field | Required | Notes |
| --- | --- | --- |
| `name` | yes | |
| `url` | yes | `https://` only |
| `events` | yes | Non-empty subset of catalog |
| `description` | no | |

**Response:** created `Webhook` plus **one-time** `secret` (full value) for the operator to copy. Subsequent GETs only return `secretHint`.

```json
{
  "id": "wh_04",
  "name": "PagerDuty incidents",
  "url": "https://hooks.example.com/modus",
  "status": "active",
  "events": ["approval.escalated", "mcp.down"],
  "secretHint": "whsec_••••9f3a",
  "secret": "whsec_live_…full…",
  "description": "",
  "createdAt": "2026-10-03T21:00:00Z",
  "lastDeliveryAt": null,
  "successRatePct": 100,
  "recentDeliveries": []
}
```

UI create overlay does not show the secret yet — still return it for future “copy secret” UX / CLI.

---

## `PATCH /webhooks/{webhookId}`

Partial update. UI uses:

- `status`: `active` ↔ `paused` (Pause / Resume)
- `events`: full replacement array when toggling subscriptions

Also allow `name`, `url`, `description` for completeness.

**Rules:**

- Empty `events` → `400`
- Non-https `url` → `400`
- Setting `status: "failing"` from client → ignore or `400` (server-owned)

---

## `DELETE /webhooks/{webhookId}`

`204` on success. Stops future deliveries; historical delivery rows may be retained per retention policy.

---

## Delivery record (`WebhookDelivery`)

| Field | Type | Notes |
| --- | --- | --- |
| `id` | string | e.g. `del_01` |
| `event` | enum | Catalog key that triggered the POST |
| `status` | enum | `delivered` \| `failed` \| `pending` |
| `statusCode` | int \| null | HTTP status from subscriber |
| `attemptAt` | datetime | |
| `latencyMs` | int \| null | |

### Outbound POST (dispatch — backend worker)

When an event fires, for each **active** (non-paused) webhook whose `events` includes the key:

1. POST JSON to `url` with a signing header (e.g. `X-Modus-Signature` HMAC over body using webhook secret).
2. Suggested body envelope:

```json
{
  "id": "evt_…",
  "type": "approval.escalated",
  "createdAt": "2026-10-03T11:36:04Z",
  "orgId": "org_…",
  "data": {}
}
```

`data` is event-specific (ids + redacted context). Exact payload schemas can be versioned later; MVP may send minimal `{ type, createdAt, resourceId }`.

3. Record a `WebhookDelivery`. Retry with backoff on 5xx / network errors; mark webhook `failing` after N consecutive failures.
4. Do **not** deliver while `paused`.

---

## Errors

| Status | When |
| --- | --- |
| `400` | Invalid URL, empty events, unknown event key, illegal status |
| `401` / `403` | Auth / insufficient role |
| `404` | Unknown webhook |
| `409` | Optional: duplicate URL in org |
| `500` | Unexpected |

---

## Open questions for backend

1. Signing scheme: Stripe-style `t=,v1=` HMAC vs simple hex HMAC header?
2. Delivery retention window vs audit retention; include delivery body/response snippets?
3. Auto-`failing` threshold and auto-recovery to `active` after successes?
4. Should `decision.caution` fire on specialist caution only, or every caution audit row?
5. Fan-out ordering / max concurrency per org when many hooks subscribe to the same event?
6. SSRF protections on `url` (block private ranges, require public HTTPS)?
