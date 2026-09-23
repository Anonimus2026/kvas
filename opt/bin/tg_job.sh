#!/bin/sh
# Задача обновления/отката KVAS с ответом в Telegram (P.8+).
# Копируется в /tmp и запускается оттуда: пакет перезаписывается opkg во время работы.
# Аргументы: $1=chat_id $2=update|rollback
. /opt/apps/kvas/bin/libs/tgq 2>/dev/null || exit 0

_ch="$1"; _mode="$2"
case "${_mode}" in
	update)   _args="";       _label="Обновление" ;;
	rollback) _args="rollback"; _label="Откат" ;;
	*) exit 1 ;;
esac

# как в web UI: 1=репозиторий; rollback: 2=предыдущая версия из списка
case "${_mode}" in
	update)   _feed='1\n' ;;
	rollback) _feed='1\n2\n' ;;
esac

_outf=/tmp/.tgjob.out.$$
printf "${_feed}" | sh /opt/apps/kvas/bin/kvas upgrade ${_args} >"${_outf}" 2>&1
_rc=$?
_out=$(tr -d '\033\r' <"${_outf}" 2>/dev/null | sed 's/\[[0-9][0-9;]*[a-zA-Z]//g; s/\[m//g' | tail -c 2500)
rm -f "${_outf}"

# как в web UI после апгрейда: перезапуск веб-монитора
sh /opt/apps/kvas/bin/kvas monitor web stop >/dev/null 2>&1
sleep 1
sh /opt/apps/kvas/bin/kvas monitor web start >/dev/null 2>&1 &
sleep 2

_t=$(tg_conf_get TG_BOT_TOKEN)
[ -n "${_t}" ] || exit 0
tg_curl "https://api.telegram.org/bot${_t}/sendMessage" \
	--data-urlencode "chat_id=${_ch}" \
	--data-urlencode "text=${_label} завершено (код ${_rc}):
${_out:-нет вывода}" >/dev/null 2>&1
exit 0
