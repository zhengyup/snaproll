# Start Roll + Exposure Creation Context

## Roadmap Placement

This document now maps to roadmap Phase 8.

## Relevant Architecture

When the creator presses `Start Roll`:

- participant list locks
- film stock locks
- exposure count locks
- invite link no longer allows joining
- exposure slots are pre-created for every participant
- roll enters `SHOOTING`

Only the roll title remains editable after start.

Exposure model:

```text
Roll
 └── Participant
      ├── Exposure 1
      ├── Exposure 2
      └── ...
```

Exposure fields relevant here:

- owner participant
- exposure number
- optional uploaded image path
- render seed

Cloud exposure immutability:

```text
EMPTY exposure → can be completed once
FILLED exposure → immutable
```

`start_roll()` is responsible for:

- validating creator ownership
- validating waiting state
- validating participant count
- validating film stock and exposure count
- creating all exposure slots transactionally
- changing participant state to `SHOOTING`
- changing roll state to `SHOOTING`

Local data layer must sync exposure slots into SwiftData after start.

## Invariants That Must Not Be Violated

- Exposure slots must be pre-created at start, not lazily created during capture.
- `start_roll()` must be the only way shared rolls enter `SHOOTING`.
- Participant list, exposure count, and film stock must become locked after start.
- No joining after start, even if an invite token still exists.
- Exposure slots must be unique per `(participant_id, exposure_number)`.
- Filled exposures are immutable and may not be replaced.
