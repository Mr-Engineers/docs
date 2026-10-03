# Profile API contract

**Status:** draft  
**UI:** Profile (`/profile`) — [`src/pages/ProfilePage.tsx`](https://github.com/Mr-Engineers/one-frontend/blob/main/src/pages/ProfilePage.tsx)  
**OpenAPI:** tag `Profile` in [`openapi/openapi.json`](https://github.com/Mr-Engineers/one-frontend/blob/main/openapi/openapi.json)  
**Auth:** Bearer (Supabase session)

Shows the signed-in operator’s account + session + workspace roster membership. Sign-out is client-side Supabase (`signOut`); no backend logout endpoint required for MVP.

Today the page mixes Supabase `user`/`session` with mock `findOperatorByEmail` + `mockWorkspaceSettings`. Contract below is the backend piece to replace mocks.

Frontend calls `/api/me` → backend `/api/v1/me`.

---

## Endpoints

| Method | Path | Purpose |
| --- | --- | --- |
| `GET` | `/me` | Current operator + workspace snippet |

---

## `GET /me`

### Response

| Field | Type | Notes |
| --- | --- | --- |
| `userId` | string | Supabase user id (optional if email is enough) |
| `email` | string | |
| `name` | string | From operator roster or auth metadata |
| `avatarUrl` | string \| null | Optional |
| `authProvider` | string | e.g. `email`, `google` |
| `lastSignInAt` | datetime \| null | From auth |
| `sessionExpiresAt` | datetime \| null | Optional; UI can use JWT `expires_at` |
| `operator` | object \| null | Roster row if invited; else null |
| `workspace` | object | Minimal workspace info |

### `operator` (when on roster)

Same fields as Settings operator: `id`, `email`, `name`, `role`, `status`, `invitedAt`, `lastActiveAt`.

### `workspace`

| Field | Type |
| --- | --- |
| `orgName` | string |
| `authMode` | `invite_only` (MVP) |

```json
{
  "userId": "usr_...",
  "email": "kamil@modus.dev",
  "name": "Kamil Salamończyk",
  "avatarUrl": null,
  "authProvider": "email",
  "lastSignInAt": "2026-10-03T14:20:00Z",
  "sessionExpiresAt": "2026-10-03T18:20:00Z",
  "operator": {
    "id": "op_owner",
    "email": "kamil@modus.dev",
    "name": "Kamil Salamończyk",
    "role": "owner",
    "status": "active",
    "invitedAt": "2026-09-12T09:00:00Z",
    "lastActiveAt": "2026-10-03T14:20:00Z"
  },
  "workspace": {
    "orgName": "Modus Demo",
    "authMode": "invite_only"
  }
}
```

When `operator` is `null`, UI shows “signed in · not on workspace roster” and points to Settings.

---

## Errors

| Status | When |
| --- | --- |
| `401` | Missing/invalid session |
| `403` | Authenticated but org context missing (if multi-tenant) |
| `500` | Unexpected |

---

## Open questions for backend

1. Prefer `/me` vs `/profile` path naming — recommend `/me`.
2. Should `lastActiveAt` update on every authenticated request?
3. Profile edit (name/avatar) — not in UI; defer PATCH.
