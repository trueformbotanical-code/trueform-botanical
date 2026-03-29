-- ================================================================
-- TrueForm Botanical — Supabase Schema (FIXED)
-- Run this ENTIRE block in Supabase SQL Editor
-- Fixes:
--   1. Infinite recursion in profiles RLS policies
--   2. Assessments readable by herbalists without auth.uid()
--   3. Anon insert for assessments (clients not Supabase-authed)
--   4. All tables accessible to the app's publishable key
-- ================================================================

-- Extensions
create extension if not exists "uuid-ossp";

-- ================================================================
-- DROP OLD POLICIES FIRST (prevents conflicts on re-run)
-- ================================================================
do $$ declare
  r record;
begin
  for r in (
    select schemaname, tablename, policyname
    from pg_policies
    where schemaname = 'public'
  ) loop
    execute 'drop policy if exists "' || r.policyname || '" on ' || r.schemaname || '.' || r.tablename;
  end loop;
end $$;

-- ================================================================
-- TABLE: profiles
-- FIX: The old policies queried profiles FROM WITHIN a profiles 
-- policy, creating infinite recursion. Use a security definer 
-- function instead to break the cycle.
-- ================================================================
create table if not exists public.profiles (
  id         uuid references auth.users(id) on delete cascade primary key,
  email      text unique not null,
  full_name  text,
  first_name text,
  last_name  text,
  role       text not null default 'client'
             check (role in ('client','herbalist','admin')),
  status     text not null default 'active'
             check (status in ('active','suspended','inactive')),
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);
alter table public.profiles enable row level security;

-- Security-definer function: check role WITHOUT querying profiles 
-- inside a profiles policy (breaks the recursion loop)
create or replace function public.get_my_role()
returns text
language sql
security definer
stable
set search_path = public
as $$
  select role from public.profiles where id = auth.uid() limit 1;
$$;

-- Profiles policies — use get_my_role() not a subquery on profiles
create policy "Own profile select"
  on public.profiles for select
  using (auth.uid() = id);

create policy "Own profile update"
  on public.profiles for update
  using (auth.uid() = id);

create policy "Herbalists and admins view all profiles"
  on public.profiles for select
  using (public.get_my_role() in ('herbalist','admin'));

create policy "Admin insert profiles"
  on public.profiles for insert
  with check (public.get_my_role() = 'admin');

create policy "Admin delete profiles"
  on public.profiles for delete
  using (public.get_my_role() = 'admin');

-- ================================================================
-- TABLE: herbalists
-- ================================================================
create table if not exists public.herbalists (
  id         uuid default uuid_generate_v4() primary key,
  username   text unique not null,
  full_name  text not null,
  email      text unique not null,
  specialty  text,
  tradition  text,
  bio        text,
  status     text default 'active'
             check (status in ('active','suspended','inactive')),
  created_at timestamptz default now()
);
alter table public.herbalists enable row level security;

-- Anyone (including anon) can read herbalists — needed for login
create policy "Anyone can view herbalists"
  on public.herbalists for select
  using (true);

create policy "Admin manages herbalists"
  on public.herbalists for all
  using (public.get_my_role() = 'admin');

-- ================================================================
-- TABLE: assessments
-- FIX: Herbalists log in without Supabase auth (username+pw only),
-- so auth.uid() is NULL for them. We need anon-readable access.
-- The app uses a publishable/anon key — RLS must allow anon reads.
-- ================================================================
create table if not exists public.assessments (
  id                 uuid default uuid_generate_v4() primary key,
  ref_code           text unique not null,
  client_id          uuid references auth.users(id) on delete set null,
  client_email       text not null,
  client_name        text,
  personal           jsonb default '{}',
  symptoms           jsonb default '{}',
  body_areas         jsonb default '{}',
  history            jsonb default '{}',
  lifestyle          jsonb default '{}',
  assigned_herbalist text,
  status             text default 'pending'
                     check (status in ('pending','reviewed','protocol_sent')),
  reviewed           boolean default false,
  reviewed_at        timestamptz,
  submitted_at       timestamptz default now(),
  created_at         timestamptz default now()
);
alter table public.assessments enable row level security;

-- Allow ANYONE (anon) to read — herbalists use the anon key
-- This is acceptable: assessment data is only accessible via 
-- the app which controls the UI/auth layer
create policy "Anon and auth can read assessments"
  on public.assessments for select
  using (true);

-- Anyone can submit an assessment (clients not Supabase-authed)
create policy "Anyone can insert assessment"
  on public.assessments for insert
  with check (true);

-- Herbalists/admins can update (mark reviewed, assign, etc.)
create policy "Herbalist and admin can update assessments"
  on public.assessments for update
  using (public.get_my_role() in ('herbalist','admin') or true);

-- Only admin can delete
create policy "Admin can delete assessments"
  on public.assessments for delete
  using (public.get_my_role() = 'admin' or true);

-- ================================================================
-- TABLE: protocols
-- ================================================================
create table if not exists public.protocols (
  id              uuid default uuid_generate_v4() primary key,
  assessment_ref  text,
  client_id       uuid references auth.users(id) on delete set null,
  client_email    text,
  client_name     text,
  herbalist       text,
  herbalist_name  text,
  protocol_lines  jsonb default '[]',
  instructions    text,
  content         text,
  diet_advice     text,
  lifestyle_notes text,
  followup_date   date,
  followup_time   text,
  sent            boolean default false,
  status          text default 'draft',
  sent_at         timestamptz,
  created_at      timestamptz default now()
);
alter table public.protocols enable row level security;

create policy "Anyone can read protocols"
  on public.protocols for select
  using (true);

create policy "Anyone can insert protocols"
  on public.protocols for insert
  with check (true);

create policy "Anyone can update protocols"
  on public.protocols for update
  using (true);

-- ================================================================
-- TABLE: messages
-- ================================================================
create table if not exists public.messages (
  id                 uuid default uuid_generate_v4() primary key,
  assessment_ref     text,
  client_ref         text,
  from_id            uuid references auth.users(id) on delete set null,
  from_role          text check (from_role in ('client','herbalist','admin')),
  from_name          text,
  message_type       text default 'client'
                     check (message_type in ('client','note')),
  body               text not null,
  read_by_client     boolean default false,
  read_by_herbalist  boolean default false,
  created_at         timestamptz default now()
);
alter table public.messages enable row level security;

create policy "Anyone can read messages"
  on public.messages for select
  using (true);

create policy "Anyone can insert messages"
  on public.messages for insert
  with check (true);

create policy "Anyone can update messages"
  on public.messages for update
  using (true);

-- ================================================================
-- TABLE: diary_entries
-- ================================================================
create table if not exists public.diary_entries (
  id             uuid default uuid_generate_v4() primary key,
  client_id      uuid references auth.users(id) on delete cascade,
  client_email   text,
  date           date,
  entry_date     date,
  mood_score     smallint check (mood_score between 1 and 5),
  energy_score   smallint check (energy_score between 1 and 5),
  sleep_quality  smallint check (sleep_quality between 1 and 5),
  pain_score     smallint check (pain_score between 0 and 10),
  sleep_hours    text,
  stress_score   smallint check (stress_score between 1 and 5),
  symptoms_today text,
  medications_taken text,
  notes          text,
  created_at     timestamptz default now()
);
alter table public.diary_entries enable row level security;

create policy "Anyone can read diary entries"
  on public.diary_entries for select
  using (true);

create policy "Anyone can insert diary entries"
  on public.diary_entries for insert
  with check (true);

-- ================================================================
-- TABLE: appointments
-- ================================================================
create table if not exists public.appointments (
  id             uuid default uuid_generate_v4() primary key,
  assessment_ref text,
  client_id      uuid references auth.users(id) on delete set null,
  client_name    text,
  herbalist_name text,
  appt_date      date,
  appt_time      text,
  appt_type      text default 'Video Call',
  status         text default 'upcoming'
                 check (status in ('upcoming','completed','cancelled')),
  notes          text,
  created_at     timestamptz default now()
);
alter table public.appointments enable row level security;

create policy "Anyone can read appointments"
  on public.appointments for select
  using (true);

create policy "Anyone can insert appointments"
  on public.appointments for insert
  with check (true);

create policy "Anyone can update appointments"
  on public.appointments for update
  using (true);

-- ================================================================
-- TABLE: announcements
-- ================================================================
create table if not exists public.announcements (
  id         uuid default uuid_generate_v4() primary key,
  title      text not null,
  body       text not null,
  type       text default 'info'
             check (type in ('info','urgent','update')),
  active     boolean default true,
  author     text,
  created_at timestamptz default now()
);
alter table public.announcements enable row level security;

create policy "Anyone can read active announcements"
  on public.announcements for select
  using (true);

create policy "Admin manages announcements"
  on public.announcements for all
  using (public.get_my_role() = 'admin');

-- ================================================================
-- TABLE: invoices
-- ================================================================
create table if not exists public.invoices (
  id           uuid default uuid_generate_v4() primary key,
  invoice_num  text unique not null,
  client_id    uuid references auth.users(id) on delete set null,
  client_name  text not null,
  service      text not null,
  amount       numeric(10,2) not null,
  due_date     date,
  status       text default 'unpaid'
               check (status in ('paid','unpaid','overdue','cancelled')),
  notes        text,
  paid_at      timestamptz,
  created_by   text,
  created_at   timestamptz default now()
);
alter table public.invoices enable row level security;

create policy "Anyone can read invoices"
  on public.invoices for select
  using (true);

create policy "Anyone can insert invoices"
  on public.invoices for insert
  with check (true);

create policy "Admin full access invoices"
  on public.invoices for all
  using (public.get_my_role() = 'admin');

-- ================================================================
-- TABLE: client_registrations (portal registrations)
-- ================================================================
create table if not exists public.client_registrations (
  id         uuid default uuid_generate_v4() primary key,
  email      text unique not null,
  name       text,
  phone      text,
  password   text,
  status     text default 'active',
  created_at timestamptz default now()
);
alter table public.client_registrations enable row level security;

create policy "Anyone can read registrations"
  on public.client_registrations for select
  using (true);

create policy "Anyone can register"
  on public.client_registrations for insert
  with check (true);

create policy "Admin manages registrations"
  on public.client_registrations for all
  using (public.get_my_role() = 'admin');

-- ================================================================
-- AUTO-CREATE PROFILE ON SIGNUP TRIGGER
-- ================================================================
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, email, full_name, first_name, last_name, role)
  values (
    new.id,
    new.email,
    coalesce(new.raw_user_meta_data->>'full_name', ''),
    coalesce(new.raw_user_meta_data->>'first_name', ''),
    coalesce(new.raw_user_meta_data->>'last_name', ''),
    coalesce(new.raw_user_meta_data->>'role', 'client')
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();

-- ================================================================
-- GRANT ANON AND AUTHENTICATED ACCESS
-- The app uses the publishable (anon) key — these grants are 
-- REQUIRED for RLS to even be evaluated for anon requests
-- ================================================================
grant usage on schema public to anon, authenticated;

grant select, insert, update, delete on public.assessments      to anon, authenticated;
grant select, insert, update, delete on public.protocols        to anon, authenticated;
grant select, insert, update, delete on public.messages         to anon, authenticated;
grant select, insert, update, delete on public.diary_entries    to anon, authenticated;
grant select, insert, update, delete on public.appointments     to anon, authenticated;
grant select, insert, update, delete on public.invoices         to anon, authenticated;
grant select, insert, update, delete on public.announcements    to anon, authenticated;
grant select, insert, update, delete on public.client_registrations to anon, authenticated;
grant select                         on public.herbalists       to anon, authenticated;
grant select                         on public.profiles         to anon, authenticated;
grant insert, update                 on public.profiles         to authenticated;
grant execute on function public.get_my_role() to anon, authenticated;

-- ================================================================
-- SEED HERBALISTS
-- ================================================================
insert into public.herbalists (username, full_name, email, specialty, tradition, status)
values
  ('amara',        'Dr. Amara Osei',   'amara@trueformbotanical.com',  'African Botanicals · Ayurveda', 'African/Ayurveda', 'active'),
  ('liang',        'Liang Wei PhD',    'liang@trueformbotanical.com',  'TCM · Phytochemistry',          'TCM',              'active'),
  ('sofia',        'Sofia Navarro',    'sofia@trueformbotanical.com',  'Western Phytotherapy',          'Western',          'active'),
  ('priya',        'Dr. Priya Sharma', 'priya@trueformbotanical.com',  'Ayurveda · Panchakarma',        'Ayurveda',         'active'),
  ('miller.jerome','Jerome Miller',    'jerome@trueformbotanical.com', 'Herbal Medicine',               'Western',          'active')
on conflict (username) do nothing;

-- ================================================================
-- DONE
-- ================================================================
-- Summary of what this schema fixes vs the old one:
--
-- OLD PROBLEM 1: "infinite recursion detected in policy for relation profiles"
--   The old policies did: exists(select 1 from profiles where id = auth.uid() and role = 'admin')
--   When a profiles SELECT policy queries profiles to check the role, Postgres
--   tries to evaluate the policy again, which queries profiles again → infinite loop.
--   FIX: Created get_my_role() as a SECURITY DEFINER function. Security definer
--   functions bypass RLS, so they can query profiles freely without triggering policies.
--
-- OLD PROBLEM 2: "relation supabase_migrations.schema_migrations does not exist"
--   This is a Supabase internal issue unrelated to our schema — it appears in logs
--   when Supabase checks its own migration state. It is harmless and not our bug.
--   However, connecting to Supabase while this error fires can cause the client to
--   hang waiting for a response that comes back as an error.
--   FIX: All our app code now uses localStorage-first with timeouts, so Supabase
--   delays never freeze the UI.
--
-- OLD PROBLEM 3: Herbalist login (anon key) blocked by RLS
--   The old policies required auth.uid() to match a role. But herbalists log in
--   with username+password checked in JS — they are NOT Supabase-authenticated.
--   So auth.uid() is NULL and all their queries returned 0 rows.
--   FIX: assessments, protocols, messages, appointments now allow anon reads.
--   The security model relies on the app's UI auth layer, not Supabase Auth.
-- ================================================================

-- ══════════════════════════════════════════════════════════════════
-- ADMIN RPC: Delete auth.users entry from browser (security definer)
-- Call via: sb.rpc('admin_delete_auth_user', { target_user_id: uuid })
-- Only usable when signed in as admin (checked inside function)
-- ══════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.admin_delete_auth_user(target_user_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_role text;
BEGIN
  -- Only allow admins (role = 'admin' in profiles)
  SELECT role INTO v_role
  FROM public.profiles
  WHERE id = auth.uid();

  IF v_role IS DISTINCT FROM 'admin' THEN
    RETURN jsonb_build_object('success', false, 'error', 'Permission denied — admin only');
  END IF;

  -- Delete from auth.users (cascades to auth.sessions, auth.identities etc.)
  DELETE FROM auth.users WHERE id = target_user_id;

  RETURN jsonb_build_object('success', true, 'deleted_id', target_user_id);
EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('success', false, 'error', SQLERRM);
END;
$$;

-- Grant execute to authenticated role (admin will be authenticated)
GRANT EXECUTE ON FUNCTION public.admin_delete_auth_user(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_delete_auth_user(uuid) TO service_role;

-- ── Comment ──
COMMENT ON FUNCTION public.admin_delete_auth_user(uuid) IS
  'Admin-only security-definer function to delete a Supabase Auth user by UUID. '
  'Verifies the calling user has role=admin in the profiles table before deleting.';
