#!/bin/zsh

set -u

script_dir="${0:A:h}"
project_dir="${script_dir:h}"
installer="${project_dir}/install.sh"
failures=0
checks=0

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

if [[ ! -x "$installer" ]]; then
  print -u2 "FAIL: installer not found at ${installer}"
  exit 1
fi

test_root="$(mktemp -d)"
trap 'rm -rf "$test_root"' EXIT
install_dir="${test_root}/bin"
curl_log="${test_root}/curl-url"
fixture_path="${project_dir}/tests/fixtures:${install_dir}:/usr/bin:/bin:/usr/sbin:/sbin"

installer_output="$(
  PATH="$fixture_path" \
  SNAPPARAZZI_BIN="$install_dir" \
  SNAPPARAZZI_REF="v9-test" \
  SNAPPARAZZI_TEST_SOURCE="${project_dir}/Sources/Snapparazzi/main.swift" \
  SNAPPARAZZI_TEST_CURL_LOG="$curl_log" \
  "$installer" 2>&1
)"
installer_status=$?

assert_equal "installer exits successfully" "0" "$installer_status"
assert_equal \
  "installer fetches source from the requested Git ref" \
  "https://raw.githubusercontent.com/RayChang/snapparazzi/v9-test/Sources/Snapparazzi/main.swift" \
  "$(cat "$curl_log")"
assert_equal \
  "installer creates a native executable" \
  "executable" \
  "$([[ -x "${install_dir}/snapparazzi" ]] && print executable || print missing)"
assert_equal \
  "installed executable reports its version" \
  "snapparazzi 1.0.0" \
  "$("${install_dir}/snapparazzi" --version)"
assert_contains \
  "installed executable includes full help" \
  "$("${install_dir}/snapparazzi" --help)" \
  "結束碼 / EXIT STATUS"
assert_contains \
  "installer reports the destination" \
  "$installer_output" \
  "${install_dir}/snapparazzi"
assert_contains \
  "installer points users to CLI help" \
  "$installer_output" \
  "snapparazzi --help"

if (( failures > 0 )); then
  print -u2 "${failures}/${checks} installer tests failed"
  exit 1
fi

print "All ${checks} installer tests passed"
