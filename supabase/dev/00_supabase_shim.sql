-- Minimal local stand-in for the Supabase platform schemas so the project's
-- migrations run on a plain PostgreSQL for development and integration tests.
-- NOT for production: Supabase provides the real auth/storage/extensions.
do $$ begin
  if not exists (select 1 from pg_roles where rolname='anon') then create role anon nologin noinherit; end if;
  if not exists (select 1 from pg_roles where rolname='authenticated') then create role authenticated nologin noinherit; end if;
  if not exists (select 1 from pg_roles where rolname='service_role') then create role service_role nologin noinherit bypassrls; end if;
  if not exists (select 1 from pg_roles where rolname='authenticator') then create role authenticator login noinherit; end if;
  if not exists (select 1 from pg_roles where rolname='supabase_admin') then create role supabase_admin nologin; end if;
end $$;
grant anon, authenticated, service_role to authenticator;
grant anon, authenticated, service_role to postgres;

create schema if not exists extensions;
create extension if not exists pgcrypto with schema extensions;
create extension if not exists "uuid-ossp" with schema extensions;
create extension if not exists pg_stat_statements with schema extensions;
grant usage on schema extensions to anon, authenticated, service_role;

create schema if not exists auth;
grant usage on schema auth to anon, authenticated, service_role;
create table if not exists auth.users (
  instance_id uuid, id uuid primary key default gen_random_uuid(), aud text default 'authenticated', role text default 'authenticated',
  email text, encrypted_password text, email_confirmed_at timestamptz, invited_at timestamptz, confirmation_token text,
  confirmation_sent_at timestamptz, recovery_token text, recovery_sent_at timestamptz, email_change_token_new text, email_change text,
  email_change_sent_at timestamptz, last_sign_in_at timestamptz, raw_app_meta_data jsonb default '{}'::jsonb, raw_user_meta_data jsonb default '{}'::jsonb,
  is_super_admin boolean, created_at timestamptz default now(), updated_at timestamptz default now(), phone text, phone_confirmed_at timestamptz,
  phone_change text, phone_change_token text, phone_change_sent_at timestamptz, confirmed_at timestamptz, email_change_token_current text,
  email_change_confirm_status smallint, banned_until timestamptz, reauthentication_token text, reauthentication_sent_at timestamptz,
  is_sso_user boolean default false, deleted_at timestamptz, is_anonymous boolean default false
);
create table if not exists auth.sessions (id uuid primary key default gen_random_uuid(), user_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz default now(), updated_at timestamptz default now(), factor_id uuid, aal text default 'aal1', not_after timestamptz,
  refreshed_at timestamp, user_agent text, ip inet, tag text);
create table if not exists auth.identities (id uuid primary key default gen_random_uuid(), provider_id text, user_id uuid references auth.users(id) on delete cascade,
  identity_data jsonb, provider text, last_sign_in_at timestamptz, created_at timestamptz default now(), updated_at timestamptz default now(), email text);
create table if not exists auth.mfa_factors (id uuid primary key default gen_random_uuid(), user_id uuid references auth.users(id) on delete cascade,
  friendly_name text, factor_type text, status text, created_at timestamptz default now(), updated_at timestamptz default now(), secret text, phone text, last_challenged_at timestamptz);
create table if not exists auth.mfa_amr_claims (id uuid primary key default gen_random_uuid(), session_id uuid references auth.sessions(id) on delete cascade,
  created_at timestamptz default now(), updated_at timestamptz default now(), authentication_method text);

create or replace function auth.jwt() returns jsonb language sql stable as $$
  select coalesce(nullif(current_setting('request.jwt.claim', true), ''), nullif(current_setting('request.jwt.claims', true), ''))::jsonb $$;
create or replace function auth.uid() returns uuid language sql stable as $$
  select coalesce(nullif(current_setting('request.jwt.claim.sub', true), ''), (auth.jwt() ->> 'sub'))::uuid $$;
create or replace function auth.role() returns text language sql stable as $$
  select coalesce(nullif(current_setting('request.jwt.claim.role', true), ''), (auth.jwt() ->> 'role'))::text $$;
create or replace function auth.email() returns text language sql stable as $$ select auth.jwt() ->> 'email' $$;
grant execute on function auth.jwt(), auth.uid(), auth.role(), auth.email() to anon, authenticated, service_role;

create schema if not exists storage;
grant usage on schema storage to anon, authenticated, service_role;
create table if not exists storage.buckets (id text primary key, name text not null, owner uuid, created_at timestamptz default now(),
  updated_at timestamptz default now(), public boolean default false, avif_autodetection boolean default false,
  file_size_limit bigint, allowed_mime_types text[], owner_id text);
create table if not exists storage.objects (id uuid primary key default gen_random_uuid(), bucket_id text references storage.buckets(id),
  name text, owner uuid, created_at timestamptz default now(), updated_at timestamptz default now(), last_accessed_at timestamptz default now(),
  metadata jsonb, path_tokens text[] generated always as (string_to_array(name, '/')) stored, version text, owner_id text, user_metadata jsonb);
alter table storage.objects enable row level security;
alter table storage.buckets enable row level security;
create or replace function storage.foldername(name text) returns text[] language plpgsql as $$
declare _parts text[]; begin select string_to_array(name, '/') into _parts; return _parts[1:array_length(_parts,1)-1]; end $$;
grant all on storage.objects, storage.buckets to anon, authenticated, service_role;

-- Supabase grants table/function/sequence privileges in public to the API roles by default.
grant usage on schema public to anon, authenticated, service_role;
alter default privileges in schema public grant all on tables to anon, authenticated, service_role;
alter default privileges in schema public grant all on functions to anon, authenticated, service_role;
alter default privileges in schema public grant all on sequences to anon, authenticated, service_role;
