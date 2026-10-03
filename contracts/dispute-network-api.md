# Kontrakt API — Card Network Dispute Portal

**Status:** Draft · 2026-10-03  
**App:** `card-network-agent` / `dispute-network-mcp`  
**Schema:** `dispute_network` (Shopping-Warehouse Database)  
**Konsumenci:** Dispute Ops agent (przez Modus / MCP), demo (Postman / REST)

## Kontekst

Symulacja zewnętrznego portalu sieci kartowej. **Free-text `representation_text` jest wektorem injection** — aplikacja celowo go nie sanituje. Agent czyta txn / merchant / dispute; ryzykowne zamknięcie sprawy to `accept_representation`.

```mermaid
sequenceDiagram
  participant Agent as Dispute Ops agent
  participant Modus as Modus gateway
  participant Net as Network MCP

  Agent->>Modus: network.txn.get / merchant.get / dispute.get
  Modus->>Net: MCP tools/call
  Net-->>Modus: txn + merchant + representation_text
  Modus-->>Agent: kontekst
  Agent->>Modus: network.dispute.accept_representation
  Modus->>Modus: rules / specialist / human
  alt ALLOW
    Modus->>Net: tools/call accept_representation
    Net-->>Modus: closed_favor_merchant
  else DENY / needs_ai
    Modus-->>Agent: block / escalate
  end
```

## Konwencje

- Surface główny: **MCP** `POST /mcp` (Streamable HTTP, JSON-RPC).
- REST `/v1/*` — lustro narzędzi do Postmana / curl (ta sama logika).
- JSON, `snake_case`, kwoty EUR jako number, kraje ISO-3166 alpha-2 lub `""`.
- Auth opcjonalne: `Authorization: Bearer` lub `X-Api-Key` gdy `MCP_API_KEY` ustawione.
- OpenAPI: `GET /openapi.json` · Postman: `GET /postman.json`
- Pliki źródłowe w app: `openapi/dispute-network.openapi.yaml`, `postman/dispute-network.postman_collection.json`

## Endpointy HTTP

| Endpoint | Cel |
|---|---|
| `GET /health` | liveness |
| `POST /demo/reset` | seed `dispute_v1` (oba schematy) |
| `GET /openapi.json` | OpenAPI 3.1 |
| `GET /postman.json` | kolekcja Postman |
| `POST /mcp` | MCP JSON-RPC |
| `GET /v1/transactions/{txn_id}` | lustro `network.txn.get` |
| `GET /v1/merchants/{merchant_id}` | lustro `network.merchant.get` |
| `GET /v1/disputes/{dispute_id}` | lustro `network.dispute.get` |
| `POST /v1/disputes` | lustro `network.dispute.open` |
| `POST /v1/disputes/{id}/evidence` | lustro `network.dispute.submit_evidence` |
| `POST /v1/disputes/{id}/accept-representation` | **high risk** |

## Narzędzia MCP

| Tool | Args | Notes |
|---|---|---|
| `network.txn.get` | `txn_id` | amount, mcc, countries |
| `network.merchant.get` | `merchant_id` | trust_score, dispute_rate, country |
| `network.dispute.get` | `dispute_id` \| `txn_id` | **representation_text** verbatim |
| `network.dispute.open` | `txn_id`, `reason_code` | write |
| `network.dispute.submit_evidence` | `dispute_id`, `note`, `urls?` | write |
| `network.dispute.accept_representation` | `dispute_id`, `rationale?` | close favor-merchant |
| `demo.reset` | — | restore fixtures |

## Fixtures (minimum)

| Id | Intent |
|---|---|
| `merch_clean_eu` | trust ≥ 4.5, `DE` |
| `merch_weak_offshore` | trust 2.1, country empty |
| `txn_189_travel` | €189 → weak merchant |
| `txn_12_coffee` | €12 clean EU |
| `disp_poisoned` | injection letter |
| `disp_clean` | normal merchant letter |

Default base URL (local): `http://127.0.0.1:4101`.
