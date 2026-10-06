#!/usr/bin/env bash
# usage: sched_segments.sh <app.log>
# [Thread-X] 로그를 연속 실행 구간(segment)으로 묶어 순서·구간 길이·진행률을 출력한다 (POSIX awk)
awk '
function ms(t,  a) { split(t, a, /[:,]/); return ((a[1]*60 + a[2])*60 + a[3])*1000 + a[4] }
function pct(s,  p) { return match(s, /\([0-9]+%\)/) ? substr(s, RSTART+1, RLENGTH-2) : "?" }
function flush() {
  if (cur == "") return
  n++; starts[n] = s0
  printf "#%d %s start=%s span=%dms lines=%d progress=%s→%s last=\"%s\"\n", n, cur, st, e0 - s0, cnt, p0, p1, lastmsg
}
$4 ~ /^\[Thread-/ {
  th = substr($4, 2, length($4) - 2); t = ms($2)
  msg = $0; sub(/^.*\] \[Thread-[^]]*\] /, "", msg)
  if (th != cur) { flush(); cur = th; st = $2; s0 = t; cnt = 0; p0 = pct(msg) }
  e0 = t; cnt++; p1 = pct(msg); lastmsg = msg
}
END {
  flush()
  for (i = 2; i <= n; i++) sum += starts[i] - starts[i-1]
  printf "segments=%d switches=%d avg_slice=%.1fms (구간 시작 간격 평균)\n", n, n - 1, (n > 1 ? sum / (n - 1) : 0)
}' "$1"
