# Architektura — przegląd

Proxy jest jedynym punktem wyjścia agenta. Każde wywołanie LLM, aplikacji, MCP i innych agentów przechodzi przez proxy, które podejmuje decyzję `ALLOW | ESCALATE | DENY` z poziomem pewności i uzasadnieniem.

## Komponenty

```mermaid
flowchart LR
  subgraph AZ["Strefa agenta · egress tylko do proxy"]
    A["purchasing-agent"]
  end

  subgraph PX["proxy-server"]
    direction TB
    AD["Adaptery<br/>LLM · REST · MCP · A2A"]
    AU["Auth + sesje"]
    PL["Pipeline decyzyjny"]
    AP["Approvals (HITL)"]
    AL["Audit log"]
    AD --> AU --> PL
    PL --> AP
    PL --> AL
  end

  subgraph UP["Upstreamy"]
    L["LLM<br/>vLLM / Ollama"]
    W["Magazyn"]
    M["Marketplace"]
  end

  H["Człowiek<br/>dashboard"]

  A --> AD
  PX --> L
  PX --> W
  PX --> M
  H <--> AP
```

## Pipeline decyzyjny

```mermaid
flowchart TB
  IN["Action<br/>{app, name, kind, args, session}"] --> V["1. Walidacja<br/>schemat, rozmiar"]
  V --> E["2. Enrichment<br/>kraj, wiek domeny, reputacja,<br/>cechy z sesji (qty_ratio, price_vs_median)"]
  E --> P{"3. Policy engine<br/>(Cedar)"}
  P -- "twarde DENY" --> D["DENY"]
  P -- "przepuszczone" --> ML["4. Sygnały ML (równolegle)<br/>injection · malicious code ·<br/>mandate alignment · merchant fraud"]
  ML --> AG{"5. Agregator<br/>P(malicious)"}
  AG -- "p < τ_low" --> OK["ALLOW"]
  AG -- "τ_low ≤ p < τ_high" --> ES["ESCALATE<br/>→ człowiek"]
  AG -- "p ≥ τ_high" --> D
  OK --> AU["Audit"]
  ES --> AU
  D --> AU
```

Progi `τ` konfigurowalne per typ akcji (`place_order` ostrzej niż `search`).

## Use case referencyjny — agent zakupowy

```mermaid
sequenceDiagram
  autonumber
  participant Agent as purchasing-agent
  participant Proxy as proxy-server
  participant LLM
  participant WH as Magazyn
  participant MP as Marketplace

  Agent->>Proxy: POST /v1/sessions
  Proxy-->>Agent: session_id
  Agent->>Proxy: GET /apps/warehouse/low-stock
  Proxy->>WH: GET /low-stock
  WH-->>Proxy: SKU poniżej progu
  Proxy-->>Agent: SKU poniżej progu (zapis qty_needed w sesji)
  Agent->>Proxy: POST /v1/chat/completions
  Proxy->>LLM: forward
  LLM-->>Proxy: plan
  Proxy-->>Agent: plan
  Agent->>Proxy: GET /apps/marketplace/search?q=…
  Proxy->>MP: GET /search
  MP-->>Proxy: oferty
  Proxy->>Proxy: skan indirect injection w ofertach
  Proxy-->>Agent: oferty (zapis widzianych ofert w sesji)
  Agent->>Proxy: POST /apps/marketplace/orders
  Proxy->>Proxy: pełny pipeline (grounding, polityki, ML, agregator)
  alt ALLOW
    Proxy->>MP: POST /orders
    MP-->>Proxy: order_id
    Proxy-->>Agent: 200
    Agent->>Proxy: POST /apps/warehouse/purchase-orders
    Proxy->>WH: POST /purchase-orders
  else ESCALATE
    Proxy-->>Agent: 202 pending_approval
  else DENY
    Proxy-->>Agent: 403 blocked
  end
```
