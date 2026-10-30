#!/bin/zsh
# Record subcommand parsing and help. Needs no Screen Recording permission or windows.

set -u

script_dir="${0:A:h}"
project_dir="${script_dir:h}"
binary="${project_dir}/.build/snapparazzi"
failures=0
checks=0
last_output=""
last_status=0

assert_equal() {
  local description="$1"
  local expected="$2"
  local actual="$3"
  checks=$((checks + 1))
  if [[ "$actual" == "$expected" ]]; then
    print "PASS: ${description}"
  else
    print -u2 "FAIL: ${description}"
    print -u2 "  expected: ${expected}"
    print -u2 "  actual:   ${actual}"
    failures=$((failures + 1))
  fi
}

assert_contains() {
  local description="$1"
  local haystack="$2"
  local needle="$3"
  checks=$((checks + 1))
  if [[ "$haystack" == *"$needle"* ]]; then
    print "PASS: ${description}"
  else
    print -u2 "FAIL: ${description}"
    print -u2 "  missing: ${needle}"
    failures=$((failures + 1))
  fi
}

run_cli() {
  last_output="$($binary "$@" 2>&1)"
  last_status=$?
}

# Parses with --test record-arguments and expects the given serialization.
parses_to() {
  local description="$1"
  local expected="$2"
  shift 2
  assert_equal "$description" "$expected" "$($binary --test record-arguments "$@" 2>&1)"
}

# Expects a usage error (exit 2) whose message contains the given text.
rejects() {
  local description="$1"
  local needle="$2"
  shift 2
  run_cli --test record-arguments "$@"
  assert_equal "${description} (exit 2)" "2" "$last_status"
  assert_contains "${description} (message)" "$last_output" "$needle"
}

if [[ ! -x "$binary" ]]; then
  print -u2 "FAIL: native executable not found at ${binary}"
  exit 1
fi

defaults="mode=record;window=42;audio=none;fps=30;codec=h264;duration=nil;output=default;maxDimension=nil"
parses_to "record defaults" "$defaults" -w 42
parses_to "long and short window options are equivalent" "$defaults" --window 42
parses_to \
  "full record options serialize in a fixed order" \
  "mode=record;window=42;audio=both;fps=60;codec=hevc;duration=3600;output=recording.mp4;maxDimension=1280" \
  --window 42 --audio both --fps 60 --codec hevc --duration 3600 --output recording.mp4 --max-dimension 1280

for mode in none system mic both; do
  parses_to "audio mode ${mode}" "mode=record;window=1;audio=${mode};fps=30;codec=h264;duration=nil;output=default;maxDimension=nil" -w 1 --audio "$mode"
done
rejects "audio modes are exact and lowercase" "Invalid audio mode: System" -w 1 --audio System
rejects "unknown audio modes are rejected" "Invalid audio mode: all" -w 1 --audio all

parses_to "minimum fps" "mode=record;window=1;audio=none;fps=1;codec=h264;duration=nil;output=default;maxDimension=nil" -w 1 --fps 1
for fps in 0 61 30.0 abc; do
  rejects "fps ${fps} is rejected" "Invalid fps: ${fps}" -w 1 --fps "$fps"
done

rejects "image formats are not video codecs" "Unsupported video codec: heic" -w 1 --codec heic
rejects "jpeg is not a video codec" "Unsupported video codec: jpeg" -w 1 --codec jpeg

for duration in .5 0.5 3600 86400; do
  run_cli --test record-arguments -w 1 --duration "$duration"
  assert_equal "duration ${duration} is accepted" "0" "$last_status"
done
parses_to "half-second duration keeps its value" "mode=record;window=1;audio=none;fps=30;codec=h264;duration=0.5;output=default;maxDimension=nil" -w 1 --duration .5
for duration in 0.4 -1 nan inf 86400.5 1e3 0x10 ""; do
  rejects "duration '${duration}' is rejected" "Invalid duration" -w 1 --duration "$duration"
done

rejects "window 0 is rejected" "Invalid window ID: 0" -w 0
rejects "window IDs above UInt32 are rejected" "Invalid window ID: 4294967296" -w 4294967296
rejects "record requires a window" "record requires --window" --audio system
rejects "record rejects positional arguments" "Unknown option: extra" -w 1 extra

parses_to "uppercase .MP4 is accepted" "mode=record;window=1;audio=none;fps=30;codec=h264;duration=nil;output=Demo.MP4;maxDimension=nil" -w 1 -o Demo.MP4
parses_to "output paths with spaces and Chinese are kept" "mode=record;window=1;audio=none;fps=30;codec=h264;duration=nil;output=我的 影片.mp4;maxDimension=nil" -w 1 -o "我的 影片.mp4"
rejects "empty output is rejected" "must be a .mp4 file" -w 1 -o ""
rejects "non-MP4 output is rejected" "must be a .mp4 file: clip.mov" -w 1 -o clip.mov

rejects "max dimension 1 is rejected" "Invalid maximum dimension: 1" -w 1 -m 1
rejects "max dimension above 8192 is rejected" "Invalid maximum dimension: 8193" -w 1 -m 8193
parses_to "max dimension 2 is accepted" "mode=record;window=1;audio=none;fps=30;codec=h264;duration=nil;output=default;maxDimension=2" -w 1 -m 2

rejects "short and long duplicates are rejected" "Duplicate option: --window" -w 1 --window 2
rejects "duplicate audio is rejected" "Duplicate option: --audio" -w 1 --audio mic --audio mic
rejects "missing values identify the option" "Missing value for --fps" -w 1 --fps

for option in --interval -i --format -f --list -l --version -V; do
  rejects "record rejects screenshot option ${option}" "Not supported by record: ${option}" -w 1 "$option"
done

parses_to "help returns early without a window" "mode=record-help" --help
parses_to "help after a valid option still returns help" "mode=record-help" -w 1 --help
rejects "errors before help are not hidden" "Invalid fps: bad" --fps bad --help
parses_to "help before a bad value still prints help" "mode=record-help" --help --fps bad

# Real command lines (subcommand dispatch, help text, exit codes).
run_cli record --help
assert_equal "record --help exits successfully" "0" "$last_status"
assert_contains "record help is bilingual" "$last_output" "用法 / USAGE"
assert_contains "record help states the macOS requirement" "$last_output" "macOS 15"
assert_contains "record help explains the audio scope" "$last_output" "聲音範圍 / AUDIO SCOPE"
assert_contains "record help warns about same-app audio" "$last_output" "same"
assert_contains "record help documents MP4 output" "$last_output" "--output <file.mp4>"
assert_contains "record help walks through the steps" "$last_output" "怎麼錄 / HOW TO RECORD"
assert_contains "record help says --window is required" "$last_output" "Required; there is no default."
assert_contains "record help gives the audio default" "$last_output" "Default: none"
assert_contains "record help explains every audio mode" "$last_output" "both    app audio and microphone"
assert_contains "record help gives the duration default" "$last_output" "Default: no limit; stop with Ctrl-C."
assert_contains "record help gives the output default" "$last_output" "Default: ~/Snapparazzi/recordings/YYYYMMDD-HHMMSS-<PID>.mp4"
assert_contains "record help gives the fps default" "$last_output" "Default: 30"
assert_contains "record help gives the codec default" "$last_output" "Default: h264"
assert_contains "record help gives the size default" "$last_output" "Default: the window's native pixel size"
assert_contains "record help has troubleshooting" "$last_output" "常見問題 / TROUBLESHOOTING"

run_cli record
assert_equal "record without a window is a usage error" "2" "$last_status"
assert_contains "usage errors point to help" "$last_output" "snapparazzi --help"

run_cli --help
assert_contains "root help points to record help" "$last_output" "snapparazzi record --help"

run_cli --audio system
assert_equal "screenshot mode rejects --audio" "2" "$last_status"
run_cli -w 1 --duration 5
assert_equal "screenshot mode rejects --duration" "2" "$last_status"
assert_contains "screenshot mode reports the recording option" "$last_output" "Unknown option: --duration"

run_cli capture --help
assert_equal "capture alias keeps the screenshot help" "0" "$last_status"
assert_contains "capture alias prints the root usage" "$last_output" "snapparazzi [options]"
run_cli capture --bogus
assert_equal "capture alias keeps screenshot errors" "2" "$last_status"
run_cli -w 1 capture
assert_equal "subcommands are only recognized first" "2" "$last_status"
assert_contains "a later subcommand token is unknown" "$last_output" "Unknown option: capture"

# Help and parse errors must not touch the filesystem.
side_effect_home="$(mktemp -d)"
HOME="$side_effect_home" "$binary" record --help >/dev/null 2>&1
HOME="$side_effect_home" "$binary" record -w 1 --fps 0 >/dev/null 2>&1
assert_equal "help and usage errors create no files" "" "$(ls -A "$side_effect_home")"
rm -rf "$side_effect_home"

if (( failures > 0 )); then
  print -u2 "${failures}/${checks} record CLI tests failed"
  exit 1
fi

print "All ${checks} record CLI tests passed"
