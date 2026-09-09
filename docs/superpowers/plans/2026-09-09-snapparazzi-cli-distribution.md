# Snapparazzi Native CLI Distribution Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship Snapparazzi as a tested native macOS CLI with bilingual help and a public one-line GitHub installer.

**Architecture:** Keep the application in one Swift source file so the installer can download and compile it directly. Separate repository tooling into black-box tests, a Makefile, installer, README, license, and macOS CI workflow.

**Tech Stack:** Swift 6, Foundation, CoreGraphics, Dispatch, POSIX shell, GitHub Actions, GitHub CLI.

---

### Task 1: Establish CLI contract with failing tests

**Files:**
- Create: `tests/run-tests.sh`

- [ ] Write black-box tests for `--help`, `--version`, invalid options, option parsing, validation, naming, and scheduling.
- [ ] Run the suite and confirm it fails because `.build/snapparazzi` is absent.
- [ ] Commit the red tests.

### Task 2: Build the native Swift CLI

**Files:**
- Create: `Sources/Snapparazzi/main.swift`
- Create: `Makefile`

- [ ] Port the existing capture behavior into compiled Swift source.
- [ ] Add `--list`, `--window`, `--interval`, `--output`, `--help`, and `--version` parsing with exit statuses 0/1/2.
- [ ] Add complete bilingual help and retain internal black-box test hooks.
- [ ] Build with `swiftc -emit-executable -O` and run the full suite until green.
- [ ] Commit the CLI implementation.

### Task 3: Add public installation and documentation

**Files:**
- Create: `install.sh`
- Create: `README.md`
- Create: `LICENSE`
- Create: `.gitignore`
- Create: `.github/workflows/ci.yml`

- [ ] Write installer tests first and verify they fail before `install.sh` exists.
- [ ] Implement the macOS source-build installer, PATH setup, and environment overrides.
- [ ] Document installation, commands, permissions, examples, development, updating, and uninstalling in both languages.
- [ ] Add MIT license, generated-file ignores, and macOS CI.
- [ ] Run installer tests using a temporary install destination and commit when green.

### Task 4: Release and verify from GitHub

- [ ] Run black-box tests and a fresh optimized build with warnings treated as errors.
- [ ] Merge the implementation to `main` and create public `RayChang/snapparazzi`.
- [ ] Push `main`, create and push annotated tag `v1.0.0`, and verify repository visibility and files.
- [ ] Run the published raw `install.sh` into a temporary destination and verify the installed binary's help and version.
- [ ] Install the verified binary to `~/.local/bin/snapparazzi`.
- [ ] Remove only the obsolete source and tests from `~/Snapparazzi`; preserve the runtime directory and any captures.
