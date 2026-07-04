# Film Rendering MVP Lock

## Status

Snaproll's current film rendering is locked for MVP.

The current Kodak Gold 200, Fujifilm Superia 400, and Black & White rendering output is accepted as good enough for the MVP experience.

This lock exists to prevent endless subjective tuning during product development.

## Supported Film Stocks

- Kodak Gold 200
- Fujifilm Superia 400
- Black & White

## Why It Is Locked

- The current rendering is strong enough to support the MVP product experience.
- Further casual tuning would create churn without clearly improving the product.
- Film rendering quality can be refined later through a more deliberate evaluation workflow instead of ad hoc production tweaks.

## Rule For Future Changes

Do not casually retune film rendering parameters during normal product work.

Future rendering improvements should go through a dedicated Film Lab workflow with reference review, test-image comparison, and output inspection.

## Known Limitations

- The renderer is still a fast on-device Core Image approximation, not a scientific film-stock emulation.
- Grain is restrained and procedural rather than stock-accurate.
- The shared base-film response does not yet capture every per-stock tonal nuance.
- Visual evaluation remains partly subjective.

## Regenerating Test Outputs

Use:

```bash
tools/run_render_test_images.sh
```

This writes comparison outputs to:

- `render-output/<image-name>/original.jpg`
- `render-output/<image-name>/kodak-gold.jpg`
- `render-output/<image-name>/fujifilm-superia.jpg`
- `render-output/contact-sheets/`

## Reference Image Location

Real film reference images live in:

- `film-references/kodak-gold/`
- `film-references/fujifilm-superia/`

## Test Image Location

Digital test images used for renderer evaluation live in:

- `test-images/`
