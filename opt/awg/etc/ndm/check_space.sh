#!/bin/sh

# Импортируем общие переменные и цвета
# shellcheck source=/dev/null
[ -f /opt/apps/kvas/awg/etc/conf/env.sh ] && . /opt/apps/kvas/awg/etc/conf/env.sh

echo "Проверка доступного дискового пространства для /opt..."

DISK_INFO=$(df -m /opt | tail -n 1)
FREE_MB=$(echo "$DISK_INFO" | awk '{print $4}')
DEV_NAME=$(echo "$DISK_INFO" | awk '{print $1}')

IS_USB=0
if echo "$DEV_NAME" | grep -q "sd"; then
    IS_USB=1
fi

if [ "$IS_USB" -eq 1 ]; then
    if [ "$FREE_MB" -lt 15 ]; then
        echo -e "${RED}Ошибка: На USB-накопителе осталось всего ${FREE_MB}MB свободных.${NC}"
        echo -e "Для загрузки и работы wireproxy-awg требуется минимум 15MB свободного места."
        exit 1
    fi
else
    if [ "$FREE_MB" -lt 20 ]; then
        echo -e "${RED}КРИТИЧЕСКАЯ ОШИБКА: Установка заблокирована!${NC}"
        echo -e "Свободно всего ${YELLOW}${FREE_MB}MB${NC} во внутренней памяти роутера."
        echo -e "Бинарный файл wireproxy занимает ~10-15MB. Переполнение памяти"
        echo -e "может привести к нестабильности KeeneticOS."
        echo -e "${BLUE}Рекомендация:${NC} Подключите USB-накопитель и перенесите Entware."
        exit 1
    elif [ "$FREE_MB" -lt 30 ]; then
        echo -e "${YELLOW}ВНИМАНИЕ: Ограниченный объём свободной памяти!${NC}"
        echo -e "Свободно всего ${FREE_MB}MB во внутренней памяти роутера."
        echo -n "Вы уверены, что хотите продолжить установку? [y/N]: "

        # Чтение из tty обходит EOF закрытого пайпа (curl | sh / фоновый запуск)
        if [ -c /dev/tty ]; then
            read -r CONFIRM < /dev/tty
        else
            read -r CONFIRM
        fi

        case "$CONFIRM" in
            [yY][eE][sS]|[yY])
                echo "Продолжаем установку..."
                ;;
            *)
                echo "Установка отменена пользователем."
                exit 1
                ;;
        esac
    fi
fi

exit 0
