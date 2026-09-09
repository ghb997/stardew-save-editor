# Tracker design QA

final result: blocked

Date: 2026-09-09.

## Evidence and blocker

- Source visual truth: ../design-reference/09-basic-editor.png (Basic / Farm Dashboard), 07-collections.png, 02-bundles.png, 06-dark-mode.png, 08-villagers.png. Public source: https://apps.apple.com/us/app/stardew-guide-tracker/id6748267484. Source images were opened for inspection.
- Source pixel dimensions: 1284 × 2778 each, promotional image including purple marketing area and phone frame.
- Implementation: native SwiftUI in PelicanSaveEditor/Views/Home/TrackerView.swift, TrackerComponents.swift, TrackerDetailView.swift.
- Implementation screenshot path: unavailable — no current-source iOS rendered capture exists.
- Viewport / implementation pixel dimensions: not measured. This is a native app; CSS viewport and browser deviceScaleFactor are not applicable.
- Density/crop normalization: not performed. Once native captures exist, crop reference to app content, match logical widths and theme, and place source and implementation in the same comparison input.
- Target states: loaded overview, collection details, recipes/wallet, light/dark, largest Dynamic Type, empty farm, unsaved draft, compatibility warning.
- Full-view comparison evidence: unavailable, not passed.
- Focused comparison evidence: unavailable, not passed. Typography, chips, row counts and progress bars require focused comparison after full views.

Windows has no Xcode/iOS Simulator; the available simulator tool also returned spawn xcrun ENOENT. The user authorized dedicated-branch upload and cloud validation on 2026-09-09. Branch codex/tracker-ui-validation-20260909 is prepared for native build/test/capture. Current version: 0.3.3 (9). No merge or Release publication is authorized. Native results are pending.

## Required fidelity surfaces

| Surface | Source intent / implemented approach | Visual verdict |
| --- | --- | --- |
| Fonts / typography | Native system type with large title, headline rows, monospaced numbers, wrapping and Dynamic Type layouts | Blocked: no native rendered evidence |
| Spacing / layout | Farm summary, horizontal chips, bordered collapsible groups, row metrics below descriptions | Blocked: small-screen and iPad proportions unmeasured |
| Colors / tokens | Warm light palette; tracker-only dark colors; semantic warning and progress colors | Blocked: native contrast/state appearance not inspected |
| Image quality / assets | Reuse existing game pixel assets with their native rendering helpers; no new app-private art | Blocked: asset crops and rendered scaling not compared |
| Copy / content | Chinese labels, four-category count explicitly not perfection, walnut balance, warning-first status | Source-reviewed; rendered wrapping still blocked |

## Findings and history

No source-to-render visual mismatch is claimed because the implementation could not be captured.

Separate code review found and fixed malformed string interpolation, warning status hidden by “no drafts”, offscreen selected detail chips, skill ratio bounds/inconsistent subtitle, and light-card dark-mode foregrounds. Seven metric test methods were added. These are code fixes, **not completed visual-QA iterations**. There has been no post-fix native comparison.

Static syntax scanning passed for 54 Swift files, and six project/resource checks passed. Two existing Swift 6 sending return qualifiers are not typechecked by that parser. XCTest has not run. Historic build 8 CI success does not validate this revision.

## Implementation checklist

- [x] Implement read-only tracker changes and register split source/test files.
- [x] Run current-source syntax and static project checks.
- [x] Prepare scripts/capture-tracker-ui.sh and validation/TRACKER_UI_CHECKLIST.md.
- [ ] Build this exact source with Xcode and run the 58 declared tests.
- [ ] Capture intended native states and verify the app has finished loading.
- [ ] Compare reference and implementation in a normalized, shared image input.
- [ ] Exercise all 11 entries, filters, collapse, search, close, large text and VoiceOver.
- [ ] Fix observed P0/P1/P2 issues and repeat capture/comparison before marking passed.

No visual completion, matching-design claim, or new installable IPA is asserted.
