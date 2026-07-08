# V2 Cloud Personal Roll Foundation Context

## Roadmap Placement

This document maps to roadmap Phase 7.

It follows:

- Phase 5 — session bootstrap
- Phase 6 — Development Authentication

It must be proven before:

- Phase 8 personal-roll shooting and exposure-slot mirroring
- Phase 9 upload / sync
- shared roll creation
- invite / join flows
- participant-scoped shared capture

## Relevant Architecture

This phase establishes that personal rolls belong to the current authenticated user in the V2 cloud-backed path.

Focus areas:

- enforce current-user ownership
- create personal rolls through V2 repositories and RPCs
- fetch only the current user’s personal rolls
- verify that switching development identity changes visible personal rolls
- keep V1 behavior unchanged behind the feature flag

Personal rolls are the proving ground for the V2 architecture.

Shared rolls must later reuse:

- ownership rules
- personal roll creation path
- cloud lifecycle transitions
- exposure-slot lifecycle after `start_roll()`
- exposure loading
- reveal/gallery loading

## Invariants That Must Not Be Violated

- V1 remains unchanged while the V2 feature flag is off.
- Personal roll ownership must be scoped to the authenticated current user.
- Shared-roll UI assumptions must not leak into the personal-roll proving path.
- `AuthRepository` remains the only identity boundary consumed by the V2 UI and ViewModels.
- Cloud-backed personal roll loading must prove the repository path before shared-roll work begins.
