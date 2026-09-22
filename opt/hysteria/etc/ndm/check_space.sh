#!/bin/sh

# Импортируем общие переменные и цвета
# shellcheck source=/dev/null
. /opt/apps/kvas/hysteria/etc/conf/env.sh

echo "Проверка доступного дискового пространства для /opt..."

# Получаем свободное место в мегабайтах и устройство монтирования
DISK_INFO=$(df -m /opt | tail -n 1)
FREE_MB=$(echo "$DISK_INFO" | awk '{print $4}')
DEV_NAME=$(echo "$DISK_INFO" | awk '{print $1}')

# Определяем тип памяти: если в имени устройства есть "sd", то это USB
IS_USB=0
if echo "$DEV_NAME" | grep -q "sd"; then
    IS_USB=1
fi

if [ "$IS_USB" -eq 1 ]; then
    # Для USB накопителей просто проверяем физический лимит (нужно хотя бы 25 МБ)
    if [ "$FREE_MB" -lt 25 ]; then
        echo -e "${RED}Ошибка: На USB-накопителе осталось всего ${FREE_MB}MB свободных.${NC}"
        echo -e "Для загрузки и работы Hysteria (размер ~22MB) требуется больше места."
        exit 1
    fi
else
    # Логика для внутренней памяти роутера
    if [ "$FREE_MB" -lt 30 ]; then
        echo -e "${RED}КРИТИЧЕСКАЯ ОШИБКА: Установка заблокирована!${NC}"
        echo -e "Свободно всего ${YELLOW}${FREE_MB}MB${NC} во внутренней памяти роутера."
        echo -e "Бинарный файл Hysteria занимает ~22MB. Заполнение внутренней памяти"
        echo -e "до предела приведет к критической нестабильности KeeneticOS."
        echo -e "${BLUE}Рекомендация:${NC} Перенесите Entware на USB флеш-карту."
        exit 1
    elif [ "$FREE_MB" -lt 40 ]; then
        echo -e "${YELLOW}ВНИМАНИЕ: Недостаточно памяти!${NC}"
        echo -e "Свободно всего ${FREE_MB}MB во внутренней памяти роутера."
        echo -e "После установки Hysteria останется критически мало места,"
        echo -e "что может вызвать сбои в работе роутера и других пакетов."
        echo -n "Вы уверены, что хотите продолжить установку? [y/N]: "
        read -r CONFIRM
        case "$CONFIRM" in
            [yY][eE][sS]|[yY])
                echo "Продолжаем установку на ваш страх и риск..."
                ;;
            *)
                echo "Установка отменена пользователем."
                exit 1
                ;;
        esac
    fi
fi

# Если все проверки пройдены успешного
exit 0