#!/bin/sh

# shellcheck source=/dev/null
[ -f /opt/apps/kvas/awg/etc/conf/env.sh ] && . /opt/apps/kvas/awg/etc/conf/env.sh

PIDFILE="/var/run/wireproxy.pid"
ACTIVE_FLAG="/var/run/wireproxy.active"
LOGFILE="/var/log/wireproxy.log"
INIT_SCRIPT="/opt/etc/init.d/S99awg"
CHECK_URL="https://api.ipify.org"
INTERVAL=30

log_msg() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [watchdog] $1" >> "$LOGFILE"
}

check_internet() {
    ping -c 1 -W 2 1.1.1.1 >/dev/null 2>&1 || ping -c 1 -W 2 77.88.8.8 >/dev/null 2>&1
}

check_proxy() {
    curl -s -m 5 --connect-timeout 4 -x "socks5h://${PROXY_LOCAL_IP:-127.0.0.1}:${PROXY_LOCAL_PORT_SOCKS:-10818}" "$CHECK_URL" >/dev/null 2>&1
}

log_msg "Служба мониторинга туннеля AmneziaWG запущена."

while [ -f "$ACTIVE_FLAG" ]; do
    sleep "$INTERVAL"

    [ ! -f "$ACTIVE_FLAG" ] && break

    # 1. Проверка аварийного падения процесса wireproxy
    NEED_RESTART=0
    if [ ! -f "$PIDFILE" ]; then
        NEED_RESTART=1
    elif ! kill -0 "$(cat "$PIDFILE" 2>/dev/null)" 2>/dev/null; then
        NEED_RESTART=1
    fi

    if [ "$NEED_RESTART" -eq 1 ]; then
        log_msg "Процесс wireproxy упал. Перезапуск..."
        "$INIT_SCRIPT" restart
        continue
    fi

    # 2. Если у роутера нет физического интернета (WAN упал), туннель не трогаем
    if ! check_internet; then
        continue
    fi

    # 3. Проверка доступности прокси-канала с защитой от единичной потери пакетов
    if ! check_proxy; then
        sleep 4
        if [ -f "$ACTIVE_FLAG" ]; then
            if ! check_proxy; then
                log_msg "Туннель AmneziaWG завис или разорван. Перезапуск службы..."
                "$INIT_SCRIPT" restart
                sleep 5
            fi
        fi
    fi
done

log_msg "Служба мониторинга туннеля AmneziaWG остановлена."
