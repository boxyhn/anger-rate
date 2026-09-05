# Animated flame concept

This directory preserves the browser design exploration that informed the native flame. The approved app icon remains unchanged.

Open `index.html` in a browser, or serve the repository locally and open `/docs/flame-concept/`. Four states compare scale, warm color variation, and sway speed. Controls demonstrate a new-signal pulse, a single in-page alert on entering the highest state, animation pause, and an optional 60-second rest timer. The rest button does not reduce the selected anger state. Reduced-motion preferences are respected. All text and events are synthetic.

`preview.png` is a browser rendering, not a native app screenshot. `flame.png` was generated with the built-in OpenAI image tool using `assets/app-icon.png` as the identity reference. The app icon was not modified.

Generation prompt:

> Use case: background-extraction / identity-preserve. Create a standalone character asset from the reference app icon, for an interactive UI design prototype. Preserve the same cute coral-orange flame character identity exactly: rounded tall curved tip with small left lick, golden inner belly, two dark glossy oval eyes, tiny calm curved mouth, warm matte clay texture and soft 3D volume. Remove the ivory rounded-square app icon tile COMPLETELY. Show ONLY the flame character, full body, centered upright, on a genuinely transparent alpha background, no backdrop, no tile, no lettering, no ground plane, no outer cast shadow. Maintain original character proportions, eyes and mouth, palette, and gentle friendly demeanor. Leave 8 percent transparent margin on all sides. Single character, square image, production clean edges. This new cutout is a sibling UI asset; the original approved app icon must remain unchanged.

## V2 — candle to campfire

The user requested visible facial expression changes, different upper-flame colors, and a stronger candle-to-campfire progression. `flame-states-v2.png` is an imagegen-authored 2×2 sprite sheet: candle, growing fire, strong fire, and campfire. CSS selects a different cell for each state; it no longer only recolors one face. The menu silhouette also changes, and stronger states add sparse rising embers. Browser interaction checks passed for all four states, motion pause, rest timer, and narrow-screen layout. `index-v1.html` preserves the previous concept; `preview-v2.png` shows the revised browser UI.

V2 prompt: preserve the referenced character's glossy eyes and golden face, but render luminous flowing fire rather than solid clay; an exact equal 2×2 grid progresses from one slender pale-gold candle flame with a small smile, through two amber tongues with raised brows and a straight mouth, to multiple orange tongues with furrowed brows, then a broad campfire plume with red-coral upper tips and a frustrated frown. No text, app icon tile, wood, or wax. Generated with the built-in image tool. A second background-only edit replaced the generated checkerboard with uniform charcoal #292825, keeping the characters and grid unchanged. Original app icon remains unchanged.

## V3 — animated menu bar flame

The menu icon now cycles through 12 distinct vector silhouettes per state instead of rotating one SVG. Flame tips rise and change shape while the base stays anchored. State-dependent intervals are 250/170/115/85ms. Actual-size and enlarged previews share the same frame. Animation respects pause, reduced motion, and page visibility. Browser checks verified changing path frames, pause, state switching, and reduced motion. `index-v2.html` preserves the previous design. This remains a browser concept; no native app files changed.


## V4 — minimal preference

User prefers minimal design. Removed the menu silhouette inner cutout; retained solid monochrome frame animation. Reference research: https://devkidd.itch.io/pixel-fire-asset-pack (size variations, 16–48px sprites), https://virusystem.itch.io/animation-fire (9-frame 32px loop), https://sumo-studios.itch.io/simple-pixel-fire (simple flame study). References inform motion/scale only; no third-party assets were imported.

## V5 — smooth minimal silhouette

Reviewed the original RunCat official page in a browser: https://kyome.io/runcat/index.html?lang=en. Its menu runner uses a small monochrome silhouette and speed-changing keyframe animation. User explicitly rejected pixel art; the revised concept uses original smooth cubic Bézier paths, a single rounded body with a restrained side curl, and 16 frames at four rates. Removed elaborate character previews from this comparison page to focus on the menu icon; original app icon and native UI are unchanged. Prior concept saved as `index-v4.html`. Browser checks passed for changing frames, state selection, pause, and narrow-screen layout. `preview-v5.png` is the revised browser rendering.

## V6 — burning motion in a fixed footprint

User asked for fire-like shape changes rather than size changes. All states now share the same base and nominal footprint. Twenty-four original Bézier frames alternate rising and curling tongues, with asynchronous side tongues merging into the body. Intensity changes tongue excursion and frame rate. No whole-icon scaling. Browser checks verified multiple distinct path frames and pause. Prior version preserved in `index-v5.html`.


## V7 — candle first

Corrected the lowest two states to single slender teardrop flames without side tongues. The calm candle only bends subtly at the tip; secondary tongues appear in higher states. Original icon unchanged. Previous version: index-v6.html.

## V8 — user-selected reference direction

User selected references5/13/51/65/89 and approved the recommendation to use51 as the middle-state form,13 as the strong flame,89 as flow inspiration. Three original Bézier forms now show candle, emerging flame, and strong fire. Rounded asymmetric outer shapes and inner flame masks replace the earlier procedural spike design. Default is a still comparison; motion is opt-in and respects reduced motion. Outer/inner curves use different phases. Original reference images are remotely embedded with attribution, not copied into the app. Native app/icon unchanged. Browser checks: default still, motion, selection, reduced motion, mobile layout, and inner masks. Previous prototype saved as index-v7.html.

## V9 — score-continuous motion and color

User requested a smaller middle flame, gentle sideways candle wind, weak emerging-fire motion, fast strong-fire motion, and color. Prototype uses three proposed display bands:0–32 /33–65 /66–100. Middle form scales to73% around its base; strong form95%. Motion frequency interpolates continuously through0.20/0.32/0.65/1.35 cycles per second at scores0/33/66/100, without phase resets. Color interpolates muted gold→orange→red; a checkbox restores monochrome. Default motion is on unless reduced motion is enabled. Slider covers every integer score. The native scoring engine and installed app remain unchanged; these band thresholds are a prototype proposal. Browser tests passed all six boundaries, motion/pause, color toggle, reduced motion, and mobile width. Prior version: index-v8.html.

## V10 — monochrome and stronger acceleration

Removed prototype color interpolation and its toggle at the user's request. Frequency now interpolates through 0.14/0.38/1.05/2.1/3.2 cycles per second at scores 0/33/66/85/100. High scores also increase curve excursion up to 1.65× while preserving body scales and continuous phase. The three score bands remain unchanged. Browser verification passed all six band boundaries, moving paths, pause, reduced motion, absence of the color control, and mobile width; no JavaScript errors. Screenshot: preview-v10.png. Prior version: index-v9.html. This change is limited to the browser prototype; the native app and approved icon remain unchanged.

## V11 — faster candle and emerging flame

Raised frequency anchors at scores 0/33/66 to 0.42/0.8/1.4 cycles per second; scores 85/100 retain 2.1/3.2. Candle and emerging flame now move more visibly while keeping the same shapes, monochrome style, and continuous phase. Browser checks confirmed motion at eight scores across all bands and pause, with no JavaScript errors. Prior version: index-v10.html. Browser prototype only.

## V12 — Korean and English

Added automatic language selection from the browser locale and a persistent Korean/English toggle. All visible copy, motion controls, band names, image alternatives, and ARIA labels switch together. The English calm prompt is “Notice the heat. Take a moment.” The approved V11 shapes, score bands, and motion frequencies are unchanged. Browser checks passed for both automatic locales, manual switching, all six band boundaries, motion/pause, reduced motion, and mobile width.
