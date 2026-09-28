#!/bin/sh

# Параметры локального прокси-сервера AmneziaWG (wireproxy-awg)
PROXY_LOCAL_IP="127.0.0.1"
PROXY_LOCAL_PORT_SOCKS=10818
PROXY_LOCAL_PORT_HTTP=10819

# Профиль использования ресурсов (eco | balanced | perf | custom)
RESOURCE_PROFILE="balanced"

# Ограничение ресурсов Go Runtime для wireproxy
# GOMAXPROCS: ограничивает число ядер/потоков планировщика (снижает количество потоков ОС)
# GOMEMLIMIT: мягкий лимит памяти Go Runtime (GC активнее сбрасывает память при приближении к лимиту)
# GOGC: процент роста кучи перед запуском сборщика мусора (меньше значение = чаще GC)
# GODEBUG: немедленный возврат свободных страниц памяти ядру Linux через MADV_DONTNEED
GOMAXPROCS=2
GOMEMLIMIT="24MiB"
GOGC=25
GODEBUG="madvdontneed=1"

# Параметры Keenetic RCI API
KEENETIC_PROXY_NAME="Proxy42"
KEENETIC_PROXY_DESC="Kvas-proxy-awg"
PROXY_PROTO="socks5"

# Цвета для вывода в терминал
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0;0m'
