#!/bin/bash
set -euo pipefail
export PATH=/usr/sbin:/usr/bin:/sbin:/bin
export LC_ALL=C

source /etc/profile.d/agent-app.sh

LOG_FILE="$AGENT_LOG_DIR/monitor.log"
MAX_BYTES=$((10 * 1024 * 1024))

# 동시 실행 방지
exec 9>"$AGENT_LOG_DIR/.monitor.lock"
flock -n 9 || exit 0

# 1. 앱 프로세스 확인
PIDS=$(pgrep -u agent-admin -f \
  '^(\./|/home/agent-admin/agent-app/)agent-app-linux-arm64([[:space:]]|$)' \
  | paste -sd, -) || {
    echo "[ERROR] App process not running"
    exit 1
}

# 2. TCP 포트 LISTEN 확인
if ! ss -H -lnt "sport = :$AGENT_PORT" | grep -q .; then
    echo "[ERROR] TCP $AGENT_PORT is not LISTEN"
    exit 1
fi

echo "[OK] Process PID:$PIDS / TCP $AGENT_PORT LISTEN"

# 3. 방화벽 확인: 실패해도 자원 측정은 계속
if FW_STATUS=$(sudo -n /usr/sbin/ufw status 2>&1); then
    if grep -qx 'Status: active' <<< "$FW_STATUS"; then
        echo "[OK] UFW active"
    else
        echo "[WARNING] UFW inactive"
    fi
else
    echo "[WARNING] Cannot query UFW status"
fi

# 4. 시스템 전체 CPU 사용률: 1초 간격으로 측정
read_cpu() {
    local tag user nice system idle iowait irq softirq steal rest
    read -r tag user nice system idle iowait irq softirq steal rest \
      < /proc/stat
    CPU_TOTAL=$((user + nice + system + idle + iowait + irq + softirq + steal))
    CPU_IDLE=$((idle + iowait))
}

read_cpu
TOTAL_BEFORE=$CPU_TOTAL
IDLE_BEFORE=$CPU_IDLE
sleep 1
read_cpu

TOTAL_DIFF=$((CPU_TOTAL - TOTAL_BEFORE))
IDLE_DIFF=$((CPU_IDLE - IDLE_BEFORE))

CPU=$(awk -v total="$TOTAL_DIFF" -v idle="$IDLE_DIFF" \
  'BEGIN {
    if (total <= 0) print "0.00";
    else printf "%.2f", 100 * (total - idle) / total
  }')

# 5. 시스템 전체 메모리 사용률
MEM=$(awk '
  /^MemTotal:/ {total=$2}
  /^MemAvailable:/ {available=$2}
  END {printf "%.2f", 100 * (total-available) / total}
' /proc/meminfo)

# 6. 루트 파티션 디스크 사용률
DISK=$(df -P / | awk 'NR==2 {gsub(/%/, "", $5); print $5}')

# 임계값을 초과해도 경고만 출력
warn_above() {
    local name=$1 value=$2 limit=$3
    if awk -v value="$value" -v limit="$limit" \
      'BEGIN {exit !(value > limit)}'; then
        echo "[WARNING] $name ${value}% > ${limit}%"
    fi
}

warn_above CPU "$CPU" 20
warn_above MEM "$MEM" 10
warn_above DISK_USED "$DISK" 80

LINE="[$(date '+%Y-%m-%d %H:%M:%S')] PID:$PIDS CPU:${CPU}% MEM:${MEM}% DISK_USED:${DISK}%"

# 7. 최대 10MiB씩, 현재 로그 포함 최대 10개 파일
if [[ -f "$LOG_FILE" ]]; then
    SIZE=$(stat -c %s "$LOG_FILE")
    if (( SIZE + ${#LINE} + 1 > MAX_BYTES )); then
        rm -f "$LOG_FILE.9"
        for ((i=8; i>=1; i--)); do
            if [[ -f "$LOG_FILE.$i" ]]; then
                mv "$LOG_FILE.$i" "$LOG_FILE.$((i+1))"
            fi
        done
        mv "$LOG_FILE" "$LOG_FILE.1"
    fi
fi

printf '%s\n' "$LINE" >> "$LOG_FILE"
printf '%s\n' "$LINE"