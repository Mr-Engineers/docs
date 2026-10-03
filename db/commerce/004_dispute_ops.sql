-- Per-app schemas on Shopping-Warehouse Database
-- App A: Card Network Dispute Portal | App B: Case Desk

CREATE SCHEMA IF NOT EXISTS dispute_network;
CREATE SCHEMA IF NOT EXISTS dispute_case_desk;

CREATE TABLE IF NOT EXISTS dispute_network.merchants (
  id text PRIMARY KEY,
  dba_name text NOT NULL,
  legal_name text NOT NULL,
  country text NOT NULL DEFAULT '',
  acquirer_id text,
  trust_score numeric(3,2) NOT NULL DEFAULT 0,
  dispute_rate numeric(5,4) NOT NULL DEFAULT 0,
  review_count integer NOT NULL DEFAULT 0,
  mcc_primary text,
  first_seen_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS dispute_network.transactions (
  id text PRIMARY KEY,
  merchant_id text NOT NULL REFERENCES dispute_network.merchants(id),
  amount_eur numeric(12,2) NOT NULL,
  currency text NOT NULL DEFAULT 'EUR',
  mcc text,
  merchant_country text NOT NULL DEFAULT '',
  acquirer_country text NOT NULL DEFAULT '',
  auth_at timestamptz NOT NULL DEFAULT now(),
  card_last4 text NOT NULL,
  status text NOT NULL DEFAULT 'posted'
);

CREATE TABLE IF NOT EXISTS dispute_network.disputes (
  id text PRIMARY KEY,
  txn_id text NOT NULL REFERENCES dispute_network.transactions(id),
  reason_code text NOT NULL,
  status text NOT NULL DEFAULT 'open',
  representation_text text,
  evidence_urls text[] NOT NULL DEFAULT '{}',
  evidence_notes text[] NOT NULL DEFAULT '{}',
  opened_at timestamptz NOT NULL DEFAULT now(),
  closed_at timestamptz,
  close_rationale text
);

CREATE INDEX IF NOT EXISTS disputes_txn_id_idx ON dispute_network.disputes(txn_id);

CREATE TABLE IF NOT EXISTS dispute_case_desk.cases (
  id text PRIMARY KEY,
  txn_id text NOT NULL,
  customer_id text NOT NULL,
  status text NOT NULL DEFAULT 'open',
  fraud_score numeric(4,3) NOT NULL,
  customer_tier text NOT NULL DEFAULT 'standard',
  internal_notes text NOT NULL DEFAULT '',
  reason_code_internal text,
  attached_policies text[] NOT NULL DEFAULT '{}',
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS dispute_case_desk.refunds (
  id text PRIMARY KEY,
  case_id text NOT NULL REFERENCES dispute_case_desk.cases(id),
  amount_eur numeric(12,2) NOT NULL,
  kind text NOT NULL CHECK (kind IN ('provisional', 'final', 'clawback')),
  status text NOT NULL DEFAULT 'posted',
  posted_at timestamptz NOT NULL DEFAULT now(),
  idempotency_key text UNIQUE
);

CREATE TABLE IF NOT EXISTS dispute_case_desk.chargeback_intents (
  id text PRIMARY KEY,
  case_id text NOT NULL REFERENCES dispute_case_desk.cases(id),
  network_dispute_id text,
  reason_code text NOT NULL,
  evidence_note text,
  status text NOT NULL DEFAULT 'filed',
  filed_at timestamptz NOT NULL DEFAULT now(),
  idempotency_key text UNIQUE
);

CREATE TABLE IF NOT EXISTS dispute_case_desk.policy_docs (
  id text PRIMARY KEY,
  slug text NOT NULL UNIQUE,
  body text NOT NULL
);

CREATE TABLE IF NOT EXISTS dispute_case_desk.case_history (
  id bigserial PRIMARY KEY,
  case_id text NOT NULL REFERENCES dispute_case_desk.cases(id),
  event_type text NOT NULL,
  details jsonb NOT NULL DEFAULT '{}',
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS cases_txn_id_idx ON dispute_case_desk.cases(txn_id);
CREATE INDEX IF NOT EXISTS refunds_case_id_idx ON dispute_case_desk.refunds(case_id);

GRANT USAGE ON SCHEMA dispute_network TO anon, authenticated, service_role;
GRANT USAGE ON SCHEMA dispute_case_desk TO anon, authenticated, service_role;
GRANT ALL ON ALL TABLES IN SCHEMA dispute_network TO service_role;
GRANT ALL ON ALL TABLES IN SCHEMA dispute_case_desk TO service_role;
GRANT ALL ON ALL SEQUENCES IN SCHEMA dispute_case_desk TO service_role;
GRANT SELECT ON ALL TABLES IN SCHEMA dispute_network TO anon, authenticated;
GRANT SELECT ON ALL TABLES IN SCHEMA dispute_case_desk TO anon, authenticated;

ALTER TABLE dispute_network.merchants ENABLE ROW LEVEL SECURITY;
ALTER TABLE dispute_network.transactions ENABLE ROW LEVEL SECURITY;
ALTER TABLE dispute_network.disputes ENABLE ROW LEVEL SECURITY;
ALTER TABLE dispute_case_desk.cases ENABLE ROW LEVEL SECURITY;
ALTER TABLE dispute_case_desk.refunds ENABLE ROW LEVEL SECURITY;
ALTER TABLE dispute_case_desk.chargeback_intents ENABLE ROW LEVEL SECURITY;
ALTER TABLE dispute_case_desk.policy_docs ENABLE ROW LEVEL SECURITY;
ALTER TABLE dispute_case_desk.case_history ENABLE ROW LEVEL SECURITY;
