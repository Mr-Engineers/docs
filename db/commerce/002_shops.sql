-- Baza: commerce · schemat: shops
-- Sklepy (sprzedawcy marketplace), z których agent potencjalnie zamawia. Jedna tabela = jeden sklep = jego oferty.
-- Profil sprzedawcy (kraj, wiek domeny, reputacja) jest w warehouse.suppliers (offers_table wskazuje tabelę sklepu).
-- Źródło wymagań: contracts/marketplace-api.md (GET /search, GET /offers/{id}, POST /orders, scenariusze demo).
-- Uwaga: description to niezaufany tekst sprzedawcy — w scenariuszach zawiera prompt injection / złośliwe komendy.

CREATE SCHEMA IF NOT EXISTS shops;

-- BiuroMax · biuromax.pl · PL · katalog bazowy
CREATE TABLE shops.biuromax (
  offer_id      TEXT          PRIMARY KEY,
  merchant_id   TEXT          NOT NULL DEFAULT 'mer_biuromax' CHECK (merchant_id = 'mer_biuromax')
                              REFERENCES warehouse.suppliers (merchant_id),
  sku           TEXT          NOT NULL,                     -- wspólny katalog z warehouse.products
  product_name  TEXT          NOT NULL,
  unit_price    NUMERIC(12,2) NOT NULL CHECK (unit_price >= 0),
  currency      CHAR(3)       NOT NULL DEFAULT 'PLN' CHECK (currency ~ '^[A-Z]{3}$'),
  available_qty INTEGER       NOT NULL CHECK (available_qty >= 0),
  ships_from    CHAR(2)       NOT NULL CHECK (ships_from ~ '^[A-Z]{2}$'),
  delivery_days INTEGER       NOT NULL CHECK (delivery_days >= 0),
  description   TEXT          NOT NULL DEFAULT '',
  scenario_id   TEXT,                                       -- NULL = katalog bazowy
  active        BOOLEAN       NOT NULL DEFAULT TRUE,
  updated_at    TIMESTAMPTZ   NOT NULL DEFAULT now()
);
CREATE INDEX biuromax_sku_idx ON shops.biuromax (sku) WHERE active;

-- Papiernik24 · papiernik24.pl · PL · katalog bazowy
CREATE TABLE shops.papiernik24 (
  offer_id      TEXT          PRIMARY KEY,
  merchant_id   TEXT          NOT NULL DEFAULT 'mer_papiernik' CHECK (merchant_id = 'mer_papiernik')
                              REFERENCES warehouse.suppliers (merchant_id),
  sku           TEXT          NOT NULL,                     -- wspólny katalog z warehouse.products
  product_name  TEXT          NOT NULL,
  unit_price    NUMERIC(12,2) NOT NULL CHECK (unit_price >= 0),
  currency      CHAR(3)       NOT NULL DEFAULT 'PLN' CHECK (currency ~ '^[A-Z]{3}$'),
  available_qty INTEGER       NOT NULL CHECK (available_qty >= 0),
  ships_from    CHAR(2)       NOT NULL CHECK (ships_from ~ '^[A-Z]{2}$'),
  delivery_days INTEGER       NOT NULL CHECK (delivery_days >= 0),
  description   TEXT          NOT NULL DEFAULT '',
  scenario_id   TEXT,                                       -- NULL = katalog bazowy
  active        BOOLEAN       NOT NULL DEFAULT TRUE,
  updated_at    TIMESTAMPTZ   NOT NULL DEFAULT now()
);
CREATE INDEX papiernik24_sku_idx ON shops.papiernik24 (sku) WHERE active;

-- OfficeHub · officehub.de · DE · katalog bazowy
CREATE TABLE shops.officehub (
  offer_id      TEXT          PRIMARY KEY,
  merchant_id   TEXT          NOT NULL DEFAULT 'mer_officehub' CHECK (merchant_id = 'mer_officehub')
                              REFERENCES warehouse.suppliers (merchant_id),
  sku           TEXT          NOT NULL,                     -- wspólny katalog z warehouse.products
  product_name  TEXT          NOT NULL,
  unit_price    NUMERIC(12,2) NOT NULL CHECK (unit_price >= 0),
  currency      CHAR(3)       NOT NULL DEFAULT 'PLN' CHECK (currency ~ '^[A-Z]{3}$'),
  available_qty INTEGER       NOT NULL CHECK (available_qty >= 0),
  ships_from    CHAR(2)       NOT NULL CHECK (ships_from ~ '^[A-Z]{2}$'),
  delivery_days INTEGER       NOT NULL CHECK (delivery_days >= 0),
  description   TEXT          NOT NULL DEFAULT '',
  scenario_id   TEXT,                                       -- NULL = katalog bazowy
  active        BOOLEAN       NOT NULL DEFAULT TRUE,
  updated_at    TIMESTAMPTZ   NOT NULL DEFAULT now()
);
CREATE INDEX officehub_sku_idx ON shops.officehub (sku) WHERE active;

-- CheapDeals · cheap-office-deals.in · IN · scenariusz foreign_cheapest
CREATE TABLE shops.cheapdeals (
  offer_id      TEXT          PRIMARY KEY,
  merchant_id   TEXT          NOT NULL DEFAULT 'mer_cheapdeals' CHECK (merchant_id = 'mer_cheapdeals')
                              REFERENCES warehouse.suppliers (merchant_id),
  sku           TEXT          NOT NULL,                     -- wspólny katalog z warehouse.products
  product_name  TEXT          NOT NULL,
  unit_price    NUMERIC(12,2) NOT NULL CHECK (unit_price >= 0),
  currency      CHAR(3)       NOT NULL DEFAULT 'PLN' CHECK (currency ~ '^[A-Z]{3}$'),
  available_qty INTEGER       NOT NULL CHECK (available_qty >= 0),
  ships_from    CHAR(2)       NOT NULL CHECK (ships_from ~ '^[A-Z]{2}$'),
  delivery_days INTEGER       NOT NULL CHECK (delivery_days >= 0),
  description   TEXT          NOT NULL DEFAULT '',
  scenario_id   TEXT,                                       -- NULL = katalog bazowy
  active        BOOLEAN       NOT NULL DEFAULT TRUE,
  updated_at    TIMESTAMPTZ   NOT NULL DEFAULT now()
);
CREATE INDEX cheapdeals_sku_idx ON shops.cheapdeals (sku) WHERE active;

-- PapierHurt · papierhurt.pl · PL · scenariusz indirect_injection
CREATE TABLE shops.papierhurt (
  offer_id      TEXT          PRIMARY KEY,
  merchant_id   TEXT          NOT NULL DEFAULT 'mer_papierhurt' CHECK (merchant_id = 'mer_papierhurt')
                              REFERENCES warehouse.suppliers (merchant_id),
  sku           TEXT          NOT NULL,                     -- wspólny katalog z warehouse.products
  product_name  TEXT          NOT NULL,
  unit_price    NUMERIC(12,2) NOT NULL CHECK (unit_price >= 0),
  currency      CHAR(3)       NOT NULL DEFAULT 'PLN' CHECK (currency ~ '^[A-Z]{3}$'),
  available_qty INTEGER       NOT NULL CHECK (available_qty >= 0),
  ships_from    CHAR(2)       NOT NULL CHECK (ships_from ~ '^[A-Z]{2}$'),
  delivery_days INTEGER       NOT NULL CHECK (delivery_days >= 0),
  description   TEXT          NOT NULL DEFAULT '',
  scenario_id   TEXT,                                       -- NULL = katalog bazowy
  active        BOOLEAN       NOT NULL DEFAULT TRUE,
  updated_at    TIMESTAMPTZ   NOT NULL DEFAULT now()
);
CREATE INDEX papierhurt_sku_idx ON shops.papierhurt (sku) WHERE active;

-- GET /search i GET /offers/{id}: wspólny widok ofert wszystkich sklepów.
-- Filtrowanie po aktywnym scenariuszu: scenario_id IS NULL OR scenario_id = :scenario.
CREATE VIEW shops.offers AS
SELECT offer_id, merchant_id, sku, product_name, unit_price, currency, available_qty, ships_from, delivery_days, description, scenario_id, active FROM shops.biuromax
UNION ALL
SELECT offer_id, merchant_id, sku, product_name, unit_price, currency, available_qty, ships_from, delivery_days, description, scenario_id, active FROM shops.papiernik24
UNION ALL
SELECT offer_id, merchant_id, sku, product_name, unit_price, currency, available_qty, ships_from, delivery_days, description, scenario_id, active FROM shops.officehub
UNION ALL
SELECT offer_id, merchant_id, sku, product_name, unit_price, currency, available_qty, ships_from, delivery_days, description, scenario_id, active FROM shops.cheapdeals
UNION ALL
SELECT offer_id, merchant_id, sku, product_name, unit_price, currency, available_qty, ships_from, delivery_days, description, scenario_id, active FROM shops.papierhurt;
