# Dispute Ops — OpenAPI & Postman

Machine-readable contracts for the two MCP apps in `card-network-agent`.

| File | App |
|---|---|
| `dispute-network.openapi.yaml` | Network Portal (`:4101`) |
| `dispute-case-desk.openapi.yaml` | Case Desk (`:4102`) |
| `dispute-ops.postman_collection.json` | **Combined** Postman (Network + Case Desk) |
| `MODUS_SETUP.md` | Modus roles / rule packs (not in DB) |

Human-readable:

- [dispute-network-api.md](../dispute-network-api.md)
- [dispute-case-desk-api.md](../dispute-case-desk-api.md)

## Postman

1. Import `dispute-ops.postman_collection.json` only
2. Start both apps (`:4101` / `:4102`)
3. **Shared → Demo reset**
4. Use **Network Portal** / **Case Desk** folders

Live: `GET /postman.json` on either server serves the same combined collection.
