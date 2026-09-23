#!/bin/sh
# Отправка очереди Telegram (P.8): из tg_notify в фоне и по cron.1min
. /opt/apps/kvas/bin/libs/tgq 2>/dev/null || exit 0
# keepalive интерактивного бота (P.8+)
if [ "$(tg_conf_get TG_ENABLED)" = "true" ]; then
	_bp=/opt/var/kvas/tg_bot.pid
	_bid=$(cat "${_bp}" 2>/dev/null)
	if [ -z "${_bid}" ] || ! kill -0 "${_bid}" 2>/dev/null; then
		( sh /opt/apps/kvas/bin/tg_bot.sh >/dev/null 2>&1 & ) 2>/dev/null
	fi
fi
Q="${TG_QUEUE}"
[ -s "${Q}" ] || exit 0
_tok=$(tg_conf_get TG_BOT_TOKEN); _cht=$(tg_conf_get TG_CHAT_ID)
[ -n "${_tok}" ] && [ -n "${_cht}" ] || exit 0
_work="${Q}.$$"
mv "${Q}" "${_work}" 2>/dev/null || exit 0
while IFS="$(printf '\t')" read -r _ev _txt || [ -n "${_ev}${_txt}" ]; do
	[ -z "${_ev}" ] && [ -z "${_txt}" ] && continue
	# форма + urlencode (не JSON -d: curl шлёт её как form, Telegram не видит text)
	_resp=$(tg_curl "https://api.telegram.org/bot${_tok}/sendMessage" \
		--data-urlencode "chat_id=${_cht}" \
		--data-urlencode "text=[${_ev}] ${_txt}")
	if [ -z "${_resp}" ]; then
		printf '%s\t%s\n' "${_ev}" "${_txt}" >> "${Q}" 2>/dev/null
	fi
done < "${_work}"
rm -f "${_work}"
exit 0
