# Phase 7 – Reveal Flow Context

## Relevant Architecture

Shared reveal lifecycle:

```text
SHOOTING
↓
READY_TO_REVEAL
↓
REVEALED
```

A participant is `FINISHED` only when all of their exposures are synced to cloud.

A roll becomes `READY_TO_REVEAL` when all participants are finished.

Reveal is a cloud event:

```text
All participants FINISHED
↓
Roll READY_TO_REVEAL
↓
Creator presses Reveal Roll
↓
Roll REVEALED
```

Only the creator can reveal.

Force Reveal is a hidden escape hatch under:

```text
⋯
Manage Roll
Force Reveal
```

Force Reveal behavior:

- uploaded photos are included
- empty exposures are lost
- roll immediately becomes `REVEALED`
- no partial uploaded photos are discarded

Shared lifecycle actions such as reveal and force reveal require cloud connectivity and are not queued offline.

Polling during shooting / waiting:

```text
Refresh every 10–15 seconds
```

Also refresh:

- on pull-to-refresh
- on app foreground
- after key actions
- after upload completion

## Invariants That Must Not Be Violated

- Roll readiness is based on synced cloud state, not just local capture state.
- Only the creator can reveal or force reveal.
- Reveal must be a cloud-owned transition.
- Force Reveal must include uploaded photos and discard only empty exposure slots.
- Shared lifecycle actions are not queued offline in V2.
