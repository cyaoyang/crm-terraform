CREATE EXTENSION IF NOT EXISTS "pgcrypto";

CREATE TABLE law_firms (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name            VARCHAR(255) NOT NULL,
    email           VARCHAR(255) NOT NULL,
    phone           VARCHAR(20),
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE collection_officers (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name            VARCHAR(255) NOT NULL,
    employee_id     VARCHAR(50) NOT NULL UNIQUE,
    email           VARCHAR(255) NOT NULL,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE customers (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name            VARCHAR(255) NOT NULL,
    phone           VARCHAR(20)  NOT NULL,
    email           VARCHAR(255) NOT NULL,
    address         TEXT,
    date_of_birth   CHAR(10) CHECK (date_of_birth ~ '^\d{2}/\d{2}/\d{4}$'),
    national_id     CHAR(9) CHECK (national_id ~ '^[STFGM][A-Z0-9]{7}[A-Z]$'),
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_customers_email ON customers (email);
CREATE INDEX idx_customers_phone ON customers (phone);

CREATE TYPE delinquency_stage AS ENUM (
    'current',
    'special_mention',
    'substandard',
    'doubtful',
    'loss',
    'legal_escalation',
    'resolved'
);

CREATE TYPE product_type AS ENUM (
    'credit_card',
    'cash_advance',
    'personal_loan',
    'property_loan'
);

CREATE TABLE accounts (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    customer_id         UUID NOT NULL REFERENCES customers(id) ON DELETE RESTRICT,
    product_type        product_type NOT NULL,
    loan_amount         NUMERIC(12,2) NOT NULL CHECK (loan_amount >= 0),
    amount_overdue      NUMERIC(12,2) NOT NULL DEFAULT 0 CHECK (amount_overdue >= 0),
    days_overdue        INTEGER NOT NULL DEFAULT 0 CHECK (days_overdue >= 0),
    delinquency_stage   delinquency_stage NOT NULL DEFAULT 'current',
    last_updated        TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_accounts_customer_id ON accounts (customer_id);
CREATE INDEX idx_accounts_stage ON accounts (delinquency_stage);
CREATE INDEX idx_accounts_days_overdue ON accounts (days_overdue);
CREATE INDEX idx_accounts_product_type ON accounts (product_type);

CREATE TABLE delinquency_events (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    account_id      UUID NOT NULL REFERENCES accounts(id) ON DELETE RESTRICT,
    stage           delinquency_stage NOT NULL,
    entered_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_delinquency_events_account_id ON delinquency_events (account_id);
CREATE INDEX idx_delinquency_events_entered_at ON delinquency_events (entered_at);

CREATE TYPE communication_channel AS ENUM ('email', 'call');
CREATE TYPE communication_status AS ENUM ('sent', 'failed', 'bounced');

CREATE TABLE communications (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    account_id      UUID NOT NULL REFERENCES accounts(id) ON DELETE RESTRICT,
    channel         communication_channel NOT NULL,
    template_used   VARCHAR(100) NOT NULL,
    status          communication_status NOT NULL DEFAULT 'sent',
    sent_at         TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_communications_account_id ON communications (account_id);

CREATE OR REPLACE FUNCTION immutable_date(timestamptz) RETURNS date AS
$$
  SELECT ($1 AT TIME ZONE 'UTC')::date
$$ LANGUAGE sql IMMUTABLE;

CREATE UNIQUE INDEX idx_communications_dedup
    ON communications (account_id, template_used, immutable_date(sent_at));

CREATE TABLE collection_calls (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    account_id          UUID NOT NULL REFERENCES accounts(id) ON DELETE RESTRICT,
    officer_id          UUID NOT NULL REFERENCES collection_officers(id) ON DELETE RESTRICT,
    call_time           TIMESTAMPTZ NOT NULL DEFAULT now(),
    successful          BOOLEAN NOT NULL,
    duration_seconds    INTEGER CHECK (duration_seconds >= 0),
    notes               TEXT,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_collection_calls_account_id ON collection_calls (account_id);
CREATE INDEX idx_collection_calls_officer_id ON collection_calls (officer_id);
CREATE INDEX idx_collection_calls_call_time ON collection_calls (call_time);

CREATE TYPE legal_status AS ENUM ('drafted', 'sent', 'acknowledged', 'closed');

CREATE TABLE legal_escalations (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    account_id          UUID NOT NULL REFERENCES accounts(id) ON DELETE RESTRICT,
    officer_id          UUID NOT NULL REFERENCES collection_officers(id) ON DELETE RESTRICT,
    law_firm_id         UUID NOT NULL REFERENCES law_firms(id) ON DELETE RESTRICT,
    escalation_type     VARCHAR(100) NOT NULL DEFAULT 'letter_of_demand',
    document_s3_key     TEXT NOT NULL,
    status              legal_status NOT NULL DEFAULT 'drafted',
    sent_at             TIMESTAMPTZ,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_legal_escalations_account_id ON legal_escalations (account_id);
CREATE INDEX idx_legal_escalations_officer_id ON legal_escalations (officer_id);
CREATE INDEX idx_legal_escalations_law_firm_id ON legal_escalations (law_firm_id);

CREATE VIEW collection_events AS
SELECT
    id,
    account_id,
    'reminder_email'::TEXT AS event_type,
    sent_at AS event_time,
    template_used AS summary
FROM communications

UNION ALL

SELECT
    id,
    account_id,
    'call'::TEXT AS event_type,
    call_time AS event_time,
    CASE WHEN successful THEN 'Call connected' ELSE 'Call attempted - no answer' END AS summary
FROM collection_calls

UNION ALL

SELECT
    id,
    account_id,
    'legal_letter'::TEXT AS event_type,
    COALESCE(sent_at, created_at) AS event_time,
    escalation_type AS summary
FROM legal_escalations;