# App icon

`app-icon.png` is the 1024×1024 master for the app bundle and README. It was created with the built-in OpenAI image generation tool on 2026-09-05, then resized with macOS `sips`. No RunCat artwork was used. The repository MIT license applies to the included asset to the extent applicable.

Design prompt: one original polished macOS app icon for AngerRate; a simple friendly coral-orange flame with two dark oval eyes, a calm small mouth and a pale golden inner belly; soft matte clay form centered on a warm ivory rounded-square tile; restrained indie utility aesthetic; legible at 32 pixels; no text, numbers, cat, busy elements, or existing app logo.

`scripts/build-icon.sh` converts the master into standard macOS icon sizes and builds `AppIcon.icns` with `iconutil`. Packaging adds the icon to the app bundle. The menu bar uses the temperature label so it remains readable at small sizes.
