# Tracker design QA

Final result: pending post-fix native recapture.

Date: 2026-09-09. Reference-inspired improvement to the existing native SwiftUI product, not a pixel-identical clone. Existing editor functionality and native navigation are preserved.

## Reference and measured native evidence

- Source: public App Store screenshots under ../design-reference: 09-basic-editor.png (Basic / Farm Dashboard), 07-collections.png, 06-dark-mode.png, 02-bundles.png, 08-villagers.png. https://apps.apple.com/us/app/stardew-guide-tracker/id6748267484
- Source dimensions: 1284 × 2778, including marketing surround and phone frame. No private code or artwork was copied from the IPA.
- First verified source commit: 0845fb70e2f45b7460ecd895ff305f8bb5c94874.
- Native run: https://github.com/ghb997/stardew-save-editor/actions/runs/34325582959 — succeeded; 58 XCTest tests executed, zero failures.
- Xcode 16.4 (16F6), SDK 18.5; iPhone SE (3rd generation), iOS 26.2. Native screenshots: 750 × 1334 pixels, 375 × 667 logical points, @2x. CSS viewport/deviceScaleFactor are not applicable.
- Screenshots: artifacts/tracker-ui-first/Tracker-native-ui-1-1/screenshots/20260909-075443-11297/01–16 PNG files. All opened for visual inspection by the review team.
- Shared comparison inputs: artifacts/tracker-ui-first/comparison-overview.png and comparison-dark.png. Both opened. Reference content crop (155,1090,973,1688), native crop (0,70,750,1264), each proportionally normalized to 420 pixels wide; no stretching or fabricated screenshot content.
- Dark comparison uses different semantic pages (reference villagers / implementation overview); it supports palette and contrast review, not identical-state pixel fidelity.

## Observed issues and implemented corrections

| Priority | Actual rendered evidence | Correction | Retest |
| --- | --- | --- | --- |
| P2 | 01 overview / 03 large type: large header and farm summary push category navigation and first module down on SE | Compact tracker-only header and summary; keep category chips immediately below header; category-specific screens omit overview summary and reset vertical scroll | Pending |
| P2 | 02 dark overview: selected bottom Tracker tab has dark red foreground against dark background | Use adaptive tracker accent only while Tracker is selected | Pending |
| P2 | 11 wallet / 12 status light: secondary text approx. RGB 138,138,142 on white, 3.44:1; 10 recipes approx. 127,127,127, 4.00:1 | Tracker-only opaque adaptive secondary color plus custom LabeledContent style; accessible sizes stack labels and values | Pending |
| P2 | Overview uses an unfinished body sprite as if it were a complete avatar | Farmhouse asset for farm summary; native SF profile symbol for character entry | Pending |

No other definite overlaps, missing images or loading failures were found in the 16 first-run captures. Offscreen scroll content alone is not classified as inaccessible. Source-specific content is intentionally not copied: collection counts explicitly are not perfection percentages; walnuts are held balance; compatibility warnings take precedence over draft status.

## Verification scope

- Static scan: 55 Swift files, six project/resource checks, 113 assets; passed. Static scanning is not typechecking.
- First native suite: 58 executed unit tests passed, including seven tracker-metric tests.
- Interaction suite added: four UI tests cover five category filters, four group toggles, all 11 detail entries/close, selected detail chips, recipe filters/search-empty state, and empty-to-tools navigation. Current run at commit 8856991: https://github.com/ghb997/stardew-save-editor/actions/runs/34327382290 (pending).
- Capture matrix: overview light/dark, maximum Dynamic Type light/dark, draft, empty light/dark/large, progress, recipes, wallet, draft status, dark relationship detail, large progress and recipes.
- Not claimed: physical-device validation, interactive VoiceOver audit, iPad screenshots, or real user save roundtrip for these UI-only changes.

## Completion gate

- [x] Compare actual source and native implementation together.
- [x] Fix definite P2 findings in source.
- [ ] Build and run tests on the post-fix source.
- [ ] Recapture post-fix native states and inspect combined comparisons.
- [ ] Verify the final unsigned IPA and tie its hash to the tested source.

The dedicated branch is user-authorized. No main merge or Release publication is performed. Windows cannot run Xcode; native verification is on the authorized GitHub macOS runner. Original IPAs, archived source and real saves remain untouched.
