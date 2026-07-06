-- Summit — transaction tags
-- Adds the user-defined tags column that TransactionRow now pushes/pulls.
-- IMPORTANT: apply before running the app build that includes tags — pushes
-- include the column and will fail against a database without it.
-- Apply via `supabase db push` (after `supabase link`) or paste into the SQL editor.

ALTER TABLE transactions ADD COLUMN IF NOT EXISTS tags text[];
