# MCP registry API contract

**Status:** draft  
**UI:** Org MCP catalog (`/mcp`) — [`src/pages/McpRegistryPage.tsx`](https://github.com/Mr-Engineers/one-frontend/blob/main/src/pages/McpRegistryPage.tsx); connect wizard [`ConnectMcpWizard.tsx`](https://github.com/Mr-Engineers/one-frontend/blob/main/src/components/mcp/ConnectMcpWizard.tsx); attach auth [`AttachMcpAuthFlow.tsx`](https://github.com/Mr-Engineers/one-frontend/blob/main/src/components/mcp/AttachMcpAuthFlow.tsx)  
**OpenAPI:** tag `MCP` in [`openapi/openapi.json`](https://github.com/Mr-Engineers/one-frontend/blob/main/openapi/openapi.json)  
**Auth:** Bearer (Supabase session), org/tenant scoped

Org-wide MCP catalog (remote URL or Modus-hosted adapter). Agents attach servers from this catalog (see [agents.md](./agents.md)).

Frontend calls `/api/mcp` → backend `/api/v1/mcp`.

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
| `tools` | string[] | Declared tool names |
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

### `POST /mcp/hosted/discover`

**Body:**

```json
{
  "source": "openapi",
  "name": "ERP",
  "baseUrl": "https://api.example.com/openapi.json",
  "authMethod": "api_key"
}
```

`authMethod`: `api_key` \| `oauth` \| `mtls` \| `none`.

**Response:**

```json
{
  "name": "ERP",
  "source": "openapi",
  "baseUrl": "https://api.example.com/openapi.json",
  "slug": "erp",
  "description": "Modus-hosted adapter for openapi / swagger.",
  "requiresAuth": false,
  "tools": [
    {
      "name": "erp.orders.list",
      "risk": "read",
      "description": "GET /orders",
      "defaultEnabled": true
    }
  ]
}
```

`risk`: `read` \| `write` \| `sensitive`.

### `POST /mcp/hosted`

**Body:**

```json
{
  "source": "openapi",
  "name": "ERP",
  "baseUrl": "https://api.example.com/openapi.json",
  "slug": "erp",
  "authMethod": "api_key",
  "credentials"?: { "apiKey": "..." },
  "enabledTools": ["erp.orders.list", "erp.orders.get"],
  "description": "..."
}
```

**Response:** `McpServer` with `kind: "hosted"`, `url: "modus://hosted/{slug}"`.

Provisioning may be async later (`202` + job id); wizard UI currently stages progress locally then registers.

---

## Errors

| Status | When |
| --- | --- |
| `400` | Bad URL / source / empty tools |
| `401` / `403` | Auth |
| `404` | Unknown server |
| `409` | Duplicate URL/slug |
| `502` | Discover/provision upstream failed |
| `500` | Unexpected |

---

## Open questions for backend

1. Sync/refresh tools: `POST /mcp/{id}/sync` — not in UI yet.
2. OAuth for remote discover vs register vs per-agent attach — three surfaces; confirm token storage model (org vs agent).
3. Hosted provision async job vs sync response.
4. Soft-delete / detach-all-agents on catalog remove.
