# Phase 10 Summary

## Work Completed

- Added `ExportService` to handle Photos permission, individual-photo export, full-roll export, and rendered share-file preparation.
- Added single-photo export and share actions to the revealed full-screen gallery view.
- Added revealed-roll export and share actions to the revealed gallery menu and to the roll detail screen menu.
- Preserved the film-rendered version during export and sharing instead of exposing the hidden original file.
- Added `ActivityShareSheet` so Snaproll uses the native iOS share sheet.
- Added Photo Library usage descriptions to the app target.
- Updated `AI_DEVELOPMENT_GUIDE.md` and `TESTING.md` for the export phase.

## Export Flow

- While a roll is still being shot or is only completed, photos remain hidden inside Snaproll.
- Once a roll is revealed, the user can:
  - export a single rendered photo from the full-screen revealed viewer
  - share a single rendered photo from the full-screen revealed viewer
  - export the entire revealed roll from the gallery menu or roll detail menu
  - share the entire revealed roll from the gallery menu or roll detail menu
- Whole-roll export continues even if one image fails and reports a final `exported / failed` summary.

## Permission Handling

- Photos permission is requested only when the user first attempts an export.
- The export flow uses the `.readWrite` Photos authorization path so limited-library access can be detected explicitly.
- `authorized` and `limited` states are treated as export-capable.
- `denied` and `restricted` states surface clear failure feedback instead of crashing.
- Share-sheet access does not require exporting to Apple Photos first.

## Architecture Decisions

- `ExportService` composes `LocalStorageService`, `PhotoStorageService`, and `PhotoRenderService` so export behavior stays modular and out of SwiftUI views.
- Roll-level export actions live in `RollActionsViewModel` to avoid pushing export logic into `RollView`.
- Revealed-photo export actions live in `RevealViewModel` because it already owns the selected rendered photo context.
- Share payloads are built from temporary rendered JPEG files so the share sheet receives the processed result without modifying stored originals.
- Whole-roll ordering is derived from exposure number and capture timestamp to preserve capture order consistently across export and share flows.

## Known Limitations

- This phase was verified with an iPhone-target build, but not with real-device Photos export testing from inside Codex.
- Apple Photos controls final library presentation after import, so display order inside the Photos app may not always visibly match Snaproll’s internal attempt order.
- Share files are recreated in a temporary directory on demand; there is no persistent share/export cache.
- The project still has older event-based wording in some top-level docs even though the implementation follows the roll-based Snaproll direction.
- Existing AVFoundation orientation deprecation warnings remain and were not changed in this phase.

## Future Improvements

- Validate the full export and share flow on a real iPhone, including denied and limited permission states.
- Consider lightweight progress UI if future rolls become much larger than the current MVP testing size.
- Reconcile the older repository docs so the written spec matches the implemented Snaproll roll experience end to end.
