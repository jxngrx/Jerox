# Releasing Jerox

A release is a git tag. CI does the rest.

## Version numbers

- **Marketing version** (`CFBundleShortVersionString`) follows [Semantic Versioning](https://semver.org): `MAJOR.MINOR.PATCH`. It comes from the tag (`v1.2.3` ships as `1.2.3`).
- **Build number** (`CFBundleVersion`) is the commit count (`git rev-list --count HEAD`), so every build is larger than the last.
- Settings shows both at the bottom of the sidebar.

## Cut a release

1. Move the items under **Unreleased** in [CHANGELOG.md](../CHANGELOG.md) into a new version section.
2. Commit, then tag and push:

   ```sh
   git tag v0.2.0
   git push origin v0.2.0
   ```

3. The **Release** workflow runs `make test`, builds with `scripts/release.sh`, and publishes a GitHub Release with:
   - `Jerox-0.2.0.dmg`: open it and drag Jerox into Applications.
   - `Jerox-0.2.0.pkg`: the macOS Installer; installs to `/Applications`.
   - `Jerox-0.2.0.zip` and `appcast.xml`: Sparkle in-app updates. See [AUTO_UPDATES.md](AUTO_UPDATES.md).
   - `Jerox-0.2.0.sha256`: checksums.

## Build a release locally

```sh
make dmg VERSION=0.2.0      # or: scripts/release.sh 0.2.0
```

Output goes to `dist/` (git-ignored).

## Signing and notarization

Without a certificate the app is signed ad hoc. macOS then asks people to confirm the first launch (Control-click Jerox, choose Open). To ship a release that opens without that prompt, set these before `scripts/release.sh`:

| Variable | Value |
|---|---|
| `SIGN_IDENTITY` | `Developer ID Application: Your Name (TEAMID)`. Signs the app with the hardened runtime. |
| `INSTALLER_IDENTITY` | `Developer ID Installer: Your Name (TEAMID)`. Signs the `.pkg`. |
| `NOTARY_PROFILE` | A profile saved with `xcrun notarytool store-credentials`. Notarizes and staples the `.dmg` and `.pkg`. |

The microphone entitlement in `Config/Jerox.entitlements` keeps dictation working under the hardened runtime.

## The disk image window

The window layout (icon positions, background) is saved in `installer/dmg-DS_Store`, so CI builds the same window without Finder. To change it, edit `installer/make-background.py`, run it, then rebuild the layout once on a Mac:

```sh
python3 installer/make-background.py
RELAYOUT=1 scripts/release.sh 0.0.0
```

macOS may ask to let Terminal control Finder the first time.
