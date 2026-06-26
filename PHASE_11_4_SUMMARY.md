# Phase 11.4 Summary

## Goal

Phase 11.4 introduced an experimental shared base-film-response stage so Snaproll no longer treats Kodak Gold 200 and Fujifilm Superia 400 as simple direct filters on the original iPhone image.

The new rendering path is:

`Original UIImage -> CIImage -> BaseFilmRenderer -> stock-specific renderer -> UIImage`

The previous Phase 11.3 renderer path was preserved behind a feature flag so the experiment is easy to disable if the results are not strong enough.

## What Changed

- Added `AppConfig.Rendering.useBaseFilmResponse` in `ios/snaproll/snaproll/Utilities/AppConfig.swift`.
- Preserved the old renderer path in `PhotoRenderService` through `legacyFilmProfile(...)`.
- Added a new shared base-film-response stage in `PhotoRenderService`.
- Added a lightweight `BaseFilmProfile` configuration to drive that shared stage.
- Applied stock-specific Kodak Gold 200 and Fujifilm Superia 400 adjustments after the base-film stage when the feature flag is enabled.
- Regenerated the developer comparison outputs in `render-output/`.

## Feature Flag

The experiment is controlled from:

`ios/snaproll/snaproll/Utilities/AppConfig.swift`

Current flag:

```swift
static let useBaseFilmResponse = true
```

To switch back to the previous renderer, change that value to `false`.

No other code changes are required.

## What BaseFilmRenderer Does

The shared base-film-response stage is designed to reduce the modern smartphone look before Kodak or Superia-specific rendering is applied.

It currently adds:

- softer highlight roll-off
- slightly lifted blacks
- lower microcontrast
- subtle digital softening
- restrained desaturation
- integrated grain that is stronger in shadows and midtones than in highlights

This stage is intentionally subtle.

Its job is not to create a visible “effect” by itself.

Its job is to make the source image feel less clinically digital before stock-specific color character is added.

## Kodak Gold 200 Tuning Decisions

After the new base-film stage, Kodak Gold 200 adds:

- warmer temperature
- soft golden highlights
- slightly richer nostalgic contrast
- warmer but still natural greens
- softer blue handling

The tuning intentionally avoids:

- orange cast
- over-saturated yellow
- crushed shadows

## Fujifilm Superia 400 Tuning Decisions

After the new base-film stage, Fujifilm Superia 400 adds:

- cooler white balance
- subtle green/cyan channel shaping
- deeper foliage
- cooler cyan-blue sky response
- flatter contrast than Kodak Gold
- a cleaner everyday snapshot feel

The tuning intentionally avoids:

- globally boosting green saturation
- teal-orange grading
- exaggerated cool tint

## Render Output Workflow

The same Phase 11.3 batch-render workflow was preserved.

Run:

```bash
tools/run_render_test_images.sh
```

Outputs are written only to:

- `render-output/<image-name>/original.jpg`
- `render-output/<image-name>/kodak-gold.jpg`
- `render-output/<image-name>/fujifilm-superia.jpg`
- `render-output/contact-sheets/`

The batch utility now compiles with `AppConfig.swift`, so the generated output respects the same `useBaseFilmResponse` flag as the app.

## Evaluation

Using the local `film-references/kodak-gold/`, `film-references/fujifilm-superia/`, and `test-images/` folders, the new base-film path appears to move the rendered output closer to real scanned consumer film in a few ways:

- highlights feel less harsh
- blacks feel less crushed
- textures feel slightly less digitally sharpened
- Kodak and Superia differences now sit on top of a more film-like shared response

This is still a subjective visual improvement rather than a scientifically matched emulation.

The best next validation step is to review the generated contact sheets on a good display and compare them against real iPhone captures rendered through both the new and legacy paths.

The current renderer is now accepted as the Snaproll MVP baseline and should not be casually retuned outside a dedicated rendering workflow.

## Known Limitations

- The experiment still uses fast Core Image operations rather than LUTs or a full scan-emulation pipeline.
- The base-film stage is shared across stocks, so deeper per-stock tonal behavior may still need more tuning later.
- Grain is intentionally restrained and procedural, not stock-accurate.
- Visual evaluation remains human-judgment-driven.

## Build And Verification

- Regenerated render outputs successfully with `tools/run_render_test_images.sh`.
- Verified the iPhone target builds successfully with `xcodebuild` after the Phase 11.4 changes.

## Recommended Next Steps

- Compare the new contact sheets against the local film reference folders on a calibrated display.
- Decide whether `useBaseFilmResponse` should remain enabled by default.
- Continue refining stock-specific skin tone, foliage, and sky behavior on top of the shared base-film response.
- Restore `AppConfig.Rolls.minimumShotLimit` to `24` before release.
