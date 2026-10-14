-- ==============================================================================
-- Migration: Medical ID & Care Plan Profile Schema & Security Alignment
-- Timestamp: 2026-10-14
--
-- Strict Rules:
-- 1) Never create RLS policies with USING (true). Never grant PHI tables to anon.
-- 2) Profile/PHI: owner-only read/write via RLS (auth.uid() = user_id).
-- 3) Honest labels: plain blood groups, date of birth, computed gestational fields.
-- ==============================================================================

-- 1. Ensure Profile Columns for Medical ID & Care Plan
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS date_of_birth date;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS care_plan text DEFAULT 'standard';
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS lmp_date text;

-- 2. Synchronize care_plan with existing profile_type / is_pregnant
UPDATE public.profiles
SET care_plan = CASE
    WHEN profile_type = 'maternal' OR is_pregnant = true THEN 'maternal'
    ELSE 'standard'
END
WHERE care_plan IS NULL;

-- 3. Strict Owner-Only Row Level Security (RLS)
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;

-- Revoke all permissions from anon
REVOKE ALL ON public.profiles FROM anon;
GRANT SELECT, INSERT, UPDATE ON public.profiles TO authenticated;

-- Ensure owner-only SELECT policy
DROP POLICY IF EXISTS profiles_read_policy ON public.profiles;
CREATE POLICY profiles_read_policy ON public.profiles
    FOR SELECT
    TO authenticated
    USING (
        user_id = auth.uid()
        OR (get_my_role() = 'admin'::text)
    );

-- Ensure owner-only UPDATE policy
DROP POLICY IF EXISTS profiles_update_own ON public.profiles;
CREATE POLICY profiles_update_own ON public.profiles
    FOR UPDATE
    TO authenticated
    USING (user_id = auth.uid())
    WITH CHECK (user_id = auth.uid());

-- Ensure owner-only INSERT policy
DROP POLICY IF EXISTS profiles_insert_own ON public.profiles;
CREATE POLICY profiles_insert_own ON public.profiles
    FOR INSERT
    TO authenticated
    WITH CHECK (user_id = auth.uid());

-- 4. Audit comments
COMMENT ON COLUMN public.profiles.date_of_birth IS 'Patient date of birth for triage and paediatric vs adult handling';
COMMENT ON COLUMN public.profiles.care_plan IS 'User emergency care plan: standard | maternal';
COMMENT ON COLUMN public.profiles.lmp_date IS 'Last menstrual period date for gestational calculation (maternal only)';
