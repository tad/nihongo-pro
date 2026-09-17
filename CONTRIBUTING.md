# Contributing to Nihongo Pro

Thanks for your interest! A few things to know up front:

**This is a personal study app.** I built it for my own daily Japanese study and it reflects how I like to study. Feature direction is mine, there's no roadmap, and there are no support guarantees or response-time promises. That said, bug reports and small, focused pull requests are genuinely welcome.

## Building

1. Open `NihongoPro.xcodeproj` in Xcode 27 or newer (Swift 6.4).
2. Select the **NihongoPro** target → **Signing & Capabilities** → pick **your own Team**. No team is committed in the project (on purpose) — the build fails with a signing error until you set one. Please don't include a `DEVELOPMENT_TEAM` change in any PR.
3. Run on an iPad or iPhone simulator running OS 26+.

For headless verification (this must pass before any PR):

```bash
xcodebuild -project NihongoPro.xcodeproj -scheme NihongoPro \
  -destination 'generic/platform=iOS Simulator' \
  -configuration Debug build CODE_SIGNING_ALLOWED=NO
```

The unit tests (`NihongoProTests`, Swift Testing) must pass too:

```bash
xcodebuild -project NihongoPro.xcodeproj -scheme NihongoPro \
  -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5)' \
  test CODE_SIGNING_ALLOWED=NO
```

They cover the pure logic (parsers, merge rules, filters). Pure logic you add should get a test; UI and network behavior are still verified by a manual run in the simulator.

## Pull request expectations

- **Small and focused.** One change per PR. Refactors and features don't mix.
- **The build and the tests must pass** (commands above).
- **Update the docs in the same PR.** This repo has a hard rule: any feature addition or behavior change must update both `CLAUDE.md` (the architecture notes) and `README.md` in the same change, so the docs always reflect current state.
- **No new dependencies.** The app is deliberately zero-third-party (no SPM, no CocoaPods). System frameworks only.
- **Match the existing style** — SwiftUI, the existing store patterns (`@Observable` vs `actor` — see `CLAUDE.md` for when each is used), and the existing naming. The project builds in Swift 6 language mode with complete strict concurrency, so new code must be data-race-free by construction (no `nonisolated(unsafe)` escape hatches without a comment explaining why).
- Adding a new Swift file requires hand-editing `project.pbxproj` — the exact steps and ID conventions are in `CLAUDE.md` under "Adding a new Swift source file".

## Licensing of contributions

Nihongo Pro is source-available under the PolyForm Noncommercial License 1.0.0 with an additional app-store restriction (see [LICENSE.md](LICENSE.md)), and the copyright holder retains exclusive commercial and app-store distribution rights.

So that those rights can cover the whole codebase: **by submitting a contribution (pull request, patch, or otherwise), you agree that Terry Donaghe may use, modify, distribute, sublicense, and relicense your contribution without restriction, including commercially and through application stores.** You retain copyright in your contribution; this is a license grant, not a copyright transfer. If you can't or don't want to grant this, please open an issue describing the change instead of a PR.

## Bug reports

Open a GitHub issue with: device/simulator model, OS version, which AI provider (Claude/ChatGPT) and voice engine you were using, what you did, what happened, and what you expected. If a sentence parse misbehaved, include the exact input text — parse issues are almost always input-specific.
