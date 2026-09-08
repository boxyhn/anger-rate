# App icon

`app-icon.png` is the 1024×1024 master for the app bundle and README. It was created with the built-in OpenAI image generation tool on 2026-09-05, then resized with macOS `sips`. No RunCat artwork was used. The repository MIT license applies to the included asset to the extent applicable.

Design prompt: one original polished macOS app icon for AngerRate; a simple friendly coral-orange flame with two dark oval eyes, a calm small mouth and a pale golden inner belly; soft matte clay form centered on a warm ivory rounded-square tile; restrained indie utility aesthetic; legible at 32 pixels; no text, numbers, cat, busy elements, or existing app logo.

`AppIcon.icns` is the existing packaged icon, preserved byte-for-byte for releases. Packaging copies this file without regenerating visual assets. The legacy `scripts/build-icon.sh` is an optional conversion tool; it is not run by normal packaging. The menu bar uses AngerRate's original animated flame.
