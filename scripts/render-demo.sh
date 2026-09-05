#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
command -v ffmpeg >/dev/null || { echo 'Install ffmpeg before exporting.' >&2; exit 1; }
swift build -c release
frames_dir=$(mktemp -d "${TMPDIR:-/tmp}/anger-rate-demo.XXXXXX")
trap 'rm -rf "$frames_dir"' EXIT
for lang in en ko; do
  if [ "$lang" = ko ]; then
    .build/release/AngerRate --render-demo "$frames_dir/$lang" --korean
  else
    .build/release/AngerRate --render-demo "$frames_dir/$lang"
  fi
  ffmpeg -hide_banner -loglevel error -y -framerate 24 -i "$frames_dir/$lang/%04d.png" -c:v libx264 -crf 20 -pix_fmt yuv420p -movflags +faststart "docs/launch/anger-rate-$lang.mp4"
  ffmpeg -hide_banner -loglevel error -y -i "docs/launch/anger-rate-$lang.mp4" -filter_complex 'fps=12,scale=960:-1:flags=lanczos,split[a][b];[a]palettegen=stats_mode=diff[p];[b][p]paletteuse=dither=bayer' -loop 0 "docs/launch/anger-rate-$lang.gif"
  cp "$frames_dir/$lang/verification.json" "docs/launch/verification-$lang.json"
done
