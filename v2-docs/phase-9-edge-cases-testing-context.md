# Phase 9 – Edge Cases + Testing Context

## Relevant Architecture

Exceptional flows explicitly called out by the architecture:

- hidden force reveal action
- partial gallery support
- failed upload UI
- retry controls
- offline messaging

Key local-first / sync edge cases:

- capture works offline
- shared lifecycle actions do not queue offline
- uploaded photos are recoverable from Supabase
- local-only photos are lost if the app is deleted before upload

Critical sync states:

```text
EMPTY
LOCAL_ONLY
UPLOADING
METADATA_PENDING
SYNCED
FAILED
```

Critical retry logic:

```text
If storage_path exists locally, retry complete_exposure().
If storage_path does not exist, retry upload.
```

Force Reveal edge-case behavior:

- uploaded photos are included
- empty exposures are lost
- roll becomes `REVEALED`

Deletion policy:

- creator can delete before start only
- after start, roll cannot be deleted in V2
- revealed rolls cannot be deleted in V2

Testing focus from roadmap:

- lobby joins/removes
- start roll transaction
- upload failure before Storage
- upload failure after Storage before RPC
- app killed during upload
- reveal readiness
- force reveal
- reinstall recovery for uploaded photos

## Invariants That Must Not Be Violated

- Failed uploads must never overwrite a filled exposure.
- `METADATA_PENDING` must be recoverable.
- Force Reveal must not discard already-uploaded photos.
- Upload completion requires both Storage upload and successful `complete_exposure()`.
- Offline capture must continue working even when shared cloud actions fail.
- After start, roll deletion must remain disallowed.
