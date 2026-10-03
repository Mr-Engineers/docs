# Settings API contract

**Status:** draft  
**UI:** Workspace settings (`/settings`) — [`src/pages/SettingsPage.tsx`](https://github.com/Mr-Engineers/one-frontend/blob/main/src/pages/SettingsPage.tsx)  
**OpenAPI:** tag `Settings` in [`openapi/openapi.json`](https://github.com/Mr-Engineers/one-frontend/blob/main/openapi/openapi.json)  
**Auth:** Bearer (Supabase session), org/tenant scoped; mutate likely **admin/owner** only

Org preferences + invite-only operator roster. Agent API keys live under Agents → Keys (not here).

Frontend calls `/api/settings/...` → backend `/api/v1/settings/...`.

---

## Endpoints

| Method | Path | Purpose |
| --- | --- | --- |
| `GET` | `/settings/workspace` | Workspace preferences |
| `PATCH` | `/settings/workspace` | Update preferences |
| `GET` | `/settings/operators` | Operator roster |
| `POST` | `/settings/operators/invite` | Send invite |
| `POST` | `/settings/operators/{operatorId}/resend` | Resend invite |
| `POST` | `/settings/operators/{operatorId}/disable` | Disable account |
| `POST` | `/settings/operators/{operatorId}/enable` | Re-enable |

---

## Workspace

### Shape (`WorkspaceSettings`)

| Field | Type | Notes |
| --- | --- | --- |
| `orgName` | string | Shell / audit export display |
| `defaultApprovalTtlSeconds` | int | UI options: 300, 900, 1800, 3600 |
| `specialistFailClosed` | boolean | On AI failure: escalate (true) vs off |
| `auditRetentionDays` | int | UI options: 30, 90, 180, 365 |
| `authMode` | enum | MVP fixed: `invite_only` (read-only in UI) |

### `GET /settings/workspace`

Returns full object.

### `PATCH /settings/workspace`

Partial update. Ignore/`400` attempts to change `authMode` if locked.

```json
{
  "orgName": "Modus Demo",
  "defaultApprovalTtlSeconds": 900,
  "specialistFailClosed": true,
  "auditRetentionDays": 90
}
```

UI autosaves on control change (optimistic “Saved” flash).

---

## Operators

### Shape (`Operator`)

| Field | Type | Notes |
| --- | --- | --- |
| `id` | string | |
| `email` | string | |
| `name` | string | |
| `role` | enum | `owner` \| `admin` \| `operator` \| `viewer` |
| `status` | enum | `active` \| `invited` \| `disabled` |
| `invitedAt` | datetime | |
| `lastActiveAt` | datetime \| null | |

### `GET /settings/operators`

| Param | Default | Purpose |
| --- | --- | --- |
| `sort` | `invited` | `name` \| `email` \| `role` \| `status` \| `invited` \| `last_active` |
| `sort_dir` | `desc` | |
| `limit` | `100` | |
| `cursor` | — | |

### `POST /settings/operators/invite`

**Body:** `{ "email": "ops@company.com", "role": "operator" }`  
Invite roles (UI): `admin` \| `operator` \| `viewer` — not `owner`.

**Response:** created `Operator` with `status: "invited"`.

**Errors:** `409` if email already on roster; `400` if invalid email/role.

### Status actions

- **Resend** (invited only): refresh `invitedAt`, keep `invited`
- **Disable** (active non-owner): → `disabled`
- **Enable** (disabled): → `active`
- **Owner** row: no actions in UI

---

## Errors

| Status | When |
| --- | --- |
| `400` | Invalid TTL / retention / email / role |
| `401` / `403` | Auth / insufficient role |
| `404` | Unknown operator |
| `409` | Duplicate invite |
| `500` | Unexpected |

---

## Open questions for backend

1. Change operator role after invite (UI has no role edit yet).
2. Remove/revoke invite entirely vs disable.
3. Who may invite owners / transfer ownership?
4. Email delivery provider / invite accept URL shape (Supabase?).
