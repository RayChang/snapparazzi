#!/bin/zsh
# Long `record --audio both` run on this Mac (opt-in: make recording-long-run,
# DURATION=seconds, default 3600). Records the fixture app's flash+beep markers and
# checks: exit 0, length, A/V offset in the first and last minute (drift), memory
# that levels off instead of growing with time, frame drops, finishing time and the
# peak disk use of stage + final files. The recording is deleted afterwards.

set -u

script_dir="${0:A:h}"
project_dir="${script_dir:h}"
binary="${project_dir}/.build/snapparazzi"
inspect="${project_dir}/.build/recording-inspect"
fixture="${project_dir}/.build/RecordingFixture.app"
duration="${DURATION:-3600}"
work="$(mktemp -d "${TMPDIR:-/tmp}/snapparazzi-long.XXXXXX")"
output="$work/long.mp4"
samples="$work/samples.txt"
failures=0
checks=0

cleanup() {
  pkill -f "RecordingFixture.app/Contents/MacOS/RecordingFixture" 2>/dev/null
  rm -rf "$work"
}
trap cleanup EXIT

check() {
  checks=$((checks + 1))
  if [[ "$2" == "1" ]]; then print "PASS: $1"; else print -u2 "FAIL: $1"; failures=$((failures + 1)); fi
}

: > "$work/fixture.log"
open -n --stdout "$work/fixture.log" --stderr "$work/fixture.log" "$fixture" \
  --args --markers --tone 440 --quit-after $((duration + 900))
window_id=""
for _ in {1..40}; do
  window_id="$(awk '/WINDOW_ID/ {print $2}' "$work/fixture.log")"
  [[ -n "$window_id" ]] && break
  perl -e 'select(undef, undef, undef, 0.25)'
done
[[ -n "$window_id" ]] || { print -u2 "fixture window did not appear"; exit 1; }

print "Recording ${duration} s of --audio both (window ${window_id}); sampling every 30 s…"
"$binary" record -w "$window_id" --audio both --duration "$duration" -o "$output" > "$work/record.out" 2>&1 &
record_pid=$!
started=$(date +%s)
# elapsed_s cpu_percent rss_kib disk_kib (stage folder + final file)
while kill -0 "$record_pid" 2>/dev/null; do
  stats="$(ps -o %cpu=,rss= -p "$record_pid" 2>/dev/null)"
  disk="$(du -sk "$work" 2>/dev/null | awk '{print $1}')"
  [[ -n "$stats" ]] && print "$(( $(date +%s) - started )) ${stats} ${disk:-0}" >> "$samples"
  for _ in {1..30}; do
    kill -0 "$record_pid" 2>/dev/null || break
    perl -e 'select(undef, undef, undef, 1)'
  done
done
wait "$record_pid"
exit_code=$?
total=$(( $(date +%s) - started ))
cat "$work/record.out"

check "exit 0" "$(( exit_code == 0 ))"
"$inspect" "$output" --sync 0 60 > "$work/start.json" 2>/dev/null
"$inspect" "$output" --sync $((duration - 60)) 60 > "$work/end.json" 2>/dev/null
python3 -I - "$work/start.json" "$work/end.json" "$samples" "$duration" "$total" > "$work/report.txt" <<'PYEOF'
import json, sys
start, end = (json.load(open(path)) for path in sys.argv[1:3])
rows = [list(map(float, line.split())) for line in open(sys.argv[3]) if len(line.split()) == 4]
duration, total = float(sys.argv[4]), float(sys.argv[5])
offsets = lambda r: [p["offset"] for p in r["sync"]["pairs"]]
s, e = offsets(start), offsets(end)
recording = [r for r in rows if r[0] <= duration]
cpu = sum(r[1] for r in recording) / max(len(recording), 1)
baseline_at = min(300, duration / 3)  # 5 min in, or a third of a short run
rss_early = next((r[2] for r in recording if r[0] >= baseline_at), recording[-1][2] if recording else 0)
rss_late = recording[-1][2] if recording else 0
rss_max = max((r[2] for r in rows), default=0)
disk_max = max((r[3] for r in rows), default=0)
print(f"duration {start['duration']:.3f}")
print(f"frames {start['video'][0]['samples']}")
print(f"start_offsets_ms {[round(x*1000,1) for x in s]}")
print(f"end_offsets_ms {[round(x*1000,1) for x in e]}")
print(f"max_abs_offset_ms {max(map(abs, s + e), default=999)*1000:.1f}")
print(f"drift_ms {(sum(e)/max(len(e),1) - sum(s)/max(len(s),1))*1000:.1f}")
print(f"cpu_avg_percent {cpu:.1f}")
print(f"rss_mib_at_baseline {rss_early/1024:.1f} rss_mib_at_end {rss_late/1024:.1f} rss_mib_max {rss_max/1024:.1f}")
print(f"disk_peak_mib {disk_max/1024:.1f}")
print(f"wall_seconds {total:.0f} (finishing ≈ {total - duration:.0f} s)")
PYEOF
cat "$work/report.txt"
value() { awk -v key="$1" '$1 == key {print $2}' "$work/report.txt"; }
check "length is ${duration} s" "$(python3 -I -c "print(int(abs(float('$(value duration)') - $duration) < 0.05))")"
check "at least 99% of $((duration * 30)) frames" "$(python3 -I -c "print(int(int('$(value frames)') >= 0.99 * $duration * 30))")"
check "A/V offset under 100 ms in the first and last minute" "$(python3 -I -c "print(int(float('$(value max_abs_offset_ms)') < 100))")"
check "memory levels off (end RSS ≤ 1.5 × RSS at 5 min + 50 MiB)" \
  "$(awk '$1 == "rss_mib_at_baseline" {print ($4 <= $2 * 1.5 + 50) ? 1 : 0}' "$work/report.txt")"

if (( failures > 0 )); then
  print -u2 "${failures}/${checks} long-run checks failed"
  exit 1
fi
print "All ${checks} long-run checks passed"
