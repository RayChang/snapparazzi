#!/bin/zsh
# Microphone checks on real hardware (opt-in: make recording-microphone). Both
# temporarily change the default input and restore it on exit.
# 1. Sync of the microphone track: the fixture beeps through the MacBook speakers
#    (only its own output is redirected) while the MacBook microphone records; the
#    beeps must line up with the white flashes within 100 ms. You will hear ~10 beeps.
#    Skipped (not passed) when the MacBook speakers are below 20% volume.
# 2. Changing the default input mid-recording: the recording must stay on the microphone
#    it started with. It starts on a temporary aggregate device; after 4 s the default
#    switches to another input and the recording must carry on; after 8 s the starting
#    device is destroyed, which must stop the recording (if it had followed the new
#    default it would run to the end).
# 3. A microphone that disappears: the current default input is wrapped in a temporary
#    aggregate device that is destroyed 4 s into a recording, which must stop with an
#    error and keep what it recorded instead of continuing with a silent track.

set -u

script_dir="${0:A:h}"
project_dir="${script_dir:h}"
binary="${project_dir}/.build/snapparazzi"
inspect="${project_dir}/.build/recording-inspect"
fixture="${project_dir}/.build/RecordingFixture.app"
device_tool="${project_dir}/.build/recording-audio-device"
work="$(mktemp -d "${TMPDIR:-/tmp}/snapparazzi-mic.XXXXXX")"
failures=0
checks=0

original="$("$device_tool" default-input)" || exit 1
test_uid=""

cleanup() {
  pkill -f "RecordingFixture.app/Contents/MacOS/RecordingFixture" 2>/dev/null
  [[ -n "$test_uid" ]] && "$device_tool" destroy "$test_uid" 2>/dev/null
  "$device_tool" set-default-input "$original" 2>/dev/null
  print "default input restored: $("$device_tool" default-input)"
  rm -rf "$work"
}
trap cleanup EXIT

check() {
  checks=$((checks + 1))
  if [[ "$2" == "1" ]]; then print "PASS: $1"; else print -u2 "FAIL: $1"; failures=$((failures + 1)); fi
}

start_fixture() {
  pkill -f "RecordingFixture.app/Contents/MacOS/RecordingFixture" 2>/dev/null
  perl -e 'select(undef, undef, undef, 0.3)'
  : > "$work/fixture.log"
  open -n --stdout "$work/fixture.log" --stderr "$work/fixture.log" "$fixture" --args "$@"
  window_id=""
  for _ in {1..40}; do
    window_id="$(awk '/WINDOW_ID/ {print $2}' "$work/fixture.log")"
    [[ -n "$window_id" ]] && break
    perl -e 'select(undef, undef, undef, 0.25)'
  done
  [[ -n "$window_id" ]] || { print -u2 "fixture window did not appear"; exit 1; }
}

# 1. Microphone-track sync through the air.
skipped=0
volume="$("$device_tool" output-volume BuiltInSpeakerDevice 2>/dev/null || print 0)"
if ! "$device_tool" list | grep -q $'\tBuiltInSpeakerDevice\t' || ! "$device_tool" list | grep -q $'\tBuiltInMicrophoneDevice\t'; then
  print "SKIP: microphone-track sync (MacBook speakers or microphone not available)"
  skipped=1
elif (( $(python3 -I -c "print(int(float('${volume:-0}') < 0.2))") )); then
  print "SKIP: microphone-track sync (MacBook speakers at ${volume}; needs at least 0.2 to be heard)"
  skipped=1
else
  "$device_tool" set-default-input BuiltInMicrophoneDevice || exit 1
  start_fixture --markers --output-device BuiltInSpeakerDevice --quit-after 60
  "$binary" record -w "$window_id" --audio mic --duration 20 -o "$work/sync.mp4" > "$work/sync.out" 2>&1
  check "microphone sync recording: exit 0" "$(( $? == 0 ))"
  "$inspect" "$work/sync.mp4" --sync > "$work/sync.json" 2>/dev/null
  print "  microphone-track offsets: $(python3 -I -c "import json; print([round(p['offset']*1000,1) for p in json.load(open('$work/sync.json'))['sync']['pairs']])") ms"
  check "microphone track: at least 8 of 10 beeps heard and matched" \
    "$(python3 -I -c "import json; print(int(len(json.load(open('$work/sync.json'))['sync']['pairs']) >= 8))")"
  check "microphone track: beeps within 100 ms of the flashes" \
    "$(python3 -I -c "import json; s=json.load(open('$work/sync.json'))['sync']; print(int(s['max_abs_offset'] is not None and s['max_abs_offset'] < 0.1))")"
  "$device_tool" set-default-input "$original"
fi

# 2. The default input changes mid-recording; the recording stays on its microphone.
test_uid="$("$device_tool" create-aggregate "$original")" || exit 1
"$device_tool" set-default-input "$test_uid" || exit 1
perl -e 'select(undef, undef, undef, 1)'
start_fixture --markers --quit-after 60
"$binary" record -w "$window_id" --audio mic --duration 20 -o "$work/switch.mp4" > "$work/switch.out" 2>&1 &
record_pid=$!
perl -e 'select(undef, undef, undef, 4)'
"$device_tool" set-default-input "$original"
print "  default input switched from the test device to: $("$device_tool" default-input)"
perl -e 'select(undef, undef, undef, 4)'
check "default input switch: still recording 4 s after the default changed" "$(kill -0 "$record_pid" 2>/dev/null && print 1 || print 0)"
"$device_tool" destroy "$test_uid" && test_uid=""
wait "$record_pid"
exit_code=$?
cat "$work/switch.out" | grep -E 'microphone:|停止原因'
check "default input switch: removing the starting device stops the recording (it never followed the new default)" \
  "$(( exit_code == 1 ))"
check "default input switch: the stop names the microphone" "$(grep -q 'microphone was disconnected' "$work/switch.out" && print 1 || print 0)"
"$inspect" "$work/switch.mp4" > "$work/switch.json" 2>/dev/null
check "default input switch: the microphone track ran through the switch (about 8 s, no gap)" \
  "$(python3 -I -c "
import json, re
r = json.load(open('$work/switch.json'))
line = [l for l in open('$work/switch.out') if 'microphone: buffers' in l][0]
padded = float(re.search(r'padded ([0-9.]+) s', line).group(1))
print(int(7 < r['duration'] < 10.5 and len(r['audio']) == 1 and padded < 1.5))")"
perl -e 'select(undef, undef, undef, 1)'

# 3. The microphone disappears mid-recording.
test_uid="$("$device_tool" create-aggregate "$original")" || exit 1
"$device_tool" set-default-input "$test_uid" || exit 1
perl -e 'select(undef, undef, undef, 1)'
check "test microphone is the default input" "$([[ "$("$device_tool" default-input)" == "$test_uid" ]] && print 1 || print 0)"
start_fixture --markers --quit-after 90

"$binary" record -w "$window_id" --audio mic --duration 30 -o "$work/removed.mp4" > "$work/record.out" 2>&1 &
record_pid=$!
perl -e 'select(undef, undef, undef, 4)'
"$device_tool" destroy "$test_uid" && test_uid=""
started=$(date +%s)
wait "$record_pid"
exit_code=$?
stopped_after=$(( $(date +%s) - started ))
cat "$work/record.out"

check "recording stops with exit 1 when the microphone disappears" "$(( exit_code == 1 ))"
check "it stops within 3 s of the removal (${stopped_after} s)" "$(( stopped_after <= 3 ))"
check "the error names the microphone or the capture stream" \
  "$(grep -qE 'microphone was disconnected|ScreenCaptureKit' "$work/record.out" && print 1 || print 0)"
"$inspect" "$work/removed.mp4" > "$work/removed.json" 2>/dev/null
check "what was recorded before the removal is kept (about 4 s)" \
  "$(python3 -I -c "import json; r=json.load(open('$work/removed.json')); print(int(2 < r['duration'] < 8 and len(r['audio']) == 1))" 2>/dev/null || print 0)"

if (( failures > 0 )); then
  print -u2 "${failures}/${checks} microphone checks failed"
  exit 1
fi
(( skipped )) && print "All ${checks} microphone checks passed (the sync check was skipped)" || print "All ${checks} microphone checks passed"
