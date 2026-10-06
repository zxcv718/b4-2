# CPU 증거 수집 명령 기록

`top.txt`, `ps.txt`, `cgroup.txt`는 `run.sh` 실행 중 다른 `docker exec`로 수집했다. 아래는 그때 쓴 명령이다(컨테이너 안, 저장소 루트).

```bash
# cgroup.txt — 컨테이너 전체 CPU (run.sh와 동시에 시작)
scripts/cgroup_cpu.sh 39 3 > evidence/cpu/before/cgroup.txt        # after: 150 3

# top.txt / ps.txt — 실행 약 27초(before) / 45초(after) 시점
P=$(pgrep -n agent-leak-app)
{ top -b -n 2 -d 1 -o %CPU | awk "/^top -/{n++} n==2" | head -12
  echo; echo "### top -H -p $P (스레드별)"
  top -H -b -n 2 -d 1 -p $P | awk "/^top -/{n++} n==2" | tail -3; } > evidence/cpu/before/top.txt
ps -eo pid,ppid,stat,ni,%cpu,%mem,etime,time,comm --sort=-%cpu | head -6 > evidence/cpu/before/ps.txt
```

## probe-1core (1코어 재검증)

```bash
docker run -d --init --name b4 --cpuset-cpus 0 -v "$PWD":/work -p 15034:15034 b4-2 sleep infinity
docker exec b4 bash -c 'nproc; grep -c ^processor /proc/cpuinfo'
# 출력: 1 / 10   (스케줄 가능한 CPU는 1개, cpuinfo에 보이는 코어는 10개)
docker exec b4 bash -c 'CASE=probe TAG=cpu1 CPU_MAX_OCCUPY=80 MEMORY_LIMIT=512 MULTI_THREAD_ENABLE=false MON_INTERVAL=2 scripts/run.sh'
```
`nproc` 출력은 파일로 저장하지 않았고 세션 터미널에서 확인한 값이다. 결과 디렉터리를 `probe/cpu1`에서 `cpu/probe-1core`로 옮겼다. 검증 후 컨테이너는 다시 10코어로 만들었다.
