# MCP registry API contract

**Status:** draft (MVP scope locked below)  
**UI:** Org MCP catalog (`/mcp`) — [`src/pages/McpRegistryPage.tsx`](https://github.com/Mr-Engineers/one-frontend/blob/main/src/pages/McpRegistryPage.tsx); connect wizard [`ConnectMcpWizard.tsx`](https://github.com/Mr-Engineers/one-frontend/blob/main/src/components/mcp/ConnectMcpWizard.tsx); attach auth [`AttachMcpAuthFlow.tsx`](https://github.com/Mr-Engineers/one-frontend/blob/main/src/components/mcp/AttachMcpAuthFlow.tsx)  
**OpenAPI:** tag `MCP` in [`openapi/openapi.json`](https://github.com/Mr-Engineers/one-frontend/blob/main/openapi/openapi.json)  
**Auth:** Bearer (Supabase session), org/tenant scoped

Org-wide MCP catalog (remote URL or Modus-hosted adapter). Agents attach servers from this catalog (see [agents.md](./agents.md)).

Frontend calls `/api/mcp` → backend `/api/v1/mcp`.

Sample OpenAPI for UI testing: [`openapi/sample-commerce.openapi.json`](https://github.com/Mr-Engineers/one-frontend/blob/main/openapi/sample-commerce.openapi.json).

---

## MVP implementation scope

Backend must implement the **must-work** paths below. Everything else may return fixtures / `501` / static catalogs — the UI already has mock fallbacks for those.

| Surface | Backend | Notes |
| --- | --- | --- |
| **Remote connect + auth** | **Must work** | Discover remote MCP URL, detect `requiresAuth`, complete OAuth (or equivalent), register in catalog |
| **Hosted · `openapi`** | **Must work** | Accept uploaded OpenAPI JSON, map ops → proposed tools, provision adapter, register |
| Hosted · `rest` | Mock OK | UI keeps the card; discover/create may stub tool lists |
| Hosted · `database` | Mock OK | Same |
| Hosted · `package` | Mock OK | Same |
| Hosted · `template` | Mock OK | Same |
| `GET /mcp/hosted/source-options` | Static OK | May hardcode all five cards; OpenAPI card is the only real path |
| Catalog list/detail/patch | Should work | Needed so created servers appear in `/mcp` and agent attach |
| Per-agent attach OAuth | **Must work for remote** | `POST /agents/{id}/mcp/{serverId}/auth` — see [agents.md](./agents.md) |
| Hosted sync / remount | Later | Not in MVP UI |

### Wizard flow (what the UI actually does)

```
Connect MCP
├─ Remote
│  1. kind → remote_form (name + url)
│  2. POST /mcp/remote/discover
│  3. if requiresAuth → auth step (OAuth hop) → review
│  4. else → review
│  5. POST /mcp/remote  → catalog row (kind: remote)
│
└─ Hosted
   1. kind → hosted_source (source-options cards)
   2. hosted_form (name, auth-to-source, openapi file and/or base url)
   3. POST /mcp/hosted/discover
   4. hosted_tools (enable/edit descriptions)
   5. hosted_provision (client-side staged UI only)
   6. POST /mcp/hosted → catalog row (kind: hosted, url: modus://hosted/{slug})
```

Staged “discover / scan / provision” progress bars are **client-side animation**. Backend responses may be synchronous.

Today the remote OAuth hop in the wizard is still a **UI mock** (`mock oauth redirect`). Backend must return real `requiresAuth` + authorization URL / callback completion so the UI can wire a real browser hop. Per-agent attach auth (`AttachMcpAuthFlow`) has the same mock today and must become real for remote servers.

### Field name aliases (frontend OpenAPI today)

Machine schema in one-frontend currently uses shorter names. Backend should accept **either** the preferred names in this brief **or** the frontend aliases until OpenAPI is aligned:

| Preferred (this brief) | Frontend alias (`openapi.json` / wizard) |
| --- | --- |
| `baseUrl` | `url` |
| `authMethod` | `auth` |
| `specText` | `openApiText` |
| `specDocument` / `specUrl` | not sent yet — `openApiText` only |
| create `tools: [{ name, description, enabled }]` | `tools: string[]` + `toolDescriptions: { [name]: string }` |

---

## Endpoints

| Method | Path | MVP |
| --- | --- | --- |
| `GET` | `/mcp` | **Implement** — list catalog |
| `GET` | `/mcp/{serverId}` | **Implement** — detail |
| `PATCH` | `/mcp/{serverId}` | Nice — enable/disable / rename |
| `GET` | `/mcp/hosted/source-options` | Static OK |
| `POST` | `/mcp/remote/discover` | **Implement** |
| `POST` | `/mcp/remote` | **Implement** (incl. auth completion fields) |
| `POST` | `/mcp/hosted/discover` | **Implement for `source: openapi`**; other sources may stub |
| `POST` | `/mcp/hosted` | **Implement for `source: openapi`**; other sources may stub |
| `DELETE` | `/mcp/{serverId}` | Later (`501` OK; prefer disable) |

Agent attach OAuth: `POST /agents/{agentId}/mcp/{serverId}/auth` (agents contract) — **implement for remote**.

---

## `GET /mcp`

### Query parameters

| Param | Default | Purpose |
| --- | --- | --- |
| `kind` | `all` | `all` \| `remote` \| `hosted` |
| `health` | — | `healthy` \| `degraded` \| `down` \| `pending` |
| `search` | — | Name / url / description |
| `limit` | `100` | |
| `cursor` | — | |

### Server shape (`McpServer` / OpenAPI `Server`)

| Field | Type | Notes |
| --- | --- | --- |
| `id` | string | e.g. `mcp_shop` |
| `name` | string | |
| `kind` | enum | `remote` \| `hosted` |
| `protocol` | enum | `rest` \| `mcp` (OpenAPI schema; UI may ignore) |
| `url` | string | Remote SSE/MCP URL or `modus://hosted/...` |
| `health` | enum | `healthy` \| `degraded` \| `down` \| `pending` |
| `toolCount` | int | |
| `tools` | string[] | Declared tool names (enabled only) |
| `toolDetails` | array | Richer tool rows when available |
| `lastSyncAt` | datetime | |
| `requiresAuth` | boolean | Per-agent auth needed to attach |
| `description` | string | |
| `enabled` | boolean | |
| `hasPolicyPack` | boolean | |

```json
{
  "items": [
    {
      "id": "mcp_shop",
      "name": "Shop Catalog",
      "kind": "remote",
      "url": "https://mcp.shop.example/sse",
      "health": "healthy",
      "toolCount": 6,
      "tools": ["shop.search", "shop.checkout"],
      "lastSyncAt": "2026-10-03T11:40:00Z",
      "requiresAuth": true,
      "description": "Product search, cart, and checkout tools."
    }
  ],
  "nextCursor": null
}
```

---

## Remote connect wizard (**must work**, including auth)

### `POST /mcp/remote/discover`

Probe the remote MCP endpoint (`initialize` + `tools/list` or equivalent). Detect whether the provider requires OAuth before tools are usable.

**Body:** `{ "url": "https://...", "name"?: "..." }`

**Response:**

```json
{
  "name": "Shop Catalog",
  "url": "https://mcp.shop.example/sse",
  "requiresAuth": true,
  "tools": ["shop.ping", "shop.list"],
  "toolCount": 2,
  "description": "Discovered remote MCP at mcp.shop.example."
}
```

| Field | Notes |
| --- | --- |
| `requiresAuth` | When `true`, UI enters auth step before create |
| `tools` / `toolCount` | From live discovery when possible; empty tools + `requiresAuth: true` is OK if auth is required before `tools/list` |

UI shows staged progress client-side; backend may be synchronous for MVP.

### Remote auth (org-level during connect)

When discover returns `requiresAuth: true`:

1. UI starts authorization (today mocked; should become real browser redirect).
2. Backend should expose either:
   - **Option A (preferred):** discover/auth start returns `{ authorizationUrl, state }` (may be a dedicated `POST /mcp/remote/auth/start` or embedded in discover when auth is required), then create accepts the callback; or
   - **Option B:** create body carries `authCode` + `state` after the UI completes the hop.

Token storage: org/gateway secret for the catalog connection. Per-agent attach may still require its own OAuth (see agents contract) when `requiresAuth` remains true on the server row.

### `POST /mcp/remote`

**Body:**

```json
{
  "name": "Shop Catalog",
  "url": "https://mcp.shop.example/sse",
  "tools": ["shop.ping", "shop.list"],
  "requiresAuth": true,
  "description": "...",
  "authCode": "oauth-callback-code",
  "state": "..."
}
```

| Field | Required | Notes |
| --- | --- | --- |
| `name`, `url` | yes | |
| `tools` | no | From discover; omit/empty = backend re-lists after auth |
| `requiresAuth` | no | Echo from discover for persistence |
| `authCode` / `state` | when OAuth completed in wizard | |
| `description` | no | |

Frontend OpenAPI today only types `{ name, url, tools }` — accept extra auth fields without failing validation.

**Response:** full `McpServer` (`kind: remote`, `health` typically `healthy` or `pending`, `requiresAuth` reflecting whether agents still need their own attach auth).

---

## Hosted connect wizard

### `GET /mcp/hosted/source-options`

Static catalog for UI cards (mock/static is fine):

| `id` | MVP |
| --- | --- |
| `openapi` | **Real path** |
| `rest` | Mock OK |
| `database` | Mock OK |
| `package` | Mock OK |
| `template` | Mock OK |

Each: `{ id, label, blurb, urlPlaceholder }`.

For `openapi`, blurb/placeholder should describe **upload a spec + API base URL** (not “paste openapi.json URL” as the primary path).

Non-openapi sources: backend may return a canned proposed-tool list (or `501`); UI will still run the wizard UX.

---

### OpenAPI source (**must work** — primary hosted UX)

Operators upload an OpenAPI 3.x / Swagger **JSON** document. Backend maps each path+method into a proposed MCP tool. The UI then:

1. Groups tools by OpenAPI tag (`group`)
2. Shows **title** (summary) + **subtitle** (`METHOD /path`)
3. Lets operators expand **structure** (parameters, request body, responses)
4. Lets operators **edit AI-facing `description`** (what the model sees)
5. Lets operators **enable/disable** tools before provision

YAML upload is out of scope for MVP (JSON only).

**Backend responsibilities for `source: "openapi"`:**

| Requirement | Notes |
| --- | --- |
| Accept uploaded spec | Prefer JSON body field `specDocument` (parsed object) and/or `specText` / `openApiText` (raw JSON string). Optional `specUrl` to fetch when no upload. |
| Separate API base URL | `baseUrl` / `url` = where the adapter calls the customer API (from form or `servers[0].url`). Do **not** treat it as the OpenAPI document URL. |
| Map operations → tools | One tool per HTTP operation under `paths`. Stable `name` from `operationId` (preferred) or `slug.method.pathSegments`. |
| Risk classification | `GET/HEAD/OPTIONS` → `read`; `POST/PUT/PATCH` → `write`; `DELETE` or pay/refund/admin-like paths → `sensitive`. `defaultEnabled: true` only for `read`. |
| Return structure | Enough for the UI to show titles/subtitles/params without re-parsing the spec client-side after discover. |
| Persist AI descriptions | On create, store the **edited** description per enabled tool (not only the original OpenAPI text). Disabled tools are not exposed on the hosted MCP. |
| Spec retention | Store the uploaded/fetched document (or content hash) for later sync/diff. |
| Auth to source | Persist `authMethod` / `auth` (+ credentials when provided) so the adapter can call the customer API. |

Sample fixture for manual QA: [`sample-commerce.openapi.json`](https://github.com/Mr-Engineers/one-frontend/blob/main/openapi/sample-commerce.openapi.json).

---

### `POST /mcp/hosted/discover`

Scan a hosted source and return proposed tools. For OpenAPI, parse the uploaded/fetched document. **MVP: only `source: "openapi"` must be real.**

**Body (`HostedDiscoverRequest`):**

```json
{
  "source": "openapi",
  "name": "Acme Commerce",
  "baseUrl": "https://api.acme-internal.example/v2",
  "authMethod": "api_key",
  "specDocument": { "openapi": "3.0.3", "info": { "title": "..." }, "paths": {} },
  "specText": null,
  "specUrl": null,
  "specFileName": "sample-commerce.openapi.json"
}
```

Frontend alias body today:

```json
{
  "source": "openapi",
  "name": "Acme Commerce",
  "url": "https://api.acme-internal.example/v2",
  "auth": "api_key",
  "openApiText": "{ \"openapi\": \"3.0.3\", ... }"
}
```

| Field | Required | Notes |
| --- | --- | --- |
| `source` | yes | `rest` \| `openapi` \| `database` \| `package` \| `template` — only `openapi` must be implemented |
| `name` | no | Display name; used for slug hint |
| `baseUrl` / `url` | conditional | Required for non-openapi sources. For `openapi`, required unless spec has `servers[0].url` |
| `authMethod` / `auth` | no | `api_key` \| `oauth` \| `mtls` \| `none` |
| `specDocument` | openapi* | Parsed OpenAPI/Swagger JSON object |
| `specText` / `openApiText` | openapi* | Raw JSON string |
| `specUrl` | openapi* | Fetch remote OpenAPI JSON when no upload |
| `specFileName` | no | Original filename for audit/UI |

\*For `source: "openapi"`, at least one of `specDocument`, `specText`/`openApiText`, or `specUrl` is required. Missing spec → `400` (do not silently invent tools).

**Response (`HostedDiscoverResponse`):**

```json
{
  "name": "Acme Commerce",
  "source": "openapi",
  "baseUrl": "https://api.acme-internal.example/v2",
  "slug": "acme_commerce",
  "description": "Internal purchasing API for agents.",
  "requiresAuth": false,
  "specTitle": "Acme Commerce API",
  "specVersion": "2.1.0",
  "tools": [
    {
      "name": "acme_commerce.searchProducts",
      "risk": "read",
      "defaultEnabled": true,
      "title": "Search products",
      "subtitle": "GET /products",
      "group": "Catalog",
      "method": "GET",
      "path": "/products",
      "operationId": "searchProducts",
      "description": "Full-text and filter search across the approved catalog.",
      "originalDescription": "Full-text and filter search across the approved catalog. Prefer sku or vendor_id when known.",
      "parameters": [
        {
          "name": "q",
          "in": "query",
          "required": false,
          "schemaType": "string",
          "description": "Free-text query"
        }
      ],
      "requestBody": null,
      "responses": [
        { "status": "200", "description": "Product page" }
      ]
    },
    {
      "name": "acme_commerce.payInvoice",
      "risk": "sensitive",
      "defaultEnabled": false,
      "title": "Pay invoice",
      "subtitle": "POST /invoices/{invoice_id}/pay",
      "group": "Invoices",
      "method": "POST",
      "path": "/invoices/{invoice_id}/pay",
      "operationId": "payInvoice",
      "description": "Initiate payment for an open invoice.",
      "originalDescription": "Initiate payment for an open invoice. Money-moving — keep disabled unless authorized.",
      "parameters": [
        {
          "name": "invoice_id",
          "in": "path",
          "required": true,
          "schemaType": "string"
        }
      ],
      "requestBody": {
        "contentTypes": ["application/json"],
        "required": true,
        "summary": "Payment instruction"
      },
      "responses": [
        { "status": "202", "description": "Payment accepted" },
        { "status": "402", "description": "Payment failed" }
      ]
    }
  ]
}
```

#### `ProposedHostedTool` fields

| Field | Type | Notes |
| --- | --- | --- |
| `name` | string | Stable tool id exposed on the hosted MCP |
| `risk` | enum | `read` \| `write` \| `sensitive` |
| `description` | string | **AI-facing** text (seeded from OpenAPI; UI may edit before create) |
| `defaultEnabled` | boolean | UI checkbox default |
| `title` | string? | Human title (OpenAPI `summary`) |
| `subtitle` | string? | e.g. `GET /orders/{id}` |
| `group` | string? | OpenAPI tag / resource group |
| `method` | string? | HTTP method |
| `path` | string? | OpenAPI path template |
| `operationId` | string? | From spec when present |
| `originalDescription` | string? | Unedited OpenAPI description/summary |
| `parameters` | array? | `{ name, in, required, schemaType?, description? }` |
| `requestBody` | object\|null? | `{ contentTypes[], required, summary? }` |
| `responses` | array? | `{ status, description }` (short list ok) |

Non-openapi (mocked) sources may omit structure fields and return a smaller tool list (name/risk/description/defaultEnabled is enough).

---

### `POST /mcp/hosted`

Provision the hosted adapter and register it in the catalog. **MVP: only `source: "openapi"` must provision for real.** Only **enabled** tools become callable; store operator-edited descriptions.

**Body (`HostedCreateRequest`):**

```json
{
  "source": "openapi",
  "name": "Acme Commerce",
  "baseUrl": "https://api.acme-internal.example/v2",
  "slug": "acme_commerce",
  "authMethod": "api_key",
  "credentials": { "apiKey": "..." },
  "description": "Modus-hosted adapter from OpenAPI.",
  "specDocument": { "openapi": "3.0.3", "paths": {} },
  "specFileName": "sample-commerce.openapi.json",
  "tools": [
    {
      "name": "acme_commerce.searchProducts",
      "description": "Search the approved product catalog. Prefer sku when known.",
      "enabled": true
    },
    {
      "name": "acme_commerce.payInvoice",
      "description": "Pay an open invoice.",
      "enabled": false
    }
  ]
}
```

Frontend alias body today:

```json
{
  "name": "Acme Commerce",
  "source": "openapi",
  "url": "https://api.acme-internal.example/v2",
  "slug": "acme_commerce",
  "auth": "api_key",
  "tools": ["acme_commerce.searchProducts"],
  "toolDescriptions": {
    "acme_commerce.searchProducts": "Search the approved product catalog. Prefer sku when known."
  },
  "description": "Modus-hosted adapter from OpenAPI.",
  "openApiText": "{ ... }"
}
```

| Field | Required | Notes |
| --- | --- | --- |
| `source`, `name`, `baseUrl`/`url` | yes | |
| `slug` | no | Backend may derive if omitted |
| `tools` | yes | Either `string[]` of enabled names **or** `{ name, description, enabled }[]` |
| `toolDescriptions` | with string[] tools | Final AI description per enabled tool |
| `authMethod` / `auth` / `credentials` | no | Gateway auth to the customer API |
| `specDocument` / `specText` / `openApiText` / `specUrl` | openapi | Persist with the server for remount/sync |
| `description` | no | Server-level blurb |

**Response:** `McpServer` with `kind: "hosted"`, `url: "modus://hosted/{slug}"`, `tools` = enabled tool names only, `toolCount` = that length.

Provisioning may be async later (`202` + job id); wizard UI currently stages progress locally then registers.

---

## Errors

| Status | When |
| --- | --- |
| `400` | Bad URL / source / empty enabled tools / invalid OpenAPI JSON / missing spec for openapi |
| `401` / `403` | Auth |
| `404` | Unknown server |
| `409` | Duplicate URL/slug |
| `413` | Spec upload too large |
| `415` | Unsupported media (e.g. YAML-only upload) |
| `501` | Non-MVP hosted source (`rest` / `database` / `package` / `template`) if not stubbing |
| `502` | Discover/provision upstream failed (fetch `specUrl`, remote MCP unreachable, OAuth provider error) |
| `500` | Unexpected |

---

## Open questions for backend

1. Sync/refresh tools: `POST /mcp/{id}/sync` — re-parse stored OpenAPI, diff added/removed ops; not in UI yet.
2. OAuth for remote discover vs register vs per-agent attach — three surfaces; confirm token storage model (org vs agent). **MVP needs both org connect auth and per-agent attach auth for remote.**
3. Hosted provision async job vs sync response.
4. Soft-delete / detach-all-agents on catalog remove.
5. Max OpenAPI size / whether multipart upload is needed vs JSON body.
6. Whether disabled tools are retained server-side (for later re-enable) or dropped until next sync.
7. Align OpenAPI field names (`url`/`auth`/`openApiText` vs `baseUrl`/`authMethod`/`specText`) in one-frontend once backend picks a canonical shape.
