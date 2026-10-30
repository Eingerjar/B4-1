# 컴퓨터가 알아서 자기 상태를 점검하게 만들기

## 1. 미션 개요

리눅스 서버의 보안·계정·권한·앱 실행 환경을 구성하고, Bash로 시스템 상태 수집과 로그 관리를 자동화한다.

## 2. 필수 제출물

1. **요구사항 수행 내역서 — 문서 1개**
   - SSH 포트, 방화벽, 계정·그룹·ACL, 디렉토리·권한, 환경 변수, cron 등록 등의 설정·명령어 기록.
   - 아래 필수 증거 자료 포함.
2. **자동화 스크립트 소스코드 — monitor.sh**

### 수행 내역서 필수 증거

- SSH 포트 20022 변경 및 Root 원격 접속 차단 확인.
- UFW 또는 firewalld 활성화, 20022/tcp·15034/tcp만 허용한 내역.
- 계정·그룹 생성 확인.
- 디렉토리 구조와 권한 확인(ACL 포함).
- 앱 Boot Sequence 5단계 [OK] 및 Agent READY 확인.
- monitor.sh 실행 결과: 프로세스·포트·리소스·경고.
- /var/log/agent-app/monitor.log 최근 라인과 누적 기록 확인.
- crontab 매분 실행 등록 및 자동 실행 확인: 1분 후 로그 증가.

## 3. 과제 목표

- SSH 포트 변경과 Root 원격 접속 차단의 보안상 이유 설명.
- 필요한 포트만 허용하는 방화벽 정책 구성·검증.
- 역할 기반 계정·그룹·ACL로 공유/보안 디렉토리를 분리하는 이유 설명.
- 환경 변수로 실행 환경을 고정하는 이유와 검증 방법 설명.
- 프로세스·포트·자원 상태 수집 및 로그 기록 흐름 설명.
- cron 주기 실행과 로그 보존 정책의 필요성 설명.

## 4. 필수 기능 요구사항

### 4.1 SSH·방화벽

- SSH 접속 포트: **20022**.
- Root 원격 로그인 차단.
- SSH 설정 파일 및 ss -tulnp 등으로 설정·리슨 상태 확인.
- **UFW 또는 firewalld 중 하나**를 활성화.
- 인바운드 허용 포트는 **TCP 20022(SSH), TCP 15034(APP)만** 허용.
- ufw status 또는 firewall-cmd --list-all 등으로 확인.

### 4.2 계정·그룹

| 계정        | 역할                         |
| ----------- | ---------------------------- |
| agent-admin | 운영·관리, cron 실행자       |
| agent-dev   | 개발·운영, monitor.sh 작성자 |
| agent-test  | QA·테스트                    |

| 그룹         | 구성원                             |
| ------------ | ---------------------------------- |
| agent-common | agent-admin, agent-dev, agent-test |
| agent-core   | agent-admin, agent-dev             |

### 4.3 디렉토리·권한

필요한 디렉토리:

- $AGENT_HOME
- $AGENT_HOME/upload_files
- $AGENT_HOME/api_keys
- /var/log/agent-app

권한 정책:

- upload_files: 그룹 agent-common, 읽기·쓰기 가능.
- api_keys 및 /var/log/agent-app: 그룹 agent-core ONLY, 읽기·쓰기 가능.
- id, ls -l, getfacl(사용 시) 등으로 계정·소유권·권한 확인.

### 4.4 앱 실행 환경

| 환경 변수        | 원문 지정값                                      |
| ---------------- | ------------------------------------------------ |
| AGENT_HOME       | 예: /home/agent-admin/agent-app                  |
| AGENT_PORT       | 15034                                            |
| AGENT_UPLOAD_DIR | $AGENT_HOME/upload_files                         |
| AGENT_KEY_PATH   | $AGENT_HOME/api_keys/t_secret.key                |
| AGENT_LOG_DIR    | /var/log/agent-app — 지정 권장, 미지정 시 기본값 |

키 파일:

- 경로: $AGENT_HOME/api_keys/t_secret.key
- 내용: agent_api_key_test — 1줄.

실행 성공 기준:

- 일반 계정으로 실행. **Root 실행 금지**.
- Boot Sequence 5단계 모두 **[OK]**.
- 마지막에 **Agent READY** 출력.
- **0.0.0.0:15034 LISTEN**.
- 종료: Ctrl+C.

### 4.5 monitor.sh 위치·권한

| 항목           | 요구사항                   |
| -------------- | -------------------------- |
| 경로           | $AGENT_HOME/bin/monitor.sh |
| 소유자         | agent-dev                  |
| 그룹           | agent-core                 |
| 권한           | 750 — rwxr-x---            |
| cron 실행 계정 | agent-admin                |

agent-admin은 agent-core에 포함되어 스크립트를 실행할 수 있어야 한다.

### 4.6 Health Check — 실패 시 종료

- agent_app.py 또는 제공 앱 파일명의 프로세스 실행 상태 확인. 비정상 시 **exit 1**.
- **TCP 15034 LISTEN** 확인. 비정상 시 **exit 1**.

### 4.7 방화벽 상태 점검 — 경고만 출력

- UFW 또는 firewalld 활성화 여부 확인.
- 비활성이면 **[WARNING]** 출력하되 스크립트는 종료하지 않음.

### 4.8 자원 수집·임계값

수집 항목:

- CPU 사용률(%).
- 메모리 사용률(%).
- 루트 파티션 디스크 사용률(Used %).

경고 조건:
| 항목 | 조건 |
| --- | --- |
| CPU | > 20% |
| MEM | > 10% |
| DISK_USED | > 80% |

임계값을 초과하면 **[WARNING]**을 출력하되 종료하지 않는다.

### 4.9 로그 저장·용량 관리

- 파일: **/var/log/agent-app/monitor.log**.
- 포맷:

```text
[YYYY-MM-DD HH:MM:SS] PID:... CPU:..% MEM:..% DISK_USED:..%
```

- 로그가 커지면 **최대 10MB/10개 파일 유지**.
- logrotate 또는 스크립트 로직 등 구현 방법은 자유.

### 4.10 cron 자동 실행

- **agent-admin 계정의 crontab**에 매분 실행 등록.
- 등록 후 **1~2분 이내** monitor.log에 새 라인이 자동 누적되는지 확인.

## 5. 선택 보너스

### 보너스 1: report.sh

- monitor.log를 분석해 CPU/MEM/DISK의 **평균·최대·최소·샘플 수**를 콘솔에 출력.
- 선택: 시작·종료 시간을 입력받아 해당 구간만 분석.

### 보너스 2: 시간 기반 로그 보존

- /var/log/agent-app/\*.log 중 **7일 이상 경과한 파일 압축**.
- **/var/log/monitor/agent-app/archive/**로 이동.
- 해당 아카이브의 \*.gz 중 **30일 이상 경과한 파일 삭제**.
- 권장: 디렉토리 미존재·권한 부족·대상 파일 없음 등의 상황에서 안전하게 종료하거나 경고.

## 6. 개발 환경·제약

- **Ubuntu 22.04 LTS 또는 동등 Linux 환경**.
- 이전 미션의 컨테이너/VM 환경 재사용 권장.
- 자동화 스크립트는 **Bash만 사용**. Python 등으로 대체 금지.
- 필요한 경우에만 sudo 사용. 가능한 일반 계정으로 진행.
- 제공 앱은 실행 대상이며 핵심은 관제·자동화 스크립트 구현.

## 7. 결과 예시 안내

- 원문의 출력 예시는 정답이 아닌 참고용이며 실제 문구·구성이 달라도 된다.
- 예시에는 Boot 출력, 모니터링 출력, 누적 로그, 보너스 리포트 출력이 포함된다.

## 8. 제공 데이터

- agent-app.zip
  - agent-app-linux-x86: x86용.
  - agent-app-linux-arm64: ARM Apple용.
