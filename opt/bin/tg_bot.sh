#!/bin/sh
# Интерактивный Telegram-бот KVAS (P.8+): long-poll, меню с кнопками, state-машина.
# Команды: /help /menu /status /list /add /del /update /rollback + кнопки меню.
# Реагирует только на TG_CHAT_ID при TG_ENABLED=true.
# Демон singleton; keepalive — cron.1min/tg_sender.
. /opt/apps/kvas/bin/libs/tgq 2>/dev/null || exit 0

export TG_CURL_MAX=30

PIDF=/opt/var/kvas/tg_bot.pid
OFFF=/opt/var/kvas/tg_bot.offset
LASTCHAT=/opt/var/kvas/tg_lastchat
STF=/opt/var/kvas/tg_bot.state
mkdir -p /opt/var/kvas 2>/dev/null
if [ -s "${PIDF}" ]; then
	_old=$(cat "${PIDF}" 2>/dev/null)
	[ -n "${_old}" ] && [ "${_old}" != "$$" ] && kill -0 "${_old}" 2>/dev/null && exit 0
fi
echo $$ > "${PIDF}" 2>/dev/null
# удаляем pid только если он всё ещё наш (гонка двух инстансов / postinst)
trap '[ "$(cat "${PIDF}" 2>/dev/null)" = "$$" ] && rm -f "${PIDF}"' EXIT INT TERM HUP

tb_send() { tg_send_msg "$1" "$2" "$3"; }

tb_state() { cat "${STF}" 2>/dev/null | head -n 1; }
tb_state_set() { printf '%s\n' "$1" > "${STF}" 2>/dev/null; }
tb_state_clear() { rm -f "${STF}" 2>/dev/null; }
# payload после | (для diag_site_url: имя тоннеля)
tb_payload() { tb_state | sed -n 's/^[^|]*|//p'; }
tb_st() { tb_state | sed -n 's/|.*//p'; }

# reply_markup: {"keyboard":[[...]],"resize_keyboard":true}
# $1... — кнопки построчно (каждый аргумент = ряд из |)
tb_kb() {
	_rows=""
	for _r in "$@"; do
		_row=$(printf '%s' "${_r}" | awk -F'|' '{printf "["; for(i=1;i<=NF;i++){printf "%s\"%s\"", (i>1?",":""), $i} printf "]"}')
		_rows="${_rows}${_rows:+,}${_row}"
	done
	printf '{"keyboard":[%s],"resize_keyboard":true}' "${_rows}"
}

KB_MAIN() { tb_kb "Работа с Kvas.list|Закваски" "Диагностика|Справка"; }
KB_LIST() { tb_kb "Добавить домены|Удалить домены" "Показать список" "Назад"; }
KB_ZK() { tb_kb "Список заквасок" "Добавить в тоннель|Убрать из тоннеля" "Назад"; }
KB_DIAG() { tb_kb "Kvas test|Kvas debug" "Тест тоннеля к сайту|Тест входящей скорости" "Перезагрузить KVAS" "Назад"; }
KB_CANCEL() { tb_kb "Отмена"; }
KB_BACK() { tb_kb "Назад"; }

tb_valid_domain() {
	case "$1" in
		''|*[!A-Za-z0-9.-]*|-*|.*|*..*|*.) return 1 ;;
	esac
	case "$1" in *.*) return 0 ;; *) return 1 ;; esac
}

tb_strip() { tr -d '\033\r' | sed 's/\[[0-9][0-9;]*[a-zA-Z]//g; s/\[m//g'; }

tb_help() {
	printf '%s' "KVAS бот — меню и команды:
/menu — главное меню (кнопки)
/list — весь защищённый список
/add <домены...> — добавить (можно несколько)
/del <домены...> — удалить (можно несколько)
/status — версия и состояние туннеля
/update — обновить KVAS
/rollback — откат
Меню: работа со списком, закваски, диагностика."
}

tb_status() {
	_v=$(sed -n 's/^APP_RELEASE=//p' /opt/etc/kvas.conf 2>/dev/null | head -1)
	_t=$(cat /opt/var/kvas/tg.tunnel.state 2>/dev/null)
	[ -n "${_t}" ] || _t="?"
	printf '%s' "KVAS сборка ${_v:-?}
Туннель: ${_t}"
}

tb_job() { # $1=chat $2=mode [$3...] — из /tmp, чтобы opkg не перезаписал скрипт
	_jch="$1"; _jmode="$2"; shift 2
	case "${_jmode}" in
		update)   _label="Обновление" ;;
		rollback) _label="Откат" ;;
		test)     _label="Kvas test" ;;
		debug)    _label="Kvas debug" ;;
		init)     _label="Перезагрузка KVAS" ;;
		site)     _label="Тест тоннеля ($1 → $2)" ;;
		speed)    _label="Тест входящей скорости ($1)" ;;
		*) return 1 ;;
	esac
	tb_send "${_jch}" "Запускаю: ${_label}… Результат пришлю отдельно."
	_w=/tmp/.tgjob.$$
	if ! cp -f /opt/apps/kvas/bin/tg_job.sh "${_w}" 2>/dev/null; then
		tb_send "${_jch}" "Ошибка запуска: не удалось подготовить задачу"
		return 1
	fi
	( sh "${_w}" "${_jch}" "${_jmode}" "$@" >/dev/null 2>&1; rm -f "${_w}" ) &
}

# список тоннелей: cli|ent|desc из inface_equals (как manage.sh vpn_interfaces)
tb_tunnel_lines() {
	_seen=""
	while IFS='|' read -r _cli _ent _desc _rest; do
		[ -n "${_ent}" ] && [ -n "${_desc}" ] || continue
		case "${_seen}" in *"|${_ent}|"*) continue ;; esac
		_seen="${_seen}|${_ent}|"
		case "${_ent}" in
			t2s*|ezcfg*) ;;
			*) ip link show "${_ent}" 2>/dev/null | grep -q '<' || continue ;;
		esac
		printf '%s\n' "${_cli}"
	done < /opt/etc/inface_equals 2>/dev/null
}

# динамическая клавиатура из строк stdin + «Назад»
tb_kb_lines() {
	_rows=""
	while IFS= read -r _line; do
		[ -n "${_line}" ] || continue
		_esc=$(printf '%s' "${_line}" | sed 's/\\/\\\\/g; s/"/\\"/g')
		_rows="${_rows}${_rows:+,}[\"${_esc}\"]"
	done
	_rows="${_rows}${_rows:+,}[\"Назад\"]"
	printf '{"keyboard":[%s],"resize_keyboard":true}' "${_rows}"
}

tb_show_main() {
	tb_state_clear
	tb_send "$1" "$(tb_help)" "$(KB_MAIN)"
}

tb_show_list_menu() {
	tb_state_set "list"
	tb_send "$1" "Работа с Kvas.list" "$(KB_LIST)"
}

tb_show_zk_menu() {
	tb_state_set "zk"
	tb_send "$1" "Закваски" "$(KB_ZK)"
}

tb_show_diag_menu() {
	tb_state_set "diag"
	tb_send "$1" "Диагностика" "$(KB_DIAG)"
}

# полный список с чанкингом ~3500
tb_send_list() {
	_ch="$1"
	_f=/opt/etc/kvas.list
	if [ ! -s "${_f}" ]; then
		tb_send "${_ch}" "Защищённый список пуст"
		return
	fi
	_cnt=$(grep -c . "${_f}" 2>/dev/null); [ -n "${_cnt}" ] || _cnt=0
	tg_send_long "${_ch}" "Защищённый список: ${_cnt} шт
$(cat "${_f}")"
}

# bulk add: несколько доменов через пробел/перенос
tb_bulk_add() { # $1=chat $2=текст
	_ch="$1"
	_raw=$(printf '%s' "$2" | tr '\n\r\t' '   ')
	_ok=""; _bad=""
	for _d in ${_raw}; do
		if tb_valid_domain "${_d}"; then
			_ok="${_ok} ${_d}"
		else
			_bad="${_bad} ${_d}"
		fi
	done
	[ -n "${_ok}" ] || { tb_send "${_ch}" "Нет корректных доменов. Ввод: example.com foo.org"; return; }
	sh /opt/apps/kvas/bin/kvas add ${_ok} >/dev/null 2>&1
	_rep=""
	for _d in ${_ok}; do
		if grep -qxF "${_d}" /opt/etc/kvas.list 2>/dev/null; then
			_rep="${_rep}
+ ${_d}"
		else
			_rep="${_rep}
! ${_d} — не добавлен"
		fi
	done
	_msg="Добавлено:${_rep}"
	[ -n "${_bad}" ] && _msg="${_msg}
Пропущено (неверный формат):${_bad}"
	tb_send "${_ch}" "${_msg}"
}

tb_bulk_del() {
	_ch="$1"
	_raw=$(printf '%s' "$2" | tr '\n\r\t' '   ')
	_ok=""; _bad=""
	for _d in ${_raw}; do
		if tb_valid_domain "${_d}"; then
			_ok="${_ok} ${_d}"
		else
			_bad="${_bad} ${_d}"
		fi
	done
	[ -n "${_ok}" ] || { tb_send "${_ch}" "Нет корректных доменов. Ввод: example.com foo.org"; return; }
	sh /opt/apps/kvas/bin/kvas del ${_ok} >/dev/null 2>&1
	_rep=""
	for _d in ${_ok}; do
		if grep -qxF "${_d}" /opt/etc/kvas.list 2>/dev/null; then
			_rep="${_rep}
! ${_d} — остался в списке"
		else
			_rep="${_rep}
- ${_d}"
		fi
	done
	_msg="Удалено:${_rep}"
	[ -n "${_bad}" ] && _msg="${_msg}
Пропущено (неверный формат):${_bad}"
	tb_send "${_ch}" "${_msg}"
}

tb_zk_list() {
	_ch="$1"
	_f=/opt/etc/tags.list
	_full=""
	while IFS= read -r _tag; do
		[ -n "${_tag}" ] || continue
		_tags=$(awk -v s="${_tag}" '$0=="["s"]"{f=1;next} /^\[.*\]$/{f=0} f && $0!~/^#/ && NF{print $1}' "${_f}" 2>/dev/null)
		_tot=0; _in=0
		for _d in ${_tags}; do
			_tot=$((_tot + 1))
			grep -qxF "${_d}" /opt/etc/kvas.list 2>/dev/null && _in=$((_in + 1))
		done
		_full="${_full}
[${_tag}] ${_in}/${_tot} в тоннеле"
	done <<EOF
$(grep -E '^\[.*\]$' "${_f}" 2>/dev/null | tr -d '[]')
EOF
	[ -n "${_full}" ] || _full=" (нет секций)"
	tb_send "${_ch}" "Закваски:${_full}"
}

tb_reply_cmd() { # $1=chat $2=cmd $3=arg (полный, не обрезан)
	_ch="$1"; _cmd="$2"; _arg="$3"
	case "${_cmd}" in
		/menu|/start) tb_show_main "${_ch}" ;;
		/help)        tb_send "${_ch}" "$(tb_help)" "$(KB_MAIN)" ;;
		/status)      tb_send "${_ch}" "$(tb_status)" ;;
		/list)        tb_send_list "${_ch}" ;;
		/add)
			[ -n "${_arg}" ] || { tb_send "${_ch}" "Использование: /add example.com foo.org"; return; }
			tb_bulk_add "${_ch}" "${_arg}"
			;;
		/del)
			[ -n "${_arg}" ] || { tb_send "${_ch}" "Использование: /del example.com foo.org"; return; }
			tb_bulk_del "${_ch}" "${_arg}"
			;;
		/update)   tb_job "${_ch}" update ;;
		/rollback) tb_job "${_ch}" rollback ;;
		/*) tb_send "${_ch}" "Неизвестная команда: ${_cmd}
$(tb_help)" "$(KB_MAIN)" ;;
	esac
	return 0
}

# обработка текста (кнопка или ввод) с учётом state
tb_on_text() { # $1=chat $2=текст
	_ch="$1"; _tx="$2"
	_st=$(tb_st)
	_pl=$(tb_payload)

	case "${_tx}" in
		Справка|Помощь)
			tb_send "${_ch}" "$(tb_help)" "$(KB_MAIN)"
			return
			;;
		Отмена)
			tb_show_main "${_ch}"
			return
			;;
	esac

	case "${_st}" in
		list)
			case "${_tx}" in
				"Добавить домены")
					tb_state_set "list_add"
					tb_send "${_ch}" "Введите домены через пробел или списком (по одному в строке):" "$(KB_CANCEL)"
					return
					;;
				"Удалить домены")
					tb_state_set "list_del"
					tb_send "${_ch}" "Введите домены для удаления (через пробел или списком):" "$(KB_CANCEL)"
					return
					;;
				"Показать список")
					tb_send_list "${_ch}"
					tb_send "${_ch}" "Меню списка:" "$(KB_LIST)"
					return
					;;
				Назад)
					tb_show_main "${_ch}"
					return
					;;
			esac
			;;
		list_add)
			case "${_tx}" in
				Назад) tb_show_list_menu "${_ch}"; return ;;
			esac
			tb_bulk_add "${_ch}" "${_tx}"
			tb_send "${_ch}" "Меню списка:" "$(KB_LIST)"
			tb_state_set "list"
			return
			;;
		list_del)
			case "${_tx}" in
				Назад) tb_show_list_menu "${_ch}"; return ;;
			esac
			tb_bulk_del "${_ch}" "${_tx}"
			tb_send "${_ch}" "Меню списка:" "$(KB_LIST)"
			tb_state_set "list"
			return
			;;
		zk)
			case "${_tx}" in
				"Список заквасок")
					tb_zk_list "${_ch}"
					tb_send "${_ch}" "Меню заквасок:" "$(KB_ZK)"
					return
					;;
				"Добавить в тоннель")
					tb_state_set "zk_add"
					_lines=$(grep -E '^\[.*\]$' /opt/etc/tags.list 2>/dev/null | tr -d '[]')
					if [ -z "${_lines}" ]; then
						tb_send "${_ch}" "Нет заквасок в tags.list" "$(KB_ZK)"
						tb_state_set "zk"
						return
					fi
					tb_send "${_ch}" "Выберите закваску для добавления в тоннель:" "$(printf '%s\n' "${_lines}" | tb_kb_lines)"
					return
					;;
				"Убрать из тоннеля")
					tb_state_set "zk_del"
					_lines=$(grep -E '^\[.*\]$' /opt/etc/tags.list 2>/dev/null | tr -d '[]')
					if [ -z "${_lines}" ]; then
						tb_send "${_ch}" "Нет заквасок в tags.list" "$(KB_ZK)"
						tb_state_set "zk"
						return
					fi
					tb_send "${_ch}" "Выберите закваску для удаления из тоннеля:" "$(printf '%s\n' "${_lines}" | tb_kb_lines)"
					return
					;;
				Назад)
					tb_show_main "${_ch}"
					return
					;;
			esac
			;;
		zk_add|zk_del)
			case "${_tx}" in
				Назад)
					tb_show_zk_menu "${_ch}"
					return
					;;
			esac
			if ! grep -qxF "[${_tx}]" /opt/etc/tags.list 2>/dev/null; then
				tb_send "${_ch}" "Закваска «${_tx}» не найдена. Выберите из списка." "$(KB_BACK)"
				return
			fi
			if [ "${_st}" = "zk_add" ]; then
				sh /opt/apps/kvas/bin/kvas tags add-protect "${_tx}" >/dev/null 2>&1
				tb_send "${_ch}" "Добавлено в тоннель: ${_tx}"
			else
				sh /opt/apps/kvas/bin/kvas tags del-protect "${_tx}" >/dev/null 2>&1
				tb_send "${_ch}" "Убрано из тоннеля: ${_tx}"
			fi
			tb_show_zk_menu "${_ch}"
			return
			;;
		diag)
			case "${_tx}" in
				"Kvas test")
					tb_job "${_ch}" test
					tb_send "${_ch}" "Меню диагностики:" "$(KB_DIAG)"
					return
					;;
				"Kvas debug")
					tb_job "${_ch}" debug
					tb_send "${_ch}" "Меню диагностики:" "$(KB_DIAG)"
					return
					;;
				"Тест тоннеля к сайту")
					_lines=$(tb_tunnel_lines)
					if [ -z "${_lines}" ]; then
						tb_send "${_ch}" "Нет доступных тоннелей" "$(KB_DIAG)"
						return
					fi
					tb_state_set "diag_site"
					tb_send "${_ch}" "Выберите тоннель:" "$(printf '%s\n' "${_lines}" | tb_kb_lines)"
					return
					;;
				"Тест входящей скорости")
					_lines=$(tb_tunnel_lines)
					if [ -z "${_lines}" ]; then
						tb_send "${_ch}" "Нет доступных тоннелей" "$(KB_DIAG)"
						return
					fi
					tb_state_set "diag_speed"
					tb_send "${_ch}" "Выберите тоннель:" "$(printf '%s\n' "${_lines}" | tb_kb_lines)"
					return
					;;
				"Перезагрузить KVAS"|"Перезагрузить Kvas")
					tb_job "${_ch}" init
					tb_send "${_ch}" "Меню диагностики:" "$(KB_DIAG)"
					return
					;;
				Назад)
					tb_show_main "${_ch}"
					return
					;;
			esac
			;;
		diag_site)
			case "${_tx}" in
				Назад) tb_show_diag_menu "${_ch}"; return ;;
			esac
			if ! printf '%s\n' "$(tb_tunnel_lines)" | grep -qxF "${_tx}"; then
				tb_send "${_ch}" "Тоннель «${_tx}» не найден. Выберите из списка." "$(KB_BACK)"
				return
			fi
			tb_state_set "diag_site_url|${_tx}"
			tb_send "${_ch}" "Укажите сайт (например example.com):" "$(KB_CANCEL)"
			return
			;;
		diag_site_url)
			case "${_tx}" in
				Назад) tb_show_diag_menu "${_ch}"; return ;;
			esac
			_site=$(printf '%s' "${_tx}" | sed 's|^https\?://||; s|/.*||; s|[[:space:]]||g')
			if ! tb_valid_domain "${_site}"; then
				tb_send "${_ch}" "Неверный сайт: ${_tx}
Пример: example.com" "$(KB_CANCEL)"
				return
			fi
			tb_job "${_ch}" site "${_pl}" "${_site}"
			tb_show_diag_menu "${_ch}"
			return
			;;
		diag_speed)
			case "${_tx}" in
				Назад) tb_show_diag_menu "${_ch}"; return ;;
			esac
			if ! printf '%s\n' "$(tb_tunnel_lines)" | grep -qxF "${_tx}"; then
				tb_send "${_ch}" "Тоннель «${_tx}» не найден. Выберите из списка." "$(KB_BACK)"
				return
			fi
			tb_job "${_ch}" speed "${_tx}"
			tb_show_diag_menu "${_ch}"
			return
			;;
	esac

	case "${_tx}" in
		"Работа с Kvas.list")
			tb_show_list_menu "${_ch}"
			;;
		Закваски)
			tb_show_zk_menu "${_ch}"
			;;
		Диагностика)
			tb_show_diag_menu "${_ch}"
			;;
		Назад)
			tb_show_main "${_ch}"
			;;
		*)
			tb_send "${_ch}" "Не понял. Используйте меню или /help:" "$(KB_MAIN)"
			;;
	esac
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
		printf '%s\n@%s\n' "${_ch}" "${_un}" > "${LASTCHAT}" 2>/dev/null
		[ -n "${_me}" ] && [ "${_ch}" = "${_me}" ] || continue
		_tx=$(printf '%s' "${_tx}" | head -c 2000)
		case "${_tx}" in
			/*)
				_cmd=${_tx%% *}
				if [ "${_tx}" = "${_cmd}" ]; then
					_arg=""
				else
					_arg=${_tx#* }
				fi
				_cmd=$(printf '%s' "${_cmd}" | sed 's/@[^ ]*$//')
				tb_reply_cmd "${_ch}" "${_cmd}" "${_arg}"
				;;
			*)
				tb_on_text "${_ch}" "${_tx}"
				;;
		esac
	done
	sleep 1
done
