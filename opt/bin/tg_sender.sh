#!/bin/sh
# Отправка очереди Telegram (P.8): из tg_notify в фоне и по cron.1min
. /opt/apps/kvas/bin/libs/tgq 2>/dev/null || exit 0
Q="${TG_QUEUE}"
[ -s "${Q}" ] || exit 0
_tok=$(tg_conf_get TG_BOT_TOKEN); _cht=$(tg_conf_get TG_CHAT_ID)
[ -n "${_tok}" ] && [ -n "${_cht}" ] || exit 0
_work="${Q}.$$"
mv "${Q}" "${_work}" 2>/dev/null || exit 0
while IFS="$(printf '\t')" read -r _ev _txt || [ -n "${_ev}${_txt}" ]; do
	[ -z "${_ev}" ] && [ -z "${_txt}" ] && continue
	_esc=$(printf '%s' "[${_ev}] ${_txt}" | sed 's/\\/\\\\/g; s/"/\\"/g')
	_body=$(printf '{"chat_id":"%s","text":"%s"}' "${_cht}" "${_esc}")
	# Telegram API — через SOCKS тоннеля (tg_curl); пустой ответ = сеть, возвращаем в очередь
	_resp=$(tg_curl "https://api.telegram.org/bot${_tok}/sendMessage" -d "${_body}")
	if [ -z "${_resp}" ]; then
		printf '%s\t%s\n' "${_ev}" "${_txt}" >> "${Q}" 2>/dev/null
	fi
done < "${_work}"
rm -f "${_work}"
exit 0
