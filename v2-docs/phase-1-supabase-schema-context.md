# Phase 1 – Supabase Schema Context

## Roadmap Placement

This document still maps directly to roadmap Phase 1.

## Relevant Architecture

Supabase is the backend for V2. No custom backend server is required.

Required cloud entities:

```text
profiles
rolls
roll_participants
exposures
invites
```

### profiles

```sql
profiles
- id uuid primary key references auth.users(id)
- display_name text
- avatar_url text nullable
- created_at timestamptz
```

### rolls

```sql
rolls
- id uuid primary key
- creator_id uuid references profiles(id)
- title text
- type text check ('PERSONAL', 'SHARED')
- status text check (
    'DRAFT',
    'WAITING_FOR_PARTICIPANTS',
    'SHOOTING',
    'READY_TO_REVEAL',
    'REVEALED'
  )
- film_stock_id text
- exposures_per_participant int check (exposures_per_participant in (12, 24, 36))
- participant_cap int default 10
- started_at timestamptz nullable
- ready_to_reveal_at timestamptz nullable
- revealed_at timestamptz nullable
- created_at timestamptz
- updated_at timestamptz
```

### roll_participants

```sql
roll_participants
- id uuid primary key
- roll_id uuid references rolls(id) on delete cascade
- user_id uuid references profiles(id)
- status text check ('JOINED', 'SHOOTING', 'FINISHED')
- joined_at timestamptz
- finished_at timestamptz nullable

unique (roll_id, user_id)
```

### exposures

```sql
exposures
- id uuid primary key
- roll_id uuid references rolls(id) on delete cascade
- participant_id uuid references roll_participants(id) on delete cascade
- exposure_number int
- storage_path text nullable
- render_seed text not null
- captured_at timestamptz nullable
- uploaded_at timestamptz nullable
- created_at timestamptz

unique (participant_id, exposure_number)
check (exposure_number >= 1)
```

`roll_id` is duplicated intentionally for easier queries.

### invites

```sql
invites
- id uuid primary key
- roll_id uuid references rolls(id) on delete cascade
- token text unique not null
- created_by uuid references profiles(id)
- is_active boolean default true
- created_at timestamptz
- revoked_at timestamptz nullable
```

Invite rules:

- One active invite per roll
- Token is random and unguessable
- Invite remains viewable after start, but cannot be used to join

Indexes:

```sql
rolls(creator_id)
roll_participants(user_id)
roll_participants(roll_id)
exposures(roll_id)
exposures(participant_id)
invites(token)
```

## Invariants That Must Not Be Violated

- There is no separate cloud `Photo` table.
- A filled exposure is defined by `storage_path != null`.
- Exposure slots are immutable once filled.
- `title` is not unique.
- `creator_id` must identify the roll owner.
- `unique (roll_id, user_id)` must prevent duplicate participation.
- `unique (participant_id, exposure_number)` must prevent duplicate exposure slots.
- Shared-roll deletion before start must cascade through participants, exposures, and invites.
