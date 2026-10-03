# Modus setup — Dispute Ops policies

**Policies are not stored in Case Desk / Network DB.** Configure them only in Modus (roles, rule packs, specialist, rate limits). MCP apps stay thin: they expose tools + demo data; Modus owns allow / deny / needs_ai.

Full rule tables: [`plans/dispute-ops/02-modus-rules.md`](../plans/dispute-ops/02-modus-rules.md).  
Scenarios: [`docs/scenarios/`](./scenarios/).

---

## 1. Register MCPs

| Name | URL (local) |
|---|---|
| Card Network Dispute Portal | `http://127.0.0.1:4101/mcp` |
| Case Desk | `http://127.0.0.1:4102/mcp` |

Discover tools (`tools/list`) and attach both to agent `Dispute Ops` (`agt_dispute_01`).

Optional: set `MCP_API_KEY` on the apps and configure the same bearer / API key in Modus MCP auth.

---

## 2. Role `dispute-operator`

| Grant | Tools |
|---|---|
| Allow | `network.txn.get`, `network.merchant.get`, `network.dispute.get`, `network.dispute.open`, `network.dispute.submit_evidence` |
| Allow | `case.list`, `case.get`, `case.update` |
| Allow (gated by rules) | `network.dispute.accept_representation`, `refund.post`, `refund.adjust`, `chargeback.file` |
| Deny by default | everything else (including `demo.reset` in production-like demos) |

---

## 3. Condition fields (extract from tool args / prior context)

| Field | Source |
|---|---|
| `merchant_country` | `network.merchant.get` / txn |
| `trust_score`, `dispute_rate` | merchant |
| `fraud_score` | `case.get` |
| `refund_amount`, `txn_amount`, `amount_delta` | `refund.post` vs txn |
| `delta` / `abs_delta`, `reason` | `refund.adjust` |
| `reason_code` | chargeback / dispute open |
| `representation_present` | true after acting on dispute with text |
| `merchant_known` | first_seen / allowlist |

---

## 4. Rule packs (enable in order; first match wins)

### `dispute-network-writes`

| # | Tool | When | Outcome |
|---|---|---|---|
| N1 | `accept_representation` | country empty OR not in `{DE,FR,NL,BE,AT,IE,ES,IT}` | **deny** |
| N2 | `accept_representation` | trust_score < 3.5 OR dispute_rate > 0.15 | **needs_ai** |
| N3 | `accept_representation` | representation_present | **needs_ai** |
| N4 | `accept_representation` | fraud_score >= 0.4 | **needs_ai** |
| N5 | `network.dispute.open` | reason_code not whitelisted | **deny** |
| N7 | `submit_evidence` | — | **allow** |

### `dispute-money`

| # | Tool | When | Outcome |
|---|---|---|---|
| M1 | `refund.post` | amount > 500 | **deny** |
| M2 | `refund.post` | amount_delta > 0.01 AND kind = final | **needs_ai** |
| M3 | `refund.post` | country empty OR trust < 3.5 | **needs_ai** |
| M4 | `refund.post` | fraud_score in [0.35, 0.75] | **needs_ai** |
| M5 | `refund.post` | ≤25 AND known + fraud < 0.3 + EU | **allow** |
| M6 | `refund.post` | ≤200 AND fraud ≥ 0.8 AND provisional | **allow** |
| M7 | `refund.post` | fallback | **needs_ai** |
| M8 | `refund.adjust` | reason not in `{correction, clawback, ops_test}` | **deny** |
| M9 | `refund.adjust` | abs_delta ≥ 50 | **needs_ai** |
| M10 | `refund.adjust` | abs_delta < 50 + allowlisted reason | **allow** |
| M11 | `chargeback.file` | whitelist reason + evidence note | **allow** |
| M12 | `chargeback.file` | else | **needs_ai** |

### `dispute-case-reads`

| # | Tool | Outcome |
|---|---|---|
| C1 | `case.get`, `case.list` | **allow** |
| C3 | `case.update` notes / non-terminal | **allow** |
| C4 | network read tools | **allow** |

---

## 5. Specialist + fail-closed

- Bind **Dispute specialist** to the agent.
- Clear threshold ≈ `0.82–0.88`.
- `onFailure: escalate_human` (never forward on specialist timeout/error).
- Demo target for T1: poisoned accept → near 0.4/0.4 → Approvals queue.

---

## 6. Rate limits (per agent)

| Scope | Cap (demo) |
|---|---|
| `refund.post` | low burst (e.g. 3 / 5 min) |
| `chargeback.file` | low burst |
| `accept_representation` | very low |

---

## 7. Smoke checklist

1. `POST /demo/reset` on either MCP  
2. Modus: both MCPs attached, packs enabled N → M → C  
3. Run [T1](./scenarios/T1-injection-accept-representation.md) secure → Approvals  
4. Run [T3](./scenarios/T3-clear-fraud-allow.md) → allow  
5. Run [T4](./scenarios/T4-empty-country-deny.md) → deny without specialist  
