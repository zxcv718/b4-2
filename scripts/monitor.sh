#!/usr/bin/env bash
# usage: monitor.sh <name-pattern> [interval_sec] [logfile] [app_log]
#   app_log: 주어지면 앱이 스스로 보고한 마지막 "Current Load"를 APP_LOAD로 함께 기록 (OS 측정값과 비교용)
set -u
PAT="${1:-agent-leak-app}"; INTERVAL="${2:-5}"; LOG="${3:-monitor.log}"; APP_LOG="${4:-}"
while :; do
  ts=$(date '+%Y-%m-%d %H:%M:%S')
  pid=$(pgrep -n "$PAT")   # comm 기준(-f 아님: 자기 자신 매칭 방지), -n: 가장 최근 = PyInstaller 자식
  disk=$(df -h / | awk 'NR==2{print $4}')
  fw=$(ufw status 2>/dev/null | awk 'NR==1{print $2}'); fw=${fw:-n/a}
  if [ -n "$pid" ]; then
    # ps %cpu는 생애 평균이라 스파이크가 묻힘 → top 2회 샘플 중 두 번째(1초 구간) 사용
    cpu=$(top -b -n 2 -d 1 -p "$pid" | awk -v p="$pid" '$1==p{c=$9} END{print c+0}')
    read -r mem rss nlwp stat < <(ps -o %mem=,rss=,nlwp=,stat= -p "$pid")
  fi
  if [ -n "$pid" ] && [ -n "${rss:-}" ]; then
    line="PID:$pid CPU:${cpu}% MEM:${mem}% RSS:$((rss/1024))MB THREADS:$nlwp STAT:$stat"
  else   # 없음, 또는 pgrep 직후 종료돼 ps가 빈 값을 준 경우
    line="PID:- STATUS:NOT_RUNNING"
  fi
  rss=""
  if [ -n "$APP_LOG" ]; then
    load=$(grep -o 'Current Load: [0-9.]*%' "$APP_LOG" 2>/dev/null | tail -1 | cut -d' ' -f3)
    line="$line APP_LOAD:${load:--}"
  fi
  echo "[$ts] PROCESS:$PAT $line DISK:$disk FIREWALL:$fw" | tee -a "$LOG"
  sleep "$INTERVAL"
done
