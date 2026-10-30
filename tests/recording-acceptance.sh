#!/bin/zsh
# Real recordings on this Mac (opt-in: make recording-acceptance). Needs Screen
# Recording and Microphone permission for the terminal and a logged-in GUI session.
# A scripted fixture window (tests/RecordingFixtureApp) provides tones, flash+beep
# sync markers and minimize/resize/close actions; recording-inspect checks results.
# Recordings stay in a temporary folder that is removed at the end.

set -u

script_dir="${0:A:h}"
project_dir="${script_dir:h}"
binary="${project_dir}/.build/snapparazzi"
inspect="${project_dir}/.build/recording-inspect"
fixture="${project_dir}/.build/RecordingFixture.app"
work="$(mktemp -d "${TMPDIR:-/tmp}/snapparazzi-acceptance.XXXXXX")"
failures=0
checks=0
window_id=""

cleanup() {
  stop_fixture
  pkill -f "$work/tone.wav" 2>/dev/null
  [[ -d "$work/small-volume" ]] && hdiutil detach "$work/small-volume" -force >/dev/null 2>&1
  rm -rf "$work"
}
trap cleanup EXIT

check() {
  local description="$1"
  local condition="$2"
  checks=$((checks + 1))
  if [[ "$condition" == "1" ]]; then
    print "PASS: ${description}"
  else
    print -u2 "FAIL: ${description}"
    failures=$((failures + 1))
  fi
}

# json FILE EXPR — evaluates a Python expression with r = the inspect report.
json() {
  python3 -I -c "import json,sys; r=json.load(open(sys.argv[1])); print($2)" "$1"
}

start_fixture() {
  stop_fixture
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

stop_fixture() {
  pkill -f "RecordingFixture.app/Contents/MacOS/RecordingFixture" 2>/dev/null
  perl -e 'select(undef, undef, undef, 0.3)'
}

# record NAME ARGS... — records into $work/NAME.mp4; sets rec_status, rec_output.
record() {
  local name="$1"
  shift
  "$binary" record -w "$window_id" -o "$work/${name}.mp4" "$@" > "$work/${name}.out" 2>&1
  rec_status=$?
  rec_output="$(cat "$work/${name}.out")"
}

inspect_file() {
  "$inspect" "$work/$1.mp4" ${2:-} > "$work/$1.json" 2>/dev/null
}

for tool in "$binary" "$inspect" "$fixture"; do
  [[ -e "$tool" ]] || { print -u2 "missing ${tool}; run make recording-acceptance"; exit 1; }
done
print "sw_vers: $(sw_vers -productVersion) $(uname -m); $("$binary" --version)"

# 1. Audio modes and codecs, with sync markers.
start_fixture --tone 440 --markers --quit-after 300
for mode in none system mic both; do
  for codec in h264 hevc; do
    [[ "$mode" != "both" && "$codec" == "hevc" && "$mode" != "none" ]] && continue
    name="mode-${mode}-${codec}"
    record "$name" --audio "$mode" --codec "$codec" --duration 6
    check "${name}: exit 0" "$(( rec_status == 0 ))"
    inspect_file "$name" --sync
    expected_audio=$([[ "$mode" == "none" ]] && print 0 || print 1)
    expected_codec=$([[ "$codec" == "hevc" ]] && print hvc1 || print avc1)
    check "${name}: 1 video, ${expected_audio} audio track" \
      "$(json "$work/$name.json" "int(len(r['video'])==1 and len(r['audio'])==$expected_audio)")"
    check "${name}: codec ${expected_codec}" "$(json "$work/$name.json" "int(r['video'][0]['codec']=='$expected_codec')")"
    check "${name}: duration 6 s" "$(json "$work/$name.json" "int(abs(r['duration']-6)<0.03)")"
    check "${name}: 180 frames" "$(json "$work/$name.json" "int(abs(r['video'][0]['samples']-180)<=3)")"
    if [[ "$mode" == "system" || "$mode" == "both" ]]; then
      check "${name}: sync markers within 100 ms" \
        "$(json "$work/$name.json" "int(r['sync']['max_abs_offset'] is not None and r['sync']['max_abs_offset']<0.1 and len(r['sync']['pairs'])>=2)")"
      print "  ${name} offsets: $(json "$work/$name.json" "[round(p['offset']*1000,1) for p in r['sync']['pairs']]") ms"
    fi
    if [[ "$mode" != "none" ]]; then
      check "${name}: audio track is 48 kHz stereo AAC" \
        "$(json "$work/$name.json" "int(r['audio'][0]['codec']=='aac ' and r['audio'][0]['sample_rate']==48000 and r['audio'][0]['channels']==2)")"
      check "${name}: audio lasts the whole recording" "$(json "$work/$name.json" "int(abs(r['audio'][0]['decoded_seconds']-6)<0.03)")"
    fi
  done
done

# 2. system captures the target app only: another process plays 880 Hz meanwhile.
python3 -I - "$work/tone.wav" <<'EOF'
import math, struct, sys, wave
w = wave.open(sys.argv[1], "wb"); w.setnchannels(1); w.setsampwidth(2); w.setframerate(48000)
w.writeframes(b"".join(struct.pack("<h", int(12000 * math.sin(2 * math.pi * 880 * i / 48000))) for i in range(48000 * 20)))
EOF
start_fixture --tone 440 --quit-after 60
afplay "$work/tone.wav" &
afplay_pid=$!
perl -e 'select(undef, undef, undef, 0.5)'
record scope --audio system --duration 5
kill "$afplay_pid" 2>/dev/null
check "scope: exit 0" "$(( rec_status == 0 ))"
levels="$("$inspect" --levels "$work/scope.mp4" 440 880 2>/dev/null)"
level440="${levels%% *}"
level880="${levels##* }"
print "  scope levels: 440 Hz ${level440}, 880 Hz ${level880} (other process)"
check "scope: target app tone recorded" "$(python3 -I -c "print(int(float('${level440:-0}')>0.03))")"
check "scope: other process not recorded" "$(python3 -I -c "print(int(float('${level880:-1}')<0.01))")"

# 3. Minimize after 2 s, restore at 5 s: held frame, then black, then live again.
start_fixture --script minimize@2,restore@5 --quit-after 60
record minimize --duration 8
check "minimize: exit 0" "$(( rec_status == 0 ))"
inspect_file minimize
check "minimize: constant frame rate through the gap" "$(json "$work/minimize.json" "int(abs(r['video'][0]['samples']-240)<=3)")"
check "minimize: black frames were written" "$(print -r -- "$rec_output" | grep -Eq '黑畫面 / black [1-9]' && print 1 || print 0)"
colors="$("$inspect" --luma "$work/minimize.mp4" 1.0 4.0 7.0 2>/dev/null)"
print "  minimize mean luma at 1 s, 4 s, 7 s: ${colors}"
check "minimize: black while minimized, live before and after" \
  "$(python3 -I -c "a,b,c=[float(x) for x in '${colors:-0 99 0}'.split()]; print(int(b<1 and a>b+4 and c>b+4))")"

# 4. Resize during recording keeps the track size.
start_fixture --script resize@2:300x700,resize@4:900x250 --quit-after 60
record resize --duration 6
check "resize: exit 0" "$(( rec_status == 0 ))"
inspect_file resize
check "resize: 180 frames, fixed size" "$(json "$work/resize.json" "int(abs(r['video'][0]['samples']-180)<=3)")"

# 5. The window disappearing (here: its app quits) stops the recording, keeps it, exits 1.
#    (A window an app merely hides on close stays alive and records black, like minimize;
#    Finder's ⌘W destroying a window gave the same -3815 error in the Task 0 probe.)
start_fixture --script quit@3 --quit-after 60
record quit --duration 20
check "app quit: exit 1" "$(( rec_status == 1 ))"
check "app quit: reports the closed window" "$(print -r -- "$rec_output" | grep -q 'window closed' && print 1 || print 0)"
inspect_file quit
check "app quit: kept recording is playable and about 2 s" "$(json "$work/quit.json" "int(1<r['duration']<3.5)")"

# 6. SIGINT and SIGTERM stop cleanly with exit 0.
for signal_name in INT TERM; do
  start_fixture --markers --quit-after 60
  "$binary" record -w "$window_id" -o "$work/signal-$signal_name.mp4" > "$work/signal-$signal_name.out" 2>&1 &
  record_pid=$!
  perl -e 'select(undef, undef, undef, 4)'
  kill -"$signal_name" "$record_pid"
  wait "$record_pid"
  exit_code=$?
  check "SIG${signal_name}: exit 0" "$(( exit_code == 0 ))"
  inspect_file "signal-$signal_name"
  check "SIG${signal_name}: file about 3–4 s" "$(json "$work/signal-$signal_name.json" "int(2.5<r['duration']<4.5)")"
done

# 7. A second SIGINT while both is mixing cancels, exits 1 and keeps the MOV.
start_fixture --tone 440 --quit-after 120
"$binary" record -w "$window_id" --audio both -o "$work/cancel.mp4" > "$work/cancel.out" 2>&1 &
record_pid=$!
perl -e 'select(undef, undef, undef, 40)'
kill -INT "$record_pid"
for _ in {1..400}; do
  grep -q '正在混音' "$work/cancel.out" && break
  perl -e 'select(undef, undef, undef, 0.01)'
done
kill -INT "$record_pid" 2>/dev/null
wait "$record_pid"
exit_code=$?
check "second SIGINT during mixing: exit 1" "$(( exit_code == 1 ))"
check "second SIGINT during mixing: final MP4 not created" "$([[ ! -e "$work/cancel.mp4" ]] && print 1 || print 0)"
check "second SIGINT during mixing: two-track MOV kept" "$(grep -q 'two separate audio tracks' "$work/cancel.out" && [[ -n "$(print -l "$work"/.cancel.mp4.snapparazzi-*/capture.mov(N))" ]] && print 1 || print 0)"

# 8. Errors before recording leave no files behind.
print "existing" > "$work/exists.mp4"
start_fixture --quit-after 30
record exists --duration 2
check "existing output: exit 1" "$(( rec_status == 1 ))"
check "existing output: file untouched" "$([[ "$(cat "$work/exists.mp4")" == "existing" ]] && print 1 || print 0)"
"$binary" record -w 4294967 --duration 2 -o "$work/nowindow.mp4" > "$work/nowindow.out" 2>&1
exit_code=$?
check "unknown window: exit 1" "$(( exit_code == 1 ))"
check "no stage folders left except the cancelled one" \
  "$(( $(print -l "$work"/.*.snapparazzi-*(N) | grep -vc cancel) == 0 ))"

# 8b. No complete frame within 5 s: stop with exit 1 and leave nothing behind.
#     (SNAPPARAZZI_TEST_IGNORE_VIDEO makes record drop every screen sample.)
start_fixture --markers --quit-after 60
started=$(date +%s)
SNAPPARAZZI_TEST_IGNORE_VIDEO=1 "$binary" record -w "$window_id" --audio system --duration 20 -o "$work/noframe.mp4" > "$work/noframe.out" 2>&1
exit_code=$?
elapsed=$(( $(date +%s) - started ))
check "no video frame: exit 1" "$(( exit_code == 1 ))"
check "no video frame: gives up after about 5 s (${elapsed} s)" "$(( elapsed >= 5 && elapsed <= 9 ))"
check "no video frame: explains the timeout" "$(grep -q 'No video frame within 5 seconds' "$work/noframe.out" && print 1 || print 0)"
check "no video frame: no output or stage folder left" \
  "$([[ ! -e "$work/noframe.mp4" && -z "$(print -l "$work"/.noframe.mp4.snapparazzi-*(N))" ]] && print 1 || print 0)"

# 9. Disk space, on a small disk image: refuse up front, and stop at the 512 MiB low-water mark.
dmg="$work/small.dmg"
volume="$work/small-volume"
mkdir -p "$volume"
if hdiutil create -size 700m -fs APFS -volname SnapparazziTest "$dmg" >/dev/null 2>&1 \
   && hdiutil attach "$dmg" -mountpoint "$volume" -nobrowse >/dev/null 2>&1; then
  start_fixture --markers --quit-after 120
  "$binary" record -w "$window_id" -o "$volume/no-duration.mp4" > "$work/disk-preflight.out" 2>&1
  exit_code=$?
  check "disk preflight: exit 1 without --duration on a small volume" "$(( exit_code == 1 ))"
  check "disk preflight: explains the space needed" "$(grep -q 'Not enough disk space' "$work/disk-preflight.out" && print 1 || print 0)"
  check "disk preflight: sees the volume's real free space (not 0)" "$(grep -q ' 0 MiB available' "$work/disk-preflight.out" && print 0 || print 1)"
  check "disk preflight: creates nothing" "$([[ -z "$(print -l "$volume"/*.mp4(N) "$volume"/.*.snapparazzi-*(N))" ]] && print 1 || print 0)"
  "$binary" record -w "$window_id" --duration 30 -o "$volume/low.mp4" > "$work/disk-low.out" 2>&1 &
  record_pid=$!
  perl -e 'select(undef, undef, undef, 3)'
  mkfile 200m "$volume/filler" 2>/dev/null
  wait "$record_pid"
  exit_code=$?
  check "low disk during recording: exit 1" "$(( exit_code == 1 ))"
  check "low disk during recording: reports low disk space" "$(grep -q 'low disk space' "$work/disk-low.out" && print 1 || print 0)"
  "$inspect" "$volume/low.mp4" > "$work/low.json" 2>/dev/null
  check "low disk during recording: kept file stops well before 30 s" "$(json "$work/low.json" "int(2<r['duration']<15)")"
  hdiutil detach "$volume" -force >/dev/null 2>&1
else
  check "disk image for the low-space test could be created" 0
fi

stop_fixture

if (( failures > 0 )); then
  print -u2 "${failures}/${checks} acceptance checks failed"
  exit 1
fi
print "All ${checks} acceptance checks passed"
