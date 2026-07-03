-- Summit — Settle Up (household shared expenses)
-- Run this once in the Supabase SQL editor to enable syncing of shared
-- expenses and settlements. Mirrors the SharedExpenseModel / SettlementModel
-- SwiftData models and the Row types in SyncService.swift.

-- ── Tables ────────────────────────────────────────────────────────────────

create table if not exists public.shared_expenses (
    id             uuid primary key,
    household_id   uuid not null references public.households(id) on delete cascade,
    title          text not null,
    amount         numeric not null,
    date           timestamptz not null,
    payer_user_id  uuid not null,
    payer_share    numeric not null,
    note           text,
    deleted_at     timestamptz
);

create table if not exists public.settlements (
    id             uuid primary key,
    household_id   uuid not null references public.households(id) on delete cascade,
    date           timestamptz not null,
    from_user_id   uuid not null,
    to_user_id     uuid not null,
    amount         numeric not null,
    note           text,
    deleted_at     timestamptz
);

-- Member display names, so settle-up shows names instead of UUIDs. Each user
-- writes their own row; household co-members can read it.
create table if not exists public.profiles (
    user_id       uuid primary key,
    display_name  text not null,
    email         text,
    updated_at    timestamptz
);

create index if not exists shared_expenses_household_idx on public.shared_expenses(household_id);
create index if not exists settlements_household_idx     on public.settlements(household_id);

-- ── Row Level Security ────────────────────────────────────────────────────
-- Any member of the household can read/write its shared expenses & settlements.

alter table public.shared_expenses enable row level security;
alter table public.settlements     enable row level security;
alter table public.profiles        enable row level security;

-- Profiles: you can read/write your own; and read anyone who shares a household with you.
create policy "profiles: upsert own"
  on public.profiles
  for all
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

create policy "profiles: read household co-members"
  on public.profiles
  for select
  using (
    user_id in (
      select hm.user_id
      from public.household_members hm
      where hm.household_id in (
        select household_id from public.household_members where user_id = auth.uid()
      )
    )
  );

create policy "shared_expenses: household members"
  on public.shared_expenses
  for all
  using (
    household_id in (
      select household_id from public.household_members where user_id = auth.uid()
    )
  )
  with check (
    household_id in (
      select household_id from public.household_members where user_id = auth.uid()
    )
  );

create policy "settlements: household members"
  on public.settlements
  for all
  using (
    household_id in (
      select household_id from public.household_members where user_id = auth.uid()
    )
  )
  with check (
    household_id in (
      select household_id from public.household_members where user_id = auth.uid()
    )
  );
