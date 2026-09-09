# Snapparazzi Native CLI Distribution Design

## Goal

Turn Snapparazzi from an interpreted personal Swift script into a public, installable macOS command-line executable while preserving its interactive window-capture workflow.

## Command interface

`snapparazzi` remains interactive by default. It also supports automation through:

```text
snapparazzi --list
snapparazzi --window <id> [--interval <seconds>] [--output <directory>]
snapparazzi -h | --help
snapparazzi -V | --version
```

Missing window or interval values are prompted interactively. `--list` is exclusive and exits after printing visible window IDs. Unknown options, missing values, and conflicting arguments return exit status 2. Runtime and permission failures return 1; help, version, listing, cancellation, and clean `Ctrl-C` shutdown return 0.

Help and README content are bilingual Traditional Chinese and English. Help documents options, interactive behavior, permission setup, output paths and names, multi-instance use, examples, and exit statuses.

## Source and installation

The public repository is `RayChang/snapparazzi`, stored locally at `~/Workspace/snapparazzi`, with an MIT license. One Swift source file is compiled into a native executable using the supported Swift driver command `swiftc -emit-executable` with release optimization.

The public installer is invoked with:

```sh
curl -fsSL https://raw.githubusercontent.com/RayChang/snapparazzi/main/install.sh | sh
```

It supports `SNAPPARAZZI_REF` and `SNAPPARAZZI_BIN`, requires macOS plus Xcode Command Line Tools, builds in a temporary directory, atomically installs to `~/.local/bin/snapparazzi`, and adds that directory to the user's shell PATH when needed.

Runtime captures remain under `~/Snapparazzi/captures` by default. Existing source files under `~/Snapparazzi` are removed only after the repository build and tests pass; capture data is never removed.

## Quality and release

Black-box tests cover argument parsing, complete help, version output, validation, naming, and scheduling helpers. CI builds and tests on `macos-latest`. Local verification includes tests, an optimized release build, installer tests with a temporary destination, and a raw-GitHub clean install after push.

The initial public release is version `1.0.0`, published on `main` with tag `v1.0.0`.
