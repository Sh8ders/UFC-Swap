# UFCSwap

UFCSwap is a self-contained macOS app that hides your current app, opens a random UFC YouTube video in Google Chrome, and restores your previous app when toggled off.

## Download and Install

1. Open the latest GitHub Release.
2. Download `UFCSwap.dmg`.
3. Open the DMG.
4. Drag `UFCSwap.app` into `Applications`.
5. Open `Applications/UFCSwap.app`.

`UFCSwap.zip` is also produced as a secondary release asset for users who prefer a direct archive download.

## First Run

On first launch, UFCSwap opens its control panel and shows a setup checklist for:

- Google Chrome installation
- Accessibility permission
- Automation permission to control Google Chrome
- Video configuration validity

Use the built-in buttons to:

- download Chrome if it is missing
- request Accessibility permission
- request Automation permission
- open the relevant macOS Settings panes

## Permissions

UFCSwap depends on the following macOS permissions and runtime requirements:

- `Accessibility`: required to manage app focus and send fullscreen keystrokes
- `Automation`: required to control Google Chrome with Apple Events
- `Google Chrome`: required for managed playback

Notes:

- The app does not install Chrome automatically.
- `F1` through `F19` are supported for the hotkey capture UI, but on many Macs `F1` through `F12` may require enabling “Use F1, F2, etc. keys as standard function keys” or holding the `fn` key.
- The default fallback hotkey is `F17`.

## Release Packaging

Local release packaging:

```bash
zsh ./scripts/package-release.sh
```

The script produces:

- `dist/UFCSwap.app`
- `dist/UFCSwap.dmg`
- `dist/UFCSwap.zip`

Optional environment variables:

- `APPLE_SIGNING_IDENTITY`: signs the app and DMG if available
- `APPLE_NOTARY_PROFILE`: notarizes the DMG if available
- `UFCSWAP_VERSION`: overrides the version string
- `UFCSWAP_BUILD_NUMBER`: overrides the build number

If signing or notarization is not configured, the script still builds unsigned artifacts and prints a Gatekeeper warning.

## GitHub Releases

GitHub Actions uses `.github/workflows/release.yml` to:

- build the release app on macOS
- package the `.dmg` and `.zip`
- optionally sign and notarize when secrets are configured
- upload release assets to GitHub Releases
