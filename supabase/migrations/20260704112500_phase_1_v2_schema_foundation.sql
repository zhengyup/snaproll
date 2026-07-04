-- Snaproll V2 Phase 1
-- Initial authoritative cloud data model foundation.
--
-- This migration intentionally creates only:
-- - core tables
-- - relational constraints
-- - baseline indexes
-- - updated_at / immutability helpers
-- - initial RLS skeleton
--
-- It intentionally does NOT create:
-- - RPC functions
-- - storage buckets
-- - storage policies
-- - auth/profile sync triggers
-- - exposure slot creation logic

create extension if not exists pgcrypto with schema extensions;

-- Shared helper for updated_at columns.
create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = timezone('utc', now());
  return new;
end;
$$;

-- Exposure slots are immutable once filled.
-- This enforces the architecture invariant:
-- EMPTY exposure -> may be filled once
-- FILLED exposure -> cannot be replaced
create or replace function public.prevent_filled_exposure_mutation()
returns trigger
language plpgsql
as $$
begin
  if old.storage_path is not null then
    if new.storage_path is distinct from old.storage_path
      or new.captured_at is distinct from old.captured_at
      or new.uploaded_at is distinct from old.uploaded_at
      or new.render_seed is distinct from old.render_seed then
      raise exception using
        errcode = 'check_violation',
        message = 'Filled exposures cannot change storage_path, captured_at, uploaded_at, or render_seed.';
    end if;
  end if;

  return new;
end;
$$;

create table if not exists public.profiles (
  id uuid primary key references auth.users (id),
  display_name text,
  avatar_url text,
  created_at timestamptz not null default timezone('utc', now())
);

create table if not exists public.rolls (
  id uuid primary key default gen_random_uuid(),
  creator_id uuid not null references public.profiles (id),
  title text not null,
  type text not null,
  status text not null,
  film_stock_id text not null,
  exposures_per_participant integer not null,
  participant_cap integer not null default 10,
  started_at timestamptz,
  ready_to_reveal_at timestamptz,
  revealed_at timestamptz,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint rolls_type_check
    check (type in ('PERSONAL', 'SHARED')),
  constraint rolls_status_check
    check (status in ('DRAFT', 'WAITING_FOR_PARTICIPANTS', 'SHOOTING', 'READY_TO_REVEAL', 'REVEALED')),
  constraint rolls_exposures_per_participant_check
    check (exposures_per_participant in (12, 24, 36)),
  constraint rolls_participant_cap_check
    check (participant_cap >= 1)
);

create table if not exists public.roll_participants (
  id uuid primary key default gen_random_uuid(),
  roll_id uuid not null references public.rolls (id) on delete cascade,
  user_id uuid not null references public.profiles (id),
  status text not null,
  joined_at timestamptz not null default timezone('utc', now()),
  finished_at timestamptz,
  constraint roll_participants_status_check
    check (status in ('JOINED', 'SHOOTING', 'FINISHED')),
  constraint roll_participants_roll_user_unique
    unique (roll_id, user_id),
  constraint roll_participants_id_roll_unique
    unique (id, roll_id)
);

create table if not exists public.exposures (
  id uuid primary key default gen_random_uuid(),
  roll_id uuid not null references public.rolls (id) on delete cascade,
  participant_id uuid not null,
  exposure_number integer not null,
  storage_path text,
  render_seed text not null,
  captured_at timestamptz,
  uploaded_at timestamptz,
  created_at timestamptz not null default timezone('utc', now()),
  constraint exposures_number_check
    check (exposure_number >= 1),
  constraint exposures_timestamps_when_empty_check
    check (
      storage_path is not null
      or (captured_at is null and uploaded_at is null)
    ),
  constraint exposures_participant_slot_unique
    unique (participant_id, exposure_number),
  constraint exposures_participant_roll_fk
    foreign key (participant_id, roll_id)
    references public.roll_participants (id, roll_id)
    on delete cascade
);

create table if not exists public.invites (
  id uuid primary key default gen_random_uuid(),
  roll_id uuid not null references public.rolls (id) on delete cascade,
  token text not null,
  created_by uuid not null references public.profiles (id),
  is_active boolean not null default true,
  created_at timestamptz not null default timezone('utc', now()),
  revoked_at timestamptz,
  constraint invites_token_unique
    unique (token)
);

create index if not exists idx_rolls_creator_id
  on public.rolls (creator_id);

create index if not exists idx_roll_participants_user_id
  on public.roll_participants (user_id);

create index if not exists idx_roll_participants_roll_id
  on public.roll_participants (roll_id);

create index if not exists idx_exposures_roll_id
  on public.exposures (roll_id);

create index if not exists idx_exposures_participant_id
  on public.exposures (participant_id);

-- Enforce exactly one active invite per roll.
create unique index if not exists idx_invites_one_active_per_roll
  on public.invites (roll_id)
  where is_active = true and revoked_at is null;

drop trigger if exists set_rolls_updated_at on public.rolls;
create trigger set_rolls_updated_at
before update on public.rolls
for each row
execute function public.set_updated_at();

drop trigger if exists prevent_filled_exposure_mutation on public.exposures;
create trigger prevent_filled_exposure_mutation
before update on public.exposures
for each row
when (old.storage_path is not null)
execute function public.prevent_filled_exposure_mutation();

alter table public.profiles enable row level security;
alter table public.rolls enable row level security;
alter table public.roll_participants enable row level security;
alter table public.exposures enable row level security;
alter table public.invites enable row level security;

-- Initial RLS skeleton only.
-- TODO: Add real policies for profiles in the dedicated RLS implementation phase.
-- TODO: Add real policies for rolls in the dedicated RLS implementation phase.
-- TODO: Add real policies for roll_participants in the dedicated RLS implementation phase.
-- TODO: Add real policies for exposures in the dedicated RLS implementation phase.
-- TODO: Add real policies for invites in the dedicated RLS implementation phase.
