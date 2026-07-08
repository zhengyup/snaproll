# V2 Personal Roll Shooting & Exposure Slots Context

## Roadmap Placement

This document maps to roadmap Phase 8.

It follows:

- Phase 7 — V2 Cloud Personal Roll Foundation

It must be completed before:

- Phase 9 — V2 Capture → Upload → Sync
- Phase 10 — V2 Personal Reveal & Gallery

## Relevant Architecture

This phase proves that a cloud-backed V2 personal roll can enter `SHOOTING` while still preserving Snaproll's local-first capture model.

Phase 8 responsibilities:

- call `start_roll()` for a personal roll where appropriate
- fetch cloud-created exposure slots
- mirror those slots into local exposure records
- show V2 personal roll detail
- show progress and remaining exposures
- capture into the next empty exposure
- save the captured original locally
- mark the local exposure as `LOCAL_ONLY`

Phase 8 intentionally stops before upload:

```text
start_roll()
↓
fetch exposures
↓
mirror to local model
↓
capture photo
↓
save local original
↓
set sync_state = LOCAL_ONLY
↓
return to shooting flow
```

Phase 8 must not:

- upload bytes to Supabase Storage
- call `complete_exposure()`
- implement retry logic
- reveal hidden photos in normal user mode

## Development Visibility for Hidden Photos

Normal user mode must keep captured photos hidden until reveal.

For development only, a debug flag may expose verification details such as:

- exposure number
- local sync state
- local file path
- whether the original file exists
- optional local thumbnail or preview
- pending upload count

This visibility must remain:

- debug-only
- easy to disable
- separate from normal user-mode behavior

## Invariants That Must Not Be Violated

- Personal-roll capture remains local-first.
- Capture must not block on network availability.
- Phase 8 must not upload photos or complete exposures in cloud.
- Hidden-film behavior remains the default in normal user mode.
- Local exposure records must mirror cloud-created exposure slots rather than inventing local-only slot numbering.
