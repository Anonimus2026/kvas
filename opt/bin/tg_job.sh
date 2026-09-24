#!/bin/sh
# Задачи бота KVAS с ответом в Telegram (P.8+).
# Копируется в /tmp: пакет перезаписывается opkg во время работы.
# Аргументы: $1=chat_id $2=mode [args...]
# modes: update|rollback|test|debug|init|site <iface> <site>|speed <iface>
. /opt/apps/kvas/bin/libs/tgq 2>/dev/null || exit 0

# friendly display name (same as bot tb_friendly)
tb_friendly() {
	case "$1" in
		Proxy21|t2s21|vless)    printf 'vless' ;;
		Proxy41|t2s41|hysteria) printf 'hysteria' ;;
		Proxy42|t2s42|awg)      printf 'AmneziaWG' ;;
		*) printf '%s' "$1" ;;
	esac
}

_ch="$1"; _mode="$2"; shift 2

tbj_send() { # $1=text — простая отправка без markup
	tg_send_msg "${_ch}" "$1"
}

tbj_send_long() { # $1=text — чанкинг ~3500
	tg_send_long "${_ch}" "$1"
}

tbj_strip() { tr -d '\033\r' | sed 's/\[[0-9][0-9;]*[a-zA-Z]//g; s/\[m//g'; }

# curl-опции для тоннеля — как manage.sh tunnel_test_site / tunnel_speed_test
tbj_curl_opt() { # $1=iface → echo опции curl
	case "$1" in
		Proxy21|t2s21|vless)    printf '%s' "-x socks5://127.0.0.1:1097" ;;
		Proxy41|t2s41|hysteria) printf '%s' "-x socks5://127.0.0.1:10808" ;;
		Proxy42|awg)           printf '%s' "-x socks5://127.0.0.1:10818" ;;
		*)
			_ent=$(grep "$1" /opt/etc/inface_equals 2>/dev/null | head -1 | cut -d'|' -f2)
			[ -z "${_ent}" ] && _ent="$1"
			printf '%s' "--interface ${_ent}"
			;;
	esac
}

case "${_mode}" in
	update|rollback)
		case "${_mode}" in
			update)   _args="";       _label="Обновление" ;;
			rollback) _args="rollback"; _label="Откат" ;;
		esac
		case "${_mode}" in
			update)   _feed='1\n' ;;
			rollback) _feed='1\n2\n' ;;
		esac
		_outf=/tmp/.tgjob.out.$$
		printf "${_feed}" | sh /opt/apps/kvas/bin/kvas upgrade ${_args} >"${_outf}" 2>&1
		_rc=$?
		_out=$(tbj_strip <"${_outf}" 2>/dev/null | tail -c 2500)
		rm -f "${_outf}"
		sh /opt/apps/kvas/bin/kvas monitor web stop >/dev/null 2>&1
		sleep 1
		sh /opt/apps/kvas/bin/kvas monitor web start >/dev/null 2>&1 &
		sleep 2
		tbj_send "${_label} завершено (код ${_rc}):
${_out:-нет вывода}"
		;;

	test)
		_outf=/tmp/.tgjob.out.$$
		sh /opt/apps/kvas/bin/kvas test >"${_outf}" 2>&1
		_rc=$?
		_out=$(tbj_strip <"${_outf}" 2>/dev/null | tail -c 3500)
		rm -f "${_outf}"
		tbj_send "Kvas test (код ${_rc}):
${_out:-нет вывода}"
		;;

	debug)
		_outf=/tmp/.tgjob.out.$$
		sh /opt/apps/kvas/bin/kvas debug >"${_outf}" 2>&1
		_rc=$?
		_out=$(tbj_strip <"${_outf}" 2>/dev/null)
		rm -f "${_outf}"
		tbj_send_long "Kvas debug (код ${_rc}):
${_out:-нет вывода}"
		;;

	init)
		_outf=/tmp/.tgjob.out.$$
		sh /opt/apps/kvas/bin/kvas init >"${_outf}" 2>&1
		_rc=$?
		_out=$(tbj_strip <"${_outf}" 2>/dev/null | tail -c 2500)
		rm -f "${_outf}"
		tbj_send "Перезагрузка KVAS (код ${_rc}):
${_out:-нет вывода}"
		;;

	site)
		_iface="$1"; _site="$2"
		[ -n "${_iface}" ] && [ -n "${_site}" ] || { tbj_send "site: нужны iface и site"; exit 1; }
		_opt=$(tbj_curl_opt "${_iface}")
		# shellcheck disable=SC2086
		_ip=$(curl -s --max-time 10 ${_opt} "https://2ip.io" 2>/dev/null)
		[ -z "${_ip}" ] && _ip=$(curl -s --max-time 15 ${_opt} "https://ifconfig.me" 2>/dev/null)
		echo "${_ip}" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' || _ip="нет ответа"
		# shellcheck disable=SC2086
		_http=$(curl -s --max-time 10 ${_opt} -o /dev/null -w '%{http_code}' "https://${_site}" 2>/dev/null)
		# shellcheck disable=SC2086
		_time=$(curl -s --max-time 10 ${_opt} -o /dev/null -w '%{time_total}' "https://${_site}" 2>/dev/null)
		[ -z "${_http}" ] && _http="000"
		[ -z "${_time}" ] && _time="0"
		_speed=0
		# shellcheck disable=SC2086
		_speed=$(curl -s --max-time 15 ${_opt} -o /dev/null -w '%{speed_download}' "https://speed.cloudflare.com/__down?bytes=1048576" 2>/dev/null)
		{ [ -z "${_speed}" ] || [ "${_speed}" = "0" ]; } && \
			# shellcheck disable=SC2086
			_speed=$(curl -s --max-time 15 ${_opt} -o /dev/null -w '%{speed_download}' "https://nbg1-speed.hetzner.com/1MB.bin" 2>/dev/null)
		[ -z "${_speed}" ] && _speed=0
		_speed=$(printf '%s' "${_speed}" | awk '{printf "%.0f", $1/1024}')
		tbj_send "Тест ${_site} через $(tb_friendly "${_iface}"):
IP: ${_ip}
HTTP: ${_http}
Отклик: ${_time} с
Скорость: ${_speed} КБ/с"
		;;

	speed)
		_iface="$1"
		[ -n "${_iface}" ] || { tbj_send "speed: нужен iface"; exit 1; }
		_opt=$(tbj_curl_opt "${_iface}")
		# shellcheck disable=SC2086
		_ip=$(curl -s --max-time 10 ${_opt} "https://2ip.io" 2>/dev/null)
		[ -z "${_ip}" ] && _ip="нет ответа"
		# shellcheck disable=SC2086
		_result=$(curl -s --max-time 60 ${_opt} -o /dev/null -w '%{speed_download} %{time_total}' "https://nbg1-speed.hetzner.com/100MB.bin" 2>/dev/null)
		_speed=$(printf '%s' "${_result}" | awk '{print $1}')
		_time=$(printf '%s' "${_result}" | awk '{print $2}')
		[ -z "${_speed}" ] && _speed=0
		[ -z "${_time}" ] && _time=0
		_speed=$(printf '%s' "${_speed}" | awk '{printf "%.0f", $1/1024}')
		tbj_send "Скорость входящего $(tb_friendly "${_iface}"):
IP: ${_ip}
100MB: ${_speed} КБ/с за ${_time} с"
		;;

	*)
		exit 1
		;;
esac
exit 0
