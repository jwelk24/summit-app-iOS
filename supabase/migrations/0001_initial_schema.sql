-- Summit initial schema
-- Run in Supabase SQL Editor (or via `supabase db push` after `supabase link`).
-- All financial tables are scoped to a household and use shared RLS helpers.

-- =============================================================================
-- 1. Enums
-- =============================================================================

CREATE TYPE household_role AS ENUM ('owner', 'member', 'viewer');

CREATE TYPE account_type AS ENUM (
    'checking', 'savings', 'creditCard', 'loan',
    'investment', 'retirement', 'manualAsset'
);

CREATE TYPE goal_type AS ENUM ('monthlyAmount', 'byDateTarget', 'savingsTarget');

CREATE TYPE scheduled_kind AS ENUM ('bill', 'paycheck', 'subscription');

CREATE TYPE liability_kind AS ENUM ('credit', 'student', 'mortgage', 'other');

-- =============================================================================
-- 2. Households + membership
-- =============================================================================

CREATE TABLE households (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    name text NOT NULL,
    owner_user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE household_members (
    household_id uuid NOT NULL REFERENCES households(id) ON DELETE CASCADE,
    user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    role household_role NOT NULL DEFAULT 'member',
    joined_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (household_id, user_id)
);

CREATE INDEX household_members_user_idx ON household_members(user_id);

CREATE TABLE household_invites (
    code text PRIMARY KEY,
    household_id uuid NOT NULL REFERENCES households(id) ON DELETE CASCADE,
    role household_role NOT NULL DEFAULT 'member',
    created_by uuid NOT NULL REFERENCES auth.users(id),
    expires_at timestamptz NOT NULL,
    used_at timestamptz,
    used_by uuid REFERENCES auth.users(id),
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX household_invites_household_idx ON household_invites(household_id);

-- =============================================================================
-- 3. RLS helper functions (SECURITY DEFINER bypasses RLS on household_members)
-- =============================================================================

CREATE OR REPLACE FUNCTION public.can_read_household(hid uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT EXISTS (
        SELECT 1 FROM household_members
        WHERE household_id = hid AND user_id = auth.uid()
    )
$$;

CREATE OR REPLACE FUNCTION public.can_write_household(hid uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT EXISTS (
        SELECT 1 FROM household_members
        WHERE household_id = hid
          AND user_id = auth.uid()
          AND role IN ('owner', 'member')
    )
$$;

CREATE OR REPLACE FUNCTION public.is_household_owner(hid uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT EXISTS (
        SELECT 1 FROM household_members
        WHERE household_id = hid
          AND user_id = auth.uid()
          AND role = 'owner'
    )
$$;

-- =============================================================================
-- 4. updated_at trigger
-- =============================================================================

CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END
$$;

-- =============================================================================
-- 5. Financial tables (mirroring SwiftData models)
-- =============================================================================

CREATE TABLE accounts (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    household_id uuid NOT NULL REFERENCES households(id) ON DELETE CASCADE,
    name text NOT NULL,
    type account_type NOT NULL,
    balance numeric(20,4) NOT NULL DEFAULT 0,
    currency_code text NOT NULL DEFAULT 'USD',
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    deleted_at timestamptz
);
CREATE INDEX accounts_household_idx ON accounts(household_id) WHERE deleted_at IS NULL;
CREATE INDEX accounts_updated_idx ON accounts(household_id, updated_at);
CREATE TRIGGER accounts_set_updated_at BEFORE UPDATE ON accounts
    FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

CREATE TABLE category_groups (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    household_id uuid NOT NULL REFERENCES households(id) ON DELETE CASCADE,
    name text NOT NULL,
    sort int NOT NULL DEFAULT 0,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    deleted_at timestamptz
);
CREATE INDEX category_groups_household_idx ON category_groups(household_id) WHERE deleted_at IS NULL;
CREATE TRIGGER category_groups_set_updated_at BEFORE UPDATE ON category_groups
    FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

CREATE TABLE categories (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    household_id uuid NOT NULL REFERENCES households(id) ON DELETE CASCADE,
    group_id uuid REFERENCES category_groups(id) ON DELETE SET NULL,
    linked_account_id uuid REFERENCES accounts(id) ON DELETE SET NULL,
    name text NOT NULL,
    sort int NOT NULL DEFAULT 0,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    deleted_at timestamptz
);
CREATE INDEX categories_household_idx ON categories(household_id) WHERE deleted_at IS NULL;
CREATE INDEX categories_group_idx ON categories(group_id);
CREATE TRIGGER categories_set_updated_at BEFORE UPDATE ON categories
    FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

CREATE TABLE transactions (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    household_id uuid NOT NULL REFERENCES households(id) ON DELETE CASCADE,
    account_id uuid REFERENCES accounts(id) ON DELETE SET NULL,
    category_id uuid REFERENCES categories(id) ON DELETE SET NULL,
    date timestamptz NOT NULL,
    amount numeric(20,4) NOT NULL,
    merchant text NOT NULL,
    memo text,
    cleared boolean NOT NULL DEFAULT false,
    flag_color text,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    deleted_at timestamptz
);
CREATE INDEX transactions_household_idx ON transactions(household_id) WHERE deleted_at IS NULL;
CREATE INDEX transactions_account_idx ON transactions(account_id);
CREATE INDEX transactions_date_idx ON transactions(household_id, date DESC);
CREATE INDEX transactions_updated_idx ON transactions(household_id, updated_at);
CREATE TRIGGER transactions_set_updated_at BEFORE UPDATE ON transactions
    FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

CREATE TABLE transaction_splits (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    household_id uuid NOT NULL REFERENCES households(id) ON DELETE CASCADE,
    transaction_id uuid NOT NULL REFERENCES transactions(id) ON DELETE CASCADE,
    category_id uuid REFERENCES categories(id) ON DELETE SET NULL,
    amount numeric(20,4) NOT NULL,
    memo text,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    deleted_at timestamptz
);
CREATE INDEX transaction_splits_household_idx ON transaction_splits(household_id) WHERE deleted_at IS NULL;
CREATE INDEX transaction_splits_tx_idx ON transaction_splits(transaction_id);
CREATE TRIGGER transaction_splits_set_updated_at BEFORE UPDATE ON transaction_splits
    FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

CREATE TABLE goals (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    household_id uuid NOT NULL REFERENCES households(id) ON DELETE CASCADE,
    category_id uuid REFERENCES categories(id) ON DELETE CASCADE,
    type goal_type NOT NULL,
    target_amount numeric(20,4) NOT NULL,
    target_date date,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    deleted_at timestamptz
);
CREATE INDEX goals_household_idx ON goals(household_id) WHERE deleted_at IS NULL;
CREATE TRIGGER goals_set_updated_at BEFORE UPDATE ON goals
    FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

CREATE TABLE scheduled_items (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    household_id uuid NOT NULL REFERENCES households(id) ON DELETE CASCADE,
    account_id uuid REFERENCES accounts(id) ON DELETE SET NULL,
    category_id uuid REFERENCES categories(id) ON DELETE SET NULL,
    kind scheduled_kind NOT NULL,
    name text NOT NULL,
    amount numeric(20,4) NOT NULL,
    next_date timestamptz NOT NULL,
    interval_days int NOT NULL DEFAULT 30,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    deleted_at timestamptz
);
CREATE INDEX scheduled_items_household_idx ON scheduled_items(household_id) WHERE deleted_at IS NULL;
CREATE TRIGGER scheduled_items_set_updated_at BEFORE UPDATE ON scheduled_items
    FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

CREATE TABLE budget_months (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    household_id uuid NOT NULL REFERENCES households(id) ON DELETE CASCADE,
    year int NOT NULL,
    month int NOT NULL CHECK (month BETWEEN 1 AND 12),
    carryover numeric(20,4) NOT NULL DEFAULT 0,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    deleted_at timestamptz,
    UNIQUE (household_id, year, month)
);
CREATE TRIGGER budget_months_set_updated_at BEFORE UPDATE ON budget_months
    FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

CREATE TABLE budget_allocations (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    household_id uuid NOT NULL REFERENCES households(id) ON DELETE CASCADE,
    month_id uuid NOT NULL REFERENCES budget_months(id) ON DELETE CASCADE,
    category_id uuid NOT NULL REFERENCES categories(id) ON DELETE CASCADE,
    amount numeric(20,4) NOT NULL DEFAULT 0,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    deleted_at timestamptz,
    UNIQUE (month_id, category_id)
);
CREATE INDEX budget_allocations_household_idx ON budget_allocations(household_id) WHERE deleted_at IS NULL;
CREATE TRIGGER budget_allocations_set_updated_at BEFORE UPDATE ON budget_allocations
    FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

CREATE TABLE balance_snapshots (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    household_id uuid NOT NULL REFERENCES households(id) ON DELETE CASCADE,
    account_id uuid NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
    date date NOT NULL,
    balance numeric(20,4) NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    deleted_at timestamptz,
    UNIQUE (account_id, date)
);
CREATE INDEX balance_snapshots_household_idx ON balance_snapshots(household_id) WHERE deleted_at IS NULL;
CREATE TRIGGER balance_snapshots_set_updated_at BEFORE UPDATE ON balance_snapshots
    FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- Investments
CREATE TABLE investment_holdings (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    household_id uuid NOT NULL REFERENCES households(id) ON DELETE CASCADE,
    account_id uuid REFERENCES accounts(id) ON DELETE CASCADE,
    plaid_account_id text NOT NULL,
    plaid_security_id text NOT NULL,
    ticker_symbol text,
    security_name text,
    security_type text,
    is_cash_equivalent boolean NOT NULL DEFAULT false,
    quantity numeric(20,8) NOT NULL,
    institution_price numeric(20,4) NOT NULL,
    institution_value numeric(20,4) NOT NULL,
    cost_basis numeric(20,4),
    currency_code text NOT NULL DEFAULT 'USD',
    as_of_date date NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    deleted_at timestamptz,
    UNIQUE (plaid_account_id, plaid_security_id)
);
CREATE INDEX investment_holdings_household_idx ON investment_holdings(household_id) WHERE deleted_at IS NULL;
CREATE TRIGGER investment_holdings_set_updated_at BEFORE UPDATE ON investment_holdings
    FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

CREATE TABLE investment_transactions (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    household_id uuid NOT NULL REFERENCES households(id) ON DELETE CASCADE,
    account_id uuid REFERENCES accounts(id) ON DELETE CASCADE,
    plaid_investment_transaction_id text NOT NULL UNIQUE,
    date date NOT NULL,
    name text NOT NULL,
    amount numeric(20,4) NOT NULL,
    fees numeric(20,4),
    quantity numeric(20,8),
    price numeric(20,4),
    type text NOT NULL,
    subtype text,
    plaid_security_id text,
    ticker_symbol text,
    security_name text,
    currency_code text NOT NULL DEFAULT 'USD',
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    deleted_at timestamptz
);
CREATE INDEX investment_transactions_household_idx ON investment_transactions(household_id) WHERE deleted_at IS NULL;
CREATE TRIGGER investment_transactions_set_updated_at BEFORE UPDATE ON investment_transactions
    FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

CREATE TABLE liabilities (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    household_id uuid NOT NULL REFERENCES households(id) ON DELETE CASCADE,
    account_id uuid REFERENCES accounts(id) ON DELETE CASCADE,
    plaid_account_id text NOT NULL UNIQUE,
    kind liability_kind NOT NULL,
    last_statement_balance numeric(20,4),
    last_statement_issue_date date,
    minimum_payment numeric(20,4),
    next_payment_due_date date,
    last_payment_amount numeric(20,4),
    last_payment_date date,
    interest_rate_percentage numeric(8,4),
    origination_principal numeric(20,4),
    origination_date date,
    maturity_date date,
    loan_name text,
    raw_json jsonb,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    deleted_at timestamptz
);
CREATE INDEX liabilities_household_idx ON liabilities(household_id) WHERE deleted_at IS NULL;
CREATE TRIGGER liabilities_set_updated_at BEFORE UPDATE ON liabilities
    FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- =============================================================================
-- 6. Plaid: client-visible metadata vs. server-only credentials
-- =============================================================================

-- Client-visible metadata (institution name, etc.)
CREATE TABLE plaid_items (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    household_id uuid NOT NULL REFERENCES households(id) ON DELETE CASCADE,
    plaid_item_id text NOT NULL UNIQUE,
    institution_name text,
    institution_id text,
    last_synced_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    deleted_at timestamptz
);
CREATE INDEX plaid_items_household_idx ON plaid_items(household_id) WHERE deleted_at IS NULL;
CREATE TRIGGER plaid_items_set_updated_at BEFORE UPDATE ON plaid_items
    FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- Credentials: NEVER exposed to clients. Only service_role (Edge Functions) read.
CREATE TABLE plaid_credentials (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    household_id uuid NOT NULL REFERENCES households(id) ON DELETE CASCADE,
    plaid_item_id text NOT NULL UNIQUE,
    access_token text NOT NULL,
    transactions_cursor text,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE TRIGGER plaid_credentials_set_updated_at BEFORE UPDATE ON plaid_credentials
    FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

CREATE TABLE plaid_account_links (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    household_id uuid NOT NULL REFERENCES households(id) ON DELETE CASCADE,
    account_id uuid REFERENCES accounts(id) ON DELETE CASCADE,
    plaid_item_id text NOT NULL,
    plaid_account_id text NOT NULL UNIQUE,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    deleted_at timestamptz
);
CREATE INDEX plaid_account_links_household_idx ON plaid_account_links(household_id) WHERE deleted_at IS NULL;
CREATE TRIGGER plaid_account_links_set_updated_at BEFORE UPDATE ON plaid_account_links
    FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

CREATE TABLE plaid_transaction_links (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    household_id uuid NOT NULL REFERENCES households(id) ON DELETE CASCADE,
    transaction_id uuid REFERENCES transactions(id) ON DELETE CASCADE,
    plaid_transaction_id text NOT NULL UNIQUE,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    deleted_at timestamptz
);
CREATE INDEX plaid_transaction_links_household_idx ON plaid_transaction_links(household_id) WHERE deleted_at IS NULL;
CREATE TRIGGER plaid_transaction_links_set_updated_at BEFORE UPDATE ON plaid_transaction_links
    FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- =============================================================================
-- 7. Row-Level Security
-- =============================================================================

-- households + membership
ALTER TABLE households ENABLE ROW LEVEL SECURITY;
ALTER TABLE household_members ENABLE ROW LEVEL SECURITY;
ALTER TABLE household_invites ENABLE ROW LEVEL SECURITY;

CREATE POLICY "households_read" ON households FOR SELECT
    USING (public.can_read_household(id));

CREATE POLICY "households_insert_self" ON households FOR INSERT
    WITH CHECK (auth.uid() = owner_user_id);

CREATE POLICY "households_owner_update" ON households FOR UPDATE
    USING (public.is_household_owner(id));

CREATE POLICY "households_owner_delete" ON households FOR DELETE
    USING (public.is_household_owner(id));

CREATE POLICY "household_members_read" ON household_members FOR SELECT
    USING (public.can_read_household(household_id));

CREATE POLICY "household_members_owner_write" ON household_members FOR ALL
    USING (public.is_household_owner(household_id))
    WITH CHECK (public.is_household_owner(household_id));

CREATE POLICY "household_members_self_join" ON household_members FOR INSERT
    WITH CHECK (user_id = auth.uid());

CREATE POLICY "household_invites_read" ON household_invites FOR SELECT
    USING (public.can_read_household(household_id));

CREATE POLICY "household_invites_owner_write" ON household_invites FOR ALL
    USING (public.is_household_owner(household_id))
    WITH CHECK (public.is_household_owner(household_id));

-- Plaid credentials: no client policies. service_role bypasses RLS automatically.
ALTER TABLE plaid_credentials ENABLE ROW LEVEL SECURITY;

-- All other tables: read = any household member, write = owner+member only
DO $$
DECLARE
    tbl text;
    financial_tables text[] := ARRAY[
        'accounts', 'category_groups', 'categories',
        'transactions', 'transaction_splits',
        'goals', 'scheduled_items',
        'budget_months', 'budget_allocations',
        'balance_snapshots',
        'investment_holdings', 'investment_transactions',
        'liabilities',
        'plaid_items', 'plaid_account_links', 'plaid_transaction_links'
    ];
BEGIN
    FOREACH tbl IN ARRAY financial_tables LOOP
        EXECUTE format('ALTER TABLE %I ENABLE ROW LEVEL SECURITY', tbl);
        EXECUTE format('CREATE POLICY "%I_read" ON %I FOR SELECT USING (public.can_read_household(household_id))', tbl, tbl);
        EXECUTE format('CREATE POLICY "%I_insert" ON %I FOR INSERT WITH CHECK (public.can_write_household(household_id))', tbl, tbl);
        EXECUTE format('CREATE POLICY "%I_update" ON %I FOR UPDATE USING (public.can_write_household(household_id)) WITH CHECK (public.can_write_household(household_id))', tbl, tbl);
        EXECUTE format('CREATE POLICY "%I_delete" ON %I FOR DELETE USING (public.can_write_household(household_id))', tbl, tbl);
    END LOOP;
END
$$;

-- =============================================================================
-- 8. Auto-create a personal household + owner membership on first sign-in
-- =============================================================================

CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    new_household_id uuid;
    display_name text;
BEGIN
    display_name := COALESCE(NEW.raw_user_meta_data->>'full_name', split_part(NEW.email, '@', 1), 'My Household');

    INSERT INTO households (name, owner_user_id)
    VALUES (display_name || '''s Household', NEW.id)
    RETURNING id INTO new_household_id;

    INSERT INTO household_members (household_id, user_id, role)
    VALUES (new_household_id, NEW.id, 'owner');

    RETURN NEW;
END
$$;

CREATE TRIGGER on_auth_user_created
    AFTER INSERT ON auth.users
    FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();
