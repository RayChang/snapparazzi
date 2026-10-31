#!/bin/zsh
# `snapparazzi update`: argument parsing, version comparison, and the whole update
# flow against a local fake release and fake installer. No network; nothing is
# installed (the fake installer only records what it was given).

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

assert_not_contains() {
  local description="$1"
  local haystack="$2"
  local needle="$3"
  checks=$((checks + 1))
  if [[ "$haystack" != *"$needle"* ]]; then
    print "PASS: ${description}"
  else
    print -u2 "FAIL: ${description}"
    print -u2 "  unexpected: ${needle}"
    failures=$((failures + 1))
  fi
}

if [[ ! -x "$binary" ]]; then
  print -u2 "FAIL: native executable not found at ${binary}"
  exit 1
fi

current="$("$binary" --version | awk '{print $2}')"

# Parsing
assert_equal "update parses" "mode=update;check=false" "$("$binary" --test command-line update)"
assert_equal "update --check parses" "mode=update;check=true" "$("$binary" --test command-line update --check)"
assert_equal "update --help parses" "mode=update-help" "$("$binary" --test command-line update --help)"
assert_equal "update -h parses" "mode=update-help" "$("$binary" --test command-line update -h)"
assert_equal "the screenshot parser is unchanged" \
  "mode=list;window=nil;interval=nil;output=default;format=jpg;maxDimension=nil" \
  "$("$binary" --test command-line --list)"

last_output="$("$binary" update --bogus 2>&1)"; last_status=$?
assert_equal "unknown update option exits 2" "2" "$last_status"
assert_contains "unknown update option is named" "$last_output" "Not supported by update: --bogus"
last_output="$("$binary" update --check --check 2>&1)"; last_status=$?
assert_equal "duplicate --check exits 2" "2" "$last_status"

last_output="$("$binary" update --help 2>&1)"; last_status=$?
assert_equal "update --help exits 0" "0" "$last_status"
assert_contains "update help explains --check" "$last_output" "snapparazzi update --check"
assert_contains "update help covers older versions" "$last_output" "install.sh | sh"
last_output="$("$binary" --help 2>&1)"
assert_contains "main help lists update" "$last_output" "snapparazzi update [--check]"

# Version comparison
assert_equal "patch is newer" "NEWER" "$("$binary" --test version-newer v1.3.1 1.3.0)"
assert_equal "minor beats patch" "NEWER" "$("$binary" --test version-newer 1.10.0 1.9.9)"
assert_equal "same version is not newer" "NOT-NEWER" "$("$binary" --test version-newer v1.3.0 1.3.0)"
assert_equal "older is not newer" "NOT-NEWER" "$("$binary" --test version-newer v1.2.9 1.3.0)"
assert_equal "two-part versions are invalid" "INVALID" "$("$binary" --test version-newer v1.3 1.3.0)"
assert_equal "suffixes are invalid" "INVALID" "$("$binary" --test version-newer v1.3.1-beta 1.3.0)"

# The update flow, with a copy of the binary in its own bin folder.
work="$(mktemp -d "${TMPDIR:-/tmp}/snapparazzi-update-tests.XXXXXX")"
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/bin"
cp "$binary" "$work/bin/snapparazzi"
cat > "$work/installer.sh" <<EOF
#!/bin/sh
printf 'REF=%s\nBIN=%s\n' "\$SNAPPARAZZI_REF" "\$SNAPPARAZZI_BIN" > "$work/installer.log"
exit "\${FAKE_INSTALL_STATUS:-0}"
EOF
release() { print -r -- "{\"tag_name\": \"$1\", \"name\": \"Snapparazzi $1\"}" > "$work/latest.json"; }
run_update() {
  rm -f "$work/installer.log"
  last_output="$(SNAPPARAZZI_TEST_RELEASE_URL="file://$work/latest.json" \
    SNAPPARAZZI_TEST_INSTALLER_URL="file://$work/installer.sh" \
    "$work/bin/snapparazzi" update "$@" 2>&1)"
  last_status=$?
}

release "v$current"
run_update
assert_equal "same release exits 0" "0" "$last_status"
assert_contains "same release says up to date" "$last_output" "Already up to date"
assert_equal "same release runs no installer" "no" "$([[ -f "$work/installer.log" ]] && print yes || print no)"

release "v0.9.0"
run_update
assert_contains "an older release is not installed" "$last_output" "Already up to date"
assert_equal "an older release runs no installer" "no" "$([[ -f "$work/installer.log" ]] && print yes || print no)"

release "v99.0.0"
run_update --check
assert_equal "--check exits 0" "0" "$last_status"
assert_contains "--check names the new release" "$last_output" "Update available: v99.0.0"
assert_equal "--check runs no installer" "no" "$([[ -f "$work/installer.log" ]] && print yes || print no)"

run_update
assert_equal "update exits 0" "0" "$last_status"
assert_contains "update says what it installed" "$last_output" "Updated to v99.0.0"
assert_equal "installer gets the release tag" "REF=v99.0.0" "$(sed -n 1p "$work/installer.log" 2>/dev/null)"
installed_dir="$(sed -n 2p "$work/installer.log" 2>/dev/null)"; installed_dir="${installed_dir#BIN=}"
assert_equal "installer replaces the running binary's folder" "yes" "$([[ -n "$installed_dir" && "$installed_dir" -ef "$work/bin" ]] && print yes || print no)"
assert_equal "no installer script is left behind" "" "$(ls "${TMPDIR:-/tmp}" | grep -E '^snapparazzi-update-[0-9]+\.sh$' || true)"

FAKE_INSTALL_STATUS=1 run_update
assert_equal "a failed install exits 1" "1" "$last_status"
assert_contains "a failed install is explained" "$last_output" "the installed version is unchanged"
assert_not_contains "a failed install claims no success" "$last_output" "Updated to"

print -r -- '{"tag_name": "nightly"}' > "$work/latest.json"
run_update
assert_equal "an unusable release tag exits 1" "1" "$last_status"
assert_contains "an unusable release tag is explained" "$last_output" "Cannot read the latest release"
assert_equal "an unusable release tag runs no installer" "no" "$([[ -f "$work/installer.log" ]] && print yes || print no)"

print -r -- 'not json' > "$work/latest.json"
run_update
assert_equal "bad JSON exits 1" "1" "$last_status"

last_output="$(SNAPPARAZZI_TEST_RELEASE_URL="file://$work/missing.json" "$work/bin/snapparazzi" update 2>&1)"
last_status=$?
assert_equal "no release information exits 1" "1" "$last_status"
assert_contains "no release information is explained" "$last_output" "Cannot check the latest release"

release "v99.0.0"
last_output="$(SNAPPARAZZI_TEST_RELEASE_URL="file://$work/latest.json" \
  SNAPPARAZZI_TEST_INSTALLER_URL="file://$work/missing.sh" "$work/bin/snapparazzi" update 2>&1)"
last_status=$?
assert_equal "a missing installer exits 1" "1" "$last_status"
assert_contains "a missing installer is explained" "$last_output" "Cannot download the installer"

chmod a-w "$work/bin"
run_update
assert_equal "an unwritable bin folder exits 1" "1" "$last_status"
assert_contains "an unwritable bin folder is explained" "$last_output" "No permission to write"
assert_equal "an unwritable bin folder runs no installer" "no" "$([[ -f "$work/installer.log" ]] && print yes || print no)"
chmod u+w "$work/bin"

if (( failures > 0 )); then
  print -u2 "${failures}/${checks} update tests failed"
  exit 1
fi

print "All ${checks} update tests passed"
