# 정찰(Recon) 결과 — 2026-10-06 UTC (컨테이너 시각, 호스트 KST = UTC+9)

환경: OrbStack, ubuntu:24.04 aarch64, 10 vCPU, 8GB, 실행 계정 agent(uid=1001)

## 부트 시퀀스 (6단계, 모두 OK)
계정(non-root) → 환경변수 → secret.key → 포트 15034 → 로그 디렉터리 쓰기 → Mission Environment.
부트 직후 `[SafetyGuard] Process priority lowered (nice=10)` — ps STAT에 `N` 표시.

## 프로세스 구조
PyInstaller onefile: 부모(부트로더, RSS ~1.7MB) → 자식(실제 Python, RSS 140MB+). 관제 대상은 자식(`pgrep -n`).

## 시나리오는 환경변수 조합으로 결정된다
| 파일 | MEMORY_LIMIT | CPU_MAX_OCCUPY | MULTI_THREAD | 시나리오 | 결과 |
|---|---|---|---|---|---|
| app-1-default | 256 | 80 | false | Memory Leak | 33s, MemoryGuard 자가 종료 |
| app-2-mem512 | 512 | 80 | false | CPU Spike | 33s, CPU Threshold Violated, EXIT 143 |
| app-3-mem512-cpu50 | 512 | 50 | false | Healthy (RR 스케줄러 + 자가 회복) | 생존 (수동 종료) |
| app-4-oom | 256 | 50 | false | Memory Leak | EXIT 137(SIGKILL), 33s |
| app-5-cpu | 512 | 80 | false | CPU Spike | EXIT 143(SIGTERM), 30s, 56.8%에서 위반 |
| app-6-deadlock | 512 | 50 | true | Deadlock | 2초 만에 BLOCKED, PID 유지, 3스레드 futex_wait |

- 배너 경고가 판단 기준을 드러낸다: `MEMORY Recommend Over 256MB`, `CPU Recommend Under 50%`, `THREAD Concurrency True WARNING`.
- MEMORY_LIMIT ≤ 256이면 CPU 값과 무관하게 Memory 시나리오가 우선(run 1).
- CPU 위반 판정은 CPU_MAX_OCCUPY가 아니라 50% 고정 임계: CPU_MAX_OCCUPY는 워커가 부하를 올리는 상한이고, 50 이하면 50% 도달 시 `Peak reached → cooldown`으로 스스로 내려간다.
- Healthy 모드의 MemoryWorker는 한도 도달 시 `Memory Cache Flushed`로 회복한다 → 누수 경로와 대비되는 "정상 해제" 경로.

## 로그 캡처 주의
- stdout을 파일로 리다이렉트하면 Python 블록 버퍼링 때문에 SIGKILL 시 마지막 출력이 사라진다 → `PYTHONUNBUFFERED=1`.
- 미션 예시의 `SELF-TERMINATED` / `WATCHDOG ... SIGTERM` 배너는 이 빌드에서 출력되지 않는다. 핵심 로그는 `[CRITICAL] [MemoryGuard] ...`, `[CRITICAL] [CpuWorker] CPU Threshold Violated!`와 종료 코드(137/143).
- 데드락 상태 프로세스도 SIGTERM에 종료된다(EXIT 143) — 계획의 Review Focus 5 가설(SIGTERM 무응답)은 반증.
