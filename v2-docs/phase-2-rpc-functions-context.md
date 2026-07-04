# Phase 2 – RPC Functions Context

## Relevant Architecture

Business transitions must go through RPC functions.

Clients must not directly mutate lifecycle state.

Required RPCs:

```text
create_roll()
join_roll(invite_token)
leave_roll(roll_id)
start_roll(roll_id)
reveal_roll(roll_id)
force_reveal_roll(roll_id)
regenerate_invite(roll_id)
complete_exposure(exposure_id, storage_path)
```

RPCs own changes to:

```text
roll.status
roll.started_at
roll.ready_to_reveal_at
roll.revealed_at
participant.status
participant.finished_at
exposure.storage_path
exposure.uploaded_at
invite.is_active
invite.revoked_at
```

### start_roll()

Must validate:

- caller is creator
- roll is waiting
- participant count is between 1 and cap
- film stock is valid
- exposure count is valid

Then it must:

- lock participant list
- lock film stock
- lock exposure count
- create exposure slots
- deactivate invite joining
- set participants to `SHOOTING`
- set roll to `SHOOTING`

### complete_exposure()

Required flow:

```text
Client uploads JPEG to Supabase Storage
↓
Client calls complete_exposure(exposure_id, storage_path)
↓
RPC validates ownership, roll state, exposure emptiness, and expected path
↓
RPC fills exposure
↓
RPC checks participant completion
↓
RPC checks roll completion
↓
Transaction commits
```

## Invariants That Must Not Be Violated

- Clients may upload bytes, but RPCs own business state.
- No direct lifecycle mutation from the client.
- `start_roll()` must create exposure slots transactionally.
- `complete_exposure()` must only fill an empty exposure once.
- Force Reveal must preserve already-uploaded photos and discard only empty exposures.
- Only the creator can reveal or force reveal.
- Joining after roll start must be impossible even if an invite token is still viewable.
