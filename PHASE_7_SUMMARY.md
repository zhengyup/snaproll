# Phase 7 Summary

## Film Stock Model

- Added `ios/snaproll/snaproll/Models/FilmStock.swift`.
- The MVP stock set is now:
  - Kodak Gold 200
  - Fujifilm Superia 400
  - Ilford HP5 Plus
- Each stock includes:
  - stable id
  - display name
  - short description
  - color or black-and-white type
- `Roll` continues to store the selected stock.
- Older saved rolls remain safe because decoding still defaults missing film data to Kodak Gold 200.

## Rendering Approach

- Replaced the generic processor with `ios/snaproll/snaproll/Services/PhotoRenderService.swift`.
- `PhotoRenderService`:
  - receives a loaded original image
  - applies a film-inspired render based on the roll's selected stock
  - returns a rendered image for display only
- Implemented stock-specific looks:
  - Kodak Gold 200: warmer temperature, gentle contrast, slight saturation, softly lifted shadows
  - Fujifilm Superia 400: cooler tone, greener and bluer color balance, slightly punchier contrast
  - Ilford HP5 Plus: black-and-white conversion, stronger contrast, light grain, documentary feel
- Rendering runs only in revealed and completed viewing flows.

## Where Originals Are Preserved

- Original captured JPEGs remain stored untouched in local storage.
- `PhotoStorageService` still owns local file loading only.
- `PhotoRenderService` works on in-memory `UIImage` instances and never overwrites the saved originals.
- If rendering fails, the app falls back to the original loaded image.

## Architectural Decisions

- `FilmStock` is now a standalone model instead of being embedded inside `Roll.swift`.
- `PhotoRenderService` is separate from `CameraService`, `PhotoStorageService`, and SwiftUI views.
- `RevealViewModel` coordinates:
  - photo metadata loading
  - original image loading
  - film rendering
  - preparation of revealed gallery items
- The create-roll flow now presents the stock descriptions directly so the user chooses a roll feel, not just a label.
- Rendering uses a lightweight in-memory `NSCache` keyed by stock plus file path, which keeps repeat viewing fast without adding a more complex disk cache.

## Limitations

- Real-device manual validation is still needed outside Codex.
- The rendering pipeline is intentionally simple and not a scientific emulation of real film stocks.
- Rendered-image caching is memory-only and not persisted to disk.
- The full-screen viewer still does not support zooming.
- Top-level repository docs still contain older event-based wording that no longer matches the implemented roll-based app.

## Future Improvements

- Add more nuanced stock tuning after real-device review of the current looks.
- Consider per-stock highlight and skin-tone refinement if the simple renders prove too broad.
- Revisit disk caching only if larger rolls make repeated rendering noticeably expensive.
