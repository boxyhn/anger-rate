# Launch demo

15-second silent, bilingual promotional composition, 1280×800 at 24 fps.

- [English MP4](anger-rate-en.mp4) / [GIF](anger-rate-en.gif)
- [한국어 MP4](anger-rate-ko.mp4) / [GIF](anger-rate-ko.gif)

This is a staged composition, not a recording of Codex, Claude Code, the macOS menu bar, or an OS notification. That distinction is labeled in the video and README. The message text is synthetic. The score engine, alert gate, flame geometry and animation frequencies come directly from the application. It does not exercise log scanning or OS notification delivery.

The story starts with a neutral request, then three profanity-bearing messages. Actual scores at those events are 30 → 64.36 → 100. AlertGate fires once. At video second 11, an explicit “10 min later” cut uses the real five-minute half-life to produce a score of about 24.77. No instant cooldown is implied.

The exporter executes before AppModel is initialized. It does not read conversation logs, launch calibration, change preferences, write real score history, or send notifications.

Reproduce on macOS with Swift and ffmpeg:

```sh
./scripts/render-demo.sh
```

Each language includes a machine-readable verification JSON. MP4 is H.264/yuv420p with faststart; GIF is a 960px, 12 fps looping preview. No audio or third-party footage is used.
