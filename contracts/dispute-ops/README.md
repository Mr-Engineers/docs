# Dispute Ops — OpenAPI & Postman

Machine-readable contracts for the two MCP apps:

- Case Desk → [`case-desk-agent`](../../../case-desk-agent/) (canonical TS app)
- Network Portal → [`card-network-agent`](../../../card-network-agent/)

Keep these files in sync with `case-desk-agent/openapi|postman` and `card-network-agent/openapi|postman`.

| File | App | Port |
|---|---|---|
| `dispute-network.openapi.yaml` | Network Portal | `4101` |
| `dispute-case-desk.openapi.yaml` | Case Desk | `4102` |
| `dispute-network.postman_collection.json` | Network Postman | |
| `dispute-case-desk.postman_collection.json` | Case Desk Postman | |
| `dispute-ops.postman_environment.json` | Local env (`4101` / `4102`) | |

Human-readable:

- [dispute-network-api.md](../dispute-network-api.md)
- [dispute-case-desk-api.md](../dispute-case-desk-api.md)

## How to use

### 1. Run the apps

```bash
# Case Desk (canonical)
cd case-desk-agent
cp .env.example .env   # DATABASE_URL
npm install && npm run seed && npm run start   # :4102

# Network Portal (sibling)
cd ../card-network-agent
npm run start:network      # :4101
```

### 2. Live docs from the server

With Case Desk running:

| URL | Content |
|---|---|
| `GET http://127.0.0.1:4102/openapi.json` | OpenAPI JSON |
| `GET http://127.0.0.1:4102/openapi.yaml` | OpenAPI YAML |
| `GET http://127.0.0.1:4102/postman.json` | Postman collection |

Same paths on `:4101` for Network Portal.

### 3. Postman

1. Import `dispute-case-desk.postman_collection.json`
2. Import `dispute-ops.postman_environment.json` and activate it
3. **Ops → Demo reset**
4. **REST mirrors → GET case_189_unrecognized**
5. Try **POST provisional refund** / **POST chargeback.file**
6. If `.env` has `MCP_API_KEY`, set collection/env variable `apiKey`

Prefer **REST mirrors** for manual smoke tests. Use the **MCP** folder when you need Modus-shaped `tools/call` payloads against `POST /mcp`.

### 4. curl smoke (Case Desk)

```bash
curl http://127.0.0.1:4102/health
curl -X POST http://127.0.0.1:4102/demo/reset
curl http://127.0.0.1:4102/v1/cases/case_189_unrecognized
```

### 5. Modus

Register `http://127.0.0.1:4102/mcp` as **Case Desk** and `http://127.0.0.1:4101/mcp` as **Card Network Dispute Portal**.
