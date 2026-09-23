#!/bin/sh
# Интерактивный Telegram-бот KVAS (P.8+): long-poll getUpdates и команды владельцу.
# Команды: /help /status /list [N] /add <домен> /del <домен> /update /rollback
# Реагирует только на TG_CHAT_ID при TG_ENABLED=true.
# Демон: singleton по pid-файлу; keepalive — cron.1min/tg_sender.
. /opt/apps/kvas/bin/libs/tgq 2>/dev/null || exit 0

# getUpdates?timeout=25 — long-poll, curl должен ждать дольше обычного
export TG_CURL_MAX=30

PIDF=/opt/var/kvas/tg_bot.pid
OFFF=/opt/var/kvas/tg_bot.offset
LASTCHAT=/opt/var/kvas/tg_lastchat
mkdir -p /opt/var/kvas 2>/dev/null
if [ -s "${PIDF}" ]; then
	_old=$(cat "${PIDF}" 2>/dev/null)
	[ -n "${_old}" ] && [ "${_old}" != "$$" ] && kill -0 "${_old}" 2>/dev/null && exit 0
fi
echo $$ > "${PIDF}" 2>/dev/null
trap 'rm -f "${PIDF}"' EXIT INT TERM HUP

tb_send() { # $1=chat $2=text
	_tb_t=$(tg_conf_get TG_BOT_TOKEN)
	[ -n "${_tb_t}" ] || return 0
	tg_curl "https://api.telegram.org/bot${_tb_t}/sendMessage" \
		--data-urlencode "chat_id=$1" \
		--data-urlencode "text=$2" >/dev/null 2>&1
}

tb_valid_domain() {
	case "$1" in
		''|*[!A-Za-z0-9.-]*|-*|.*|*..*|*.) return 1 ;;
	esac
	case "$1" in *.*) return 0 ;; *) return 1 ;; esac
}

tb_help() {
	printf '%s' "KVAS бот — команды:
/help — эта справка
/status — версия и состояние туннеля
/list [N] — защищённый список (первые N, по умолч. 15)
/add <домен> — добавить в защищённый список
/del <домен> — удалить из защищённого списка
/update — обновить KVAS до свежей версии
/rollback — откат на предыдущую версию"
}

tb_status() {
	_v=$(sed -n 's/^APP_RELEASE=//p' /opt/etc/kvas.conf 2>/dev/null | head -1)
	_t=$(cat /opt/var/kvas/tg.tunnel.state 2>/dev/null)
	[ -n "${_t}" ] || _t="?"
	printf '%s' "KVAS сборка ${_v:-?}
Туннель: ${_t}"
}

tb_job() { # $1=chat $2=update|rollback — из /tmp, чтобы opkg не перезаписал скрипт под ногами
	_mode="$2"
	case "${_mode}" in
		update)   _label="Обновление" ;;
		rollback) _label="Откат" ;;
		*) return 1 ;;
	esac
	tb_send "$1" "Запускаю: ${_label} KVAS... Результат пришлю отдельным сообщением."
	_w=/tmp/.tgjob.$$
	if ! cp -f /opt/apps/kvas/bin/tg_job.sh "${_w}" 2>/dev/null; then
		tb_send "$1" "Ошибка запуска: не удалось подготовить задачу"
		return 1
	fi
	( sh "${_w}" "$1" "${_mode}" >/dev/null 2>&1; rm -f "${_w}" ) &
}

tb_reply() { # $1=chat $2=команда $3=аргумент
	_ch="$1"; _cmd="$2"; _arg="$3"
	case "${_cmd}" in
		/help|/start) tb_send "${_ch}" "$(tb_help)" ;;
		/status)      tb_send "${_ch}" "$(tb_status)" ;;
		/list)
			_n=$(printf '%s' "${_arg}" | tr -cd '0-9')
			[ -n "${_n}" ] || _n=15
			[ "${_n}" -gt 50 ] 2>/dev/null && _n=50
			_f=/opt/etc/kvas.list
			if [ ! -f "${_f}" ]; then
				tb_send "${_ch}" "Защищённый список пуст"
				return
			fi
			_cnt=$(grep -c . "${_f}" 2>/dev/null); [ -n "${_cnt}" ] || _cnt=0
			_body=$(head -n "${_n}" "${_f}" 2>/dev/null)
			[ -n "${_body}" ] || _body="(пусто)"
			tb_send "${_ch}" "Защищённый список: ${_cnt} шт (первые ${_n}):
${_body}"
			;;
		/add)
			if ! tb_valid_domain "${_arg}"; then
				tb_send "${_ch}" "Неверный домен: ${_arg:-нет параметра}
Использование: /add example.com"
				return
			fi
			_out=$(sh /opt/apps/kvas/bin/kvas add "${_arg}" 2>&1 | tr -d '\033\r' | sed 's/\[[0-9][0-9;]*[a-zA-Z]//g; s/\[m//g' | tail -c 600)
			if grep -qe "${_arg}\$" /opt/etc/kvas.list 2>/dev/null; then
				tb_send "${_ch}" "Добавлено: ${_arg}"
			else
				tb_send "${_ch}" "Не удалось добавить ${_arg}:
${_out:-нет вывода}"
			fi
			;;
		/del)
			if ! tb_valid_domain "${_arg}"; then
				tb_send "${_ch}" "Неверный домен: ${_arg:-нет параметра}
Использование: /del example.com"
				return
			fi
			_out=$(sh /opt/apps/kvas/bin/kvas del "${_arg}" 2>&1 | tr -d '\033\r' | sed 's/\[[0-9][0-9;]*[a-zA-Z]//g; s/\[m//g' | tail -c 600)
			if grep -qe "${_arg}\$" /opt/etc/kvas.list 2>/dev/null; then
				tb_send "${_ch}" "Не найдено в списке: ${_arg}
${_out}"
			else
				tb_send "${_ch}" "Удалено: ${_arg}"
			fi
			;;
		/update)   tb_job "${_ch}" update ;;
		/rollback) tb_job "${_ch}" rollback ;;
		/*) tb_send "${_ch}" "Неизвестная команда: ${_cmd}
$(tb_help)" ;;
	esac
	return 0
}

while true; do
	if [ "$(tg_conf_get TG_ENABLED)" != "true" ] || [ -z "$(tg_conf_get TG_BOT_TOKEN)" ]; then
		sleep 15
		continue
	fi
	_tok=$(tg_conf_get TG_BOT_TOKEN)
	_me=$(tg_conf_get TG_CHAT_ID)
	_off=$(cat "${OFFF}" 2>/dev/null); [ -n "${_off}" ] || _off=0
	_resp=$(tg_curl "https://api.telegram.org/bot${_tok}/getUpdates?timeout=25&offset=${_off}&allowed_updates=%5B%22message%22%5D")
	if [ -z "${_resp}" ]; then
		sleep 5
		continue
	fi
	_max=$(printf '%s' "${_resp}" | jq -r '[.result[]?.update_id] | max // empty' 2>/dev/null)
	[ -n "${_max}" ] && echo $((_max + 1)) > "${OFFF}" 2>/dev/null
	printf '%s' "${_resp}" | jq -r '.result[]? | select((.message.text // "") != "") | [(.message.chat.id|tostring), (.message.from.username // ""), .message.text] | @tsv' 2>/dev/null |
	while IFS="$(printf '\t')" read -r _ch _un _tx; do
		[ -n "${_ch}" ] && [ -n "${_tx}" ] || continue
		# свежий chat_id для UI «Получить chat_id» (любой, кто написал боту)
		printf '%s\n@%s\n' "${_ch}" "${_un}" > "${LASTCHAT}" 2>/dev/null
		[ -n "${_me}" ] && [ "${_ch}" = "${_me}" ] || continue
		_tx=$(printf '%s' "${_tx}" | head -c 500)
		case "${_tx}" in
			/*) ;;
			*) continue ;;
		esac
		case "${_tx}" in
			*' '*) _cmd=${_tx%% *}; _arg=${_tx#* } ;;
			*)     _cmd=${_tx};     _arg="" ;;
		esac
		_cmd=$(printf '%s' "${_cmd}" | sed 's/@[^ ]*$//')
		_arg=$(printf '%s' "${_arg}" | awk '{print $1}')
		tb_reply "${_ch}" "${_cmd}" "${_arg}"
	done
	sleep 1
done
