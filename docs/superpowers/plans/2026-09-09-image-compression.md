# Snapparazzi Image Compression Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Default captures to compact JPEG and add selectable image formats plus optional dimension limiting.

**Architecture:** Extend the existing CLI configuration with a typed image format and optional maximum dimension. Capture directly into the requested format, then invoke macOS `sips` only when resizing is requested.

**Tech Stack:** Swift 6, Foundation, CoreGraphics, `/usr/sbin/screencapture`, `/usr/bin/sips`, POSIX shell.

---

### Task 1: Define the compression CLI contract

**Files:**
- Modify: `tests/run-tests.sh`

- [ ] Add failing tests for the 1.1.0 version, format and dimension help, JPEG defaults, accepted formats and alias, invalid input, extensions, capture arguments, and resize arguments.
- [ ] Run the suite and confirm failures are caused by missing compression behavior.
- [ ] Commit the red tests.

### Task 2: Implement direct compressed capture

**Files:**
- Modify: `Sources/Snapparazzi/main.swift`

- [ ] Add `CaptureFormat`, JPEG defaulting, CLI parsing, filename extensions, and direct `screencapture -t<format>` arguments.
- [ ] Add optional in-place `sips -Z` resizing with shared child-process cancellation and cleanup on failure.
- [ ] Update bilingual help and runtime summary.
- [ ] Run all tests and commit when green.

### Task 3: Document, benchmark, and release

**Files:**
- Modify: `README.md`

- [ ] Document compression tradeoffs, examples, benchmark context, and preservation of PNG mode.
- [ ] Run a real JPEG capture and dimension-limited JPEG capture against a visible test window, verifying format and dimensions.
- [ ] Run a clean release build, complete tests, shell analysis, and installer test.
- [ ] Merge to `main`, push, tag `v1.1.0`, wait for CI, and verify a clean raw-GitHub install.
- [ ] Reinstall `~/.local/bin/snapparazzi` from the published installer and verify version/help.
