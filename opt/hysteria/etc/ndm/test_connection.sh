#!/bin/sh

# Импортируем общие переменные
# shellcheck source=/dev/null
. /opt/apps/kvas/hysteria/etc/conf/env.sh

echo "Выполняется проверка проксирования через Hysteria 2..."
#echo "Запрос к ipinfo.io через socks5://${PROXY_LOCAL_IP}:${PROXY_LOCAL_PORT_SOCKS}..."

# Делаем запрос с таймаутом в 6 секунд, скрывая прогресс-бар curl
# Используем ipinfo.io, так как он отдает более стабильный и чистый JSON/текст
IP_RESPONSE=$(curl -s --connect-timeout 6 --max-time 15 -x "socks5://${PROXY_LOCAL_IP}:${PROXY_LOCAL_PORT_SOCKS}" "https://ifconfig.me")

if [ -n "$IP_RESPONSE" ] && ! echo "$IP_RESPONSE" | grep -q -E "(Failed|Error|404)"; then
    echo -e "${GREEN}Тест успешно пройден!${NC}"
    echo -e "Ваш внешний IP через туннель: ${GREEN}${IP_RESPONSE}${NC}"
    exit 0
else
    echo -e "${RED}Ошибка теста! Прокси-сервер не отвечает или соединение разорвано.${NC}"
    echo -e "${YELLOW}Рекомендации:${NC}"
    echo " 1. Проверьте статус службы: kvas hysteria"
    echo " 2. Убедитесь, что параметры в ссылке (add) были верными."
    echo " 3. Проверьте системный лог роутера (logread)."
    exit 1
fi