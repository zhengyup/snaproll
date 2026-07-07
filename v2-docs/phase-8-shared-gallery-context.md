# Shared Gallery Context

## Roadmap Placement

This document now maps to roadmap Phase 11.

## Relevant Architecture

Gallery behavior for shared rolls:

- gallery is available after `REVEALED`
- exposures are grouped by participant
- not displayed in one global chronological stream

Example:

```text
You
□□□□□□

Sarah
□□□□□□

Alex
□□□□□□
```

Intended feel:

- like opening each person’s disposable camera separately

Reveal/gallery loading flow:

```text
Fetch roll metadata
↓
Fetch participants
↓
Fetch filled exposures
↓
Download originals
↓
Render locally
↓
Cache previews
↓
Display progressively
```

Rendering architecture:

- rendering happens entirely on-device
- cloud stores original JPEG, `film_stock_id`, and `render_seed`
- rendered output is derived from:

```text
original JPEG
+ film_stock_id
+ render_seed
+ renderer_version
```

- no backend rendering
- no rendered files in Supabase Storage
- device may cache rendered previews locally

Repository responsibilities likely involved:

- `ExposureRepository.downloadRevealedExposures(rollId)`
- `RenderCacheRepository.getRenderedImage(exposureId)`
- `RenderCacheRepository.renderAndCache(exposureId)`

## Invariants That Must Not Be Violated

- Shared gallery must group by participant, not by global chronology.
- Gallery display must not block on caching every image before first render.
- Cloud stores only canonical originals, not rendered derivatives.
- Rendering remains on-device only.
- Historical photos must remain re-renderable if renderer versions change later.
