#!/bin/sh
# Build only the standalone probe; do not install or alter Snapparazzi.
set -eu

if [ "$(uname -s)" != Darwin ]; then
  printf '%s\n' 'recording-probe requires macOS 15+ and an Apple macOS SDK.' >&2
  exit 1
fi

probe_dir=$(CDPATH= cd -P "$(dirname "$0")" && pwd)
build_dir="$probe_dir/../../.build/recording-probe"
mkdir -p "$build_dir"
plutil -lint "$probe_dir/Info.plist"
xcrun --sdk macosx swiftc \
  -swift-version 5 -O -whole-module-optimization -warnings-as-errors \
  -target "$(uname -m)-apple-macosx15.0" \
  "$probe_dir/Sources/Options.swift" \
  "$probe_dir/Sources/StreamProbe.swift" \
  "$probe_dir/Sources/Inspect.swift" \
  "$probe_dir/Sources/ProbeMain.swift" \
  -Xlinker -sectcreate -Xlinker __TEXT -Xlinker __info_plist \
  -Xlinker "$probe_dir/Info.plist" \
  -o "$build_dir/recording-probe"
codesign --force --sign - --identifier dev.snapparazzi.recording-probe \
  "$build_dir/recording-probe"
printf 'Built: %s\n' "$build_dir/recording-probe"
