<p align="center">
  <img src="assets/app-icon.png" width="144" alt="AngerRate — a little coral flame">
</p>
<h1 align="center">AngerRate</h1>
<p align="center"><strong>Notice the heat. Take a breath.</strong><br>A tiny macOS menu bar companion for Codex and Claude Code.</p>
<p align="center">
  <img alt="macOS 13 or later" src="https://img.shields.io/badge/macOS-13%2B-242424?style=flat-square">
  <img alt="Built with SwiftUI" src="https://img.shields.io/badge/SwiftUI-native-F05138?style=flat-square">
  <a href="LICENSE"><img alt="MIT License" src="https://img.shields.io/badge/license-MIT-70927C?style=flat-square"></a>
</p>
<p align="center">English · <a href="README.ko.md">한국어</a> · <a href="#getting-started">Get started</a> · <a href="CONTRIBUTING.md">Contribute</a></p>

<p align="center"><img src="docs/panel-preview.png" width="360" alt="AngerRate menu panel showing conversation temperature, recent trend, and reasons"></p>
<p align="center"><sub>Actual app UI rendered with synthetic data. The interface is currently in Korean.</sub></p>

Coding with an AI can get frustrating. AngerRate watches language signals in your local coding sessions and puts a small temperature in your menu bar. When things reach boiling point, one gentle notification gives you a moment to notice and pause.

**Early preview.** Build from source today; a signed, notarized public release is not available yet.

## Small by design

- **A temperature at a glance.** Start at **36.5°C**, rise toward **100°C**, and cool down over time. Prefer Fahrenheit? Switch to **97.7–212°F**.
- **One nudge at boiling point.** A single notification per escalation, rearmed after the internal score falls to 50 or below.
- **Your patterns, once.** Review accessible current and archived sessions with your existing Codex or Claude Code login, then review the suggested personal signals.
- **Korean + English defaults.** 90 built-in profanity expressions remain active alongside your personal criteria.
- **One Mac is enough.** Optionally combine scored events across Macs through a folder you choose. No AngerRate account or server.

The temperature represents a language-based heuristic, not body temperature or a clinical assessment. The internal score is 0–100; displayed Celsius is `36.5 + score × 0.635`.

## Getting started

You need **macOS 13+**, a **Swift 5.9+ toolchain** to build, and local Codex or Claude Code session logs. AI personalization additionally requires a supported, signed-in CLI; it uses that account's allowance and does not need a separate API key.

From the repository root:

```sh
./scripts/package.sh
./scripts/install.sh
```

This builds `dist/AngerRate.app` and `dist/AngerRate-0.1.0.dmg`, installs the app in `~/Applications`, and opens it. An existing installation is backed up before replacement. You can also drag the app from the DMG into Applications.

1. Open AngerRate from Applications and find its temperature in the menu bar.
2. Start with the built-in defaults or run the one-time history review.
3. Review and apply personal criteria. Zero additional criteria is a valid result.
4. Allow notifications to receive the boiling-point nudge. Choose Celsius or Fahrenheit in settings.

Local builds are ad-hoc signed, not notarized. Apple Silicon has been tested; Intel and the macOS 13 minimum still need physical-device verification. Build on the target architecture. See [release notes for maintainers](docs/RELEASE.md) for signing and notarization.

## What happens to your conversations?

| Stage | What AngerRate does |
| --- | --- |
| Live detection | Reads direct user messages from local logs; matches rules and cools the score locally. No ongoing AI calls. |
| Initial review | Streams all accessible current and archived log files, deduplicates messages, and gathers coverage statistics. |
| AI personalization | Sends selected context and aggregate statistics through your chosen Codex/Claude Code CLI to its AI provider. |
| Local persistence | Stores scored events, reasons, timestamps, device IDs, audit counts, and personal phrase rules. Does not persist full message bodies. |
| Optional folder sync | Shares scored events and personal criteria, including their phrases, through your chosen folder provider. Does not sync message bodies. |

The initial review selects up to 600 representative candidates across the corpus. The CLI receives at most 400, limited to 1,500 characters per message and 48 KiB of source text, plus statistics. It does **not** send the entire history to the model. Failed reads, malformed records, and rows over 4 MiB are reported as coverage gaps.

“Whole history” means **accessible local files**, including archives. Signing in does not download cloud-only account conversations or sessions stored only on another Mac. Live discovery is limited to the most recent 4,096 files; the initial audit has no file-count cap.

Data lives in `~/Library/Application Support/AngerRate/`. Sources include `CODEX_HOME` or discovered `~/.codex*` session directories, and `CLAUDE_CONFIG_DIR` or `~/.claude/projects`. Original session logs are read-only.

## More than one Mac

On each Mac, choose the same synced folder in **Settings → Devices**. AngerRate writes per-device snapshots under `AngerRate-Sync` and deduplicates event IDs. Events and the last healthy peer cache are retained for 24 hours.

Sync speed depends on your folder provider. Notifications originate on the Mac that detects the signal; simultaneous activity on disconnected Macs cannot guarantee exactly one notification globally.

## Development

Native SwiftUI, Swift Charts, Foundation, and UserNotifications. No third-party package dependencies.

```sh
swift test
swift run AngerRate
./scripts/package.sh
```

| Location | Responsibility |
| --- | --- |
| `Sources/AngerCore` | Session parsing, history audit, language rules, scoring, CLI personalization, sync |
| `Sources/AngerRate` | Menu bar UI, settings, notifications, app lifecycle |
| `Tests/AngerCoreTests` | Synthetic fixtures and behavior tests |
| `assets` | Original app icon and provenance |
| `scripts` | Reproducible icon, app, and DMG packaging |

Read [the design](docs/DESIGN.md), [verification and remaining gaps](docs/VERIFICATION.md), or [contribution guide](CONTRIBUTING.md). Logs are not a stable public API, and context matching can produce false positives. Sanitized reproductions are especially helpful.

## License & inspiration

[MIT](LICENSE). Contributions, language improvements, and small usability fixes are welcome.

Inspired by the approachable, focused menu bar utility spirit of [RunCat](https://github.com/runcat-dev/RunCatNeo). AngerRate is an independent project with original artwork; it is not affiliated with RunCat, OpenAI, or Anthropic.
