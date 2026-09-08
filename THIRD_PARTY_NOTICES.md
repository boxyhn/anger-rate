# Third-party notices

## RunCat Neo

The Core Animation template-mask and ARM64 static-fallback composition in
`Sources/AngerRate/MenuFlameAnimator.swift` and `Sources/AngerRate/MenuBarController.swift`
are adapted from RunCat Neo's RunnerLayer.swift / BackgroundLayer.swift / RunnerBarView.swift.
The flame shapes and application behavior remain AngerRate's own implementation.

- Copyright 2026 Kyome22 (Takuto Nakamura)
- Source: https://github.com/runcat-dev/RunCatNeo/tree/b3b1543049ea0a051ecb78654a45f144724ea737
- License: Apache License 2.0; full text in `ThirdPartyLicenses/RunCatNeo-Apache-2.0.txt`.
- Modifications: native status-item integration, original flame frame cache, score-dependent
  timing, pause/sleep/reduce-motion controls, and deterministic clock tests.

These adapted portions are provided under Apache License 2.0. Original AngerRate code
remains under the repository's MIT license. No RunCat artwork is included.
