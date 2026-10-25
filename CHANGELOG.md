# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

## [Unreleased]

### Fixed

- Dock badges no longer show over full-screen apps.
- A window whose restore timed out (hung app) stays in Peek's list and can be
  restored later instead of being stranded off-screen.
- Cmd+H on a window that is already hidden no longer overwrites its saved
  position.
- Quitting Peek via `killall`/Ctrl-C now restores parked windows; a second
  signal exits immediately.
- The Cmd+H/Dock click event tap is retried if creating it fails right after
  granting Accessibility.

## [0.1.0] - 2026-09-18

### Added

- Hover preview panel with thumbnails and titles for a Dock icon's windows,
  including hidden and minimized ones.
- Click a thumbnail to bring that window to the front.
- Hide and close buttons on each thumbnail.
- Cmd+H hides only the focused window, with two hide methods: instant
  "parking" without animation (default), or minimizing as an alternative/
  fallback.
- Windows are restored on Dock icon click, from the menu bar menu, from the
  preview panel, or on app activation when no window of that app is visible.
- A count badge on the Dock icon shows how many windows Peek is currently
  hiding for that app.
- Exclusion list to disable the Cmd+H behavior for specific apps.
- Launch at login.
- Built-in diagnostics report.
