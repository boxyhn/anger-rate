# Contributing to AngerRate

Thanks for helping make a small, useful menu bar companion. Korean and English issues and pull requests are welcome.

## Run locally

Use macOS 13+ and Swift 5.9+:

```sh
swift test
swift run AngerRate
```

For bundle, icon, and notification changes, also run `./scripts/package.sh` and test the app bundle. Tests use synthetic data; real CLI tests require explicit opt-in and a signed-in account. Never add credentials to fixtures or CI.

## Send a change

1. Explain the user-visible problem in an issue or pull request.
2. Keep changes focused. Add behavior tests for scoring, parsing, calibration, or sync changes.
3. Run relevant checks and describe what you verified and any remaining gaps.
4. For UI changes, include a screenshot using synthetic data.

Default detection and personal criteria must remain separate. Changes to profanity matching should include both a match and a neutral counterexample. Do not turn off the common defaults through a personal profile.

## Report a bug

Include macOS and CLI versions, steps, expected behavior, and actual behavior. For parsing or false-positive reports, replace private conversations with a minimal synthetic example that reproduces the issue. Do not upload full session logs, tokens, audit drafts, or personal profiles.

## Scope

AngerRate helps the user notice rising frustration. Keep interaction small, preserve local live scoring, and make any AI processing explicit. English UI localization and additional synthetic parser fixtures are welcome. Discuss new dependencies or substantial features before implementing them.

Code and included assets are provided under the MIT license. By contributing, you agree that your contributions use the same license.
