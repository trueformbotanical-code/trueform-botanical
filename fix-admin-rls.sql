-- ══════════════════════════════════════════════════
-- Fix admin visibility of all clients
-- Run this in Supabase SQL Editor
-- ══════════════════════════════════════════════════

-- 1. Drop existing restrictive policies on profiles
DROP POLICY IF EXISTS "Users can view own profile" ON public.profiles;
DROP POLICY IF EXISTS "Users can update own profile" ON public.profiles;
DROP POLICY IF EXISTS "Admin full access to profiles" ON public.profiles;
DROP POLICY IF EXISTS "Herbalists can view client profiles" ON public.profiles;

-- 2. Re-create with correct policies
-- Users can view their own profile
CREATE POLICY "Users can view own profile"
  ON public.profiles FOR SELECT
  USING (auth.uid() = id);

-- Users can update their own profile
CREATE POLICY "Users can update own profile"
  ON public.profiles FOR UPDATE
  USING (auth.uid() = id);

-- Admin can see and manage ALL profiles
CREATE POLICY "Admin full access to profiles"
  ON public.profiles FOR ALL
  USING (
    EXISTS (
      SELECT 1 FROM public.profiles p
      WHERE p.id = auth.uid() AND p.role = 'admin'
    )
  );

-- Herbalists can see all client profiles
CREATE POLICY "Herbalists can view all profiles"
  ON public.profiles FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.profiles p
      WHERE p.id = auth.uid() AND p.role IN ('herbalist', 'admin')
    )
  );

-- Anyone can insert their own profile (needed for registration)
CREATE POLICY "Users can insert own profile"
  ON public.profiles FOR INSERT
  WITH CHECK (auth.uid() = id OR auth.uid() IS NOT NULL);

-- 3. Fix assessments RLS too
DROP POLICY IF EXISTS "Herbalists can view all assessments" ON public.assessments;
DROP POLICY IF EXISTS "Herbalists can update assessments" ON public.assessments;
DROP POLICY IF EXISTS "Client can view own assessments" ON public.assessments;
DROP POLICY IF EXISTS "Client can insert own assessment" ON public.assessments;

CREATE POLICY "Client can view own assessments"
  ON public.assessments FOR SELECT
  USING (
    auth.uid() = client_id OR
    client_email = (SELECT email FROM public.profiles WHERE id = auth.uid())
  );

CREATE POLICY "Anyone can insert assessment"
  ON public.assessments FOR INSERT
  WITH CHECK (true);

CREATE POLICY "Herbalists and admin can view all assessments"
  ON public.assessments FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.profiles
      WHERE id = auth.uid() AND role IN ('herbalist', 'admin')
    )
  );

CREATE POLICY "Herbalists and admin can update assessments"
  ON public.assessments FOR UPDATE
  USING (
    EXISTS (
      SELECT 1 FROM public.profiles
      WHERE id = auth.uid() AND role IN ('herbalist', 'admin')
    )
  );

-- 4. Verify: show all profiles
SELECT id, email, role, status, created_at FROM public.profiles ORDER BY created_at DESC;
