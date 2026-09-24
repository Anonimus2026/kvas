#!/bin/sh
# Интерактивный Telegram-бот KVAS (P.8+): long-poll, меню с кнопками, state-машина.
# Кнопки — только ASCII (busybox case + UTF-8 на роутере ненадёжен).
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

# singleton: убиваем ВСЕ чужие инстансы (старые после opkg иначе живут вечно)
_tb_kill_others() {
	for _p in $(ps 2>/dev/null | grep 'tg_bot\.sh' | grep -v grep | awk '{print $1}'); do
		[ "${_p}" = "$$" ] && continue
		kill "${_p}" 2>/dev/null
	done
}
_tb_kill_others

if [ -s "${PIDF}" ]; then
	_old=$(cat "${PIDF}" 2>/dev/null)
	[ -n "${_old}" ] && [ "${_old}" != "$$" ] && kill -0 "${_old}" 2>/dev/null && kill "${_old}" 2>/dev/null
fi
echo $$ > "${PIDF}" 2>/dev/null
trap '[ "$(cat "${PIDF}" 2>/dev/null)" = "$$" ] && rm -f "${PIDF}"' EXIT INT TERM HUP

tb_send() { tg_send_msg "$1" "$2" "$3"; }

tb_state() { head -n 1 "${STF}" 2>/dev/null; }
tb_state_set() { printf '%s\n' "$1" > "${STF}" 2>/dev/null; }
tb_state_clear() { rm -f "${STF}" 2>/dev/null; }
tb_payload() { _s=$(tb_state); printf '%s' "${_s#*|}"; }
tb_st() { _s=$(tb_state); printf '%s' "${_s%%|*}"; }

# reply_markup: {"keyboard":[[...]],"resize_keyboard":true}
# $1... — кнопки построчно (каждый аргумент = ряд из |)
tb_kb() {
	_rows=""
	for _r in "$@"; do
		_row=""
		_rest="${_r}"
		while [ -n "${_rest}" ]; do
			case "${_rest}" in
				*|*) _btn=${_rest%%|*}; _rest=${_rest#*|} ;;
				*)   _btn="${_rest}";  _rest="" ;;
			esac
			_row="${_row}${_row:+,}\"${_btn}\""
		done
		[ -n "${_row}" ] || continue
		_rows="${_rows}${_rows:+,}[${_row}]"
	done
	[ -n "${_rows}" ] || _rows="[[]]"
	printf '{"keyboard":[%s],"resize_keyboard":true}' "${_rows}"
}

KB_MAIN() { tb_kb "Kvas.list|Tags" "Diagnostics|Help"; }
KB_LIST() { tb_kb "Add domains|Delete domains" "Show list" "Back"; }
KB_ZK() { tb_kb "List tags" "Add to tunnel|Remove from tunnel" "Back"; }
KB_DIAG() { tb_kb "Kvas test|Kvas debug" "Site test|Speed test" "Restart KVAS" "Back"; }
KB_CANCEL() { tb_kb "Cancel"; }
KB_BACK() { tb_kb "Back"; }

tb_valid_domain() {
	case "$1" in
		''|*[!A-Za-z0-9.-]*|-*|.*|*..*|*.) return 1 ;;
	esac
	case "$1" in *.*) return 0 ;; *) return 1 ;; esac
}

tb_help() {
	printf '%s' "KVAS bot — menu and commands:
/menu — main menu (buttons)
/list — full protected list
/add <domains...> — add (multiple ok)
/del <domains...> — remove (multiple ok)
/status — version and tunnel state
/update — update KVAS
/rollback — rollback
Menu: Kvas.list, Tags, Diagnostics."
}

tb_status() {
	_v=$(sed -n 's/^APP_RELEASE=//p' /opt/etc/kvas.conf 2>/dev/null | head -1)
	_t=$(cat /opt/var/kvas/tg.tunnel.state 2>/dev/null)
	[ -n "${_t}" ] || _t="?"
	printf '%s' "KVAS build ${_v:-?}
Tunnel: ${_t}"
}

tb_job() { # $1=chat $2=mode [$3...] — из /tmp, чтобы opkg не перезаписал скрипт
	_jch="$1"; _jmode="$2"; shift 2
	case "${_jmode}" in
		update)   _label="Update" ;;
		rollback) _label="Rollback" ;;
		test)     _label="Kvas test" ;;
		debug)    _label="Kvas debug" ;;
		init)     _label="Restart KVAS" ;;
		site)     _label="Site test ($1 -> $2)" ;;
		speed)    _label="Inbound speed test ($1)" ;;
		*) return 1 ;;
	esac
	tb_send "${_jch}" "Starting: ${_label}… Result will be sent separately."
	_w=/tmp/.tgjob.$$
	if ! cp -f /opt/apps/kvas/bin/tg_job.sh "${_w}" 2>/dev/null; then
		tb_send "${_jch}" "Launch error: cannot prepare job"
		return 1
	fi
	( sh "${_w}" "${_jch}" "${_jmode}" "$@" >/dev/null 2>&1; rm -f "${_w}" ) &
}

# список тоннелей: cli|ent|desc из inface_equals
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

# динамическая клавиатура из строк stdin + «Back»
tb_kb_lines() {
	_rows=""
	while IFS= read -r _line; do
		[ -n "${_line}" ] || continue
		_esc=$(printf '%s' "${_line}" | sed 's/\\/\\\\/g; s/"/\\"/g')
		_rows="${_rows}${_rows:+,}[\"${_esc}\"]"
	done
	_rows="${_rows}${_rows:+,}[\"Back\"]"
	printf '{"keyboard":[%s],"resize_keyboard":true}' "${_rows}"
}

tb_show_main() {
	tb_state_clear
	tb_send "$1" "$(tb_help)" "$(KB_MAIN)"
}

tb_show_list_menu() {
	tb_state_set "list"
	tb_send "$1" "Kvas.list menu" "$(KB_LIST)"
}

tb_show_zk_menu() {
	tb_state_set "zk"
	tb_send "$1" "Tags menu" "$(KB_ZK)"
}

tb_show_diag_menu() {
	tb_state_set "diag"
	tb_send "$1" "Diagnostics menu" "$(KB_DIAG)"
}

tb_send_list() {
	_ch="$1"
	_f=/opt/etc/kvas.list
	if [ ! -s "${_f}" ]; then
		tb_send "${_ch}" "Protected list is empty" "$(KB_MAIN)"
		return
	fi
	_cnt=$(grep -c . "${_f}" 2>/dev/null); [ -n "${_cnt}" ] || _cnt=0
	tg_send_long "${_ch}" "Protected list: ${_cnt}
$(cat "${_f}")"
}

tb_bulk_add() {
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
	[ -n "${_ok}" ] || { tb_send "${_ch}" "No valid domains. Format: example.com foo.org"; return; }
	sh /opt/apps/kvas/bin/kvas add ${_ok} >/dev/null 2>&1
	_rep=""
	for _d in ${_ok}; do
		if grep -qxF "${_d}" /opt/etc/kvas.list 2>/dev/null; then
			_rep="${_rep}
+ ${_d}"
		else
			_rep="${_rep}
! ${_d} not added"
		fi
	done
	_msg="Added:${_rep}"
	[ -n "${_bad}" ] && _msg="${_msg}
Skipped (bad format):${_bad}"
	tb_send "${_ch}" "${_msg}" "$(KB_MAIN)"
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
	[ -n "${_ok}" ] || { tb_send "${_ch}" "No valid domains. Format: example.com foo.org"; return; }
	sh /opt/apps/kvas/bin/kvas del ${_ok} >/dev/null 2>&1
	_rep=""
	for _d in ${_ok}; do
		if grep -qxF "${_d}" /opt/etc/kvas.list 2>/dev/null; then
			_rep="${_rep}
! ${_d} still in list"
		else
			_rep="${_rep}
- ${_d}"
		fi
	done
	_msg="Removed:${_rep}"
	[ -n "${_bad}" ] && _msg="${_msg}
Skipped (bad format):${_bad}"
	tb_send "${_ch}" "${_msg}" "$(KB_MAIN)"
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
[${_tag}] ${_in}/${_tot} in tunnel"
	done <<EOF
$(grep -E '^\[.*\]$' "${_f}" 2>/dev/null | tr -d '[]')
EOF
	[ -n "${_full}" ] || _full=" (no sections)"
	tb_send "${_ch}" "Tags:${_full}" "$(KB_ZK)"
}

tb_reply_cmd() { # $1=chat $2=cmd $3=arg
	_ch="$1"; _cmd="$2"; _arg="$3"
	case "${_cmd}" in
		/menu|/start) tb_show_main "${_ch}" ;;
		/help)        tb_send "${_ch}" "$(tb_help)" "$(KB_MAIN)" ;;
		/status)      tb_send "${_ch}" "$(tb_status)" "$(KB_MAIN)" ;;
		/list)
			tb_send_list "${_ch}"
			tb_send "${_ch}" "Menu:" "$(KB_MAIN)"
			;;
		/add)
			[ -n "${_arg}" ] || { tb_send "${_ch}" "Usage: /add example.com foo.org" "$(KB_MAIN)"; return; }
			tb_bulk_add "${_ch}" "${_arg}"
			tb_send "${_ch}" "Menu:" "$(KB_MAIN)"
			;;
		/del)
			[ -n "${_arg}" ] || { tb_send "${_ch}" "Usage: /del example.com foo.org" "$(KB_MAIN)"; return; }
			tb_bulk_del "${_ch}" "${_arg}"
			tb_send "${_ch}" "Menu:" "$(KB_MAIN)"
			;;
		/update)   tb_job "${_ch}" update ;;
		/rollback) tb_job "${_ch}" rollback ;;
		/*) tb_send "${_ch}" "Unknown command: ${_cmd}
$(tb_help)" "$(KB_MAIN)" ;;
	esac
	return 0
}

# обработка текста (кнопка или ввод) с учётом state
tb_on_text() { # $1=chat $2=text
	_ch="$1"
	_tx=$(printf '%s' "$2" | tr -d '\r' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
	_st=$(tb_st)
	_pl=$(tb_payload)

	# глобальные кнопки — до state-машины (только ASCII-лейблы)
	case "${_tx}" in
		Help|/help)
			tb_send "${_ch}" "$(tb_help)" "$(KB_MAIN)"
			return
			;;
		Cancel|/menu|/start)
			tb_show_main "${_ch}"
			return
			;;
		Back)
			case "${_st}" in
				list_add|list_del) tb_show_list_menu "${_ch}" ;;
				zk_add|zk_del)     tb_show_zk_menu "${_ch}" ;;
				diag_site|diag_site_url|diag_speed) tb_show_diag_menu "${_ch}" ;;
				list|zk|diag)      tb_show_main "${_ch}" ;;
				*)                 tb_show_main "${_ch}" ;;
			esac
			return
			;;
		"Kvas.list"|*Kvas.list*)
			tb_show_list_menu "${_ch}"
			return
			;;
		Tags|*Tags*)
			tb_show_zk_menu "${_ch}"
			return
			;;
		Diagnostics|*Diagnostics*)
			tb_show_diag_menu "${_ch}"
			return
			;;
	esac

	case "${_st}" in
		list)
			case "${_tx}" in
				"Add domains")
					tb_state_set "list_add"
					tb_send "${_ch}" "Enter domains space-separated or one per line:" "$(KB_CANCEL)"
					return
					;;
				"Delete domains")
					tb_state_set "list_del"
					tb_send "${_ch}" "Enter domains to remove (space or lines):" "$(KB_CANCEL)"
					return
					;;
				"Show list")
					tb_send_list "${_ch}"
					tb_send "${_ch}" "List menu:" "$(KB_LIST)"
					return
					;;
				Back)
					tb_show_main "${_ch}"
					return
					;;
			esac
			;;
		list_add)
			case "${_tx}" in
				Back|Cancel) tb_show_list_menu "${_ch}"; return ;;
			esac
			tb_bulk_add "${_ch}" "${_tx}"
			tb_send "${_ch}" "List menu:" "$(KB_LIST)"
			tb_state_set "list"
			return
			;;
		list_del)
			case "${_tx}" in
				Back|Cancel) tb_show_list_menu "${_ch}"; return ;;
			esac
			tb_bulk_del "${_ch}" "${_tx}"
			tb_send "${_ch}" "List menu:" "$(KB_LIST)"
			tb_state_set "list"
			return
			;;
		zk)
			case "${_tx}" in
				"List tags")
					tb_zk_list "${_ch}"
					tb_send "${_ch}" "Tags menu:" "$(KB_ZK)"
					return
					;;
				"Add to tunnel")
					tb_state_set "zk_add"
					_lines=$(grep -E '^\[.*\]$' /opt/etc/tags.list 2>/dev/null | tr -d '[]')
					if [ -z "${_lines}" ]; then
						tb_send "${_ch}" "No tags in tags.list" "$(KB_ZK)"
						tb_state_set "zk"
						return
					fi
					tb_send "${_ch}" "Choose tag to add to tunnel:" "$(printf '%s\n' "${_lines}" | tb_kb_lines)"
					return
					;;
				"Remove from tunnel")
					tb_state_set "zk_del"
					_lines=$(grep -E '^\[.*\]$' /opt/etc/tags.list 2>/dev/null | tr -d '[]')
					if [ -z "${_lines}" ]; then
						tb_send "${_ch}" "No tags in tags.list" "$(KB_ZK)"
						tb_state_set "zk"
						return
					fi
					tb_send "${_ch}" "Choose tag to remove from tunnel:" "$(printf '%s\n' "${_lines}" | tb_kb_lines)"
					return
					;;
				Back)
					tb_show_main "${_ch}"
					return
					;;
			esac
			;;
		zk_add|zk_del)
			case "${_tx}" in
				Back|Cancel)
					tb_show_zk_menu "${_ch}"
					return
					;;
			esac
			if ! grep -qxF "[${_tx}]" /opt/etc/tags.list 2>/dev/null; then
				tb_send "${_ch}" "Tag '${_tx}' not found. Choose from list." "$(KB_BACK)"
				return
			fi
			if [ "${_st}" = "zk_add" ]; then
				sh /opt/apps/kvas/bin/kvas tags add-protect "${_tx}" >/dev/null 2>&1
				tb_send "${_ch}" "Added to tunnel: ${_tx}"
			else
				sh /opt/apps/kvas/bin/kvas tags del-protect "${_tx}" >/dev/null 2>&1
				tb_send "${_ch}" "Removed from tunnel: ${_tx}"
			fi
			tb_show_zk_menu "${_ch}"
			return
			;;
		diag)
			case "${_tx}" in
				"Kvas test")
					tb_job "${_ch}" test
					tb_send "${_ch}" "Diagnostics menu:" "$(KB_DIAG)"
					return
					;;
				"Kvas debug")
					tb_job "${_ch}" debug
					tb_send "${_ch}" "Diagnostics menu:" "$(KB_DIAG)"
					return
					;;
				"Site test")
					_lines=$(tb_tunnel_lines)
					if [ -z "${_lines}" ]; then
						tb_send "${_ch}" "No tunnels available" "$(KB_DIAG)"
						return
					fi
					tb_state_set "diag_site"
					tb_send "${_ch}" "Choose tunnel:" "$(printf '%s\n' "${_lines}" | tb_kb_lines)"
					return
					;;
				"Speed test")
					_lines=$(tb_tunnel_lines)
					if [ -z "${_lines}" ]; then
						tb_send "${_ch}" "No tunnels available" "$(KB_DIAG)"
						return
					fi
					tb_state_set "diag_speed"
					tb_send "${_ch}" "Choose tunnel:" "$(printf '%s\n' "${_lines}" | tb_kb_lines)"
					return
					;;
				"Restart KVAS")
					tb_job "${_ch}" init
					tb_send "${_ch}" "Diagnostics menu:" "$(KB_DIAG)"
					return
					;;
				Back)
					tb_show_main "${_ch}"
					return
					;;
			esac
			;;
		diag_site)
			case "${_tx}" in
				Back|Cancel) tb_show_diag_menu "${_ch}"; return ;;
			esac
			if ! printf '%s\n' "$(tb_tunnel_lines)" | grep -qxF "${_tx}"; then
				tb_send "${_ch}" "Tunnel '${_tx}' not found. Choose from list." "$(KB_BACK)"
				return
			fi
			tb_state_set "diag_site_url|${_tx}"
			tb_send "${_ch}" "Enter site (e.g. example.com):" "$(KB_CANCEL)"
			return
			;;
		diag_site_url)
			case "${_tx}" in
				Back|Cancel) tb_show_diag_menu "${_ch}"; return ;;
			esac
			_site=$(printf '%s' "${_tx}" | sed 's|^https\?://||; s|/.*||; s|[[:space:]]||g')
			if ! tb_valid_domain "${_site}"; then
				tb_send "${_ch}" "Invalid site: ${_tx}
Example: example.com" "$(KB_CANCEL)"
				return
			fi
			tb_job "${_ch}" site "${_pl}" "${_site}"
			tb_show_diag_menu "${_ch}"
			return
			;;
		diag_speed)
			case "${_tx}" in
				Back|Cancel) tb_show_diag_menu "${_ch}"; return ;;
			esac
			if ! printf '%s\n' "$(tb_tunnel_lines)" | grep -qxF "${_tx}"; then
				tb_send "${_ch}" "Tunnel '${_tx}' not found. Choose from list." "$(KB_BACK)"
				return
			fi
			tb_job "${_ch}" speed "${_tx}"
			tb_show_diag_menu "${_ch}"
			return
			;;
	esac

		case "${_tx}" in
			*)
				tb_send "${_ch}" "Unknown. Use menu or /help:" "$(KB_MAIN)"
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
		_tx=$(printf '%s' "${_tx}" | head -c 2000 | tr -d '\r')
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
