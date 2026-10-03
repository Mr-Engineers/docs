# API contracts (frontend → backend)

Human-readable page briefs for the Modus control-plane API (frontend → backend). Machine schemas live in [one-frontend `openapi/openapi.json`](https://github.com/Mr-Engineers/one-frontend/blob/main/openapi/openapi.json) — regenerate types there with `npm run api:generate`.

Paths below are relative to the client base `/api` (backend `/api/v1`).

| Page | Brief | Endpoints | Status |
| --- | --- | --- | --- |
| Overview | [overview.md](./overview.md) | `GET /overview` | draft |
| Agents | [agents.md](./agents.md) | `GET/PATCH /agents`, `GET /agents/{id}`, `POST …/revoke`, `GET …/overview`, `GET …/posture`, MCP attach/detach/auth, rules CRUD + meta + dry-run, quotas | draft |
| Approvals | [approvals.md](./approvals.md) | `GET /approvals`, `GET /approvals/{id}`, `POST …/allow`, `…/deny`, `…/allow-temporary` | draft |
| Audit | [audit.md](./audit.md) | `GET /audit`, `GET /audit/{id}` | draft |
| Specialists | [specialists.md](./specialists.md) | `GET /specialists`, `GET /specialists/{id}` | draft |
| Roles | [roles.md](./roles.md) | `GET /roles`, `GET/PATCH /roles/{id}`, `POST …/publish`, `…/archive` | draft |
| MCP | [mcp.md](./mcp.md) | `GET /mcp`, `GET /mcp/{id}`, remote/hosted discover + register, hosted source-options | draft |
| Settings | [settings.md](./settings.md) | `GET/PATCH /settings/workspace`, operators list/invite/resend/disable/enable | draft |
| Profile | [profile.md](./profile.md) | `GET /me` | draft |
| Simulator | [simulator.md](./simulator.md) | Proposed: scenarios + runs (UI stub; `501` until built) | draft |

**Status legend:** `draft` → proposed by frontend · `agreed` → backend accepted · `implemented` → live on API and wired in UI.

When adding a page: write `api/<page>.md` here first, then append paths/schemas to one-frontend `openapi/openapi.json` under a matching tag.

### Not an API page

| UI | Notes |
| --- | --- |
| Not found (`*`) | No backend contract |
| Rules / Rate limits | Nested under **Agents** (no standalone routes in `App.tsx`) |
| Login | Supabase Auth client; not `/api/v1` REST |
