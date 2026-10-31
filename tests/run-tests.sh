#!/bin/zsh

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

if [[ ! -x "$binary" ]]; then
  print -u2 "FAIL: native executable not found at ${binary}"
  exit 1
fi

run_cli --help
assert_equal "--help exits successfully" "0" "$last_status"
assert_contains "help has an English usage section" "$last_output" "USAGE"
assert_contains "help has a Traditional Chinese usage section" "$last_output" "用法"
assert_contains "help documents window selection" "$last_output" "--window <id>"
assert_contains "help documents interval configuration" "$last_output" "--interval <seconds>"
assert_contains "help documents output configuration" "$last_output" "--output <directory>"
assert_contains "help documents image formats" "$last_output" "--format <jpg|heic|png>"
assert_contains "help documents dimension limiting" "$last_output" "--max-dimension <pixels>"
assert_contains "help identifies JPEG as the default" "$last_output" "Default: jpg"
assert_contains "help documents listing" "$last_output" "--list"
assert_contains "help documents permissions bilingually" "$last_output" "螢幕錄製 / Screen Recording"
assert_contains "help documents exit statuses" "$last_output" "結束碼 / EXIT STATUS"
assert_contains "help documents concurrent instances" "$last_output" "multiple Terminal"
assert_contains "help explains how to find a window ID first" "$last_output" "STEP 1: FIND THE WINDOW ID"
assert_contains "help explains the usage notation" "$last_output" "Notation:"
assert_contains "help gives the window default" "$last_output" "Default: you pick one from a numbered list."
assert_contains "help gives the interval default" "$last_output" "just pressing Enter uses 2 seconds"
assert_contains "help gives the output default" "$last_output" "Default: ~/Snapparazzi/captures"
assert_contains "help gives the size default" "$last_output" "Default: original size."
assert_contains "help points to recording" "$last_output" "snapparazzi record --window <id> [options]"

run_cli -h
assert_equal "short help exits successfully" "0" "$last_status"
assert_contains "short help prints the same usage" "$last_output" "snapparazzi [options]"

run_cli --version
assert_equal "--version exits successfully" "0" "$last_status"
assert_equal "version output is stable" "snapparazzi 1.3.1" "$last_output"

run_cli -V
assert_equal "short version exits successfully" "0" "$last_status"
assert_equal "short version matches long version" "snapparazzi 1.3.1" "$last_output"

run_cli --definitely-not-an-option
assert_equal "unknown options use the usage exit status" "2" "$last_status"
assert_contains "unknown options explain the problem" "$last_output" "未知選項 / Unknown option"

run_cli --window
assert_equal "missing option values use the usage exit status" "2" "$last_status"
assert_contains "missing values identify the option" "$last_output" "--window"

run_cli --list --interval 2
assert_equal "list rejects capture options" "2" "$last_status"
assert_contains "conflicts are explained" "$last_output" "--list"

run_cli --format gif
assert_equal "unsupported image formats use the usage exit status" "2" "$last_status"
assert_contains "unsupported formats identify the bad value" "$last_output" "gif"

run_cli --max-dimension 0
assert_equal "zero maximum dimensions use the usage exit status" "2" "$last_status"
assert_contains "invalid dimensions identify the option" "$last_output" "--max-dimension"
assert_contains "zero dimensions identify the bad value" "$last_output" "Invalid maximum dimension: 0"

run_cli --max-dimension 1280.5
assert_equal "fractional maximum dimensions are rejected" "2" "$last_status"
assert_contains "fractional dimensions identify the bad value" "$last_output" "Invalid maximum dimension: 1280.5"

run_cli --list --format jpg
assert_equal "list rejects image format options" "2" "$last_status"
assert_contains "list and format conflicts are explained" "$last_output" "--list cannot be combined"

assert_equal \
  "unsafe filename characters are replaced" \
  "Foo_Bar_ Demo_App" \
  "$($binary --test sanitize $'Foo/Bar: Demo\nApp')"

assert_equal \
  "empty app names receive a fallback" \
  "UnknownApp" \
  "$($binary --test sanitize $'\n\t')"

assert_equal \
  "PNG filename contains app, session timestamp, and padded sequence" \
  "Google Chrome_20260909-153012_000007.png" \
  "$($binary --test filename "Google Chrome" "20260909-153012" "7" "png")"

assert_equal \
  "compressed filename uses the selected extension" \
  "Google Chrome_20260909-153012_000007.jpg" \
  "$($binary --test filename "Google Chrome" "20260909-153012" "7" "jpg")"

assert_equal \
  "empty interval uses the two-second default" \
  "2" \
  "$($binary --test interval "")"

assert_equal \
  "fractional intervals are accepted" \
  "2.5" \
  "$($binary --test interval "2.5")"

assert_equal \
  "intervals below the minimum are rejected" \
  "INVALID" \
  "$($binary --test interval "0.49")"

assert_equal \
  "non-finite intervals are rejected" \
  "INVALID" \
  "$($binary --test interval "nan")"

assert_equal \
  "one in-range window selection is accepted" \
  "2" \
  "$($binary --test selection "3" "2")"

assert_equal \
  "multiple selections are rejected" \
  "INVALID" \
  "$($binary --test selection "3" "1,2")"

assert_equal \
  "late schedules skip missed ticks" \
  "6" \
  "$($binary --test next-tick "2" "5.2")"

assert_equal \
  "automation options parse into one capture configuration" \
  "mode=capture;window=42;interval=1.25;output=/tmp/caps;format=heic;maxDimension=1280" \
  "$($binary --test arguments --window 42 --interval 1.25 --output /tmp/caps --format heic --max-dimension 1280)"

assert_equal \
  "list mode parses independently" \
  "mode=list;window=nil;interval=nil;output=default;format=jpg;maxDimension=nil" \
  "$($binary --test arguments --list)"

assert_equal \
  "JPEG is the default capture format" \
  "mode=capture;window=nil;interval=nil;output=default;format=jpg;maxDimension=nil" \
  "$($binary --test arguments)"

assert_equal \
  "jpeg alias normalizes to jpg" \
  "mode=capture;window=nil;interval=nil;output=default;format=jpg;maxDimension=nil" \
  "$($binary --test arguments --format jpeg)"

assert_equal \
  "capture arguments encode directly to the selected format" \
  "-x|-o|-theic|-l42|/tmp/frame.heic" \
  "$($binary --test capture-arguments 42 heic /tmp/frame.heic)"

assert_equal \
  "resize arguments preserve aspect ratio within a maximum dimension" \
  "-Z|1280|/tmp/frame.jpg" \
  "$($binary --test resize-arguments 1280 /tmp/frame.jpg)"

assert_equal \
  "dimension limiting skips images already within the maximum" \
  "SKIP" \
  "$($binary --test resize-needed 100 50 1280)"

assert_equal \
  "dimension limiting resizes images above the maximum" \
  "RESIZE" \
  "$($binary --test resize-needed 2560 1410 1280)"

if (( failures > 0 )); then
  print -u2 "${failures}/${checks} tests failed"
  exit 1
fi

print "All ${checks} tests passed"
