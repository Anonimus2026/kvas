#!/bin/sh
# Launch KVAS monitoring web UI
PORT=${MONITOR_PORT:-8085}
WWW_DIR=/opt/apps/kvas/bin/monitor/www
PID_FILE=/var/run/kvas-monitor-web.pid
HTTPD_SCRIPT=/opt/apps/kvas/bin/monitor/httpd.sh
LOG_FILE=${MONITOR_WEB_LOG:-/tmp/kvas-monitor-web.log}

log() {
    local ts
    ts=$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null)
    [ -z "$ts" ] && ts="unknown-time"
    echo "[$ts] [launcher] $*" >> "$LOG_FILE"
}

kill_port() {
    log "cleanup requested for port $PORT"
    if [ -f "$PID_FILE" ]; then
        local pid
        pid=$(cat "$PID_FILE" 2>/dev/null)
        if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
            log "terminating pid from pidfile: $pid"
            kill "$pid" 2>/dev/null
            sleep 1
            kill -9 "$pid" 2>/dev/null
        fi
    fi
    if command -v netstat >/dev/null 2>&1; then
        local pids
        pids=$(netstat -tulnp 2>/dev/null | grep ":${PORT} " | grep -oE '[0-9]+/' | sed 's|/||g')
        if [ -n "$pids" ]; then
            log "killing port listeners: $pids"
            for pid in $pids; do kill "$pid" 2>/dev/null; done
            sleep 1
            for pid in $pids; do kill -9 "$pid" 2>/dev/null; done
        fi
    fi
    rm -f "$PID_FILE" /tmp/kvas-httpd-handler.sh
    log "cleanup finished"
}

preflight() {
    local ok=1
    if ! command -v socat >/dev/null 2>&1; then
        log "WARN: socat not found, installing..."
        echo "Устанавливаю socat..."
        opkg update >/dev/null 2>&1
        opkg install socat >/dev/null 2>&1
        if ! command -v socat >/dev/null 2>&1; then
            log "ERROR: socat install failed"
            echo "ОШИБКА: не удалось установить socat"
            ok=0
        else
            log "socat installed successfully"
            echo "socat установлен"
        fi
    fi
    if ! command -v conntrack >/dev/null 2>&1 && [ ! -f /proc/net/nf_conntrack ]; then
        log "WARN: conntrack not found"
        ok=0
    fi
    if [ ! -d "$WWW_DIR" ]; then
        log "ERROR: www dir missing: $WWW_DIR"
        echo "ERROR: www dir missing: $WWW_DIR"
        exit 1
    fi
    if [ ! -f "$HTTPD_SCRIPT" ]; then
        log "ERROR: httpd script missing: $HTTPD_SCRIPT"
        echo "ERROR: httpd script missing: $HTTPD_SCRIPT"
        exit 1
    fi
    return $ok
}

start_socat_server() {
    log "starting socat backend via $HTTPD_SCRIPT on port $PORT"
    MONITOR_WEB_LOG="$LOG_FILE" "$HTTPD_SCRIPT" "$PORT"
    local rc=$?
    if [ $rc -eq 0 ]; then
        log "socat backend started successfully"
    else
        log "socat backend failed with exit code $rc"
    fi
    return $rc
}

if [ "$1" = "stop" ]; then
    log "stop requested"
    kill_port
    exit 0
fi

kill_port
preflight

if command -v socat >/dev/null 2>&1 && [ -x "$HTTPD_SCRIPT" ]; then
    start_socat_server
    exit $?
fi

log "no http server available"
echo "ERROR: no HTTP server available. Install socat"
exit 1
