#!/bin/sh
# ------------------------------------------------------------------------------------------
#
#   УСТАНОВОЧНЫЙ СКРИПТ KVAS-HYSTERIA
#   Добавляет поддержку Hysteria 2 в уже установленный KVAS
#
# ------------------------------------------------------------------------------------------

# Определяем пути
KVAS_APP_DIR="/opt/apps/kvas"
HYSTERIA_DIR="${KVAS_APP_DIR}/hysteria"

# Цвета
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0;0m'

print_line() { printf "%83s\n" | tr " " "="; }

echo "=== Установка Hysteria 2 для KVAS ==="
print_line

# Проверяем, установлен ли KVAS
if [ ! -f "${KVAS_APP_DIR}/bin/kvas" ]; then
    echo -e "${RED}Ошибка: KVAS не установлен!${NC}"
    echo "Сначала установите KVAS: opkg install kvas_*.ipk"
    exit 1
fi

# Проверяем, есть ли уже hysteria
if [ -f "${HYSTERIA_DIR}/etc/conf/env.sh" ]; then
    echo -e "${YELLOW}Hysteria уже установлена. Обновляем компоненты...${NC}"
fi

# Создаем директории
echo "Создание структуры каталогов..."
mkdir -p "${HYSTERIA_DIR}/bin"
mkdir -p "${HYSTERIA_DIR}/etc/conf"
mkdir -p "${HYSTERIA_DIR}/etc/init.d"
mkdir -p "${HYSTERIA_DIR}/etc/ndm"
mkdir -p "/opt/etc/hysteria"

# Определяем URL репозитория
REPO_RAW="https://raw.githubusercontent.com/Anonimus2026/kvas/main"

# Скачиваем компоненты
echo "Загрузка компонентов..."
curl -sL --connect-timeout 10 --max-time 60 -f -o "${HYSTERIA_DIR}/bin/.gitkeep" "${REPO_RAW}/opt/apps/kvas/hysteria/bin/.gitkeep" 2>/dev/null
curl -sL --connect-timeout 10 --max-time 60 -f -o "${HYSTERIA_DIR}/etc/conf/env.sh" "${REPO_RAW}/opt/apps/kvas/hysteria/etc/conf/env.sh"
curl -sL --connect-timeout 10 --max-time 60 -f -o "${HYSTERIA_DIR}/etc/conf/config.yaml" "${REPO_RAW}/opt/apps/kvas/hysteria/etc/conf/config.yaml"
curl -sL --connect-timeout 10 --max-time 60 -f -o "${HYSTERIA_DIR}/etc/init.d/S99hysteria" "${REPO_RAW}/opt/apps/kvas/hysteria/etc/init.d/S99hysteria"
curl -sL --connect-timeout 10 --max-time 60 -f -o "${HYSTERIA_DIR}/etc/ndm/check_space.sh" "${REPO_RAW}/opt/apps/kvas/hysteria/etc/ndm/check_space.sh"
curl -sL --connect-timeout 10 --max-time 60 -f -o "${HYSTERIA_DIR}/etc/ndm/test_connection.sh" "${REPO_RAW}/opt/apps/kvas/hysteria/etc/ndm/test_connection.sh"

# Скачиваем обновленный kvas с поддержкой hysteria
echo "Обновление основного скрипта KVAS..."
curl -sL --connect-timeout 10 --max-time 60 -f -o "${KVAS_APP_DIR}/bin/libs/hysteria" "${REPO_RAW}/opt/bin/libs/hysteria"

# Проверяем загрузку
if [ ! -s "${HYSTERIA_DIR}/etc/conf/env.sh" ] || ! head -1 "${HYSTERIA_DIR}/etc/conf/env.sh" 2>/dev/null | grep -q '^#!'; then
    echo -e "${RED}Ошибка: Не удалось загрузить файлы из репозитория.${NC}"
    echo "Проверьте подключение к интернету."
    exit 1
fi

# Устанавливаем права
chmod +x "${HYSTERIA_DIR}/etc/init.d/S99hysteria"
chmod +x "${HYSTERIA_DIR}/etc/ndm/check_space.sh"
chmod +x "${HYSTERIA_DIR}/etc/ndm/test_connection.sh"
chmod +x "${KVAS_APP_DIR}/bin/libs/hysteria"

echo ""
echo -e "${GREEN}Компоненты Hysteria успешно установлены!${NC}"
echo ""
print_line
echo "Для завершения настройки:"
echo "  1. kvas hysteria install   - скачать бинарный файл Hysteria"
echo "  2. kvas hysteria add \"hysteria2://...\" - настроить подключение"
echo ""
echo "Подробнее: kvas help hysteria"
print_line