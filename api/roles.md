# Roles API contract

**Status:** draft  
**UI:** Role grant templates (`/roles`, `/roles/:roleId`) — [`src/pages/RolesPage.tsx`](https://github.com/Mr-Engineers/one-frontend/blob/main/src/pages/RolesPage.tsx)  
**OpenAPI:** tag `Roles` in [`openapi/openapi.json`](https://github.com/Mr-Engineers/one-frontend/blob/main/openapi/openapi.json)  
**Auth:** Bearer (Supabase session), org/tenant scoped

Deny-by-default tool grant templates. Assigned agents are derived from `Agent.roleId` (bind on Agents page). MCP attach is per-agent; this page only edits which tools a template allows.

Deep-link only (not in side nav).

Frontend calls `/api/roles` → backend `/api/v1/roles`.

---

## Endpoints

| Method | Path | Purpose |
| --- | --- | --- |
| `GET` | `/roles` | List roles |
| `GET` | `/roles/{roleId}` | Detail + grants + assigned agents |
| `PATCH` | `/roles/{roleId}` | Update name/description/grants |
| `POST` | `/roles/{roleId}/publish` | `draft` → `active` |
| `POST` | `/roles/{roleId}/archive` | → `archived` |

Create-role wizard not in UI yet — open question.

---

## `GET /roles`

### Query parameters

| Param | Default | Purpose |
| --- | --- | --- |
| `search` | — | Match name / description |
| `status` | — | `active` \| `draft` \| `archived` |
| `sort` | `updated` | `name` \| `status` \| `agents` \| `grants` \| `updated` |
| `sort_dir` | `desc` | |
| `limit` | `50` | |
| `cursor` | — | |

### List item

| Field | Type | Notes |
| --- | --- | --- |
| `id` | string | |
| `name` | string | Slug-like display, e.g. `purchasing-operator` |
| `description` | string | |
| `status` | enum | `active` \| `draft` \| `archived` |
| `grantedToolCount` | int | Count of allowed tools |
| `assignedAgentIds` | string[] | Or `assignedAgents: { id, name }[]` |
| `createdAt` | datetime | |
| `updatedAt` | datetime | |

---

## `GET /roles/{roleId}`

### Role shape

| Field | Type |
| --- | --- |
| `id` | string |
| `name` | string |
| `description` | string |
| `status` | enum |
| `grants` | `ServerGrant[]` |
| `createdAt` / `updatedAt` | datetime |
| `assignedAgents` | `{ id, name, status }[]` |
| `effectiveTools` | `{ serverId, serverName, tool, via }[]` optional denorm |

### `ServerGrant`

| Field | Type | Notes |
| --- | --- | --- |
| `serverId` | string | Org MCP id |
| `serverName` | string | Display |
| `serverWide` | boolean | All tools on server |
| `tools` | `Record<string, boolean>` | Tool name → granted |

Everything starts denied; only `true` (or `serverWide`) is callable at RBAC.

```json
{
  "id": "role_purchasing_operator",
  "name": "purchasing-operator",
  "description": "Buy and checkout on Shop Catalog; notify Slack on escalations.",
  "status": "active",
  "grants": [
    {
      "serverId": "mcp_shop",
      "serverName": "Shop Catalog",
      "serverWide": true,
      "tools": {
        "shop.search": true,
        "shop.checkout": true
      }
    }
  ],
  "createdAt": "2026-09-01T09:00:00Z",
  "updatedAt": "2026-10-02T14:20:00Z",
  "assignedAgents": [
    { "id": "agt_purchasing_01", "name": "Purchasing", "status": "active" }
  ]
}
```

---

## `PATCH /roles/{roleId}`

**Body** (partial):

```json
{
  "name": "purchasing-operator",
  "description": "...",
  "grants": [
    {
      "serverId": "mcp_shop",
      "serverWide": false,
      "tools": { "shop.search": true, "shop.checkout": false }
    }
  ]
}
```

Archived roles: reject grant edits with `403`/`409`. UI disables checkboxes when archived.

When toggling tools, if all tools become true, set `serverWide: true` (UI does this).

---

## Publish / archive

- `POST /roles/{roleId}/publish` — only from `draft`
- `POST /roles/{roleId}/archive` — from `active` or `draft`; updates `updatedAt`

---

## Errors

| Status | When |
| --- | --- |
| `400` | Invalid grants (unknown server/tool) |
| `401` / `403` | Auth / archived edit |
| `404` | Unknown role |
| `409` | Invalid status transition |
| `500` | Unexpected |

---

## Open questions for backend

1. `POST /roles` create + which MCP servers appear in empty grant matrix (all org MCPs)?
2. Should grant matrix auto-expand when new tools appear on an MCP after sync?
3. Soft-delete vs archive only?
