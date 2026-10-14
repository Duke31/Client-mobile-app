-- Solace EMS: Maternal Wellness Logs & Check-ins Security Migration
-- Strictly adheres to Rules:
-- 1. Never create RLS policies with USING (true).
-- 2. Never grant PHI tables to anon.
-- 3. Owner-only RLS: auth.uid() = user_id only.

CREATE TABLE IF NOT EXISTS public.maternal_wellness_logs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  log_date DATE NOT NULL,
  mood_score INTEGER CHECK (mood_score >= 1 AND mood_score <= 5),
  kicks_count INTEGER NOT NULL DEFAULT 0 CHECK (kicks_count >= 0),
  water_glasses INTEGER NOT NULL DEFAULT 0 CHECK (water_glasses >= 0),
  sleep_hours INTEGER NOT NULL DEFAULT 8 CHECK (sleep_hours >= 0 AND sleep_hours <= 24),
  vitamins_taken BOOLEAN NOT NULL DEFAULT false,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT uq_maternal_wellness_user_date UNIQUE (user_id, log_date)
);

-- Indexes for efficient querying of user's past 7 days logs
CREATE INDEX IF NOT EXISTS idx_maternal_wellness_user_date ON public.maternal_wellness_logs (user_id, log_date DESC);

-- Strict RLS Hardening
ALTER TABLE public.maternal_wellness_logs ENABLE ROW LEVEL SECURITY;

-- Deny anon access unconditionally
REVOKE ALL ON public.maternal_wellness_logs FROM anon;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.maternal_wellness_logs TO authenticated;

-- Owner-only Policies: Authenticated users can ONLY interact with their own logs
DROP POLICY IF EXISTS "Users can only view their own maternal wellness logs" ON public.maternal_wellness_logs;
CREATE POLICY "Users can only view their own maternal wellness logs"
  ON public.maternal_wellness_logs
  FOR SELECT
  TO authenticated
  USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can only insert their own maternal wellness logs" ON public.maternal_wellness_logs;
CREATE POLICY "Users can only insert their own maternal wellness logs"
  ON public.maternal_wellness_logs
  FOR INSERT
  TO authenticated
  WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can only update their own maternal wellness logs" ON public.maternal_wellness_logs;
CREATE POLICY "Users can only update their own maternal wellness logs"
  ON public.maternal_wellness_logs
  FOR UPDATE
  TO authenticated
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can only delete their own maternal wellness logs" ON public.maternal_wellness_logs;
CREATE POLICY "Users can only delete their own maternal wellness logs"
  ON public.maternal_wellness_logs
  FOR DELETE
  TO authenticated
  USING (auth.uid() = user_id);
