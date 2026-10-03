-- Projekt AUDIT: schemat audit i uprawnienia
-- Wklej całość do Supabase → SQL Editor → Run.
BEGIN;

-- ===== audit/001_audit.sql =====
-- Baza: audit (osobna od commerce) · schemat: audit
-- Audit log działań agenta przechodzących przez proxy: decyzje pipeline'u, łańcuch decyzyjny, approvals (HITL),
-- limity, cykl życia akcji (statusy).
-- Źródło wymagań: architecture.md, ADR 0001–0005, ui/ui-fields.md (Overview, Approvals, Audit, Rate Limits).
-- Zasada: zdarzenia są append-only; zmiany statusu to nowe wiersze w action_status_history.
-- Konfiguracja (agenci, role, reguły, kwoty, MCP) żyje w konfiguracji proxy — tu tylko migawki potrzebne do audytu.

CREATE SCHEMA IF NOT EXISTS audit;

-- ---------------------------------------------------------------------------
-- Typy
-- ---------------------------------------------------------------------------

-- Decyzja proxy w nazewnictwie UI: ESCALATE = caution.
CREATE TYPE audit.decision AS ENUM ('allow', 'deny', 'caution', 'rate_limited');

-- Hop A = ruch do/z LLM (tylko obserwacja), hop B = wywołanie aplikacji (egzekwowanie) — ADR 0005.
CREATE TYPE audit.hop AS ENUM ('llm', 'app');
CREATE TYPE audit.protocol AS ENUM ('openai', 'rest', 'mcp', 'a2a');
CREATE TYPE audit.action_kind AS ENUM ('read', 'write');

-- Cykl życia akcji (co realnie stało się z requestem agenta).
CREATE TYPE audit.action_status AS ENUM (
  'observed',            -- hop A, tylko zapis do sesji
  'forwarded',           -- ALLOW → wysłane do upstreamu
  'executed',            -- upstream odpowiedział 2xx
  'upstream_error',      -- upstream 4xx/5xx / timeout
  'blocked',             -- automatyczny DENY → 403 blocked
  'rate_limited',        -- przekroczona kwota
  'pending_approval',    -- ESCALATE → 202
  'approved',            -- człowiek zatwierdził, czeka na wykonanie
  'rejected',            -- człowiek odrzucił (feedback do agenta)
  'expired',             -- timeout approvala
  'session_terminated',  -- limit odmów przekroczony
  'invalid'              -- walidacja / nieznana trasa / stream:true / auth
);

CREATE TYPE audit.chain_stage AS ENUM ('rbac', 'rules', 'specialist', 'human');
CREATE TYPE audit.session_status AS ENUM ('active', 'closed', 'terminated');
CREATE TYPE audit.approval_status AS ENUM ('pending', 'approved', 'rejected', 'expired', 'executed');

CREATE FUNCTION audit.forbid_mutation() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  RAISE EXCEPTION '% is append-only', TG_TABLE_NAME;
END $$;

-- ---------------------------------------------------------------------------
-- Sesje (ADR 0002, ADR 0004: jedna sesja = jedno zadanie, limit odmów)
-- ---------------------------------------------------------------------------

CREATE TABLE audit.sessions (
  session_id         UUID        PRIMARY KEY,
  agent_id           TEXT        NOT NULL,
  agent_name         TEXT        NOT NULL,                    -- migawka nazwy z momentu startu
  task               TEXT,                                    -- niezaufany kontekst od agenta
  status             audit.session_status NOT NULL DEFAULT 'active',
  denial_count       INTEGER     NOT NULL DEFAULT 0 CHECK (denial_count >= 0),
  denial_limit       INTEGER     NOT NULL DEFAULT 3,
  qty_needed         JSONB,                                   -- {sku: qty_needed} z GET /low-stock (grounding)
  seen_offer_ids     TEXT[]      NOT NULL DEFAULT '{}',       -- oferty widziane w /search (grounding)
  termination_reason TEXT,
  created_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
  ended_at           TIMESTAMPTZ,
  CHECK ((status = 'active') = (ended_at IS NULL))
);

CREATE INDEX sessions_agent_created_idx ON audit.sessions (agent_id, created_at DESC);

-- ---------------------------------------------------------------------------
-- Zdarzenia audytu — jedno na każdy request agenta przez proxy
-- ---------------------------------------------------------------------------

CREATE TABLE audit.events (
  id               UUID          PRIMARY KEY,               -- auditEventId
  decision_id      TEXT          NOT NULL UNIQUE,           -- zwracany agentowi
  request_id       TEXT          NOT NULL,                  -- X-Request-Id przekazywany do upstreamu
  occurred_at      TIMESTAMPTZ   NOT NULL DEFAULT now(),    -- timestamp w UI
  session_id       UUID          REFERENCES audit.sessions (session_id),
  agent_id         TEXT          NOT NULL,
  agent_name       TEXT          NOT NULL,
  -- co agent próbował zrobić (znormalizowane Action)
  hop              audit.hop      NOT NULL,
  protocol         audit.protocol NOT NULL,
  app              TEXT,                                    -- warehouse, marketplace, mcp server…
  tool             TEXT          NOT NULL,                  -- nazwa akcji z katalogu: place_order, search_products…
  kind             audit.action_kind,
  http_method      TEXT,
  path             TEXT,
  args_redacted    JSONB         NOT NULL DEFAULT '{}',     -- argsRedacted w UI
  request_hash     TEXT,                                    -- SHA-256 body (approval → wykonanie dokładnie tego requestu)
  -- decyzja
  decision         audit.decision,                          -- NULL dla hop A / błędów walidacji
  p_malicious      NUMERIC(5,4)  CHECK (p_malicious BETWEEN 0 AND 1),
  allow_prob       NUMERIC(5,4)  CHECK (allow_prob BETWEEN 0 AND 1),
  deny_prob        NUMERIC(5,4)  CHECK (deny_prob BETWEEN 0 AND 1),
  tau_low          NUMERIC(5,4),
  tau_high         NUMERIC(5,4),
  reason           TEXT,                                    -- pełne uzasadnienie (tylko dashboard)
  agent_message    TEXT,                                    -- ogólny komunikat widziany przez agenta
  matched_rules    TEXT[]        NOT NULL DEFAULT '{}',
  enrichment       JSONB         NOT NULL DEFAULT '{}',     -- country, domain_age_days, reputation, qty_ratio, price_vs_median…
  degraded         BOOLEAN       NOT NULL DEFAULT FALSE,    -- awaria komponentu → fail-open/closed (ADR 0005)
  -- rate limit
  quota_name       TEXT,
  retry_after_seconds INTEGER    CHECK (retry_after_seconds >= 0),
  -- odpowiedź
  http_status      SMALLINT,                                -- co dostał agent
  upstream_status  SMALLINT,                                -- co odpowiedział upstream
  latency_ms       INTEGER       CHECK (latency_ms >= 0),
  -- ponowne wykonanie po approve wskazuje na zdarzenie źródłowe
  parent_event_id  UUID          REFERENCES audit.events (id),
  CHECK ((decision = 'rate_limited') = (quota_name IS NOT NULL)),
  CHECK (hop = 'app' OR decision IS NULL OR decision IN ('allow', 'rate_limited'))  -- hop A nie blokuje (poza limitami)
);

CREATE INDEX events_occurred_idx       ON audit.events (occurred_at DESC);
CREATE INDEX events_agent_occurred_idx ON audit.events (agent_id, occurred_at DESC);
CREATE INDEX events_tool_occurred_idx  ON audit.events (tool, occurred_at DESC);
CREATE INDEX events_decision_idx       ON audit.events (decision, occurred_at DESC);
CREATE INDEX events_session_idx        ON audit.events (session_id, occurred_at);
CREATE INDEX events_request_id_idx     ON audit.events (request_id);

CREATE TRIGGER events_append_only
  BEFORE UPDATE OR DELETE ON audit.events
  FOR EACH ROW EXECUTE FUNCTION audit.forbid_mutation();

-- ---------------------------------------------------------------------------
-- Łańcuch decyzyjny (decisionChain w UI) + sygnały ML
-- ---------------------------------------------------------------------------

CREATE TABLE audit.decision_chain (
  event_id   UUID              NOT NULL REFERENCES audit.events (id),
  seq        SMALLINT          NOT NULL,
  stage      audit.chain_stage NOT NULL,
  outcome    TEXT              NOT NULL,                    -- pass / deny / needs_ai / clear / caution / approve / reject…
  detail     TEXT,
  specialist TEXT,                                          -- injection, malicious_code, mandate_alignment, merchant_fraud
  score      NUMERIC(5,4)      CHECK (score BETWEEN 0 AND 1),
  latency_ms INTEGER           CHECK (latency_ms >= 0),
  failed     BOOLEAN           NOT NULL DEFAULT FALSE,      -- specjalista nie odpowiedział
  PRIMARY KEY (event_id, seq),
  CHECK (stage <> 'specialist' OR specialist IS NOT NULL)
);

CREATE TRIGGER decision_chain_append_only
  BEFORE UPDATE OR DELETE ON audit.decision_chain
  FOR EACH ROW EXECUTE FUNCTION audit.forbid_mutation();

-- ---------------------------------------------------------------------------
-- Approvals / HITL (ADR 0004)
-- ---------------------------------------------------------------------------

CREATE TABLE audit.approvals (
  approval_id       UUID                  PRIMARY KEY,
  event_id          UUID                  NOT NULL UNIQUE REFERENCES audit.events (id),
  session_id        UUID                  NOT NULL REFERENCES audit.sessions (session_id),
  agent_id          TEXT                  NOT NULL,
  agent_name        TEXT                  NOT NULL,
  tool              TEXT                  NOT NULL,
  status            audit.approval_status NOT NULL DEFAULT 'pending',
  request_hash      TEXT                  NOT NULL,           -- approve wykonuje dokładnie ten request, raz
  model_choice      TEXT,                                     -- modelChoice w UI
  allow_prob        NUMERIC(5,4),
  deny_prob         NUMERIC(5,4),
  matched_rules     TEXT[]                NOT NULL DEFAULT '{}',
  args_redacted     JSONB                 NOT NULL DEFAULT '{}',
  ttl_seconds       INTEGER               NOT NULL DEFAULT 900 CHECK (ttl_seconds > 0),
  created_at        TIMESTAMPTZ           NOT NULL DEFAULT now(),
  expires_at        TIMESTAMPTZ           NOT NULL,
  decided_by        TEXT,                                     -- e-mail operatora
  decided_at        TIMESTAMPTZ,
  feedback          TEXT,                                     -- komentarz przy reject (trafia do agenta w całości)
  executed_at       TIMESTAMPTZ,
  execution_event_id UUID                 UNIQUE REFERENCES audit.events (id),  -- jednokrotne wykonanie
  CHECK (expires_at > created_at),
  CHECK ((status IN ('approved', 'rejected', 'executed')) = (decided_by IS NOT NULL)),
  CHECK ((status = 'executed') = (execution_event_id IS NOT NULL)),
  CHECK (feedback IS NULL OR status = 'rejected')
);

CREATE INDEX approvals_pending_idx ON audit.approvals (expires_at) WHERE status = 'pending';

-- Mutowalne tylko przejścia stanów zgodne z diagramem z ADR 0004.
CREATE FUNCTION audit.approvals_transition() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF TG_OP = 'DELETE' THEN
    RAISE EXCEPTION 'approvals cannot be deleted';
  END IF;
  IF NOT (
       (OLD.status = 'pending'  AND NEW.status IN ('approved', 'rejected', 'expired'))
    OR (OLD.status = 'approved' AND NEW.status = 'executed')
  ) THEN
    RAISE EXCEPTION 'illegal approval transition % → %', OLD.status, NEW.status;
  END IF;
  RETURN NEW;
END $$;

CREATE TRIGGER approvals_transition
  BEFORE UPDATE OR DELETE ON audit.approvals
  FOR EACH ROW EXECUTE FUNCTION audit.approvals_transition();

-- ---------------------------------------------------------------------------
-- Historia statusów akcji (append-only)
-- ---------------------------------------------------------------------------

CREATE TABLE audit.action_status_history (
  id         BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  event_id   UUID                NOT NULL REFERENCES audit.events (id),
  status     audit.action_status NOT NULL,
  actor      TEXT                NOT NULL,                  -- proxy / e-mail operatora / scheduler
  detail     TEXT,
  changed_at TIMESTAMPTZ         NOT NULL DEFAULT now()
);

CREATE INDEX action_status_history_event_idx ON audit.action_status_history (event_id, changed_at DESC, id DESC);

CREATE TRIGGER action_status_history_append_only
  BEFORE UPDATE OR DELETE ON audit.action_status_history
  FOR EACH ROW EXECUTE FUNCTION audit.forbid_mutation();

-- ---------------------------------------------------------------------------
-- Alerty dla dashboardu (np. session_terminated, degraded)
-- ---------------------------------------------------------------------------

CREATE TABLE audit.alerts (
  id              BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  kind            TEXT        NOT NULL,                     -- session_terminated, specialist_down, circuit_open…
  severity        TEXT        NOT NULL CHECK (severity IN ('info', 'warning', 'critical')),
  agent_id        TEXT,
  session_id      UUID        REFERENCES audit.sessions (session_id),
  event_id        UUID        REFERENCES audit.events (id),
  message         TEXT        NOT NULL,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  acknowledged_by TEXT,
  acknowledged_at TIMESTAMPTZ
);

-- ---------------------------------------------------------------------------
-- Widoki pod dashboard
-- ---------------------------------------------------------------------------

-- Lista/detal audytu z bieżącym statusem; pending = eskalacja bez decyzji człowieka (enum Decision w UI).
CREATE VIEW audit.events_current AS
SELECT
  e.*,
  s.status AS action_status,
  s.changed_at AS status_changed_at,
  CASE WHEN e.decision = 'caution' AND s.status = 'pending_approval' THEN 'pending'
       ELSE e.decision::TEXT END AS ui_decision
FROM audit.events e
LEFT JOIN LATERAL (
  SELECT h.status, h.changed_at
  FROM audit.action_status_history h
  WHERE h.event_id = e.id
  ORDER BY h.changed_at DESC, h.id DESC
  LIMIT 1
) s ON TRUE;

-- Overview: callsToday, decisionSplit, denyRatePct, cautionRatePct, rateLimitedToday, activeAgents.
CREATE VIEW audit.overview_today AS
SELECT
  COUNT(*)                                                       AS calls_today,
  COUNT(*) FILTER (WHERE decision = 'allow')                     AS allow_count,
  COUNT(*) FILTER (WHERE decision = 'deny')                      AS deny_count,
  COUNT(*) FILTER (WHERE decision = 'caution')                   AS caution_count,
  COUNT(*) FILTER (WHERE decision = 'rate_limited')              AS rate_limited_today,
  ROUND(100.0 * COUNT(*) FILTER (WHERE decision = 'deny')    / NULLIF(COUNT(*), 0), 1) AS deny_rate_pct,
  ROUND(100.0 * COUNT(*) FILTER (WHERE decision = 'caution') / NULLIF(COUNT(*), 0), 1) AS caution_rate_pct,
  COUNT(DISTINCT agent_id)                                       AS active_agents,
  (SELECT COUNT(*) FROM audit.approvals WHERE status = 'pending') AS pending_approvals
FROM audit.events
WHERE hop = 'app' AND occurred_at >= date_trunc('day', now());

-- ===== audit/002_supabase_grants.sql =====
-- Supabase: uprawnienia dla schematu audit (osobny projekt Supabase = osobna baza).
-- Wymaga też dodania schematu w Settings → API → Exposed schemas (inaczej PostgREST zwraca PGRST106).
-- Lokalnie (Supabase CLI): supabase/config.toml → [api] schemas = ["public", "graphql_public", "audit"].
-- Dostęp ma tylko service_role (proxy, backend dashboardu). Uprawnienia odzwierciedlają append-only.

GRANT USAGE ON SCHEMA audit TO service_role;

-- Zdarzenia, łańcuch decyzyjny i historia statusów: tylko odczyt i dopisywanie.
GRANT SELECT, INSERT ON audit.events, audit.decision_chain, audit.action_status_history TO service_role;
-- Stan zmienny: sesje (licznik odmów, zakończenie), approvals (przejścia pilnowane triggerem), alerty (potwierdzenie).
GRANT SELECT, INSERT, UPDATE ON audit.sessions, audit.approvals, audit.alerts TO service_role;
GRANT SELECT ON audit.events_current, audit.overview_today TO service_role;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA audit TO service_role;

REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA audit FROM PUBLIC;

ALTER TABLE audit.sessions              ENABLE ROW LEVEL SECURITY;
ALTER TABLE audit.events                ENABLE ROW LEVEL SECURITY;
ALTER TABLE audit.decision_chain        ENABLE ROW LEVEL SECURITY;
ALTER TABLE audit.approvals             ENABLE ROW LEVEL SECURITY;
ALTER TABLE audit.action_status_history ENABLE ROW LEVEL SECURITY;
ALTER TABLE audit.alerts                ENABLE ROW LEVEL SECURITY;

ALTER VIEW audit.events_current SET (security_invoker = true);
ALTER VIEW audit.overview_today SET (security_invoker = true);

NOTIFY pgrst, 'reload schema';
COMMIT;
