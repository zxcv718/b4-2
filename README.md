# [B4-2] 컴퓨터가 갑자기 느려지거나 멈췄을 때 원인 찾아 고치기

`agent-leak-app`을 리눅스 컨테이너에서 실행하며 발생한 **OOM / CPU Spike / Deadlock** 장애 3건을 관제 데이터와 로그로 분석하고, GitHub Issue 형식의 리포트로 남겼다. 보너스로 스케줄링 알고리즘 추론 리포트 1건을 추가했다.

## 리포트

| # | 리포트 | 장애 유형 | 조정 변수 | Before → After |
|---|---|---|---|---|
| 1 | [issues/01-oom.md](issues/01-oom.md) | OOM Crash (MemoryGuard) | `MEMORY_LIMIT` 256 → 512 | 33s 후 SIGKILL(137) → 153s+ 생존, 한도 도달 시 회수 |
| 2 | [issues/02-cpu-spike.md](issues/02-cpu-spike.md) | CPU Latency (Watchdog) | `CPU_MAX_OCCUPY` 80 → 50 | 30s 후 SIGTERM(143) → 155s+ 생존, 50%에서 cooldown |
| 3 | [issues/03-deadlock.md](issues/03-deadlock.md) | Deadlock (Hang) | `MULTI_THREAD_ENABLE` true → false | 로그 189s 정지·전 스레드 `futex_wait` → 정상 진행 |
| 보너스 | [issues/04-bonus-scheduling.md](issues/04-bonus-scheduling.md) | 스케줄링 추론 | - | Round-Robin, 퀀텀 ≈ 2단계(약 110ms), 4회 재현 |
| 템플릿 | [issues/TEMPLATE.md](issues/TEMPLATE.md) | 이슈 리포트 마크다운 템플릿 | | |

평가 대비 Q&A: [docs/qna.md](docs/qna.md)

## 평가항목 1 체크리스트 매핑

| 평가 항목 | 근거 위치 |
|---|---|
| [OOM] 메모리 선형 증가 후 강제 종료 패턴이 로그에 기록 | [01-oom §2-1 RSS 그래프](issues/01-oom.md#2-1-monitorsh-관제-로그-rss-선형-증가-monitorlog-약-3초-간격), [§2-2 MemoryGuard 로그](issues/01-oom.md#2-2-프로그램-실행-로그-핵심-구간-applog) |
| [OOM] `MEMORY_LIMIT` 조정 후 생존 시간 증가 Before & After | [01-oom §4 표·그래프](issues/01-oom.md#before--after) |
| [CPU] CPU 사용률이 임계치를 넘어 종료되는 패턴이 로그에 기록 | [02-cpu §2-1 관제](issues/02-cpu-spike.md#2-1-monitorsh-관제-로그-monitorlog), [§2-2 Threshold Violated](issues/02-cpu-spike.md#2-2-프로그램-실행-로그-핵심-구간-applog) |
| [CPU] `CPU_MAX_OCCUPY` 조정 후 종료 여부/생존 시간 변화 | [02-cpu §4](issues/02-cpu-spike.md#before--after) |
| [Deadlock] PID 존재 + CPU/메모리 변화 없음 + 로그 정지 식별 | [03-deadlock §2-1 ~ §2-5](issues/03-deadlock.md#2-evidence--logs-증거-자료) |
| [Deadlock] `MULTI_THREAD_ENABLE` 조정 후 재현/회피 비교 | [03-deadlock §4](issues/03-deadlock.md#before--after) |
| [Format] 3건 모두 현상 → 증거 → 원인 → 조치 구조 | 각 리포트의 `## 1.` ~ `## 4.` |
| [Evidence] PID, 로그 타임스탬프, 핵심 로그 메시지 포함 | 각 리포트 상단 표(PID·시각) + §2 발췌 |

## 실행 환경

| 항목 | 값 |
|---|---|
| 호스트 | macOS (Apple Silicon) + OrbStack |
| 실행 환경 | Docker `ubuntu:24.04` **aarch64**, 10 vCPU / 8GB, `--init` |
| 실행 계정 | `agent` (uid 1001, non-root) |
| 바이너리 | `agent-leak-app-arm64` (Linux aarch64 ELF, PyInstaller onefile → 부모/자식 2개 프로세스) |
| 시각 | 모든 로그는 **UTC** 기준이다 (KST = UTC+9) |

## 재현 방법

바이너리(`agent-leak-app-arm64`, Intel은 x86 판)는 미션 첨부 zip에서 받아 저장소 루트에 둔다(`.gitignore` 처리됨). 스크립트는 저장소 루트에서 실행한다.

```bash
docker build -t b4-2 .
docker run -d --init --name b4 -v "$PWD":/work -p 15034:15034 b4-2 sleep infinity

# 케이스 실행: env.txt / app.log / monitor.log / run.txt(종료코드·생존시간) / agent_logs 가 evidence/<CASE>/<TAG>/ 에 저장된다
docker exec b4 bash -c 'CASE=oom      TAG=before MEMORY_LIMIT=256 MON_INTERVAL=2 scripts/run.sh'
docker exec b4 bash -c 'CASE=cpu      TAG=before CPU_MAX_OCCUPY=80 MEMORY_LIMIT=512 MON_INTERVAL=2 scripts/run.sh'
docker exec b4 bash -c 'CASE=deadlock TAG=before MULTI_THREAD_ENABLE=true MEMORY_LIMIT=512 scripts/run.sh'   # Hang: 다른 터미널에서 probe 후 kill

# Hang 진단 (판단 순서대로 ps -ef → ps -L → top -H → /proc/*/task → 로그 mtime)
docker exec b4 scripts/probe_hang.sh evidence/deadlock/before/probe.txt
```

필수 환경변수는 [`scripts/agent.env`](scripts/agent.env)에 있다(`AGENT_HOME`, `AGENT_PORT=15034`, 디렉터리 생성, `secret.key`). 케이스별 값은 실행할 때 덮어쓴다.

## 스크립트

| 파일 | 역할 | 자가 점검 |
|---|---|---|
| [scripts/monitor.sh](scripts/monitor.sh) | 관제: PID / CPU(`top` 1초 구간) / MEM% / RSS / THREADS / STAT / DISK / FIREWALL (+ 앱이 보고한 Load) | `scripts/test_monitor.sh` (컨테이너) |
| [scripts/run.sh](scripts/run.sh) | 케이스 실행 + 관제 + 종료 코드·생존 시간 기록 | `scripts/test_run.sh` (컨테이너) |
| [scripts/probe_hang.sh](scripts/probe_hang.sh) | "살아있지만 멈춘" 프로세스 진단 | - |
| [scripts/cgroup_cpu.sh](scripts/cgroup_cpu.sh) | 컨테이너 전체 CPU 사용률(cgroup v2 `cpu.stat`) | - |
| [scripts/sched_segments.sh](scripts/sched_segments.sh) | 스레드 로그 → 실행 구간 분석 (보너스) | `scripts/test_sched.sh` |
| [scripts/test_evidence.sh](scripts/test_evidence.sh) | 케이스별 필수 증거가 원본 로그에 있는지 점검 | 자체 |

## 분석 중 확인한 사실 (미션 예시와 다른 점)

- **시나리오는 환경변수 조합으로 결정된다**: `MEMORY_LIMIT ≤ 256`이면 Memory Leak, `CPU_MAX_OCCUPY > 50`이면 CPU Spike, `MULTI_THREAD_ENABLE=true`이면 Deadlock, 모두 정상이면 Healthy(RR 스케줄러 + 자가 회복)가 선택된다 ([evidence/recon/notes.md](evidence/recon/notes.md)). 시험한 값은 MEMORY 256/512, CPU 50/80, MT true/false이고, 경계값은 배너의 권고 문구(`Recommend Over 256MB`, `Recommend Under 50%`) 기준 추정이다. OOM·CPU의 After 설정이 Healthy 시나리오를 고르는 것도 이 때문이다.
- 미션 예시의 `SELF-TERMINATED`, `WATCHDOG ... SIGTERM` 배너는 이 빌드에서 출력되지 않는다. 같은 사실을 `[CRITICAL] [MemoryGuard]` / `[CRITICAL] CPU Threshold Violated!` 로그와 종료 코드 137(SIGKILL) / 143(SIGTERM)로 입증했다.
- CpuWorker의 `Current Load`는 앱이 스스로 계산해 보고하는 지표이고, OS가 측정한 실제 CPU 사용률은 0~5%였다(1코어 재검증 포함). 그래서 관제는 두 값을 함께 기록한다 ([02-cpu §2-3](issues/02-cpu-spike.md#2-3-시스템-도구-출력-시스템-전체-부하가-아니다-toptxt-pstxt-cgrouptxt)).
- 파일로 리다이렉트할 때 Python 출력이 버퍼링돼 SIGKILL 직전 로그가 사라질 수 있다. 그래서 `PYTHONUNBUFFERED=1`을 설정했다.
