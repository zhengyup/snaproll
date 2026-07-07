# Development Authentication Context

## Roadmap Placement

This document maps to roadmap Phase 6.

It follows:

- Phase 4 — Supabase networking foundation
- Phase 5 — session bootstrap

It must precede:

- personal-roll ownership enforcement
- cloud-backed personal roll creation
- shared-roll lobby work
- start-roll shared flows
- capture/upload shared sync flows

## Relevant Architecture

Development Authentication exists to let Snaproll V2 shared-roll features be built and manually tested without depending on production sign-in providers.

It also exists to prove that the V2 personal-roll pipeline is properly user-scoped before multi-user shared-roll work begins.

Core rules:

- authentication remains provider-agnostic
- `AuthRepository` is the only authentication boundary
- shared-roll features must never depend directly on Google Sign-In or Apple Sign In
- production authentication must be swappable later without shared-roll logic changes

Acceptable development-auth behavior:

- fixed development identities
- selectable development identities
- development-only bootstrap into a signed-in V2 session

Development auth still needs to satisfy backend invariants:

- shared-roll RPCs require an authenticated Supabase user
- a matching `profiles` row must exist before business RPCs run

## Invariants That Must Not Be Violated

- V1 behavior remains unchanged when V2 flags are disabled.
- Development auth must be gated behind development/debug configuration.
- Shared-roll code must continue depending only on `AuthRepository`.
- Development identities must be stable enough for repeatable shared-roll testing.
- Development identities must be stable enough for repeatable personal-roll ownership testing before shared-roll work begins.
- Profile ensuring must happen before shared-roll RPC usage.
- This phase does not introduce production authentication UI.
