# Capture + Sync Context

## Roadmap Placement

This document now maps to roadmap Phase 9.

## Relevant Architecture

This phase describes the V2 personal-roll upload and sync pipeline after Phase 8 has already proven local-first shooting and exposure-slot filling.

Shared-roll capture should later reuse the same pipeline with participant-specific ownership layered on top.

Phase boundary:

```text
Phase 8
Capture
↓
Save locally
↓
Mark LOCAL_ONLY
↓
Continue shooting

Phase 9
Pick LOCAL_ONLY exposure
↓
Generate JPEG upload copy
↓
Upload to Storage
↓
Call complete_exposure(exposure_id, storage_path)
↓
Transition to SYNCED
```

Capture is local-first:

```text
Capture
↓
Save locally
↓
Mark LOCAL_ONLY
↓
Continue shooting
```

Network is not required to take photos, and capture must not directly perform uploads.

Shared exposure upload flow:

```text
Capture into next empty exposure
↓
Save local original
↓
Convert upload copy to JPEG
↓
Upload to Supabase Storage
↓
Call complete_exposure(exposure_id, storage_path)
```

Cloud canonical storage:

- bucket: `snaproll-originals`
- path: `rolls/{roll_id}/participants/{participant_id}/{exposure_number}.jpg`
- format: JPEG only

Local sync states:

```text
EMPTY
LOCAL_ONLY
UPLOADING
METADATA_PENDING
SYNCED
FAILED
```

Required transition model:

```text
EMPTY
→ capture
→ LOCAL_ONLY

LOCAL_ONLY
→ start upload
→ UPLOADING

UPLOADING
→ storage upload succeeds
→ METADATA_PENDING

UPLOADING
→ storage upload fails
→ FAILED

METADATA_PENDING
→ complete_exposure succeeds
→ SYNCED

METADATA_PENDING
→ complete_exposure fails
→ FAILED

FAILED
→ retry
→ LOCAL_ONLY or METADATA_PENDING
```

Upload rules:

- capture never waits for upload
- upload in exposure-number order per participant
- one upload at a time per participant for V2
- failed uploads retry automatically
- upload is complete only after Storage upload and `complete_exposure()` both succeed
- Phase 8 must stop before upload begins
- Phase 9 owns upload, retry, and metadata reconciliation

Retry rule:

```text
If storage_path exists locally, retry complete_exposure().
If storage_path does not exist, retry upload.
```

## Invariants That Must Not Be Violated

- Camera must work offline.
- Capture must never block on network.
- Phase 8 local capture and Phase 9 sync must remain separate responsibilities.
- Only the next empty exposure for that participant can be filled.
- Storage upload alone does not complete an exposure.
- `complete_exposure()` must validate ownership, roll state, emptiness, and expected path.
- Cloud originals are JPEG only.
- No exposure overwrite, replacement, or retake support.
