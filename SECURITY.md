# Security Policy

## Reporting a vulnerability

Please do not open a public issue for a security problem.

Use GitHub's private vulnerability reporting: open the repository's **Security** tab and choose **Report a vulnerability**. Include the steps to reproduce, the affected version or commit, and the impact you expect.

You will get an acknowledgement as soon as a maintainer can review it. Fixes ship in the next release, and reporters are credited unless they ask not to be.

## Scope

Areas that matter most:

- API keys stored in the Keychain (`Jerox/Rephrase/APIKey.swift`).
- Clipboard history stored on disk (`~/Library/Application Support/Jerox`).
- Downloaded speech models and their SHA-256 checks (`Jerox/Dictation/SpeechModels.swift`).
- Paste-back through Accessibility and synthetic key events.
