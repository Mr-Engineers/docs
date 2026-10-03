# Dokumentacja architektury

Diagramy w Mermaid — renderują się na GitHubie i w IDE (VS Code: rozszerzenie *Markdown Preview Mermaid Support*, JetBrains: wbudowane).

| Dokument | Zakres |
|---|---|
| [architecture.md](architecture.md) | przegląd systemu, przepływ ruchu, pipeline decyzyjny |
| [ADR 0001 — Adaptery protokołów](adr/0001-protocol-adapters.md) | adaptery REST/MCP/A2A, REST jako pierwszy, routing, katalog akcji, API magazynu i marketplace |
| [ADR 0002 — Tożsamość agenta i sesje](adr/0002-agent-identity-and-sessions.md) | `agent_key`, sesje wydawane przez proxy, limity per agent, OIDC na później |
| [ADR 0003 — Dostęp do aplikacji](adr/0003-upstream-access.md) | granice zaufania, poświadczenia upstreamów w proxy, izolacja sieciowa |
| [ADR 0004 — Odpowiedzi na decyzje i HITL](adr/0004-decision-outcomes-and-hitl.md) | co widzi agent, eskalacja z czekaniem w sesji, reject z komentarzem, limit odmów |
| [ADR 0005 — Egzekwowanie, streaming, awarie](adr/0005-enforcement-points-streaming-failure-modes.md) | blokowanie tylko na wywołaniu aplikacji, LLM tylko obserwowany, `stream: false`, fail-open dla odczytów / fail-closed dla zapisów |

## Kontrakty z zespołem magazyn/sklepy

| Dokument | Zakres |
|---|---|
| [Magazyn](contracts/warehouse-api.md) | `GET /low-stock`, `POST /purchase-orders`, endpointy demo, dane scenariuszy |
| [Marketplace](contracts/marketplace-api.md) | `GET /search`, `POST /orders`, `GET /offers/{id}` i `GET /merchants/{id}` (tylko proxy), dane scenariuszy |

## Bazy danych

| Dokument | Zakres |
|---|---|
| [Schematy baz](db/README.md) | `commerce` (`warehouse` + `shops`) i osobna baza `audit` — DDL PostgreSQL, dane demo |

## UI (one-frontend)

| Dokument | Zakres |
|---|---|
| [Pola UI / wymagania backendu](ui/ui-fields.md) | inwentarz pól per ekran (listy, detale, enumy) pod kontrakt API |

Roadmapa i statusy storek: [`../STORIES.md`](../STORIES.md).

## Format ADR

Każdy ADR: **Status**, **Kontekst**, **Decyzja**, **Konsekwencje**, **Rozważane alternatywy**. Zmiana decyzji = nowy ADR, który oznacza poprzedni jako `Zastąpiony przez`.
