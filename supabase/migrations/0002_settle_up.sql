-- Summit — Settle Up (household shared expenses) + member profiles
-- Adds shared_expenses, settlements, and profiles. Depends on 0001 (households,
-- household_members, and the can_read_household / can_write_household helpers).
-- Apply via `supabase db push` (after `supabase link`) or paste into the SQL editor.

-- =============================================================================
-- 1. Tables
-- =============================================================================

CREATE TABLE shared_expenses (
    id             uuid PRIMARY KEY,
    household_id   uuid NOT NULL REFERENCES households(id) ON DELETE CASCADE,
    title          text NOT NULL,
    amount         numeric NOT NULL,
    date           timestamptz NOT NULL,
    payer_user_id  uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    payer_share    numeric NOT NULL,
    note           text,
    deleted_at     timestamptz
);

CREATE TABLE settlements (
    id             uuid PRIMARY KEY,
    household_id   uuid NOT NULL REFERENCES households(id) ON DELETE CASCADE,
    date           timestamptz NOT NULL,
    from_user_id   uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    to_user_id     uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    amount         numeric NOT NULL,
    note           text,
    deleted_at     timestamptz
);

CREATE TABLE profiles (
    user_id       uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    display_name  text NOT NULL,
    email         text,
    updated_at    timestamptz
);

CREATE INDEX shared_expenses_household_idx ON shared_expenses(household_id);
CREATE INDEX settlements_household_idx     ON settlements(household_id);

-- =============================================================================
-- 2. RLS — shared_expenses & settlements use the shared household helpers
--    (read = any member, write = owner+member), matching every other table.
-- =============================================================================

DO $$
DECLARE
    tbl text;
    tables text[] := ARRAY['shared_expenses', 'settlements'];
BEGIN
    FOREACH tbl IN ARRAY tables LOOP
        EXECUTE format('ALTER TABLE %I ENABLE ROW LEVEL SECURITY', tbl);
        EXECUTE format('CREATE POLICY "%I_read" ON %I FOR SELECT USING (public.can_read_household(household_id))', tbl, tbl);
        EXECUTE format('CREATE POLICY "%I_insert" ON %I FOR INSERT WITH CHECK (public.can_write_household(household_id))', tbl, tbl);
        EXECUTE format('CREATE POLICY "%I_update" ON %I FOR UPDATE USING (public.can_write_household(household_id)) WITH CHECK (public.can_write_household(household_id))', tbl, tbl);
        EXECUTE format('CREATE POLICY "%I_delete" ON %I FOR DELETE USING (public.can_write_household(household_id))', tbl, tbl);
    END LOOP;
END
$$;

-- =============================================================================
-- 3. Profiles RLS — you manage your own row; you can read anyone who shares a
--    household with you. SECURITY DEFINER helper avoids RLS recursion.
-- =============================================================================

CREATE OR REPLACE FUNCTION public.shares_household(target uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM household_members m1
        JOIN household_members m2 ON m1.household_id = m2.household_id
        WHERE m1.user_id = auth.uid() AND m2.user_id = target
    );
$$;

ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;

CREATE POLICY "profiles_own" ON profiles
    FOR ALL
    USING (user_id = auth.uid())
    WITH CHECK (user_id = auth.uid());

CREATE POLICY "profiles_read_co_members" ON profiles
    FOR SELECT
    USING (public.shares_household(user_id));
