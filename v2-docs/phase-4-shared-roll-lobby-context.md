# Phase 4 – Shared Roll Lobby Context

## Relevant Architecture

This phase covers shared rolls before `Start Roll`.

Lifecycle:

```text
DRAFT
↓
WAITING_FOR_PARTICIPANTS
```

Before Start Roll, creator may:

- rename roll
- change film stock
- change exposure count
- invite participants
- remove participants
- delete roll

Before Start Roll, participants may:

- join
- leave

Leaving and removal before Start both hard-delete the participant row.

Creator counts as a participant.

Invite rules:

- one active invite per roll
- invite token is random and unguessable
- invite remains viewable after start, but cannot be used to join

Polling for lobby:

```text
Refresh every 3–5 seconds
```

Also refresh:

- on pull-to-refresh
- on app foreground
- after key actions

Repositories involved:

- `RollRepository`
- `ParticipantRepository`
- `InviteRepository`

## Invariants That Must Not Be Violated

- Shared lobby membership must remain mutable only before start.
- Creator is always treated as a participant.
- `unique (roll_id, user_id)` must still prevent duplicate joins.
- Joining shared rolls must happen through `join_roll()`, not direct inserts.
- Participant removal or leaving before start must hard-delete the participant row.
- Roll deletion is allowed only before start.
- Polling, not Realtime, is the MVP update mechanism.
