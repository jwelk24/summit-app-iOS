# summit-app
Summit App for budgeting

## Database migrations (Supabase)

SQL schema lives in `supabase/migrations/`, applied in filename order
(`0001_initial_schema.sql`, `0002_settle_up.sql`, …). Migrations are additive
(`CREATE TABLE` + RLS policies) and safe to run against the existing database.

**Apply the latest migrations:**

```bash
# one-time: link the local repo to your Supabase project
supabase link --project-ref <your-project-ref>

# push any unapplied migrations
supabase db push
```

No Supabase CLI? Open **Supabase → SQL Editor**, paste the contents of the
new migration file, and run it.

**Adding a new migration:** create the next-numbered file in
`supabase/migrations/` (e.g. `0003_*.sql`) whose column/table names match the
`Row` structs in `Summit/SyncService.swift`, reuse the `can_read_household` /
`can_write_household` RLS helpers from `0001`, then `supabase db push`.

> Note: the app ships only the Supabase **anon key**, which cannot run DDL —
> migrations must be applied with project (DB) credentials via the CLI or SQL editor.
