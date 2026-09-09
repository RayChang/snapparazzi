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
assert_contains "help documents listing" "$last_output" "--list"
assert_contains "help documents permissions bilingually" "$last_output" "螢幕錄製 / Screen Recording"
assert_contains "help documents exit statuses" "$last_output" "結束碼 / EXIT STATUS"
assert_contains "help documents concurrent instances" "$last_output" "multiple Terminal"

run_cli -h
assert_equal "short help exits successfully" "0" "$last_status"
assert_contains "short help prints the same usage" "$last_output" "snapparazzi [options]"

run_cli --version
assert_equal "--version exits successfully" "0" "$last_status"
assert_equal "version output is stable" "snapparazzi 1.0.0" "$last_output"

run_cli -V
assert_equal "short version exits successfully" "0" "$last_status"
assert_equal "short version matches long version" "snapparazzi 1.0.0" "$last_output"

run_cli --definitely-not-an-option
assert_equal "unknown options use the usage exit status" "2" "$last_status"
assert_contains "unknown options explain the problem" "$last_output" "未知選項 / Unknown option"

run_cli --window
assert_equal "missing option values use the usage exit status" "2" "$last_status"
assert_contains "missing values identify the option" "$last_output" "--window"

run_cli --list --interval 2
assert_equal "list rejects capture options" "2" "$last_status"
assert_contains "conflicts are explained" "$last_output" "--list"

assert_equal \
  "unsafe filename characters are replaced" \
  "Foo_Bar_ Demo_App" \
  "$($binary --test sanitize $'Foo/Bar: Demo\nApp')"

assert_equal \
  "empty app names receive a fallback" \
  "UnknownApp" \
  "$($binary --test sanitize $'\n\t')"

assert_equal \
  "filename contains app, session timestamp, and padded sequence" \
  "Google Chrome_20260909-153012_000007.png" \
  "$($binary --test filename "Google Chrome" "20260909-153012" "7")"

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
  "mode=capture;window=42;interval=1.25;output=/tmp/caps" \
  "$($binary --test arguments --window 42 --interval 1.25 --output /tmp/caps)"

assert_equal \
  "list mode parses independently" \
  "mode=list;window=nil;interval=nil;output=default" \
  "$($binary --test arguments --list)"

if (( failures > 0 )); then
  print -u2 "${failures}/${checks} tests failed"
  exit 1
fi

print "All ${checks} tests passed"
