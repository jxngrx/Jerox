# Changelog

All notable changes to Jerox are listed here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added
- First-run onboarding: one page per job (history, rewrite, dictate, read the screen) and a permissions page with live status. Debug builds can reopen it from Settings → Advanced → Developer.
- Versioned releases: `scripts/release.sh` builds a `.dmg` and a `.pkg` installer; pushing a `v*` tag publishes a GitHub Release.
- Settings shows the app version and build number.

## [0.1.0]

### Added
- Clipboard history at the cursor, with pins, search, and paste as plain text.
- Rewrite in place with built-in and custom prompts (Apple Intelligence or your own key).
- Dictation with Apple Speech or downloadable Whisper models that run offline.
- Read text off the screen.
