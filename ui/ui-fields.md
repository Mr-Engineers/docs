# UI fields inventory (backend requirements)

Fields currently rendered in the frontend ([one-frontend](https://github.com/Mr-Engineers/one-frontend)). Property names match mock/API shapes in `src/mocks/`. Computed = derived in UI, still needed as inputs or as a dedicated API field.

---

## Overview

### Main view
- `callsToday`
- `callsDeltaPct` (±% vs yesterday)
- `pendingApprovals`
- `denyRatePct`
- `cautionRatePct`
- `rateLimitedToday`
- `activeAgents`
- `callsOverTime[].label`
- `callsOverTime[].count`
- `decisionSplit[].decision` (`allow` | `deny` | `caution` | `rate_limited`)
- `decisionSplit[].count`
- `agentSplit[].agentId`
- `agentSplit[].clear`
- `agentSplit[].caution`
- `budgets[].label`
- `budgets[].used`
- `budgets[].cap`
- `budgets[].unit`
- `topAgents[].name`
- `topAgents[].count`
- `topTools[].name`
- `topTools[].count`

---

## Agents

### List
- `name`
- `role`
- `status` (`active` | `revoked` | `disabled`)
- `apiKeyHint`
- `lastSeenAt`

### Detail
- `name`
- `role`
- `status`
- `lastSeenAt`
- `rateLimitOverride` (null → show “Org default”)
- `apiKeyHint`
- `createdAt`
- Connected MCP (via `mcpServerIds` → MCP registry):
  - `server.name`
  - `server.kind`
  - `server.toolCount`
  - `server.health`
- Attachable MCP picker:
  - `server.name`
  - `server.requiresAuth`

### Attach MCP auth flow
- `agent.name`
- `server.name`
- `server.url`
- `server.health`
- auth mode (UI: oauth when `requiresAuth`)

---

## Specialists

### List (cards)
- `name`
- `agentId`
- `version`
- `health` (`healthy` | `degraded` | `down` | `circuit_open`)
- `criteriaSummary`
- `latencyP95Ms`
- `errorRatePct`
- `evaluatesToday`
- Auto-cleared % (computed from `clearToday` / `cautionToday`)

### Detail
- `name`
- `version`
- `lastEvaluateAt`
- `agentId`
- `health`
- `loadedAt`
- `latencyP95Ms`
- `latencyBudgetMs`
- `errorRatePct`
- `falseClearRatePct`
- `evaluatesToday`
- `clearToday`
- `cautionToday`
- `onFailure` (currently `escalate_human`)
- `circuitBreaker.open`
- `circuitBreaker.failures`
- `circuitBreaker.threshold`
- `circuitBreaker.cooldownSeconds`
- `criteriaSummary`

> Note: `modelId` exists on the type but is not shown in the UI.

---

## Approvals

### List
- `tool`
- `agentName`
- `ageSeconds`
- `ttlSeconds`

### Detail
- `tool`
- `agentName`
- `ageSeconds`
- `modelChoice`
- `allowProb`
- `denyProb`
- `ttlSeconds`
- `matchedRules[]`
- `argsRedacted` (object, redacted JSON)

> Note: `specialist`, `agentId`, `createdAt` exist on the type but are not shown in the UI.

---

## Audit

### List
- `timestamp`
- `tool`
- `agentId` (badge; filter uses `agentName`)
- `decision` (`allow` | `deny` | `caution` | `rate_limited`)

### Detail
- `tool`
- `agentName`
- `timestamp`
- `decision`
- `agentId`
- `decisionChain[].stage` (`rbac` | `rules` | `specialist` | `human`)
- `decisionChain[].outcome`
- `decisionChain[].detail`
- `argsRedacted` (object, redacted JSON)

---

## Rules

### Pack list
- Filter: `agentId`
- `name`
- `activeVersion`
- Rule count (from active version `rules.length`)
- Pack status (from active version `status`: `draft` | `published` | `archived`)
- `agentId`

### Create pack wizard
- `name`
- `agentId`
- `description`

### Pack workspace / detail
- `name`
- `activeVersion`
- `versions[].version`
- `versions[].status`
- `agentId`
- `rules.length` (for selected version)
- `updatedAt`
- MCP filter chips: server name + rule count per MCP (resolved from rule `tool`)

### Rule table (inside pack)
- `name`
- MCP (resolved `server.name` from `tool`)
- `tool`
- `then` (`allow` | `deny` | `needs_ai`)

### Rule editor
- `name`
- MCP select (drives tool list)
- `tool`
- `when.combinator` (`and` | `or`)
- `when.children[].field`
- `when.children[].op`
- `when.children[].value` (when operator needs a value)
- Nested groups allowed under `when.children`
- `then`
- `enabled` (on rule model; editor focuses on the fields above)

### Dry-run samples
- `sample.label`
- `sample.tool`
- MCP (resolved from `sample.tool`)
- Evaluate outcome (computed)
- Matched rule `name` (computed)
- `sample.args` (JSON)

### Condition field catalog (needed for editor)
Fields used as `when.children[].field`:
- `shop_location`, `total_eur`, `vendor`, `qty`, `delta`, `abs_delta`, `reason`, `sku`, `priority`, `audience`

Each field def needs: `id`, `label`, `type` (`enum` | `number` | `text`), optional `options[]`, `tools[]` (tool globs).

---

## MCP Registry

### List
- Filter: `kind` (`remote` | `hosted`)
- `name`
- `kind`
- `toolCount`
- `health` (`healthy` | `degraded` | `down` | `pending`)

### Connect MCP wizard
- `kind` (remote vs hosted; hosted is placeholder)
- `name`
- `url`
- Discovery / review:
  - `name`
  - `url`
  - `toolCount`
  - `tools[]`
- Auth provider URL (from discovery)

### Not shown in list but used elsewhere
- `id`
- `requiresAuth`
- `description`
- `lastSyncAt`
- `tools[]`

---

## Rate Limits

### Overview strip (computed from quotas/hits)
- Blocked today (hit count)
- Exhausted count
- Tight count
- Org remaining (org daily quota)
- Agent override count

### Quota list
- `name`
- `scope` (`org` | `agent` | `tool`)
- `targetLabel`
- `window` (`1m` | `1h` | `1d`)
- `used`
- `cap`
- Remaining (computed: `cap - used`)
- Pressure status (computed from `enabled` + usage: Ok / Tight / Exhausted / Disabled)

### Recently blocked table
- `timestamp`
- `agentName`
- `tool`
- `quotaName`
- `retryAfterSeconds`
- Decision badge (fixed `rate_limited`)

### Quota detail / form
- `name`
- `scope`
- `targetLabel`
- `used` / `cap` / remaining / % used
- Pressure status
- `unit` (`calls`)
- `cap` (editable)
- `burst` (editable)
- `window` (editable)
- `enabled` (editable)
- `updatedAt`
- Related hits:
  - `tool`
  - `agentId`
  - `retryAfterSeconds`
  - `auditEventId` (link when present)

---

## Roles

### List
- `name`
- `status` (`active` | `draft` | `archived`)
- `agentIds[]` (assigned agents)
- Tools allowed (computed grant count)
- `updatedAt`

### Detail
- `name`
- `description`
- `status`
- `agentIds.length`
- Tools allowed (grant count)
- `createdAt`
- `updatedAt`
- Grants:
  - `grants[].serverName`
  - `grants[].serverWide`
  - `grants[].tools` (tool name → allow/deny boolean)
- Assigned agents:
  - `agent.name`
  - `agent.role`
  - `agent.id`
  - `agent.status`
- Effective allow-list (computed):
  - tool name
  - via (`Whole server` | `Single tool`)

---

## Settings

### Workspace settings
- `orgName`
- `authMode` (`invite_only`)
- `defaultApprovalTtlSeconds`
- `specialistFailClosed`
- `auditRetentionDays`

### Operators table
- `name`
- `email`
- `role` (`owner` | `admin` | `operator` | `viewer`)
- `status` (`active` | `invited` | `disabled`)
- `invitedAt`
- `lastActiveAt`

### Invite form
- email
- role (`admin` | `operator` | `viewer`)

---

## Profile

### Main view
- Display name (`user_metadata.full_name` / `name`, else email local-part)
- `email`
- Avatar URL (`user_metadata.avatar_url` / `picture`)
- Sign-in method (`app_metadata.provider`)
- `last_sign_in_at`
- Session `expires_at`
- Workspace `authMode`
- Workspace `orgName`
- Operator (when email matches roster):
  - `role`
  - `status`
  - `invitedAt`
  - `lastActiveAt`

---

## Auth / Login

### Form
- `email`
- `password`
- error message (on failure)

---

## Simulator

Stub — no data fields rendered.

---

## Quick enum reference

| Domain | Values |
| --- | --- |
| Agent status | `active`, `revoked`, `disabled` |
| Role status | `active`, `draft`, `archived` |
| Decision | `allow`, `deny`, `caution`, `rate_limited`, `pending` |
| Rule outcome | `allow`, `deny`, `needs_ai` |
| Rule pack version | `draft`, `published`, `archived` |
| MCP kind | `remote`, `hosted` |
| MCP / specialist health | `healthy`, `degraded`, `down`, (+ MCP `pending`, specialist `circuit_open`) |
| Quota scope | `org`, `agent`, `tool` |
| Quota window | `1m`, `1h`, `1d` |
| Operator role | `owner`, `admin`, `operator`, `viewer` |
| Operator status | `active`, `invited`, `disabled` |
| Decision chain stage | `rbac`, `rules`, `specialist`, `human` |
