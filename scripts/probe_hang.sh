#!/usr/bin/env bash
# usage: probe_hang.sh <out_file>  — "살아있지만 멈춘" 프로세스 진단을 판단 순서대로 기록
P=$(pgrep -n agent-leak-app); L="${AGENT_LOG_DIR:-$HOME/agent/logs}/agent_app.log"
[ -n "$P" ] || { echo "### $(date '+%F %T') 대상 프로세스 없음 (pgrep agent-leak-app)" | tee "$1"; exit 1; }
{
  echo "### 0) 시각: $(date '+%F %T')  대상 PID: ${P:-없음}"
  echo; echo "### 1) 살아있는가 — ps -ef | grep"; ps -ef | grep '[a]gent-leak-app-'   # x86/arm64 공통, 관찰자 명령줄 제외
  echo; echo "### 2) 스레드별 상태·대기 지점 — ps -L (STAT, WCHAN)"; ps -L -o pid,lwp,stat,%cpu,%mem,rss,wchan:20,time,comm -p "$P"
  echo; echo "### 3) 스레드별 CPU 변화 — top -H (2초 간격 3회, TIME+ 정체 확인)"; top -H -b -n 3 -d 2 -p "$P" | grep -E '^ *[0-9]+ |^top -'
  echo; echo "### 4) 커널 대기 지점 — /proc/$P/task/*/{wchan,stat}"
  for t in /proc/"$P"/task/*; do printf '%s state=%s wchan=%s utime=%s stime=%s\n' "$(basename "$t")" "$(awk '{print $3}' "$t"/stat)" "$(cat "$t"/wchan)" "$(awk '{print $14}' "$t"/stat)" "$(awk '{print $15}' "$t"/stat)"; done
  echo; echo "### 5) 로그 진행 여부 — 마지막 기록 시각 vs 현재"; echo "now : $(date '+%F %T')"; echo "mtime: $(stat -c '%y' "$L")"; echo "age : $(( $(date +%s) - $(stat -c %Y "$L") ))s"; tail -3 "$L"
} | tee "$1"
