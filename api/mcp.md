# MCP registry API contract

**Status:** draft  
**UI:** Org MCP catalog (`/mcp`) — [`src/pages/McpRegistryPage.tsx`](https://github.com/Mr-Engineers/one-frontend/blob/main/src/pages/McpRegistryPage.tsx); connect wizard [`ConnectMcpWizard.tsx`](https://github.com/Mr-Engineers/one-frontend/blob/main/src/components/mcp/ConnectMcpWizard.tsx); attach auth [`AttachMcpAuthFlow.tsx`](https://github.com/Mr-Engineers/one-frontend/blob/main/src/components/mcp/AttachMcpAuthFlow.tsx)  
**OpenAPI:** tag `MCP` in [`openapi/openapi.json`](https://github.com/Mr-Engineers/one-frontend/blob/main/openapi/openapi.json)  
**Auth:** Bearer (Supabase session), org/tenant scoped

Org-wide MCP catalog (remote URL or Modus-hosted adapter). Agents attach servers from this catalog (see [agents.md](./agents.md)).

Frontend calls `/api/mcp` → backend `/api/v1/mcp`.

Sample OpenAPI for UI testing: [`openapi/sample-commerce.openapi.json`](https://github.com/Mr-Engineers/one-frontend/blob/main/openapi/sample-commerce.openapi.json).

---

## Endpoints

| Method | Path | Purpose |
| --- | --- | --- |
| `GET` | `/mcp` | List catalog servers |
| `GET` | `/mcp/{serverId}` | Server detail |
| `GET` | `/mcp/hosted/source-options` | Hosted wizard source kinds (static ok) |
| `POST` | `/mcp/remote/discover` | Probe remote MCP URL → tools |
| `POST` | `/mcp/remote` | Register remote after discover (+ optional auth) |
| `POST` | `/mcp/hosted/discover` | Scan hosted source → proposed tools |
| `POST` | `/mcp/hosted` | Provision hosted adapter + register |
| `DELETE` | `/mcp/{serverId}` | Remove from catalog (not in UI yet) |

Agent attach OAuth: `POST /agents/{agentId}/mcp/{serverId}/auth` (agents contract).

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

### Server shape (`McpServer`)

| Field | Type | Notes |
| --- | --- | --- |
| `id` | string | e.g. `mcp_shop` |
| `name` | string | |
| `kind` | enum | `remote` \| `hosted` |
| `url` | string | Remote SSE/MCP URL or `modus://hosted/...` |
| `health` | enum | `healthy` \| `degraded` \| `down` \| `pending` |
| `toolCount` | int | |
| `tools` | string[] | Declared tool names (enabled only) |
| `lastSyncAt` | datetime | |
| `requiresAuth` | boolean | Per-agent auth needed to attach |
| `description` | string | |

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

## Remote connect wizard

### `POST /mcp/remote/discover`

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

UI shows staged progress client-side; backend may be synchronous for MVP.

### `POST /mcp/remote`

**Body:**

```json
{
  "name": "Shop Catalog",
  "url": "https://mcp.shop.example/sse",
  "tools": ["shop.ping", "shop.list"],
  "requiresAuth": true,
  "description": "...",
  "authCode"?: "oauth-callback-code",
  "state"?: "..."
}
```

**Response:** full `McpServer` (`kind: remote`, `health` typically `healthy` or `pending`).

---

## Hosted connect wizard

### `GET /mcp/hosted/source-options`

Static catalog for UI cards:

| `id` | label examples |
| --- | --- |
| `rest` | HTTP / REST API |
| `openapi` | OpenAPI / Swagger |
| `database` | Database |
| `package` | MCP package |
| `template` | Template |

Each: `{ id, label, blurb, urlPlaceholder }`.

For `openapi`, blurb/placeholder should describe **upload a spec + API base URL** (not “paste openapi.json URL” as the primary path).

---

### OpenAPI source (primary UX)

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
| Accept uploaded spec | Prefer JSON body field `specDocument` (parsed object) and/or `specText` (raw JSON string). Optional `specUrl` to fetch when no upload. |
| Separate API base URL | `baseUrl` = where the adapter calls the customer API (from form or `servers[0].url`). Do **not** treat `baseUrl` as the OpenAPI document URL. |
| Map operations → tools | One tool per HTTP operation under `paths`. Stable `name` from `operationId` (preferred) or `slug.method.pathSegments`. |
| Risk classification | `GET/HEAD/OPTIONS` → `read`; `POST/PUT/PATCH` → `write`; `DELETE` or pay/refund/admin-like paths → `sensitive`. `defaultEnabled: true` only for `read`. |
| Return structure | Enough for the UI to show titles/subtitles/params without re-parsing the spec client-side after discover. |
| Persist AI descriptions | On create, store the **edited** description per enabled tool (not only the original OpenAPI text). Disabled tools are not exposed on the hosted MCP. |
| Spec retention | Store the uploaded/fetched document (or content hash) for later sync/diff. |

Sample fixture for manual QA: [`sample-commerce.openapi.json`](https://github.com/Mr-Engineers/one-frontend/blob/main/openapi/sample-commerce.openapi.json).

---

### `POST /mcp/hosted/discover`

Scan a hosted source and return proposed tools. For OpenAPI, parse the uploaded/fetched document.

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

| Field | Required | Notes |
| --- | --- | --- |
| `source` | yes | `rest` \| `openapi` \| `database` \| `package` \| `template` |
| `name` | no | Display name; used for slug hint |
| `baseUrl` | conditional | Required for non-openapi sources. For `openapi`, required unless `specDocument`/`specText` has `servers[0].url` |
| `authMethod` | no | `api_key` \| `oauth` \| `mtls` \| `none` |
| `specDocument` | openapi* | Parsed OpenAPI/Swagger JSON object |
| `specText` | openapi* | Raw JSON string (alternative to `specDocument`) |
| `specUrl` | openapi* | Fetch remote OpenAPI JSON when no upload |
| `specFileName` | no | Original filename for audit/UI |

\*For `source: "openapi"`, at least one of `specDocument`, `specText`, or `specUrl` is required.

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

Non-openapi sources may omit structure fields and return a smaller tool list (name/risk/description/defaultEnabled is enough).

---

### `POST /mcp/hosted`

Provision the hosted adapter and register it in the catalog. Only **enabled** tools become callable; store operator-edited descriptions.

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

| Field | Required | Notes |
| --- | --- | --- |
| `source`, `name`, `baseUrl`, `slug` | yes | |
| `tools` | yes | Full selection from the review step |
| `tools[].name` | yes | Must match a discovered tool |
| `tools[].description` | yes | Final AI description to publish |
| `tools[].enabled` | yes | `false` = not exposed on the MCP |
| `authMethod` / `credentials` | no | Gateway auth to the customer API |
| `specDocument` / `specText` / `specUrl` | openapi | Persist with the server for remount/sync |
| `description` | no | Server-level blurb |

**Backward-compatible alternative (not preferred):** `enabledTools: string[]` plus `toolDescriptions: { [name]: string }`. Prefer the `tools[]` array so enablement and AI text travel together.

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
| `502` | Discover/provision upstream failed (fetch `specUrl`, reachability) |
| `500` | Unexpected |

---

## Open questions for backend

1. Sync/refresh tools: `POST /mcp/{id}/sync` — re-parse stored OpenAPI, diff added/removed ops; not in UI yet.
2. OAuth for remote discover vs register vs per-agent attach — three surfaces; confirm token storage model (org vs agent).
3. Hosted provision async job vs sync response.
4. Soft-delete / detach-all-agents on catalog remove.
5. Max OpenAPI size / whether multipart upload is needed vs JSON body.
6. Whether disabled tools are retained server-side (for later re-enable) or dropped until next sync.
