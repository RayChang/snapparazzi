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
installer_tmp="${test_root}/tmp"
mkdir -p "$installer_tmp"
curl_log="${test_root}/curl-url"
installer_output=""
installer_status=0

# Builds a GitHub-style archive (one top-level folder) from the working tree.
# An optional function name is run inside the staged copy to break it on purpose.
make_archive() {
  local name="$1"
  local mutate="${2:-}"
  local stage="${test_root}/stage-${name}"
  local top="${stage}/snapparazzi-${name}"
  mkdir -p "$top"
  cp -R "${project_dir}/Sources" "${project_dir}/Resources" "${project_dir}/Makefile" "$top/"
  if [[ -n "$mutate" ]]; then
    (cd "$top" && "$mutate")
  fi
  tar -czf "${test_root}/${name}.tar.gz" -C "$stage" "snapparazzi-${name}"
  print -r -- "${test_root}/${name}.tar.gz"
}

# run_installer ARCHIVE REF BIN_DIR [extra env assignments...]
run_installer() {
  local archive="$1" ref="$2" bin_dir="$3"
  shift 3
  rm -f "$curl_log"
  installer_output="$(
    env PATH="${project_dir}/tests/fixtures:/usr/bin:/bin:/usr/sbin:/sbin" \
      TMPDIR="$installer_tmp" \
      SNAPPARAZZI_BIN="$bin_dir" \
      SNAPPARAZZI_REF="$ref" \
      SNAPPARAZZI_TEST_ARCHIVE="$archive" \
      SNAPPARAZZI_TEST_CURL_LOG="$curl_log" \
      "$@" \
      "$installer" 2>&1
  )"
  installer_status=$?
}

# A previously installed binary that failed installs must leave untouched.
place_old_binary() {
  mkdir -p "$1"
  print -r -- '#!/bin/sh
echo old-snapparazzi' > "$1/snapparazzi"
  chmod 0755 "$1/snapparazzi"
}

good_archive="$(make_archive v9-test)"

# 1. Normal install from a tag.
install_dir="${test_root}/bin"
run_installer "$good_archive" "v9-test" "$install_dir"
assert_equal "installer exits successfully" "0" "$installer_status"
assert_equal \
  "installer fetches the source archive for the requested Git ref" \
  "https://codeload.github.com/RayChang/snapparazzi/tar.gz/v9-test" \
  "$(cat "$curl_log")"
assert_equal \
  "installer creates a native executable" \
  "executable" \
  "$([[ -x "${install_dir}/snapparazzi" ]] && print executable || print missing)"
assert_equal \
  "installed executable reports its version" \
  "snapparazzi 1.1.0" \
  "$("${install_dir}/snapparazzi" --version)"
assert_contains \
  "installed executable includes full help" \
  "$("${install_dir}/snapparazzi" --help)" \
  "結束碼 / EXIT STATUS"
assert_contains \
  "installed executable embeds the microphone usage description" \
  "$(launchctl plist __TEXT,__info_plist "${install_dir}/snapparazzi" 2>&1)" \
  "NSMicrophoneUsageDescription"
assert_contains \
  "installed executable is signed with the stable identifier" \
  "$(codesign -dv "${install_dir}/snapparazzi" 2>&1)" \
  "Identifier=dev.snapparazzi.cli"
assert_contains \
  "installed executable includes record help" \
  "$("${install_dir}/snapparazzi" record --help)" \
  "snapparazzi record --window <id>"
assert_contains \
  "installer reports the destination" \
  "$installer_output" \
  "${install_dir}/snapparazzi"
assert_contains \
  "installer points users to CLI help" \
  "$installer_output" \
  "snapparazzi --help"

# 2. Branch name with a slash, installed into a directory containing spaces.
spaced_dir="${test_root}/dir with spaces/bin"
run_installer "$good_archive" "feat/recording" "$spaced_dir"
assert_equal "branch refs with a slash install successfully" "0" "$installer_status"
assert_equal \
  "branch refs keep the slash in the archive URL" \
  "https://codeload.github.com/RayChang/snapparazzi/tar.gz/feat/recording" \
  "$(cat "$curl_log")"
assert_equal \
  "install locations with spaces work" \
  "snapparazzi 1.1.0" \
  "$("${spaced_dir}/snapparazzi" --version 2>&1)"

# 3. Unsafe refs are rejected before any download.
run_installer "$good_archive" "../evil" "${test_root}/bin-badref"
assert_equal "invalid refs fail" "1" "$installer_status"
assert_contains "invalid refs are explained" "$installer_output" "invalid SNAPPARAZZI_REF"
assert_equal \
  "invalid refs never reach curl" \
  "no-request" \
  "$([[ -e "$curl_log" ]] && print requested || print no-request)"

# 4. Download failure keeps the existing binary.
old_dir="${test_root}/bin-old"
place_old_binary "$old_dir"
run_installer "$good_archive" "main" "$old_dir" SNAPPARAZZI_TEST_CURL_FAIL=1
assert_equal "download failures fail" "1" "$installer_status"
assert_contains "download failures are explained" "$installer_output" "cannot download"
assert_equal "download failures keep the old binary" "old-snapparazzi" "$("${old_dir}/snapparazzi")"

# 5. An archive that is not Snapparazzi keeps the existing binary.
drop_makefile() { rm Makefile; }
run_installer "$(make_archive no-makefile drop_makefile)" "main" "$old_dir"
assert_equal "archives missing files fail" "1" "$installer_status"
assert_contains "missing files are explained" "$installer_output" "does not look like Snapparazzi"
assert_equal "archives missing files keep the old binary" "old-snapparazzi" "$("${old_dir}/snapparazzi")"

# 5b. An archive without Info.plist is rejected (the binary must embed it).
drop_plist() { rm -r Resources; }
run_installer "$(make_archive no-plist drop_plist)" "main" "$old_dir"
assert_equal "archives without Info.plist fail" "1" "$installer_status"
assert_equal "archives without Info.plist keep the old binary" "old-snapparazzi" "$("${old_dir}/snapparazzi")"

# 6. A compile failure keeps the existing binary.
break_swift() { print 'this is not swift' >> Sources/Snapparazzi/main.swift; }
run_installer "$(make_archive broken break_swift)" "main" "$old_dir"
assert_equal "compile failures fail" "1" "$installer_status"
assert_contains "compile failures are explained" "$installer_output" "build failed"
assert_equal "compile failures keep the old binary" "old-snapparazzi" "$("${old_dir}/snapparazzi")"

# 7. Archives with paths escaping the extraction folder are rejected.
unsafe_stage="${test_root}/stage-unsafe/snapparazzi-unsafe"
mkdir -p "$unsafe_stage"
print 'x' > "${unsafe_stage}/evil"
tar -czf "${test_root}/unsafe.tar.gz" -s ',^snapparazzi-unsafe/evil,snapparazzi-unsafe/../../evil,' \
  -C "${test_root}/stage-unsafe" snapparazzi-unsafe
run_installer "${test_root}/unsafe.tar.gz" "main" "$old_dir"
assert_equal "archives with unsafe paths fail" "1" "$installer_status"
assert_contains "unsafe paths are explained" "$installer_output" "unsafe paths"

# 8. Every run, successful or not, removes its temporary files.
assert_equal \
  "installer leaves no temporary files" \
  "" \
  "$(ls -A "$installer_tmp")"

if (( failures > 0 )); then
  print -u2 "${failures}/${checks} installer tests failed"
  exit 1
fi

print "All ${checks} installer tests passed"
