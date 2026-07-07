-- Summit — refund tracking
-- Adds the two columns behind "expecting refund" flags and refund links.
-- IMPORTANT: apply before running the app build that includes refund
-- tracking — pushes include the columns and will fail against a database
-- without them.
-- Apply via `supabase db push` (after `supabase link`) or paste into the SQL editor.

ALTER TABLE transactions ADD COLUMN IF NOT EXISTS awaiting_refund boolean;
ALTER TABLE transactions ADD COLUMN IF NOT EXISTS refunds_transaction_id uuid;
