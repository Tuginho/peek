# Contributing to Peek

## Build and test

```
swift build
swift test
```

`./scripts/build.sh` produces a signed, runnable `build/Peek.app` (see
README.md for signing identity details); `./scripts/install.sh` builds and
installs it to `/Applications`.

## Conventions

- Swift language mode 5 (set in `Package.swift`).
- Code and comments are written in English.
- User-facing UI strings are in German.

## Pull request checklist

- `swift build` completes without warnings.
- `swift test` is green.
- README.md and README.de.md are updated if the change affects behavior
  described there.

## Manual test checklist

AX/Dock/ScreenCaptureKit behavior cannot be exercised by the unit tests —
check these by hand before and after a change that touches them:

- Cmd+H with 2+ windows of the same app open: the focused window hides, the
  next window of that app is raised.
- Cmd+H with only one window of the app open: falls back to hiding the whole
  app.
- Cmd+H on a full-screen window: falls back to hiding the whole app.
- Cmd+H on an app in the exclusion list: behaves like stock Cmd+H.
- Restoring a hidden window by clicking its Dock icon.
- Restoring a hidden window from the menu bar menu.
- Hover preview panel with the Dock at the bottom, and with it moved to the
  left or right edge of the screen.
- Hover preview panel on a secondary display.
- Clicking a thumbnail in the preview panel brings that window to the front.
- The hide and close buttons on a thumbnail.
- Dock badge position, including while the Dock is magnifying icons under
  the pointer.
- Quitting Peek restores any parked windows.
- Recovery after `killall Dock`.
- Typing stays responsive while another app is suspended with `kill -STOP
  <pid>`.

## Localization

The UI is German only at the moment. Localization contributions are
welcome.

## Releasing

For maintainers, to publish a release build.

By default `./scripts/release.sh` produces an ad-hoc signed, universal
`dist/Peek-<version>.zip` that is not notarized — no paid Apple account is
required for this. Notarizing a release is optional and needs a paid Apple
Developer Program membership.

### Regenerating the app icon

`scripts/make-icon.sh` regenerates `Resources/AppIcon.icns` and
`Resources/AppIcon-256.png` from `Resources/AppIcon.svg`. Run it after
editing the SVG, and commit the three files (the SVG and both generated
outputs) together.

### Steps

1. Bump `CFBundleShortVersionString` and `CFBundleVersion` in
   `Resources/Info.plist`, and add a new entry to `CHANGELOG.md`.
2. Run `./scripts/release.sh`. Without a "Developer ID Application"
   signing identity in the keychain, it produces an ad-hoc signed,
   non-notarized zip (see the warning it prints) — this is the normal case.
3. Optional, with a paid Apple Developer Program membership: notarize the
   release instead of shipping an ad-hoc build.
   - Create a "Developer ID Application" certificate once, as the account
     holder, in Xcode → Settings → Accounts → Manage Certificates.
   - Store notary credentials once:
     ```
     xcrun notarytool store-credentials <profile> \
         --apple-id <apple-id> --team-id <team-id> --password <app-specific password>
     ```
   - Run `PEEK_NOTARY_PROFILE=<profile> ./scripts/release.sh`. With the
     Developer ID identity installed and `PEEK_NOTARY_PROFILE` set, the
     script signs with hardened runtime, notarizes, staples the ticket, and
     re-zips the stapled app.
4. Test the resulting zip on a second Mac, or in a fresh user account, before
   publishing it.
5. Tag the release and publish it with the exact `gh release create` command
   `release.sh` prints at the end of its output.
