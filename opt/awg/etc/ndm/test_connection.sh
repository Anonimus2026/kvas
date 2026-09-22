#!/bin/sh
# Тест проксирования через AmneziaWG (wireproxy-awg)
. /opt/apps/kvas/awg/etc/conf/env.sh 2>/dev/null

test_ip=$(curl -4 -s --max-time 10 -x "socks5://${PROXY_LOCAL_IP}:${PROXY_LOCAL_PORT_SOCKS}" "https://myip.addr.tools" 2>/dev/null)
if [ -z "$test_ip" ] || echo "$test_ip" | grep -q -E "(Failed|Error|404|html)"; then
    test_ip=$(curl -4 -s --max-time 15 -x "socks5://${PROXY_LOCAL_IP}:${PROXY_LOCAL_PORT_SOCKS}" "https://myip.addr.tools" 2>/dev/null)
fi
if [ -n "$test_ip" ] && echo "$test_ip" | grep -qE "^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$"; then
    echo "AmneziaWG: РАБОТАЕТ (IP: $test_ip)"
    exit 0
else
    echo "AmneziaWG: НЕ РАБОТАЕТ"
    exit 1
fi
