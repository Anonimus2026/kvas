#!/bin/sh
# HTTP server on socat for KVAS monitoring
# Static files + CGI
PORT=${1:-8085}
WWW_DIR=/opt/apps/kvas/bin/monitor/www
PID_FILE=/var/run/kvas-monitor-web.pid
LOG_FILE=${MONITOR_WEB_LOG:-/tmp/kvas-monitor-web.log}

log() {
    local ts
    ts=$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null)
    [ -z "$ts" ] && ts="unknown-time"
    echo "[$ts] [httpd] $*" >> "$LOG_FILE"
}

if [ "$1" = "stop" ]; then
    log "stop requested"
    [ -f "$PID_FILE" ] && kill "$(cat "$PID_FILE")" 2>/dev/null
    rm -f "$PID_FILE"
    exit 0
fi

if ! command -v socat >/dev/null 2>&1; then
    log "socat not found"
    echo "ERROR: socat not found"
    exit 1
fi

if [ ! -d "$WWW_DIR" ]; then
    log "www dir not found: $WWW_DIR"
    echo "ERROR: www dir not found: $WWW_DIR"
    exit 1
fi

# CGI handler — written to file, no heredoc issues
cat > /tmp/kvas-httpd-handler.sh << 'HANDLER_EOF'
#!/bin/sh
W="/opt/apps/kvas/bin/monitor/www"
LOG_FILE=${MONITOR_WEB_LOG:-/tmp/kvas-monitor-web.log}
log() {
    local ts
    ts=$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null)
    [ -z "$ts" ] && ts="unknown-time"
    echo "[$ts] [handler] $*" >> "$LOG_FILE"
}
R=""
L=""
while IFS='' read -r L; do
    L=$(echo "$L" | tr -d '\r')
    [ -z "$L" ] && break
    [ -z "$R" ] && R="$L"
done
M=$(echo "$R" | awk '{print $1}')
P=$(echo "$R" | awk '{print $2}')
S=$(echo "$P" | sed 's/[?#].*//')
log "request method=${M:-unknown} path=${P:-/}"

if echo "$S" | grep -q '^/cgi-bin/'; then
    Q="${P#*\?}"
    [ "$Q" = "$P" ] && Q=""
    X="$W$S"
    if [ -x "$X" ]; then
        export QUERY_STRING="$Q"
        export REQUEST_METHOD="$M"
        printf "HTTP/1.0 200 OK\r\nContent-Type: application/json\r\nAccess-Control-Allow-Origin: *\r\n\r\n"
        "$X"
        log "cgi ok script=$X query=${Q:-<empty>}"
    else
        log "cgi missing script=$X"
        printf "HTTP/1.0 404 Not Found\r\nContent-Type: application/json\r\n\r\n{\"error\":\"script not found\"}"
    fi
else
    if [ -z "$S" ] || [ "$S" = "/" ]; then
        S="/index.html"
    fi
    F="$W$S"
    if [ -f "$F" ]; then
        T="text/html"
        case "$S" in
            *.css) T="text/css";;
            *.js) T="application/javascript";;
            *.json) T="application/json";;
            *.png) T="image/png";;
            *.jpg) T="image/jpeg";;
            *.gif) T="image/gif";;
            *.svg) T="image/svg+xml";;
            *.ico) T="image/x-icon";;
        esac
        log "static ok file=$F type=$T"
        printf "HTTP/1.0 200 OK\r\nContent-Type: %s\r\nCache-Control: no-cache\r\n\r\n" "$T"
        cat "$F"
    else
        log "static missing file=$F"
        printf "HTTP/1.0 404 Not Found\r\nContent-Type: text/plain\r\n\r\nNot found: %s" "$S"
    fi
fi
HANDLER_EOF
chmod +x /tmp/kvas-httpd-handler.sh

log "starting socat listener on port $PORT"
MONITOR_WEB_LOG="$LOG_FILE" socat TCP-LISTEN:"$PORT",bind=0.0.0.0,reuseaddr,fork EXEC:"sh /tmp/kvas-httpd-handler.sh" >> "$LOG_FILE" 2>&1 &
echo $! > "$PID_FILE"
sleep 1
if kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
    log "socat listener started with pid $(cat "$PID_FILE")"
    echo "OK socat $PORT"
else
    log "socat listener failed to start"
    echo "ERROR: socat failed to start on port $PORT"
    rm -f "$PID_FILE"
    exit 1
fi
