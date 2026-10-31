# Product

<!-- impeccable:product-schema 1 -->

## Platform

web

## Stack

Static HTML/CSS (plus the small script the language toggle needs) in `site/`, published to GitHub Pages by a GitHub Actions workflow. No build step. Confirmed by the owner on 2026-10-31.

## Users

Mac users who want to record or capture one specific app window: an online course, a meeting, a demo. They are comfortable typing a command into Terminal, but are not necessarily developers. They come to the page to find out what the tool does, whether it fits their Mac, and how to install it and make their first recording.

## Product Purpose

Snapparazzi is a native macOS command-line tool for one app window. It either saves a screenshot of that window at a fixed interval (JPG, HEIC or PNG), or records it to an MP4 with the app's own audio, the microphone, or both. Pick the window from a list or pass its window ID, and press Ctrl-C to stop. Success: a visitor installs it with one command and gets a clean recording of just the window they care about.

## Positioning

It records one window, not the whole screen, and only that app's sound, so other apps' notifications and audio stay out. It is a small native binary built on the visitor's own Mac from source, run from Terminal, and stopped with Ctrl-C. The window may be on another desktop or in full screen.

## Operating Context

- Install: `curl -fsSL https://raw.githubusercontent.com/RayChang/snapparazzi/main/install.sh | sh` builds from source into `~/.local/bin`. It needs Xcode or its Command Line Tools.
- Update: `snapparazzi update` (1.3.1 and later).
- Workflow: `snapparazzi --list` to find the window ID, then `snapparazzi -w <id>` for screenshots or `snapparazzi record -w <id>` for video.
- Permissions: Screen & System Audio Recording for the terminal app, plus Microphone for `--audio mic|both`.
- Screenshots need macOS 14; recording needs macOS 15.
- Output defaults to `~/Snapparazzi/captures` and `~/Snapparazzi/recordings`.

## Capabilities and Constraints

- Screenshots: interval of at least 0.5 s, JPG, HEIC or PNG, an optional longest-edge limit, and an interactive picker.
- Recording: H.264 or HEVC at 1–60 fps, an optional duration, and `--audio none|system|mic|both`. With `both`, the two sources are mixed into one AAC track.
- One process handles one window. Run several processes for several windows.
- `system` audio is the whole app, so other tabs of the same browser can be heard.
- Chrome stops drawing web video while its window is on another desktop. The workaround is to reopen Chrome with `--disable-backgrounding-occluded-windows`.
- DRM-protected content may not be captured.
- Current version: 1.3.1. MIT license (see `LICENSE`).

## Brand Commitments

- The name is "Snapparazzi" with two p's. Tagline in the CLI: "📸 Snapparazzi — 專業地打擾你的視窗 / professionally bothering your windows."
- The voice is bilingual, Traditional Chinese and English, like the README and `--help`. On the website, the language is switched with a toggle button rather than shown side by side.
- The owner first supplied a retro badge reference: the logo of an unrelated photo-booth business called "Snaparazzi". Never use its marks, wording or layout. In the direction round of 2026-10-31, the owner chose a full ASCII / character-grid world for the website instead.

## Evidence on Hand

- README.md, the CLI help text (`Sources/Snapparazzi/CLI/Help.swift`), and the GitHub releases (v1.1.0–v1.3.1) hold the real facts and wording.
- There are no product screenshots, demo videos, user testimonials, download counts or press. Do not invent any of them. Real terminal output, copied from the CLI's actual messages, may be shown.

## Product Principles

1. One window, done well: every claim on the page is about recording or capturing a single window cleanly.
2. Honest about limits. Requirements, permissions and known caveats are stated plainly where they matter.
3. Copy and paste beats explanation. The install command and the first commands must be one click away.
4. Playful name, careful tool: the personality lives in the brand, and the instructions stay precise.
