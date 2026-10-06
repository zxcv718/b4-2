#!/usr/bin/env bash
# usage: cgroup_cpu.sh <seconds> [interval]  — 컨테이너(cgroup v2) 전체 CPU 사용률을 interval마다 출력 (1코어=100%)
n=$(( $1 / ${2:-3} )); prev=$(awk '/usage_usec/{print $2}' /sys/fs/cgroup/cpu.stat)
for _ in $(seq "$n"); do
  sleep "${2:-3}"; u=$(awk '/usage_usec/{print $2}' /sys/fs/cgroup/cpu.stat)
  echo "[$(date '+%F %T')] CGROUP_CPU:$(( (u - prev) / (${2:-3} * 10000) ))%"; prev=$u
done
