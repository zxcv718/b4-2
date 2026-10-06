#!/usr/bin/env bash
# usage: CASE=oom TAG=before MEMORY_LIMIT=128 scripts/run.sh
set -u
: "${CASE:?CASE 필요}" "${TAG:?TAG 필요}"
source "$(dirname "$0")/agent.env"
out="evidence/$CASE/$TAG"; mkdir -p "$out"; rm -rf "$out/monitor.log" "$out/agent_logs"
rm -f "$AGENT_LOG_DIR"/*   # 앱 로그 파일을 실행 단위로 분리
env | grep -E '^(AGENT_|MEMORY_LIMIT|CPU_MAX_OCCUPY|MULTI_THREAD_ENABLE)=' | sort > "$out/env.txt"
scripts/monitor.sh agent-leak-app "${MON_INTERVAL:-5}" "$out/monitor.log" > /dev/null & mon=$!
trap 'kill $mon 2>/dev/null' EXIT
start=$(date +%s); echo "START $(date '+%F %T')" | tee "$out/run.txt"
./agent-leak-app-arm64 2>&1 | tee "$out/app.log"
rc=${PIPESTATUS[0]}; end=$(date +%s)
echo "END $(date '+%F %T') EXIT:$rc SURVIVED:$((end-start))s" | tee -a "$out/run.txt"
cp -r "$AGENT_LOG_DIR" "$out/agent_logs"
sleep "${MON_INTERVAL:-5}"   # 종료 후 NOT_RUNNING 한 줄을 관제 로그에 남긴다
