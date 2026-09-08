# AngerRate performance — current result (2026-09-08)

The menu flame now animates continuously through Core Animation, without a per-frame app timer or image-view replacement. Initial concurrent 30-second measurement: AngerRate **6.23% → 0.93%**, RunCat **0.80% → 0.83%**. WindowServer measured **17.59% → 14.89%**; it serves the whole desktop, so this is a check for an obvious cost shift, not attribution of its CPU to either app.

A second concurrent 30-second run measured AngerRate **0.83%**, RunCat **0.77%**, WindowServer **13.53%**. The two post-change samples support roughly **0.8–0.9%** AngerRate CPU in this workload; they do not establish a universal ceiling.

## Source-informed implementation

[RunCat Neo RunnerBarView](https://github.com/runcat-dev/RunCatNeo/blob/b3b1543049ea0a051ecb78654a45f144724ea737/LocalPackage/Sources/UserInterface/Views/RunnerBar/RunnerBarView.swift#L24) explicitly documents the same per-icon-swap CPU cost and uses compositor animation instead. [RunnerLayer](https://github.com/runcat-dev/RunCatNeo/blob/b3b1543049ea0a051ecb78654a45f144724ea737/LocalPackage/Sources/UserInterface/Views/RunnerBar/RunnerLayer.swift) provides the cached `contents` animation/template mask pattern. The public Neo repository is not asserted to be identical to installed RunCat 12.8. The older archived `Kyome22/menubar_runcat` uses timer-driven icon swaps and is not the optimization reference.

- `MenuFlameAnimator.swift`: 24 cached 34×42 RGBA frames per cycle; only the current integer-score bank is retained. Original flame geometry is reused. The exact score still drives motion frequency; score bands remain at 33 and 66. Raster shape strength is quantized to the displayed integer score.
- `MenuBarController.swift`: mask tint follows status-window appearance. ARM64 static template fallback remains visible on inactive monitors, erased behind the animated layer on the active monitor using the source's composition technique. Intel does not use the fallback-erasing filter and has not been UI-tested; inactive-display visibility is a known limitation there.
- The 8 fps menu timer has been removed. Core Animation repeats cached frames; the open panel still uses its original 24 fps renderer. Pause, Reduce Motion and sleep freeze phase; resume and speed changes preserve continuity.
- Imported technique attribution and Apache-2.0 license are in `THIRD_PARTY_NOTICES.md` / `ThirdPartyLicenses/` and are included in the installed bundle and packaging script. No RunCat artwork is used.

## Current verification

77 tests executed: 76 passed, one authenticated CLI integration test skipped. Tests include cache reuse/bounds, score-band transitions, phase continuity, actual layer speed/time offsets, pause/Reduce Motion/sleep, and lifecycle release. Release build, scoring smoke test, signature verification, packaging shell syntax, and whitespace checks pass. Independent review found no material blocker.

Live menu screenshots confirmed distinct animation frames. Native UI automation verified open/pause/resume/close. All three connected monitors (Retina internal, 2× external, 1× external) show a single icon. Changes are installed locally with the prior app bundle backed up. Neither RunCat nor user detection/scoring/sync settings were modified.

## Session polling

File size checks now use Darwin `lstat` instead of full Foundation attributes, avoiding extended-attribute and owner/group lookups. On 232 real JSONL paths over 25 passes, size totals matched; elapsed lookup time was 0.205759s versus 0.004952s (41.55× for the lookup only). Symlink-root append regression coverage was added. The three-second scan interval, scoring, storage and sync behavior are preserved.
