-- Baza: commerce · schemat: warehouse
-- Magazyn: katalog produktów, stany, zamówienia zakupowe (purchase orders), historia ruchów magazynowych.
-- Źródło wymagań: contracts/warehouse-api.md, ADR 0001 (on_order), ui/ui-fields.md (pola reguł: sku, qty, delta, abs_delta, reason, vendor, total_eur, shop_location).
-- Konwencje: kwoty NUMERIC(12,2) + waluta ISO 4217 (bez floatów), kraje ISO 3166-1 alpha-2, czas TIMESTAMPTZ (UTC).

CREATE SCHEMA IF NOT EXISTS warehouse;

-- ---------------------------------------------------------------------------
-- Typy
-- ---------------------------------------------------------------------------

CREATE TYPE warehouse.po_status AS ENUM ('open', 'received', 'cancelled');

CREATE TYPE warehouse.movement_type AS ENUM (
  'receipt',        -- przyjęcie dostawy z purchase order (POST /purchase-orders/{id}/receive)
  'issue',          -- wydanie z magazynu
  'adjustment',     -- korekta ręczna (delta + reason)
  'scenario_reset'  -- POST /admin/scenarios/{id}/load
);

-- ---------------------------------------------------------------------------
-- Katalog produktów (SKU wspólne z marketplace)
-- ---------------------------------------------------------------------------

CREATE TABLE warehouse.products (
  sku               TEXT        PRIMARY KEY,
  name              TEXT        NOT NULL,
  unit              TEXT        NOT NULL,                     -- szt, karton, …
  reorder_threshold INTEGER     NOT NULL CHECK (reorder_threshold >= 0),
  target_level      INTEGER     NOT NULL CHECK (target_level > 0),
  max_order_qty     INTEGER     CHECK (max_order_qty > 0),    -- opcjonalny sufit dla polityk proxy (qty_ratio)
  active            BOOLEAN     NOT NULL DEFAULT TRUE,
  created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
  CHECK (target_level >= reorder_threshold)
);

-- Stan fizyczny. on_order NIE jest przechowywany — liczony z otwartych purchase orders (brak dryfu).
CREATE TABLE warehouse.stock_levels (
  sku        TEXT        PRIMARY KEY REFERENCES warehouse.products (sku) ON DELETE CASCADE,
  on_hand    INTEGER     NOT NULL DEFAULT 0 CHECK (on_hand >= 0),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ---------------------------------------------------------------------------
-- Dostawcy (sprzedawcy z marketplace) — profil do enrichmentu proxy (GET /merchants/{id})
-- Oferty każdego sklepu leżą w schemacie shops (jedna tabela na sklep).
-- ---------------------------------------------------------------------------

CREATE TABLE warehouse.suppliers (
  merchant_id          TEXT        PRIMARY KEY,               -- mer_biuromax
  name                 TEXT        NOT NULL,
  domain               TEXT        NOT NULL UNIQUE,
  country              CHAR(2)     NOT NULL CHECK (country ~ '^[A-Z]{2}$'),
  domain_registered_at DATE        NOT NULL,
  verified             BOOLEAN     NOT NULL DEFAULT FALSE,
  reputation_score     NUMERIC(3,2) CHECK (reputation_score BETWEEN 0 AND 1),  -- NULL = brak opinii
  reviews_count        INTEGER     NOT NULL DEFAULT 0 CHECK (reviews_count >= 0),
  offers_table         TEXT        NOT NULL UNIQUE,           -- np. 'shops.biuromax'
  scenario_id          TEXT,                                  -- NULL = katalog bazowy
  created_at           TIMESTAMPTZ NOT NULL DEFAULT now(),
  CHECK ((reputation_score IS NULL) = (reviews_count = 0))
);

-- ---------------------------------------------------------------------------
-- Purchase orders — rejestr zamówień złożonych w marketplace (POST /purchase-orders)
-- ---------------------------------------------------------------------------

CREATE TABLE warehouse.purchase_orders (
  id                   TEXT          PRIMARY KEY,             -- po_3b91
  sku                  TEXT          NOT NULL REFERENCES warehouse.products (sku),
  quantity             INTEGER       NOT NULL CHECK (quantity > 0),
  unit_price           NUMERIC(12,2) NOT NULL CHECK (unit_price >= 0),
  currency             CHAR(3)       NOT NULL CHECK (currency ~ '^[A-Z]{3}$'),
  total                NUMERIC(14,2) GENERATED ALWAYS AS (unit_price * quantity) STORED,
  total_eur            NUMERIC(14,2),                         -- przeliczenie dla reguł/budżetów (pole total_eur)
  status               warehouse.po_status NOT NULL DEFAULT 'open',
  marketplace_order_id TEXT          NOT NULL UNIQUE,         -- ord_8f2c
  merchant_id          TEXT          NOT NULL REFERENCES warehouse.suppliers (merchant_id),
  -- idempotencja: ten sam klucz + ten sam hash body → ten sam wynik; inny hash → 409 idempotency_conflict
  idempotency_key      UUID          NOT NULL UNIQUE,
  request_hash         TEXT          NOT NULL,
  -- korelacja z audytem proxy (nagłówki informacyjne)
  request_id           TEXT,                                  -- X-Request-Id
  on_behalf_of         TEXT,                                  -- X-On-Behalf-Of (agent_id)
  created_at           TIMESTAMPTZ   NOT NULL DEFAULT now(),
  received_at          TIMESTAMPTZ,
  cancelled_at         TIMESTAMPTZ,
  CHECK ((status = 'received') = (received_at IS NOT NULL)),
  CHECK ((status = 'cancelled') = (cancelled_at IS NOT NULL))
);

CREATE INDEX purchase_orders_sku_open_idx ON warehouse.purchase_orders (sku) WHERE status = 'open';
CREATE INDEX purchase_orders_sku_created_idx ON warehouse.purchase_orders (sku, created_at DESC);
CREATE INDEX purchase_orders_request_id_idx ON warehouse.purchase_orders (request_id);

-- ---------------------------------------------------------------------------
-- Historia ruchów magazynowych (append-only) — „historia transakcji” magazynu
-- ---------------------------------------------------------------------------

CREATE TABLE warehouse.stock_movements (
  id                BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  sku               TEXT        NOT NULL REFERENCES warehouse.products (sku),
  movement_type     warehouse.movement_type NOT NULL,
  delta             INTEGER     NOT NULL CHECK (delta <> 0 OR movement_type = 'scenario_reset'),
  on_hand_after     INTEGER     NOT NULL CHECK (on_hand_after >= 0),
  purchase_order_id TEXT        REFERENCES warehouse.purchase_orders (id),
  reason            TEXT,
  actor             TEXT        NOT NULL,                     -- operator / konto serwisowe / agent_id
  request_id        TEXT,                                     -- X-Request-Id
  created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
  CHECK ((movement_type = 'receipt') = (purchase_order_id IS NOT NULL)),
  CHECK (movement_type <> 'adjustment' OR reason IS NOT NULL)
);

CREATE INDEX stock_movements_sku_created_idx ON warehouse.stock_movements (sku, created_at DESC);

CREATE FUNCTION warehouse.forbid_mutation() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  RAISE EXCEPTION '% is append-only', TG_TABLE_NAME;
END $$;

CREATE TRIGGER stock_movements_append_only
  BEFORE UPDATE OR DELETE ON warehouse.stock_movements
  FOR EACH ROW EXECUTE FUNCTION warehouse.forbid_mutation();

-- ---------------------------------------------------------------------------
-- Widoki pod API
-- ---------------------------------------------------------------------------

-- Dostępność: on_hand + on_order (suma otwartych PO) + qty_needed.
CREATE VIEW warehouse.stock_availability AS
SELECT
  p.sku,
  p.name,
  p.unit,
  COALESCE(s.on_hand, 0)                                  AS on_hand,
  COALESCE(o.on_order, 0)                                 AS on_order,
  p.reorder_threshold,
  p.target_level,
  GREATEST(p.target_level - COALESCE(s.on_hand, 0) - COALESCE(o.on_order, 0), 0) AS qty_needed,
  o.last_order_at
FROM warehouse.products p
LEFT JOIN warehouse.stock_levels s ON s.sku = p.sku
LEFT JOIN (
  SELECT sku, SUM(quantity)::INTEGER AS on_order, MAX(created_at) AS last_order_at
  FROM warehouse.purchase_orders
  WHERE status = 'open'
  GROUP BY sku
) o ON o.sku = p.sku
WHERE p.active;

-- GET /low-stock: on_hand + on_order < reorder_threshold.
CREATE VIEW warehouse.low_stock AS
SELECT sku, name, unit, on_hand, on_order, reorder_threshold, target_level, qty_needed
FROM warehouse.stock_availability
WHERE on_hand + on_order < reorder_threshold;

-- ---------------------------------------------------------------------------
-- Operacje atomowe
-- ---------------------------------------------------------------------------

-- POST /purchase-orders/{id}/receive: status → received, on_hand += quantity, wpis w historii.
-- on_order spada automatycznie (widok liczy tylko otwarte PO).
CREATE FUNCTION warehouse.receive_purchase_order(p_id TEXT, p_actor TEXT, p_request_id TEXT DEFAULT NULL)
RETURNS warehouse.purchase_orders LANGUAGE plpgsql AS $$
DECLARE
  po        warehouse.purchase_orders;
  new_level INTEGER;
BEGIN
  UPDATE warehouse.purchase_orders
     SET status = 'received', received_at = now()
   WHERE id = p_id AND status = 'open'
  RETURNING * INTO po;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'purchase order % not found or not open', p_id;
  END IF;

  INSERT INTO warehouse.stock_levels AS s (sku, on_hand) VALUES (po.sku, po.quantity)
  ON CONFLICT (sku) DO UPDATE SET on_hand = s.on_hand + EXCLUDED.on_hand, updated_at = now()
  RETURNING s.on_hand INTO new_level;

  INSERT INTO warehouse.stock_movements (sku, movement_type, delta, on_hand_after, purchase_order_id, actor, request_id)
  VALUES (po.sku, 'receipt', po.quantity, new_level, po.id, p_actor, p_request_id);

  RETURN po;
END $$;
