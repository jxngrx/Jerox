# Automatic updates (Sparkle 2)

Jerox uses [Sparkle 2](https://sparkle-project.org) to check GitHub Releases, verify an EdDSA signature, install, and relaunch.

Existing **v0.0.1** installs do not include Sparkle. Those people install the first Sparkle-enabled release by hand (DMG or PKG). Later versions update from the menu bar.

Do not commit private keys or signing certificates.

## What the app reads

| Info.plist key | Value |
|---|---|
| `SUFeedURL` | `https://github.com/jxngrx/Jerox/releases/latest/download/appcast.xml` |
| `SUPublicEDKey` | EdDSA public key (already in `Jerox/Resources/Info.plist`) |
| `SUEnableAutomaticChecks` | `true` |

`CFBundleShortVersionString` comes from the git tag (`v1.2.3` ships as `1.2.3`). `CFBundleVersion` is the commit count. Sparkle uses the build number to decide what is newer.

In the app: **Jerox → Check for Updates…**, the menu-bar right-click item, and **Settings → Advanced → Updates**. When a feed item is newer, the sidebar shows **Update to \<version\>** and Advanced shows **Update Now**. That action is Sparkle’s standard download / verify / install / relaunch flow. Signature verification is not optional.

## GitHub Actions secrets

Set these on `jxngrx/Jerox` before you push a `v*` tag that should ship updates.

### Sparkle (required for `appcast.xml`)

| Secret | What it is |
|---|---|
| `SPARKLE_PRIVATE_ED_KEY` | Contents of `Config/sparkle_eddsa_private.key` (git-ignored). One line, base64. Must match the public key in Info.plist. |

The private key for the public key already in the repo lives on the machine that ran `generate_keys --account jerox` (exported to `Config/sparkle_eddsa_private.key`). Copy that file into the secret. Do not regenerate a new pair unless you also change `SUPublicEDKey` and ship that build as a manual install.

### Developer ID (required for Gatekeeper-friendly builds)

Without these, `scripts/release.sh` still builds, but the app is ad hoc signed and macOS may ask people to Control-click → Open.

| Secret | What it is |
|---|---|
| `BUILD_CERTIFICATE_BASE64` | Developer ID Application `.p12`, base64 (`base64 -i cert.p12 \| pbcopy`). |
| `P12_PASSWORD` | Password for that `.p12`. |
| `KEYCHAIN_PASSWORD` | Password for the temporary CI keychain. Any strong value. |
| `SIGN_IDENTITY` | Exact codesign identity, e.g. `Developer ID Application: Name (TEAMID)`. |

### Installer package (optional)

| Secret | What it is |
|---|---|
| `INSTALLER_CERTIFICATE_BASE64` | Developer ID Installer `.p12`, base64. |
| `INSTALLER_P12_PASSWORD` | Password; defaults to `P12_PASSWORD` if omitted. |
| `INSTALLER_IDENTITY` | e.g. `Developer ID Installer: Name (TEAMID)`. |

Notarization is still local-only (`NOTARY_PROFILE` for `scripts/release.sh`). CI does not notarize until you add that separately.

## Release steps

Same as [RELEASING.md](RELEASING.md): tag `vMAJOR.MINOR.PATCH` and push the tag. The Release workflow:

1. Runs `make test`.
2. Imports Developer ID certs when those secrets exist.
3. Runs `scripts/release.sh`, which writes:
   - `Jerox-<version>.dmg`
   - `Jerox-<version>.pkg`
   - `Jerox-<version>.zip` (Sparkle)
   - `appcast.xml` (only if `SPARKLE_PRIVATE_ED_KEY` is set)
   - `Jerox-<version>.sha256`
4. Uploads `dist/*` to the GitHub Release.

Sparkle’s feed URL is `…/releases/latest/download/appcast.xml`, so the latest tagged release must include `appcast.xml` and `Jerox-<version>.zip`.

## Local keys (only if you replace the committed public key)

```sh
# Sparkle 2.10 tools from https://github.com/sparkle-project/Sparkle/releases
./bin/generate_keys --account jerox
./bin/generate_keys --account jerox -p   # public key → SUPublicEDKey
./bin/generate_keys --account jerox -x Config/sparkle_eddsa_private.key
```

Then put the private file in `SPARKLE_PRIVATE_ED_KEY` and change `SUPublicEDKey` in Info.plist. Everyone on the old public key must install that build by hand.

## Local Sparkle archive

```sh
export SPARKLE_PRIVATE_ED_KEY="$(cat Config/sparkle_eddsa_private.key)"
# optional: SIGN_IDENTITY / INSTALLER_IDENTITY / NOTARY_PROFILE
scripts/release.sh 0.2.0
```
