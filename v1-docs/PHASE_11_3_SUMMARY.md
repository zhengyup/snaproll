# Phase 11.3 Summary

## Reference Observations

### Kodak Gold 200

- Warm overall daylight balance.
- Golden but soft highlights rather than orange highlights.
- Blues are gentler and less clinical.
- Greens stay natural and slightly warmed.
- Contrast feels nostalgic and pleasant, not punchy.
- Skin tones feel warm and friendly without turning red.
- Grain is present but fine.

### Fujifilm Superia 400

- Cooler white balance overall.
- Greens are deeper and slightly cooler.
- Skies lean cooler blue with a mild cyan influence.
- Skin tones stay more neutral than Kodak Gold.
- Contrast feels a touch softer and cleaner than Kodak Gold.
- The overall mood feels more everyday snapshot than golden-hour nostalgia.
- Grain is fine and restrained.

## Rendering Changes Made

- Preserved the existing `PhotoRenderService` and `FilmProfile` architecture.
- Refactored the renderer so the same service can now produce `CGImage` output for developer batch evaluation.
- Tuned Kodak Gold 200 with:
  - warmer temperature
  - slightly softer blues
  - warmer midtones
  - gentle highlight lift
  - softer vignette
- Tuned Fujifilm Superia 400 with:
  - cooler white balance
  - greener foliage bias
  - slightly cooler skies
  - more neutral overall saturation
  - softer contrast than Kodak Gold
- Kept grain subtle and shadow-weighted in both stocks.

## Test Rendering Utility

Developer utility files:

- [render_test_images.swift](/Users/zhengyu/Desktop/projects/snaproll/tools/render_test_images.swift)
- [run_render_test_images.sh](/Users/zhengyu/Desktop/projects/snaproll/tools/run_render_test_images.sh)

Run from the repository root with:

```bash
tools/run_render_test_images.sh
```

This compiles the utility locally and uses the real `PhotoRenderService` plus `FilmStock` model from the app codebase.

## Output Locations

Rendered files are written only to:

- `/Users/zhengyu/Desktop/projects/snaproll/render-output/`

Per-image structure:

```text
render-output/
    <image-name>/
        original.jpg
        kodak-gold.jpg
        fujifilm-superia.jpg
```

Comparison contact sheets:

```text
render-output/contact-sheets/
```

## Originals Preserved

- Nothing inside `test-images/` is overwritten.
- Nothing inside `film-references/` is overwritten.
- All generated artifacts are isolated under `render-output/`.

## Known Limitations

- `PHASE_11_SUMMARY.md` was referenced in the prompt but is not currently present in the repository.
- The utility is intended for macOS development because it compiles against Apple image frameworks locally.
- Renderer tuning remains approximate and intentionally subtle, not a scientific stock emulation.
- This phase was validated by generated outputs and iPhone-target compilation, but not by real-device visual review from inside Codex.

## Recommended Next Tuning Steps

- Compare the generated contact sheets side by side with the Kodak Gold and Superia reference folders on a good display.
- Prioritize mixed-light scenes, foliage, and skin tones for the next tuning pass.
- If the Kodak/Superia split still feels too close, widen the difference primarily through:
  - color temperature
  - tone curve
  - blue/green channel shaping
  - highlight behavior
- Restore `AppConfig.Rolls.minimumShotLimit` to `24` before release once renderer evaluation is complete.
