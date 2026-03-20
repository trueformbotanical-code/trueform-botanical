-- ══════════════════════════════════════════════════
-- Create client_registrations table
-- This is a simple open-read table the admin can
-- always query without RLS blocking it.
-- Run this in Supabase SQL Editor
-- ══════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS public.client_registrations (
  id          uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id     uuid,
  email       text UNIQUE NOT NULL,
  full_name   text,
  first_name  text,
  last_name   text,
  status      text DEFAULT 'active',
  created_at  timestamptz DEFAULT now()
);

-- Enable RLS but allow all authenticated users to insert
ALTER TABLE public.client_registrations ENABLE ROW LEVEL SECURITY;

-- Anyone authenticated can insert their own registration
CREATE POLICY "Anyone can insert registration"
  ON public.client_registrations FOR INSERT
  WITH CHECK (true);

-- Admin can read ALL registrations (this is the key policy)
CREATE POLICY "Admin can read all registrations"
  ON public.client_registrations FOR SELECT
  USING (true);

-- Admin can update/delete
CREATE POLICY "Admin can manage registrations"
  ON public.client_registrations FOR ALL
  USING (true);

-- Backfill: copy existing clients from profiles table
INSERT INTO public.client_registrations (id, user_id, email, full_name, first_name, last_name, status, created_at)
SELECT id, id, email, full_name, first_name, last_name, status, created_at
FROM public.profiles
WHERE role = 'client'
ON CONFLICT (email) DO NOTHING;

-- Verify
SELECT * FROM public.client_registrations ORDER BY created_at DESC;
