# Contributing to Jerox

Thanks for helping. This guide covers setup, the code layout, and what a good pull request looks like.

## Set up

1. Install Xcode 26 or later.
2. Fork and clone the repo.
3. Run `make run`. The build is signed ad hoc, so you need no developer account. To sign with your team, see "Build and run" in the [README](README.md).

## Before you open a pull request

- Run `make test`. It must pass.
- Run `make build`. It must build with no new warnings.
- Run the app and try the feature you changed. Say in the pull request what you tried.

## Where code goes

Sources live in `Jerox/`, one folder per feature (see the layout in the README). The Xcode project uses a synchronized folder, so a new `.swift` file under `Jerox/` builds without editing `project.pbxproj`.

- Put pure logic (no AppKit, no SwiftUI) in the feature's plain Foundation files, such as `Clipboard/ClipboardHistory.swift` or `Dictation/DictationText.swift`, and add a check to the matching `selfCheck`. If you add a new pure file, add it to `LOGIC` in the `Makefile`.
- `AppDelegate` is split into extensions by feature (`App/AppDelegate+Dictation.swift` and so on). Stored properties stay in `App/AppDelegate.swift`.
- Colors and shared styles live in `DesignSystem/JeroxTheme.swift`. Use `JeroxInk` instead of new literal colors.

## Testing onboarding

In a Debug build, open Settings → Advanced → Developer and press **Open** next to `__dev__ Onboarding`. To render every page to PNGs without clicking through, run the Debug binary with `JEROX_SNAPSHOT_ONBOARDING=<folder>`.

## Style

- Follow the code around you: naming, comment density, and SwiftUI patterns.
- Keep changes small and focused. One concern per pull request.
- Prefer the standard library and Apple frameworks over new dependencies. A new dependency needs a reason in the pull request.
- A deliberate shortcut gets a `// ponytail:` comment that names its limit and the upgrade path.

## Product rules

Jerox works where the person already is. Before you add a feature, read [PRODUCT.md](PRODUCT.md). In short:

- No Dock icon while the person works.
- Dictation and screen reading stay on the Mac. The network is only for a rephrase the person asked for.
- Do not add telemetry.

## Commit messages

Use [Conventional Commits](https://www.conventionalcommits.org/): `feat:`, `fix:`, `docs:`, `refactor:`, `chore:`. Write the subject in the imperative, for example `fix: keep caret after pasted link`.

## Reporting bugs and ideas

Open an issue with the bug or feature template. For security issues, follow [SECURITY.md](SECURITY.md) instead of opening a public issue.
