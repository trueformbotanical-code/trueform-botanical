-- Run this in Supabase SQL Editor to backfill missing profile rows
-- for any users who registered before this fix was applied

INSERT INTO public.profiles (id, email, full_name, first_name, last_name, role, status, created_at, updated_at)
SELECT 
  id,
  email,
  COALESCE(raw_user_meta_data->>'full_name', ''),
  COALESCE(raw_user_meta_data->>'first_name', split_part(email,'@',1)),
  COALESCE(raw_user_meta_data->>'last_name', ''),
  COALESCE(raw_user_meta_data->>'role', 'client'),
  'active',
  created_at,
  now()
FROM auth.users
ON CONFLICT (id) DO UPDATE SET
  role       = COALESCE(profiles.role, EXCLUDED.role, 'client'),
  status     = COALESCE(profiles.status, 'active'),
  updated_at = now();

-- Verify result
SELECT id, email, role, status FROM public.profiles ORDER BY created_at DESC;
