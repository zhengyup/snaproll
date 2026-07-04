# Phase 11.1 Summary

## Work Completed

- Preserved the existing rendering architecture inside `PhotoRenderService`.
- Reworked the renderer around internal film profiles so each stock now defines its own:
  - tone curve
  - highlight and shadow behavior
  - subtle softening
  - grain intensity
  - vignette
- Improved Kodak Gold 200 with warmer midtones, richer contrast, and softer highlights.
- Improved Fujifilm Superia 400 with cooler balance, more believable greens and blues, softer highlight handling, and restrained saturation.
- Improved black-and-white rendering with deeper tonal separation, smoother highlight roll-off, and stronger but still controlled grain.
- Reduced the testing shot limit from `3` to `1` in `ios/snaproll/snaproll/Utilities/AppConfig.swift` for faster manual renderer iteration.

## Tone Curve Decisions

- Tone curves are now a primary contributor to the film look rather than simple saturation and contrast changes.
- Kodak Gold 200:
  - slightly lifted black floor
  - warmer-feeling midtone openness
  - softer top-end highlight finish
- Fujifilm Superia 400:
  - lifted blacks
  - gentler midtone contrast
  - softer highlight roll-off
- Black & White:
  - deeper blacks
  - stronger tonal separation
  - smoother monochrome highlight response

## Highlight Handling

- Highlight roll-off is now shaped by the stock tone curves and then refined with `CIHighlightShadowAdjust`.
- This reduces the harsher clipped-digital feel in bright skies and bright objects.
- The result is intentionally subtle and aimed at a more scanned-film response rather than a dramatic filter look.

## Grain Improvements

- Grain is still procedural and generated on-device with Core Image.
- It is now:
  - softer overall
  - weighted more toward shadows and midtones
  - weaker in bright highlights
  - stronger for black and white than for color stocks
- The goal is to feel closer to film texture and less like a flat overlay.

## Digital Softness

- Added a subtle post-reduction softening stage to reduce the over-crisp digital look from modern iPhone images.
- The softening is intentionally low-opacity so images stay clear and not blurry.

## Testing Configuration

- Development tuning now uses:
  - `AppConfig.Rolls.minimumShotLimit = 1`
- This lives in:
  - [AppConfig.swift](/Users/zhengyu/Desktop/projects/snaproll/ios/snaproll/snaproll/Utilities/AppConfig.swift)
- Restore that value to `24` before release.

## Known Limitations

- The renderer is still an approximation using fast Core Image operations, not a true scanned-film emulation.
- This phase was build-verified for iPhone, but not visually tuned on a real device from inside Codex.
- Rendered images are still cached in memory only.
- `PHASE_11_SUMMARY.md` was referenced by the prompt but is not currently present in the repository.

## Future Improvements

- Tune the new profiles against real outdoor and skin-tone captures on an actual iPhone.
- Revisit per-stock grain characteristics once real-device comparisons are available.
- Consider additional subtle stock-specific color shaping only after validating that the current tone-curve-first approach remains natural.
