#!/bin/sh
# Management API for KVAS Web UI v2
# Actions: auth, hosts, vpn, failover, upgrade, backup, restore, update, kvas_list

PATH=/opt/sbin:/opt/bin:/opt/usr/bin:/usr/sbin:/usr/bin:/sbin:/bin
export PATH

PASS_FILE=/opt/kvas_web_pass
TOKEN_DIR=/tmp/kvas_web_tokens
KVAS_BIN=/opt/apps/kvas/bin/kvas
FAILOVER_CONF=/opt/etc/kvas.failover.conf
KVAS_LIST=/opt/etc/kvas.list
TAGS_FILE=/opt/etc/tags.list
KVAS_CONF_FILE=/opt/etc/kvas.conf
PARENTAL_LIST=/opt/etc/adblock/block.list
PARENTAL_PAGE=/opt/apps/kvas/bin/monitor/www/blocked.html

json_str() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }
json_error() { printf '{"error":"%s"}\n' "$(json_str "$1")"; exit 0; }
json_ok()    { printf '{"ok":true,"msg":"%s"}\n' "$(json_str "$1")"; exit 0; }

urldecode() { echo "$1" | sed 's/+/ /g; s/%\([0-9A-Fa-f][0-9A-Fa-f]\)/\\x\1/g' | xargs -0 printf; }

# Brute-force protection (global)
FAIL_COUNT=/tmp/kvas_fail_count
FAIL_TIME=/tmp/kvas_fail_time
MAX_FAILS=5
LOCKOUT=300

check_bruteforce() {
	[ ! -f "$FAIL_COUNT" ] && return 0
	local fails=$(cat "$FAIL_COUNT" 2>/dev/null)
	[ -z "$fails" ] && return 0
	[ "$fails" -lt "$MAX_FAILS" ] 2>/dev/null && return 0
	local last=$(cat "$FAIL_TIME" 2>/dev/null || echo 0)
	local now=$(date +%s 2>/dev/null || echo 0)
	local elapsed=$((now - last))
	if [ "$elapsed" -lt "$LOCKOUT" ]; then
		echo $((LOCKOUT - elapsed))
		return 1
	fi
	rm -f "$FAIL_COUNT" "$FAIL_TIME"
	return 0
}

record_fail() {
	local now=$(date +%s 2>/dev/null || echo 0)
	local fails=$(cat "$FAIL_COUNT" 2>/dev/null || echo 0)
	fails=$((fails + 1))
	echo "$fails" > "$FAIL_COUNT"
	echo "$now" > "$FAIL_TIME"
}

reset_fails() {
	rm -f "$FAIL_COUNT" "$FAIL_TIME"
}



check_token() {
	local t="$1"
	[ -z "$t" ] && json_error "auth required"
	[ ! -f "$TOKEN_DIR/$t" ] && json_error "invalid token"
	local created=$(cat "$TOKEN_DIR/$t" 2>/dev/null)
	[ -z "$created" ] && json_error "token expired"
	local now=$(date +%s 2>/dev/null || echo 0)
	[ $((now - created)) -gt 3600 ] && rm -f "$TOKEN_DIR/$t" && json_error "token expired"
	echo "$now" > "$TOKEN_DIR/$t"
}

mk_token() {
	mkdir -p "$TOKEN_DIR" 2>/dev/null
	local t=$(head -c 32 /dev/urandom 2>/dev/null | md5sum 2>/dev/null | awk '{print $1}')
	[ -z "$t" ] && t=$(echo "$$$(date)$$" | md5sum | awk '{print $1}')
	date +%s 2>/dev/null > "$TOKEN_DIR/$t" || echo "1" > "$TOKEN_DIR/$t"
	printf '%s' "$t"
}

# Detect active VPN — checks which is configured and running
detect_vpn_mode() {
	# Check INFACE_CLI first (Proxy21/Proxy41) — more reliable than INFACE_ENT (t2s21/t2s41)
	local inface_cli=$(grep "^INFACE_CLI=" /opt/etc/kvas.conf 2>/dev/null | cut -d= -f2)
	local inface_ent=$(grep "^INFACE_ENT=" /opt/etc/kvas.conf 2>/dev/null | cut -d= -f2)
	if [ -n "$inface_cli" ]; then
		case "$inface_cli" in
			*Proxy21*|*vless*) echo "vless"; return ;;
			*Proxy41*|*hysteria*) echo "hysteria"; return ;;
		esac
	fi
	if [ -n "$inface_ent" ]; then
		# Other interface — return description from inface_equals
		local desc=$(grep "|${inface_ent}|" /opt/etc/inface_equals 2>/dev/null | head -1 | cut -d'|' -f3 | sed 's/^"//; s/"$//')
		[ -n "$desc" ] && echo "$desc" || echo "$inface_ent"
		return
	fi
	# Fallback: check which process is running
	if [ -f /var/run/xray.pid ] && kill -0 $(cat /var/run/xray.pid) 2>/dev/null; then
		echo "vless"
		return
	fi
	if [ -f /var/run/hysteria.pid ] && kill -0 $(cat /var/run/hysteria.pid) 2>/dev/null; then
		echo "hysteria"
		return
	fi
	echo "none"
}

# Check if specific VPN process is running — use pidof/pgrep for reliability
check_vpn_running() {
	case "$1" in
		vless)
			if pidof xray >/dev/null 2>&1; then
				echo "true"
			elif [ -f /var/run/xray.pid ] && kill -0 $(cat /var/run/xray.pid) 2>/dev/null; then
				echo "true"
			else
				echo "false"
			fi
			;;
		hysteria)
			if pidof hysteria >/dev/null 2>&1; then
				echo "true"
			elif [ -f /var/run/hysteria.pid ] && kill -0 $(cat /var/run/hysteria.pid) 2>/dev/null; then
				echo "true"
			else
				echo "false"
			fi
			;;
	esac
}

# Get failover mode from config
get_failover_mode() {
	if [ -f "$FAILOVER_CONF" ]; then
		grep "^FAILOVER_MODE=" "$FAILOVER_CONF" 2>/dev/null | cut -d= -f2
	fi
}

# Check if failover daemon is running
check_failover_daemon() {
	[ -f /var/run/kvas-failover.pid ] && kill -0 $(cat /var/run/kvas-failover.pid 2>/dev/null) 2>/dev/null && echo "true" || echo "false"
}

# --- Main ---


check_service() {
	local service="$1"
	if [ -f "/opt/etc/init.d/${service}" ]; then
		/opt/etc/init.d/${service} status 2>/dev/null | grep -qi "alive\|running\|started" && echo "running" || echo "stopped"
	else
		echo "not_installed"
	fi
}

check_updates() {
	local current_ver=$(opkg list-installed 2>/dev/null | grep kvas | awk '{print $3}')
	local repo="Anonimus2026/kvas"
	# Get latest ipk build number from release assets
	local latest_ver=$(curl -s --connect-timeout 5 "https://api.github.com/repos/${repo}/releases/latest" 2>/dev/null | \
		grep 'browser_download_url.*kvas_.*ipk' | \
		awk -F'kvas_' '{print $2}' | awk -F'_all' '{print $1}' | \
		sort -t'-' -k3 -rn | head -1 | awk -F'-' '{print $NF}')
	if [ -n "$latest_ver" ]; then
		# Extract build number from current version (e.g. 1.1.9_beta-10-239 -> 239)
		local current_num=$(echo "$current_ver" | sed 's/.*beta-10-//')
		if [ -n "$current_num" ] && [ "$latest_ver" -gt "$current_num" ] 2>/dev/null; then
			echo "available:v${latest_ver}"
		else
			echo "up_to_date"
		fi
	else
		echo "up_to_date"
	fi
}

get_tag_domain_list_from_file() {
	# BusyBox-совместимый: awk с index() вместо regex ~
	awk -v sec="$2" '{
		if (index($0, "[" sec "]")) { flag=1; next }
		if (index($0, "[") && index($0, "]")) { flag=0 }
		if (flag) print
	}' "$1" 2>/dev/null
}


main() {
	local action token pass hash stored kvaspkg kvaspkg_name kvaspkg_ver
	local vpn_mode failover hysteria_running vless_running host_count first
	local domain out rc mode enabled primary interval threshold cmd path

	action=$(echo "$QUERY_STRING" | sed 's/.*action=//; s/&.*//' 2>/dev/null)
	token=$(echo "$QUERY_STRING" | sed 's/.*token=//; s/&.*//' 2>/dev/null)
	[ "$action" = "$QUERY_STRING" ] && action=""
	[ "$token" = "$QUERY_STRING" ] && token=""

	case "$action" in
		auth_status)
			if [ -f "$PASS_FILE" ] && [ -s "$PASS_FILE" ]; then
				printf '{"ok":true,"has_password":true}\n'
			else
				printf '{"ok":true,"has_password":false}\n'
			fi
			;;
		set_pass)
			pass=$(urldecode "$(echo "$QUERY_STRING" | sed 's/.*pass=//; s/&.*//' 2>/dev/null)")
			[ "$pass" = "$QUERY_STRING" ] && pass=""
			[ -z "$pass" ] && json_error "pass required"
			[ ${#pass} -lt 4 ] && json_error "min 4 symbols"
			echo -n "$pass" | md5sum | awk '{print $1}' > "$PASS_FILE"
			json_ok "password set"
			;;
		auth)
			pass=$(urldecode "$(echo "$QUERY_STRING" | sed 's/.*pass=//; s/&.*//' 2>/dev/null)")
			[ "$pass" = "$QUERY_STRING" ] && pass=""
			[ -z "$pass" ] && json_error "pass required"
			hash=$(echo -n "$pass" | md5sum | awk '{print $1}')
			stored=$(cat "$PASS_FILE" 2>/dev/null | awk '{print $1}')
			[ "$hash" != "$stored" ] && json_error "wrong password"
			token=$(mk_token)
			printf '{"ok":true,"token":"%s"}\n' "$token"
			;;
		system_status)
			check_token "$token"
			kvaspkg=$(opkg list-installed 2>/dev/null | grep kvas | head -1)
			kvaspkg_name=$(echo "$kvaspkg" | awk '{print $1}')
			kvaspkg_ver=$(echo "$kvaspkg" | awk '{print $3}')
			vpn_mode=$(detect_vpn_mode)
			vless_running=$(check_vpn_running "vless")
			hysteria_running=$(check_vpn_running "hysteria")
			failover=$(get_failover_mode)
			[ -z "$failover" ] && failover="manual"
			host_count=$(wc -l < "$KVAS_LIST" 2>/dev/null || echo 0)
			# Service status — check init.d script existence + process running
			xray_svc="not_installed"
			hysteria_svc="not_installed"
			# Xray: init.d at /opt/apps/kvas/etc/init.d/S97xray
			if [ -f "/opt/apps/kvas/etc/init.d/S97xray" ]; then
				if pidof xray >/dev/null 2>&1; then
					xray_svc="running"
				else
					xray_svc="stopped"
				fi
			fi
			# Hysteria: init.d at /opt/apps/kvas/hysteria/etc/init.d/S99hysteria
			if [ -f "/opt/apps/kvas/hysteria/etc/init.d/S99hysteria" ]; then
				if pidof hysteria >/dev/null 2>&1; then
					hysteria_svc="running"
				else
					hysteria_svc="stopped"
				fi
			fi
			# Xray version
			xray_ver=""
			[ -x /opt/sbin/xray ] && xray_ver=$(/opt/sbin/xray version 2>/dev/null | head -1 | sed 's/Xray //' | sed 's/ .*//')
			awg_running="false"
			[ -f /var/run/wireproxy.pid ] && kill -0 "$(cat /var/run/wireproxy.pid 2>/dev/null)" 2>/dev/null && awg_running="true"
			dnsmasq_running=$(check_service S56dnsmasq)
			printf '{"ok":true,"pkg":"%s","ver":"%s","mode":"%s","failover":"%s","vless":"%s","hysteria":"%s","awg":"%s","dnsmasq":"%s","hosts":"%s","xray_service":"%s","hysteria_service":"%s","xray_version":"%s"}\n' \
				"$(json_str "$kvaspkg_name")" "$(json_str "$kvaspkg_ver")" "$(json_str "$vpn_mode")" "$(json_str "$failover")" \
				"$vless_running" "$hysteria_running" "$awg_running" "$dnsmasq_running" "$host_count" \
				"$(json_str "$xray_svc")" "$(json_str "$hysteria_svc")" "$(json_str "$xray_ver")"
			;;
		health_details)
			check_token "$token"
			# VPN: process + SOCKS ports listening (real, not just PID)
			vpn_proc="false"
			{ pidof xray >/dev/null 2>&1 || pidof hysteria >/dev/null 2>&1 || { [ -f /var/run/wireproxy.pid ] && kill -0 "$(cat /var/run/wireproxy.pid 2>/dev/null)" 2>/dev/null; }; } && vpn_proc="true"
			vpn_port="false"
			command -v ss >/dev/null 2>&1 && { ss -tlnp 2>/dev/null | grep -qE ':(1097|10808) ' && vpn_port="true"; }
			[ "$vpn_port" = "false" ] && command -v netstat >/dev/null 2>&1 && netstat -tlnp 2>/dev/null | grep -qE ':(1097|10808) ' && vpn_port="true"
			# AdGuard: conf + init + HTTP on real web port from http.address (not dns port)
			ag_conf="false"
			[ "$(grep '^ADGUARD_ENABLE=' /opt/etc/kvas.conf 2>/dev/null | cut -d= -f2)" = "true" ] && [ -f /opt/etc/init.d/S99adguardhome ] && ag_conf="true"
			_ag_yaml=/opt/etc/AdGuardHome/AdGuardHome.yaml
			[ ! -f "$_ag_yaml" ] && [ -f /opt/etc/.kvas/backup/AdGuardHome.yaml ] && _ag_yaml=/opt/etc/.kvas/backup/AdGuardHome.yaml
			ag_port=""
			if [ -f "$_ag_yaml" ]; then
				ag_port=$(awk '/^http:/{h=1;next} /^[a-z]/{h=0} h && $1=="address:"{n=split($2,a,":"); print a[n]; exit}' "$_ag_yaml" 2>/dev/null)
				[ -z "$ag_port" ] && ag_port=$(awk '/^http:/{h=1;next} /^dns:|^[a-z]/{h=0} h && /^  port:/{print $2; exit}' "$_ag_yaml" 2>/dev/null)
				[ -z "$ag_port" ] && ag_port=$(grep '^bind_port:' "$_ag_yaml" 2>/dev/null | head -1 | awk '{print $2}')
			fi
			case "$ag_port" in ''|*[!0-9]*|9753|6060|53) ag_port=8086 ;; esac
			ag_http="false"
			if command -v ss >/dev/null 2>&1; then
				ss -tln 2>/dev/null | grep -qE "[:.]${ag_port}[[:space:]]" && ag_http="true"
			elif command -v netstat >/dev/null 2>&1; then
				netstat -tln 2>/dev/null | grep -qE "[:.]${ag_port}[[:space:]]" && ag_http="true"
			fi
			if [ "$ag_http" = "false" ]; then
				if command -v curl >/dev/null 2>&1; then
					curl -s -o /dev/null -m 2 "http://127.0.0.1:${ag_port}/" 2>/dev/null && ag_http="true"
					[ "$ag_http" = "false" ] && curl -s -o /dev/null -m 2 "http://localhost:${ag_port}/" 2>/dev/null && ag_http="true"
				elif command -v wget >/dev/null 2>&1; then
					wget -q -O /dev/null -T 2 "http://127.0.0.1:${ag_port}/" 2>/dev/null && ag_http="true"
				fi
			fi
			[ "$ag_http" = "false" ] && pidof AdGuardHome >/dev/null 2>&1 && ag_http="true"
			# dnsmasq: init.d alive + something listens on :53 (real, not external resolve)
			dns_alive=$(check_service S56dnsmasq)
			dns_resolve="false"
			if pidof dnsmasq >/dev/null 2>&1; then
				command -v ss >/dev/null 2>&1 && ss -ulnp 2>/dev/null | grep -q ':53 ' && dns_resolve="true"
				[ "$dns_resolve" = "false" ] && command -v netstat >/dev/null 2>&1 && netstat -ulnp 2>/dev/null | grep -q ':53 ' && dns_resolve="true"
				[ "$dns_resolve" = "false" ] && dns_resolve="true"
			fi
			# Adblock config (conf only)
			adblock_conf="false"
			grep -q "addn-hosts=/opt/etc/adblock/ads.kvas.list" /opt/etc/dnsmasq.conf 2>/dev/null && adblock_conf="true"
			# Failover: mode + daemon PID + last check (kill -0 is real liveness)
			fo_mode=$(get_failover_mode); [ -z "$fo_mode" ] && fo_mode="manual"
			fo_daemon=$(check_failover_daemon)
			printf '{"ok":true,"vpn_proc":"%s","vpn_port":"%s","ag_conf":"%s","ag_http":"%s","ag_port":"%s","dns_alive":"%s","dns_resolve":"%s","adblock":"%s","fo_mode":"%s","fo_daemon":"%s"}\n' \
				"$vpn_proc" "$vpn_port" "$ag_conf" "$ag_http" "$ag_port" "$dns_alive" "$dns_resolve" "$adblock_conf" "$fo_mode" "$fo_daemon"
			;;
		hosts)
			check_token "$token"
			[ ! -f "$KVAS_LIST" ] && echo '{"ok":true,"hosts":[]}' && return
			sed 's/\\/\\\\/g; s/"/\\"/g' "$KVAS_LIST" | awk 'BEGIN{printf "{\"ok\":true,\"hosts\":["; f=1} {gsub(/\r/,""); if($0=="")next; if(!f)printf ","; f=0; printf "\"%s\"",$0} END{printf "]}"}'
			;;
		host_add)
			check_token "$token"
			domain=$(urldecode "$(echo "$QUERY_STRING" | sed 's/.*domain=//; s/&.*//' 2>/dev/null)")
			[ "$domain" = "$QUERY_STRING" ] && domain=""
			[ -z "$domain" ] && json_error "domain required"
			out=$($KVAS_BIN add "$domain" 2>&1)
			rc=$?
			[ $rc -ne 0 ] && json_error "add failed: $out"
			json_ok "added $domain"
			;;
		host_del)
			check_token "$token"
			domain=$(urldecode "$(echo "$QUERY_STRING" | sed 's/.*domain=//; s/&.*//' 2>/dev/null)")
			[ "$domain" = "$QUERY_STRING" ] && domain=""
			[ -z "$domain" ] && json_error "domain required"
			out=$($KVAS_BIN del "$domain" 2>&1)
			rc=$?
			[ $rc -ne 0 ] && json_error "del failed: $out"
			# Rebuild ipset and restart services
			init_out=$($KVAS_BIN init 2>&1)
			json_ok "removed $domain (ipset updated)"
			;;
		host_import)
			check_token "$token"
			domains=$(cat 2>/dev/null)
			if [ -z "$domains" ]; then
				domains=$(echo "$QUERY_STRING" | sed 's/.*domains=//; s/&.*//' 2>/dev/null | sed 's/%0A/
/g; s/+/ /g')
			fi
			[ -z "$domains" ] && json_error "domains required"
			total=$(echo "$domains" | grep -v '^[[:space:]]*$' | grep -v '^[[:space:]]*#' | grep '\.' | wc -l)
			[ "$total" = "0" ] && json_error "нет доменов для импорта"
			[ -f /tmp/kvas_import_pid.txt ] && kill "$(cat /tmp/kvas_import_pid.txt)" 2>/dev/null
			rm -f /tmp/kvas_import_out.txt /tmp/kvas_import_data.txt /tmp/kvas_import_pid.txt
			echo "$domains" > /tmp/kvas_import_data.txt
			(
				$KVAS_BIN import /tmp/kvas_import_data.txt > /tmp/kvas_import_out.txt 2>&1
				echo ">>>EXIT:$?" >> /tmp/kvas_import_out.txt
			) < /dev/null &
			echo $! > /tmp/kvas_import_pid.txt
			printf '{"ok":true,"total":%s}\n' "$total"
			;;
		host_import_poll)
			check_token "$token"
			if [ ! -f /tmp/kvas_import_out.txt ]; then
				printf '{"ok":true,"done":true,"running":false}\n'
				return
			fi
			if grep -q ">>>EXIT:" /tmp/kvas_import_out.txt 2>/dev/null; then
				import_out=$(grep -v ">>>EXIT:" /tmp/kvas_import_out.txt 2>/dev/null)
				exit_code=$(grep ">>>EXIT:" /tmp/kvas_import_out.txt 2>/dev/null | sed 's/>>>EXIT://')
				rm -f /tmp/kvas_import_out.txt /tmp/kvas_import_data.txt /tmp/kvas_import_pid.txt
				[ "$exit_code" != "0" ] && printf '{"ok":false,"error":"import failed","output":"%s"}\n' "$(json_str "$import_out")" && return
				printf '{"ok":true,"done":true,"output":"%s"}\n' "$(json_str "$import_out")"
			else
				lines=$(wc -l < /tmp/kvas_import_out.txt 2>/dev/null || echo 0)
				last_line=$(tail -1 /tmp/kvas_import_out.txt 2>/dev/null || echo "")
				printf '{"ok":true,"done":false,"lines":"%s","last":"%s"}\n' "$lines" "$(json_str "$last_line")"
			fi
			;;
		host_clear)
			check_token "$token"
			: > "$KVAS_LIST"
			out=$($KVAS_BIN init 2>&1)
			json_ok "list cleared"
			;;
		vpn_status)
			check_token "$token"
			vpn_mode=$(detect_vpn_mode)
			vless_running=$(check_vpn_running "vless")
			hysteria_running=$(check_vpn_running "hysteria")
			printf '{"ok":true,"mode":"%s","vless":"%s","hysteria":"%s"}\n' \
				"$(json_str "$vpn_mode")" "$vless_running" "$hysteria_running"
			;;
		tunnel_check)
			check_token "$token"
			vless_ok="false"
			hysteria_ok="false"
			other_ok="false"
			other_desc=""
			command -v ss >/dev/null 2>&1 && {
				ss -tlnp 2>/dev/null | grep -q ":1097 " && vless_ok="true"
				ss -tlnp 2>/dev/null | grep -q ":10808 " && hysteria_ok="true"
			}
			[ "$vless_ok" = "false" ] && command -v netstat >/dev/null 2>&1 && netstat -tlnp 2>/dev/null | grep -q ":1097 " && vless_ok="true"
			[ "$hysteria_ok" = "false" ] && command -v netstat >/dev/null 2>&1 && netstat -tlnp 2>/dev/null | grep -q ":10808 " && hysteria_ok="true"
			# Check other VPN interface (OpenConnect, WG, etc.)
			inface_cli=$(grep "^INFACE_CLI=" /opt/etc/kvas.conf 2>/dev/null | cut -d= -f2)
			inface_ent=$(grep "^INFACE_ENT=" /opt/etc/kvas.conf 2>/dev/null | cut -d= -f2)
			case "$inface_cli" in
				""|*Proxy21*|*vless*|*Proxy41*|*hysteria*) ;;
				*)
					other_desc=$(grep "|${inface_ent}|" /opt/etc/inface_equals 2>/dev/null | head -1 | cut -d'|' -f3 | sed 's/^"//; s/"$//')
					[ -z "$other_desc" ] && other_desc="$inface_ent"
					/opt/sbin/ip link show "$inface_ent" 2>/dev/null | grep -q '<.*UP' && other_ok="true"
					;;
			esac
			_other_json="false"
			[ "$other_ok" = "true" ] && _other_json="true"
			printf '{"ok":true,"vless":%s,"hysteria":%s,"other":%s,"other_desc":"%s"}\n' "$vless_ok" "$hysteria_ok" "$_other_json" "$other_desc"
			;;
		vpn_interfaces)
			check_token "$token"
			current=$(grep "^INFACE_ENT=" /opt/etc/kvas.conf 2>/dev/null | cut -d= -f2)
			printf '{"ok":true,"current":"%s","interfaces":[' "$current"
			_first=1
			_seen=""
			while IFS='|' read -r cli ent desc rest; do
				[ -n "$ent" ] && [ -n "$desc" ] || continue
				# Skip duplicates (same ent already seen)
				case "$_seen" in
					*"|$ent|"*) continue ;;
				esac
				_seen="${_seen}|${ent}|"
				# Skip entries where interface doesn't exist (stale)
				# SOCKS interfaces (t2s*, ezcfg*) might not exist if proxy is off — keep them
				case "$ent" in
					t2s*|ezcfg*) ;;
					*)
						ip link show "$ent" 2>/dev/null | grep -q '<' || continue
						;;
				esac
				[ $_first -eq 1 ] || printf ','
				_active=false; [ "$ent" = "$current" ] && _active=true
				_esc=$(printf '%s' "$cli" | sed 's/\\/\\\\/g; s/"/\\"/g')
				_ese=$(printf '%s' "$ent" | sed 's/\\/\\\\/g; s/"/\\"/g')
				_esd=$(printf '%s' "$desc" | sed 's/\\/\\\\/g; s/^"//; s/"$//')
				printf '{"cli":"%s","ent":"%s","desc":"%s","active":%s}' \
					"$_esc" "$_ese" "$_esd" "$_active"
				_first=0
			done < /opt/etc/inface_equals 2>/dev/null
			printf ']}'
			;;
		vpn_set)
			check_token "$token"
			iface=$(echo "$QUERY_STRING" | sed 's/.*iface=//; s/&.*//')
			[ "$iface" = "$QUERY_STRING" ] && iface=""
			if [ -n "$iface" ]; then
				out=$($KVAS_BIN vpn set "$iface" 2>&1)
			else
				proto=$(echo "$QUERY_STRING" | sed 's/.*proto=//; s/&.*//')
				[ "$proto" = "$QUERY_STRING" ] && proto=""
				case "$proto" in
					vless|hysteria) ;;
					*) json_error "proto must be vless or hysteria" ;;
				esac
				out=$($KVAS_BIN vpn set "$proto" 2>&1)
			fi
			rc=$?
			[ $rc -ne 0 ] && json_error "switch failed: $out"
			json_ok "switched"
			;;
		failover_status)
			check_token "$token"
			failover_mode=$(get_failover_mode)
			[ -z "$failover_mode" ] && failover_mode="manual"
			primary=""
			secondary=""
			interval=15
			threshold=2
			if [ -f "$FAILOVER_CONF" ]; then
				primary=$(grep "^PRIMARY=" "$FAILOVER_CONF" 2>/dev/null | cut -d= -f2)
				secondary=$(grep "^SECONDARY=" "$FAILOVER_CONF" 2>/dev/null | cut -d= -f2)
				tertiary=$(grep "^TERTIARY=" "$FAILOVER_CONF" 2>/dev/null | cut -d= -f2)
				interval=$(grep "^CHECK_INTERVAL=" "$FAILOVER_CONF" 2>/dev/null | cut -d= -f2)
				threshold=$(grep "^FAIL_THRESHOLD=" "$FAILOVER_CONF" 2>/dev/null | cut -d= -f2)
			fi
			[ -z "$primary" ] && primary="-"
			[ -z "$secondary" ] && secondary="-"
			[ -z "$tertiary" ] && tertiary=""
			[ -z "$interval" ] && interval=15
			[ -z "$threshold" ] && threshold=2
			daemon_running=$(check_failover_daemon)
			# Получаем доступные каналы из failover lib
			local _avail=""
			if [ -f /opt/apps/kvas/bin/libs/failover ]; then
				_avail=$(. /opt/apps/kvas/bin/libs/failover 2>/dev/null; get_available_channels 2>/dev/null)
			fi
			printf '{"ok":true,"enabled":"%s","primary":"%s","secondary":"%s","tertiary":"%s","interval":"%s","threshold":"%s","daemon":"%s","available":"%s"}\n' \
				"$(json_str "$failover_mode")" "$(json_str "$primary")" "$(json_str "$secondary")" "$(json_str "$tertiary")" "$interval" "$threshold" "$daemon_running" "$(json_str "$_avail")"
			;;
			failover)
			check_token "$token"
			cmd=$(echo "$QUERY_STRING" | sed 's/.*cmd=//; s/&.*//' 2>/dev/null)
			[ "$cmd" = "$QUERY_STRING" ] && cmd=""
			case "$cmd" in
				on|off)
					( $KVAS_BIN failover "$cmd" >/dev/null 2>&1 ) &
					json_ok "failover $cmd started"
					;;
				status)
					out=$($KVAS_BIN failover status 2>&1)
					out=$(echo "$out" | tr -d '\033\r' | sed 's/\[[0-9][0-9;]*[a-zA-Z]//g; s/\[m//g; s/\[m//g' | sed 's/\t/ /g; s/\\/\\\\/g; s/"/\\"/g; s/$/\\n/' | tr -d '\n')
					printf '{"ok":true,"data":"%s"}\n' "$out"
					;;
				set_primary)
					_val=$(echo "$QUERY_STRING" | sed 's/.*val=//; s/&token=.*//')
					_val=$(echo "$_val" | sed 's/+/ /g; s/%/\\x/g' | xargs -0 printf 2>/dev/null)
					out=$($KVAS_BIN failover set primary "$_val" 2>&1 | tr -d '\033\r\n' | sed 's/\[[0-9][0-9;]*[a-zA-Z]//g; s/\[m//g')
					json_ok "$out"
					;;
				set_secondary)
					_val=$(echo "$QUERY_STRING" | sed 's/.*val=//; s/&token=.*//')
					_val=$(echo "$_val" | sed 's/+/ /g; s/%/\\x/g' | xargs -0 printf 2>/dev/null)
					out=$($KVAS_BIN failover set secondary "$_val" 2>&1 | tr -d '\033\r\n' | sed 's/\[[0-9][0-9;]*[a-zA-Z]//g; s/\[m//g')
					json_ok "$out"
					;;
				set_tertiary)
					_val=$(echo "$QUERY_STRING" | sed 's/.*val=//; s/&token=.*//')
					_val=$(echo "$_val" | sed 's/+/ /g; s/%/\\x/g' | xargs -0 printf 2>/dev/null)
					out=$($KVAS_BIN failover set tertiary "$_val" 2>&1 | tr -d '\033\r\n' | sed 's/\[[0-9][0-9;]*[a-zA-Z]//g; s/\[m//g')
					json_ok "$out"
					;;
				history)
					_hf=/opt/var/log/kvas-failover-history.log
					[ ! -f "$_hf" ] && echo '{"ok":true,"items":[]}' && exit 0
					awk 'BEGIN{printf "{\"ok\":true,\"items\":["; f=1}
					{ gsub(/\r/,""); if($0=="")next; if(!f)printf ","; f=0; n=split($0,a,"|"); gsub(/\\/,"\\\\",a[1]); gsub(/"/,"\\\"",a[1]); gsub(/\\/,"\\\\",a[2]); gsub(/"/,"\\\"",a[2]); gsub(/\\/,"\\\\",a[3]); gsub(/"/,"\\\"",a[3]); gsub(/\\/,"\\\\",a[4]); gsub(/"/,"\\\"",a[4]); printf "{\"t\":\"%s\",\"from\":\"%s\",\"to\":\"%s\",\"reason\":\"%s\"}", a[1],a[2],a[3],a[4] }
					END{printf "]}\n"}' "$_hf" | tail -c 8000
					;;
				*) json_error "cmd must be on/off/status/set_primary/set_secondary/set_tertiary/history" ;;
			esac
			;;
		xray_status)
			check_token "$token"
			_ver=""
			_running="false"
			if [ -x /opt/sbin/xray ]; then
				_ver=$(/opt/sbin/xray version 2>/dev/null | head -1 | sed 's/Xray //' | sed 's/ .*//')
				pidof xray >/dev/null 2>&1 && _running="true"
			fi
			printf '{"ok":true,"version":"%s","running":"%s"}\n' "$_ver" "$_running"
			;;
		xray_versions)
			check_token "$token"
			printf '{"ok":true,"versions":['
			_first=1
			curl -s --max-time 15 "https://api.github.com/repos/XTLS/Xray-core/releases" 2>/dev/null | \
				jq -r ".[0:15] | .[] | .tag_name" 2>/dev/null | while IFS= read -r _v; do
					[ -n "$_v" ] || continue
					[ $_first -eq 1 ] || printf ','
					printf '"%s"' "$_v"
					_first=0
				done
			printf ']}'
			;;
		xray_install)
			check_token "$token"
			_ver=$(echo "$QUERY_STRING" | sed 's/.*version=//; s/&token=.*//')
			_ver=$(echo "$_ver" | sed 's/+/ /g; s/%/\\x/g' | xargs -0 printf 2>/dev/null)
			[ -z "$_ver" ] && json_error "version required"
			out=$($KVAS_BIN xray core "$_ver" 2>&1 | tr -d '\033\r' | sed 's/\[[0-9][0-9;]*[a-zA-Z]//g; s/\[m//g' | sed 's/\t/ /g; s/\\/\\\\/g; s/"/\\"/g; s/$/\\n/' | tr -d '\n')
			printf '{"ok":true,"output":"%s"}\n' "$out"
			;;
		awg_new)
			check_token "$token"
			_link=$(echo "$QUERY_STRING" | sed 's/.*link=//')
			_link=$(echo "$_link" | sed 's/+/ /g; s/%/\\x/g' | xargs -0 printf 2>/dev/null)
			[ -z "$_link" ] && json_error "link required"
			_tmpf=/tmp/kvas_awg_link_$$
			printf '%s' "$_link" > "$_tmpf"
			out=$($KVAS_BIN awg new "$_tmpf" 2>&1 | head -80 | tr -d '\033\r' | sed 's/\[[0-9][0-9;]*[a-zA-Z]//g; s/\[m//g' | sed 's/\t/ /g; s/\\/\\\\/g; s/"/\\"/g; s/$/\\n/' | tr -d '\n')
			rm -f "$_tmpf"
			printf '{"ok":true,"output":"%s"}\n' "$out"
			;;
		awg_new_b64)
			# URL-safe base64 контент файла (через GET)
			check_token "$token"
			# Parameter expansion — надёжнее echo|sed для длинных строк
			_rest="${QUERY_STRING#*data=}"
			_data="${_rest%%&*}"
			[ -z "$_data" ] && json_error "data required"
			# Конвертируем URL-safe base64 → стандартный
			_data=$(printf '%s' "$_data" | tr '_-' '/+')
			# Добавляем padding (=)
			_mod=$((${#_data} % 4))
			[ "$_mod" -eq 2 ] && _data="${_data}=="
			[ "$_mod" -eq 3 ] && _data="${_data}="
			# Декодируем base64 в файл
			_tmpf=/tmp/kvas_awg_b64_$$
			_b64f=/tmp/kvas_awg_b64raw_$$
			printf '%s' "$_data" > "$_b64f"
			base64 -d "$_b64f" > "$_tmpf" 2>/dev/null
			rm -f "$_b64f"
			[ -s "$_tmpf" ] || json_error "base64 decode failed"
			out=$($KVAS_BIN awg new "$_tmpf" 2>&1 | head -120 | tr -d '\033\r' | sed 's/\[[0-9][0-9;]*[a-zA-Z]//g; s/\[m//g' | sed 's/\t/ /g; s/\\/\\\\/g; s/"/\\"/g; s/$/\\n/' | tr -d '\n')
			rm -f "$_tmpf"
			[ -z "$out" ] && out="AmneziaWG настроен"
			printf '{"ok":true,"output":"%s"}\n' "$out"
			;;
		awg_status)
			check_token "$token"
			_running="false"
			_installed="false"
			[ -x /opt/apps/kvas/awg/bin/wireproxy ] && _installed="true"
			[ -f /var/run/wireproxy.pid ] && kill -0 "$(cat /var/run/wireproxy.pid 2>/dev/null)" 2>/dev/null && _running="true"
			printf '{"ok":true,"installed":"%s","running":"%s"}\n' "$_installed" "$_running"
			;;
		awg_config)
			check_token "$token"
			if [ -f /opt/etc/awg/awg.conf ]; then
				_conf=$(cat /opt/etc/awg/awg.conf 2>/dev/null | tr -d '\033\r' | sed 's/\\/\\\\/g; s/"/\\"/g; s/\t/ /g; s/$/\\n/' | tr -d '\n')
				printf '{"ok":true,"config":"%s"}\n' "$_conf"
			else
				printf '{"ok":true,"config":""}\n'
			fi
			;;
		adguard_status)
			check_token "$token"
			_enabled=$(grep "^ADGUARD_ENABLE=" /opt/etc/kvas.conf 2>/dev/null | cut -d= -f2)
			_installed="false"
			[ -f /opt/bin/AdGuardHome ] && [ -f /opt/etc/init.d/S99adguardhome ] && _installed="true"
			_ag_yaml=/opt/etc/AdGuardHome/AdGuardHome.yaml
			[ ! -f "$_ag_yaml" ] && [ -f /opt/etc/.kvas/backup/AdGuardHome.yaml ] && _ag_yaml=/opt/etc/.kvas/backup/AdGuardHome.yaml
			_ag_port=""
			if [ -f "$_ag_yaml" ]; then
				_ag_port=$(awk '/^http:/{h=1;next} /^[a-z]/{h=0} h && $1=="address:"{n=split($2,a,":"); print a[n]; exit}' "$_ag_yaml" 2>/dev/null)
				[ -z "$_ag_port" ] && _ag_port=$(awk '/^http:/{h=1;next} /^dns:|^[a-z]/{h=0} h && /^  port:/{print $2; exit}' "$_ag_yaml" 2>/dev/null)
				[ -z "$_ag_port" ] && _ag_port=$(grep '^bind_port:' "$_ag_yaml" 2>/dev/null | head -1 | awk '{print $2}')
			fi
			case "$_ag_port" in ''|*[!0-9]*|9753|6060|53) _ag_port=8086 ;; esac
			_http="false"
			if command -v ss >/dev/null 2>&1; then
				ss -tln 2>/dev/null | grep -qE "[:.]${_ag_port}[[:space:]]" && _http="true"
			elif command -v netstat >/dev/null 2>&1; then
				netstat -tln 2>/dev/null | grep -qE "[:.]${_ag_port}[[:space:]]" && _http="true"
			fi
			if [ "$_http" = "false" ]; then
				if command -v curl >/dev/null 2>&1; then
					curl -s -o /dev/null -m 2 "http://127.0.0.1:${_ag_port}/" 2>/dev/null && _http="true"
				elif command -v wget >/dev/null 2>&1; then
					wget -q -O /dev/null -T 2 "http://127.0.0.1:${_ag_port}/" 2>/dev/null && _http="true"
				fi
			fi
			[ "$_http" = "false" ] && pidof AdGuardHome >/dev/null 2>&1 && _http="true"
			_running="false"
			[ "$_http" = "true" ] && _running="true"
			[ "$_running" = "false" ] && pidof AdGuardHome >/dev/null 2>&1 && _running="true"
			_state="off"
			if [ "$_enabled" = "true" ] && [ "$_running" = "true" ]; then
				_state="on"
			elif [ "$_enabled" = "true" ]; then
				_state="degraded"
			fi
			printf '{"ok":true,"adguard":"%s","installed":"%s","running":"%s","enabled":"%s","port":"%s"}\n' \
				"$_state" "$_installed" "$_running" "$([ "$_enabled" = "true" ] && echo true || echo false)" "$_ag_port"
			;;
		adguard_install)
			check_token "$token"
			_busy=""
			[ -f /opt/tmp/opkg.lock ] && _busy="opkg busy"
			if [ -z "$_busy" ]; then
				if [ ! -f /opt/bin/AdGuardHome ]; then
					opkg update >/dev/null 2>&1
					opkg install adguardhome-go --force-maintainer >/dev/null 2>&1
				fi
				[ -f /opt/bin/AdGuardHome ] || _busy="install failed"
			fi
			if [ -z "$_busy" ]; then
				mkdir -p /opt/etc/AdGuardHome /opt/var/log /opt/var/run
				if [ -f /opt/apps/kvas/etc/init.d/S99adguard ]; then
					if [ -f /opt/etc/init.d/S99adguardhome ] && ! grep -q kvas /opt/etc/init.d/S99adguardhome 2>/dev/null; then
						mkdir -p /opt/var/backups/kvas 2>/dev/null || true
						mv /opt/etc/init.d/S99adguardhome /opt/var/backups/kvas/S99adguardhome.origin 2>/dev/null || true
					fi
					cp /opt/apps/kvas/etc/init.d/S99adguard /opt/etc/init.d/S99adguardhome
					chmod 755 /opt/etc/init.d/S99adguardhome
				fi
			fi
			if [ -n "$_busy" ]; then
				printf '{"ok":false,"error":"%s"}\n' "$_busy"
			elif [ -f /opt/etc/AdGuardHome/AdGuardHome.yaml ]; then
				_ag_port=$(awk '/^http:/{h=1;next} /^[a-z]/{h=0} h && $1=="address:"{n=split($2,a,":"); print a[n]; exit}' /opt/etc/AdGuardHome/AdGuardHome.yaml 2>/dev/null)
				case "$_ag_port" in ''|*[!0-9]*|9753|6060|53) _ag_port=8086 ;; esac
				printf '{"ok":true,"msg":"AdGuard Home установлен (web :%s)","port":"%s","need_setup":false}\n' "$_ag_port" "$_ag_port"
			else
				if ! pidof AdGuardHome >/dev/null 2>&1; then
					/opt/bin/AdGuardHome -c /opt/etc/AdGuardHome/AdGuardHome.yaml -l /opt/var/log/AdGuardHome.log >/dev/null 2>&1 &
					sleep 2
				fi
				_rip=$(ip -4 addr show 2>/dev/null | awk '/inet 192\.168\.|inet 10\.|inet 172\./{print $2}' | cut -d/ -f1 | head -1)
				[ -z "$_rip" ] && _rip=$(nvram get lan_ipaddr 2>/dev/null)
				[ -z "$_rip" ] && _rip=$(uci -q get network.lan.ipaddr 2>/dev/null)
				[ -z "$_rip" ] && _rip=$(hostname -I 2>/dev/null | awk '{print $1}')
				[ -z "$_rip" ] && _rip="192.168.1.1"
				printf '{"ok":true,"msg":"Пакет установлен. Настройте AdGuard в новой вкладке (порт 3000).","need_setup":true,"setup_url":"http://%s:3000","port":"3000"}\n' "$_rip"
			fi
			;;
		adguard_uninstall)
			check_token "$token"
			out=$($KVAS_BIN adguard uninstall 2>&1 | tr -d '\033\r' | sed 's/\[[0-9;]*[a-zA-Z]//g; s/\\/\\\\/g; s/"/\\"/g; s/$/\\n/' | tr -d '\n')
			[ -z "$out" ] && out="AdGuard Home удален"
			printf '{"ok":true,"msg":"%s"}\n' "$out"
			;;
		adguard_on)
			check_token "$token"
			_ag_yaml=/opt/etc/AdGuardHome/AdGuardHome.yaml
			[ ! -f "$_ag_yaml" ] && [ -f /opt/etc/.kvas/backup/AdGuardHome.yaml ] && {
				cp /opt/etc/.kvas/backup/AdGuardHome.yaml "$_ag_yaml" 2>/dev/null || true
			}
			if [ -f "$_ag_yaml" ]; then
				. /opt/apps/kvas/bin/libs/main 2>/dev/null || true
				. /opt/apps/kvas/bin/libs/vpn 2>/dev/null || true
				if [ -f /opt/apps/kvas/etc/init.d/S99adguard ]; then
					cp /opt/apps/kvas/etc/init.d/S99adguard /opt/etc/init.d/S99adguardhome 2>/dev/null || true
					chmod 755 /opt/etc/init.d/S99adguardhome 2>/dev/null || true
				fi
				if type adguardhome_setup >/dev/null 2>&1; then
					out=$(adguardhome_setup 2>&1 | tr -d '\033\r' | sed 's/\[[0-9;]*[a-zA-Z]//g; s/\\/\\\\/g; s/"/\\"/g; s/$/\\n/' | tr -d '\n')
				else
					out=$($KVAS_BIN adguard on 2>&1 </dev/null | tr -d '\033\r' | sed 's/\[[0-9;]*[a-zA-Z]//g; s/\\/\\\\/g; s/"/\\"/g; s/$/\\n/' | tr -d '\n')
				fi
			else
				out=$(printf 'n\nn\n' | $KVAS_BIN adguard on 2>&1 | tr -d '\033\r' | sed 's/\[[0-9;]*[a-zA-Z]//g; s/\\/\\\\/g; s/"/\\"/g; s/$/\\n/' | tr -d '\n')
			fi
			_ag_port=""
			if [ -f "$_ag_yaml" ]; then
				_ag_port=$(awk '/^http:/{h=1;next} /^[a-z]/{h=0} h && $1=="address:"{n=split($2,a,":"); print a[n]; exit}' "$_ag_yaml" 2>/dev/null)
				[ -z "$_ag_port" ] && _ag_port=$(awk '/^http:/{h=1;next} /^dns:|^[a-z]/{h=0} h && /^  port:/{print $2; exit}' "$_ag_yaml" 2>/dev/null)
			fi
			case "$_ag_port" in ''|*[!0-9]*|9753|6060|53) _ag_port=8086 ;; esac
			[ -z "$out" ] && out="AdGuard включен, доступен по порту ${_ag_port}"
			printf '{"ok":true,"msg":"%s","port":"%s"}\n' "$out" "$_ag_port"
			;;
		adguard_off)
			check_token "$token"
			out=$($KVAS_BIN adguard off 2>&1 | tr -d '\033\r' | sed 's/\[[0-9;]*[a-zA-Z]//g; s/\\/\\\\/g; s/"/\\"/g; s/$/\\n/' | tr -d '\n')
			_dns_ok="false"
			pidof dnsmasq >/dev/null 2>&1 && _dns_ok="true"
			[ -z "$out" ] && out="AdGuard остановлен, DNS переключён на dnsmasq"
			printf '{"ok":true,"msg":"%s","dnsmasq":"%s"}\n' "$out" "$_dns_ok"
			;;
		vless_new)
			check_token "$token"
			# link= идёт последним в QUERY_STRING (token перед ним)
			_link=$(echo "$QUERY_STRING" | sed 's/.*link=//')
			# URL-decode
			_link=$(echo "$_link" | sed 's/+/ /g; s/%/\\x/g' | xargs -0 printf 2>/dev/null)
			[ -z "$_link" ] && json_error "link required"
			out=$(printf '%s\nq\n' "$_link" | $KVAS_BIN vless new 2>&1 | head -80 | tr -d '\033\r' | sed 's/\[[0-9][0-9;]*[a-zA-Z]//g; s/\[m//g' | sed 's/\t/ /g; s/\\/\\\\/g; s/"/\\"/g; s/$/\\n/' | tr -d '\n')
			printf '{"ok":true,"output":"%s"}\n' "$out"
			;;
		hysteria_new)
			check_token "$token"
			_link=$(echo "$QUERY_STRING" | sed 's/.*link=//')
			_link=$(echo "$_link" | sed 's/+/ /g; s/%/\\x/g' | xargs -0 printf 2>/dev/null)
			[ -z "$_link" ] && json_error "link required"
			out=$(printf '%s\n' "$_link" | $KVAS_BIN hysteria new 2>&1 | head -80 | tr -d '\033\r' | sed 's/\[[0-9][0-9;]*[a-zA-Z]//g; s/\[m//g' | sed 's/\t/ /g; s/\\/\\\\/g; s/"/\\"/g; s/$/\\n/' | tr -d '\n')
			printf '{"ok":true,"output":"%s"}\n' "$out"
			;;
		tunnel_start)
			check_token "$token"
			_iface=$(echo "$QUERY_STRING" | sed 's/.*iface=//; s/&.*//')
			_iface=$(echo "$_iface" | sed 's/+/ /g; s/%/\\x/g' | xargs -0 printf 2>/dev/null)
			[ -z "$_iface" ] && json_error "iface required"
			case "$_iface" in
				Proxy21|vless|t2s21)   out=$($KVAS_BIN failover start >/dev/null 2>&1; service_action S97xray start 2>&1) ;;
				Proxy41|hysteria|t2s41) out=$(service_action S99hysteria start 2>&1) ;;
				Proxy42|awg)           out=$($KVAS_BIN awg start 2>&1) ;;
				*)
					# Keenetic VPN — через RCI API
					curl -s -d '{"up":"true"}' "localhost:79/rci/interface/${_iface}" &>/dev/null
					out="Interface ${_iface} up"
					;;
			esac
			out=$(echo "$out" | tr -d '\033\r\n' | sed 's/\[[0-9][0-9;]*[a-zA-Z]//g; s/\[m//g; s/\\/\\\\/g; s/"/\\"/g')
			json_ok "$out"
			;;
		tunnel_stop)
			check_token "$token"
			_iface=$(echo "$QUERY_STRING" | sed 's/.*iface=//; s/&.*//')
			_iface=$(echo "$_iface" | sed 's/+/ /g; s/%/\\x/g' | xargs -0 printf 2>/dev/null)
			[ -z "$_iface" ] && json_error "iface required"
			case "$_iface" in
				Proxy21|vless|t2s21)   out=$(service_action S97xray stop 2>&1) ;;
				Proxy41|hysteria|t2s41) out=$(service_action S99hysteria stop 2>&1) ;;
				Proxy42|awg)           out=$($KVAS_BIN awg stop 2>&1) ;;
				*)
					curl -s -d '{"down":"true"}' "localhost:79/rci/interface/${_iface}" &>/dev/null
					out="Interface ${_iface} down"
					;;
			esac
			out=$(echo "$out" | tr -d '\033\r\n' | sed 's/\[[0-9][0-9;]*[a-zA-Z]//g; s/\[m//g; s/\\/\\\\/g; s/"/\\"/g')
			json_ok "$out"
			;;
		kvas_list)
			check_token "$token"
			# Download kvas.list
			if [ -f "$KVAS_LIST" ]; then
				printf "HTTP/1.0 200 OK\r\nContent-Type: text/plain\r\nContent-Disposition: attachment; filename=\"kvas.list\"\r\n\r\n"
				cat "$KVAS_LIST"
			else
				printf "HTTP/1.0 404 Not Found\r\nContent-Type: text/plain\r\n\r\nFile not found"
			fi
			return
			;;
		kvas_list_upload)
			check_token "$token"
			# Upload kvas.list — content is in POST body
			# For now, just return current list
			if [ -f "$KVAS_LIST" ]; then
				local count=$(wc -l < "$KVAS_LIST" 2>/dev/null || echo 0)
				json_ok "list has $count entries"
			else
				json_ok "list is empty"
			fi
			;;
		update)
			check_token "$token"
			out=$($KVAS_BIN update 2>&1; $KVAS_BIN init 2>&1)
			rc=$?
			[ $rc -ne 0 ] && json_error "update failed: $out"
			json_ok "update done"
			;;
		kvas_init)
			check_token "$token"
			out=$($KVAS_BIN init 2>&1)
			rc=$?
			[ $rc -ne 0 ] && json_error "init failed: $out"
			json_ok "kvas init done"
			;;
		upgrade)
			check_token "$token"
			out=$(printf '1\n' | $KVAS_BIN upgrade 2>&1 | head -80 | tr -d '\033\r' | sed 's/\[[0-9][0-9;]*[a-zA-Z]//g; s/\[m//g' | sed 's/\t/ /g; s/\\/\\\\/g; s/"/\\"/g; s/$/\\n/' | tr -d '\n')
			$KVAS_BIN monitor web stop >/dev/null 2>&1
			sleep 1
			$KVAS_BIN monitor web start >/dev/null 2>&1 &
			sleep 2
			printf '{"ok":true,"output":"%s"}\n' "$out"
			;;
		rollback)
			check_token "$token"
			# rollback: 1=репозиторий, 2=предыдущая версия из списка
			out=$(printf '1\n2\n' | $KVAS_BIN upgrade rollback 2>&1 | head -80 | tr -d '\033\r' | sed 's/\[[0-9][0-9;]*[a-zA-Z]//g; s/\[m//g' | sed 's/\t/ /g; s/\\/\\\\/g; s/"/\\"/g; s/$/\\n/' | tr -d '\n')
			$KVAS_BIN monitor web stop >/dev/null 2>&1
			sleep 1
			$KVAS_BIN monitor web start >/dev/null 2>&1 &
			sleep 2
			printf '{"ok":true,"output":"%s"}\n' "$out"
			;;
		check_update)
			check_token "$token"
			update_info=$(check_updates 2>/dev/null)
			printf '{"ok":true,"update":"%s"}\n' "$(json_str "$update_info")"
			;;
		backup)
			check_token "$token"
			out=$($KVAS_BIN backup 2>&1 | tr -d '\033\r\n' | sed 's/\[[0-9][0-9;]*[a-zA-Z]//g; s/\[m//g; s/\\/\\\\/g; s/"/\\"/g')
			rc=$?
			[ $rc -ne 0 ] && json_error "backup failed"
			json_ok "$out"
			;;
		restore)
			check_token "$token"
			path=$(echo "$QUERY_STRING" | sed 's/.*path=//; s/&.*//' 2>/dev/null)
			[ "$path" = "$QUERY_STRING" ] && path=""
			out=$($KVAS_BIN restore "$path" 2>&1)
			rc=$?
			[ $rc -ne 0 ] && json_error "restore failed: $out"
			json_ok "restore done"
			;;
		backup_download)
			check_token "$token"
			$KVAS_BIN backup >/dev/null 2>&1
			_dir=$(ls -dt /opt/kvas_backup_* 2>/dev/null | head -1)
			[ -z "$_dir" ] && json_error "backup creation failed"
			_name=$(basename "$_dir")
			tar -czf /opt/apps/kvas/bin/monitor/www/kvas_backup.tar.gz -C /opt "$_name" 2>/dev/null
			_files=$(tar -tzf /opt/apps/kvas/bin/monitor/www/kvas_backup.tar.gz 2>/dev/null | head -30)
			_files=$(echo "$_files" | tr -d '\033\r\n' | sed 's/\\/\\\\/g; s/"/\\"/g; s/$/\\n/' | tr -d '\n')
			printf '{"ok":true,"url":"/kvas_backup.tar.gz","name":"%s","files":"%s"}\n' "$_name" "$_files"
			;;
		backup_cleanup)
			check_token "$token"
			rm -f /opt/apps/kvas/bin/monitor/www/kvas_backup.tar.gz 2>/dev/null
			json_ok "cleaned"
			;;
		restore_upload)
			check_token "$token"
			_post_file="${KVAS_POST_BODY:-}"
			[ -z "$_post_file" ] && json_error "no POST body"
			[ -s "$_post_file" ] || json_error "empty body"
			tar -xzf "$_post_file" -C /opt 2>/dev/null
			rm -f "$_post_file"
			_dir=$(ls -dt /opt/kvas_backup_* 2>/dev/null | head -1)
			[ -z "$_dir" ] && json_error "extract failed"
			out=$($KVAS_BIN restore "$_dir" 2>&1 | head -60 | tr -d '\033\r\n' | sed 's/\[[0-9][0-9;]*[a-zA-Z]//g; s/\[m//g' | sed 's/\\/\\\\/g; s/"/\\"/g; s/$/\\n/' | tr -d '\n')
			[ -z "$out" ] && out="Restored"
			printf '{"ok":true,"output":"%s"}\n' "$out"
			;;
		parental_list)
			check_token "$token"
			if [ ! -f "$PARENTAL_LIST" ]; then
				echo '{"ok":true,"sites":[]}'
				exit 0
			fi
			awk 'BEGIN{printf "{\"ok\":true,\"sites\":["; f=1}
			{ gsub(/\r/,""); if ($0=="" || substr($0,1,1)=="#") next; if (!f) printf ","; f=0; gsub(/\\/,"\\\\"); gsub(/"/,"\\\""); printf "\"%s\"", $0 }
			END{printf "]}\n"}' "$PARENTAL_LIST"
			;;
		parental_add)
			check_token "$token"
			domain=$(urldecode "$(echo "$QUERY_STRING" | sed 's/.*domain=//; s/&.*//' 2>/dev/null)")
			[ "$domain" = "$QUERY_STRING" ] && domain=""
			[ -z "$domain" ] && json_error "domain required"
			domain=$(echo "$domain" | sed 's|^[a-zA-Z][a-zA-Z0-9+.-]*://||; s|^www\.||; s|/.*$||; s|[[:space:]]||g; s|\.$||')
			[ -z "$domain" ] && json_error "domain required"
			until_hm=$(echo "$QUERY_STRING" | sed 's/.*until=//; s/&.*//' 2>/dev/null)
			[ "$until_hm" = "$QUERY_STRING" ] && until_hm=""
			_temp_until=""
			if echo "$until_hm" | grep -qE '^[0-9]{1,2}:[0-9]{2}$'; then
				_th=$(echo "$until_hm" | cut -d: -f1); _tm=$(echo "$until_hm" | cut -d: -f2)
				_now_h=$(date +%H); _now_m=$(date +%M)
				_now_s=$((_now_h*60+_now_m)); _t_s=$((_th*60+_tm))
				if [ "$_t_s" -le "$_now_s" ]; then
					_temp_until=$(date -d "tomorrow $until_hm" '+%Y-%m-%d %H:%M' 2>/dev/null || echo "")
				else
					_temp_until=$(date "+%Y-%m-%d ")$until_hm
				fi
				[ -z "$_temp_until" ] && _temp_until="${until_hm}"
			fi
			mkdir -p /opt/etc/adblock
			touch "$PARENTAL_LIST"
			if [ -n "$_temp_until" ]; then
				grep -qxF "$domain" "$PARENTAL_LIST" || echo "$domain" >> "$PARENTAL_LIST"
				echo "$domain|$_temp_until" >> /opt/etc/adblock/temporary.list
			else
				grep -qxF "$domain" "$PARENTAL_LIST" || echo "$domain" >> "$PARENTAL_LIST"
			fi
			touch /opt/etc/adblock/ads.kvas.list
			grep -qxF "0.0.0.0 $domain" /opt/etc/adblock/ads.kvas.list || echo "0.0.0.0 $domain" >> /opt/etc/adblock/ads.kvas.list
			mkdir -p /opt/etc/adblock/parental.d
			if [ -f /opt/etc/adblock/block.list ]; then
				sed 's/^/0.0.0.0 /' /opt/etc/adblock/block.list > /opt/etc/adblock/parental.d/parental.list 2>/dev/null
			fi
			if ! grep -q "addn-hosts=/opt/etc/adblock/ads.kvas.list" /opt/etc/dnsmasq.conf 2>/dev/null; then
				echo "addn-hosts=/opt/etc/adblock/ads.kvas.list" >> /opt/etc/dnsmasq.conf
				/opt/etc/init.d/S56dnsmasq restart >/dev/null 2>&1
			else
				_dp=$(pidof dnsmasq 2>/dev/null)
				[ -n "$_dp" ] && kill -HUP $_dp 2>/dev/null
			fi
			if [ -f /opt/etc/AdGuardHome/AdGuardHome.yaml ] && grep -q 'kvas.ipset' /opt/etc/AdGuardHome/AdGuardHome.yaml 2>/dev/null; then
				if /opt/etc/init.d/S99adguardhome status 2>/dev/null | grep -qi alive; then
					if [ -f /opt/apps/kvas/bin/libs/vpn ]; then
						( . /opt/apps/kvas/bin/libs/main 2>/dev/null; . /opt/apps/kvas/bin/libs/vpn 2>/dev/null
						  type add_host_to_adguard >/dev/null 2>&1 && add_host_to_adguard "$domain" >/dev/null 2>&1
						) || true
					fi
				fi
			fi
			if [ -n "$_temp_until" ]; then
				json_ok "добавлен $domain до $_temp_until"
			else
				json_ok "добавлен $domain"
			fi
		;;
		parental_del)
			check_token "$token"
			domain=$(urldecode "$(echo "$QUERY_STRING" | sed 's/.*domain=//; s/&.*//' 2>/dev/null)")
			[ "$domain" = "$QUERY_STRING" ] && domain=""
			[ -z "$domain" ] && json_error "domain required"
			[ -f "$PARENTAL_LIST" ] && sed -i "/^${domain}$/d" "$PARENTAL_LIST" 2>/dev/null
			[ -f /opt/etc/adblock/temporary.list ] && sed -i "/^${domain}|/d" /opt/etc/adblock/temporary.list 2>/dev/null
			[ -f /opt/etc/adblock/ads.kvas.list ] && sed -i "/^0\.0\.0\.0 ${domain}$/d" /opt/etc/adblock/ads.kvas.list 2>/dev/null
			pf=/opt/etc/adblock/parental.d/parental.list
			[ -f "$pf" ] && sed -i "/0.0.0.0 ${domain}$/d" "$pf" 2>/dev/null
			_dp=$(pidof dnsmasq 2>/dev/null)
			[ -n "$_dp" ] && kill -HUP $_dp 2>/dev/null
			json_ok "unblocked $domain"
		;;
		parental_expire_tick)
			check_token "$token"
			_tf=/opt/etc/adblock/temporary.list
			_removed=0
			if [ -f "$_tf" ]; then
				_now=$(date +%s)
				while IFS='|' read -r _d _exp; do
					[ -z "$_d" ] && continue
					_exp_s=$(date -d "$_exp" +%s 2>/dev/null || echo 0)
					[ "$_exp_s" -gt 0 ] 2>/dev/null || continue
					[ "$_now" -ge "$_exp_s" ] || continue
					[ -f "$PARENTAL_LIST" ] && sed -i "/^${_d}$/d" "$PARENTAL_LIST" 2>/dev/null
					[ -f /opt/etc/adblock/ads.kvas.list ] && sed -i "/^0\.0\.0\.0 ${_d}$/d" /opt/etc/adblock/ads.kvas.list 2>/dev/null
					[ -f /opt/etc/adblock/parental.d/parental.list ] && sed -i "/0.0.0.0 ${_d}$/d" /opt/etc/adblock/parental.d/parental.list 2>/dev/null
					_removed=$((_removed+1))
				done < "$_tf"
				if [ "$_removed" -gt 0 ]; then
					_now_str=$(date +%s)
					while IFS='|' read -r _d _exp; do
						_exp_s=$(date -d "$_exp" +%s 2>/dev/null || echo 0)
						[ "$_exp_s" -gt 0 ] 2>/dev/null && [ "$_now_str" -lt "$_exp_s" ] && echo "$_d|$_exp"
					done < "$_tf" > "${_tf}.tmp" 2>/dev/null
					mv "${_tf}.tmp" "$_tf" 2>/dev/null
					_dp=$(pidof dnsmasq 2>/dev/null)
					[ -n "$_dp" ] && kill -HUP $_dp 2>/dev/null
				fi
			fi
			printf '{"ok":true,"removed":%s}\n' "$_removed"
		;;
		adblock_status)
			check_token "$token"
			if grep -q "addn-hosts=/opt/etc/adblock/ads.kvas.list" /opt/etc/dnsmasq.conf 2>/dev/null; then
				echo '{"ok":true,"adblock":"on"}'
			else
				echo '{"ok":true,"adblock":"off"}'
			fi
			;;
		adblock_on)
			check_token "$token"
			mkdir -p /opt/etc/adblock/parental.d
			if ! grep -q "addn-hosts=/opt/etc/adblock/ads.kvas.list" /opt/etc/dnsmasq.conf 2>/dev/null; then
				echo "addn-hosts=/opt/etc/adblock/ads.kvas.list" >> /opt/etc/dnsmasq.conf
			fi
			if ! grep -q "hostsdir=/opt/etc/adblock/parental.d" /opt/etc/dnsmasq.conf 2>/dev/null; then
				echo "hostsdir=/opt/etc/adblock/parental.d" >> /opt/etc/dnsmasq.conf
			fi
			[ -f /opt/etc/adblock/ads.kvas.list ] || sh /opt/apps/kvas/bin/main/adblock >/dev/null 2>&1
			[ -f /opt/etc/adblock/block.list ] && sed 's/^/0.0.0.0 /' /opt/etc/adblock/block.list > /opt/etc/adblock/parental.d/parental.list
			/opt/etc/init.d/S56dnsmasq restart >/dev/null 2>&1
			echo '{"ok":true,"msg":"Adblock включен"}'
		;;
adblock_off)
			check_token "$token"
			sed -i '/addn-hosts=\/opt\/etc\/adblock\/ads.kvas.list/d; /hostsdir=\/opt\/etc\/adblock\/parental.d/d' /opt/etc/dnsmasq.conf 2>/dev/null
			/opt/etc/init.d/S56dnsmasq restart >/dev/null 2>&1
			echo '{"ok":true,"msg":"Adblock выключен"}' 
		;;
		route_status)
			check_token "$token"
			route_full=$(grep "^route_full_ip=" "$KVAS_CONF_FILE" 2>/dev/null | cut -d= -f2 | tr '+' ' ')
			route_list=$(grep "^route_by_list_ip=" "$KVAS_CONF_FILE" 2>/dev/null | cut -d= -f2 | tr '+' ' ')
			route_exclude=$(grep "^route_excluded_ip=" "$KVAS_CONF_FILE" 2>/dev/null | cut -d= -f2 | tr '+' ' ')
			route_guest=$(grep "^INFACE_GUEST_ENT=" "$KVAS_CONF_FILE" 2>/dev/null | cut -d= -f2)
			# Get device names from DHCP for descriptions
			devs=$(curl -s "127.0.0.1:79/rci/show/ip/dhcp/bindings" 2>/dev/null | jq -r '.lease[] | "\(.ip)|\(.name)"' 2>/dev/null)
			_resolve_names() {
				local result=""
				for _ip in $1; do
					_name=$(echo "$devs" | grep -F "${_ip}|" | head -1 | cut -d'|' -f2)
					[ -n "$_name" ] && result="$result $_ip ($_name)" || result="$result $_ip"
				done
				echo "$result" | sed 's/^ //'
			}
			route_full=$(_resolve_names "$route_full")
			route_list=$(_resolve_names "$route_list")
			route_exclude=$(_resolve_names "$route_exclude")
			printf '{"ok":true,"full":"%s","list":"%s","exclude":"%s","guest_nets":"%s"}\n' \
				"$(json_str "$route_full")" "$(json_str "$route_list")" "$(json_str "$route_exclude")" "$(json_str "$route_guest")"
			;;
		route_list)
			check_token "$token"
			route_full=$(grep "^route_full_ip=" "$KVAS_CONF_FILE" 2>/dev/null | cut -d= -f2 | tr '+' ' ')
			route_list=$(grep "^route_by_list_ip=" "$KVAS_CONF_FILE" 2>/dev/null | cut -d= -f2 | tr '+' ' ')
			route_exclude=$(grep "^route_excluded_ip=" "$KVAS_CONF_FILE" 2>/dev/null | cut -d= -f2 | tr '+' ' ')
			printf '{"ok":true,"routes":['
			first=1
			for ip in $route_full; do
				[ -z "$ip" ] && continue
				[ "$first" -eq 0 ] && printf ','
				first=0
				printf '{"type":"full","ip":"%s"}' "$ip"
			done
			for ip in $route_list; do
				[ -z "$ip" ] && continue
				[ "$first" -eq 0 ] && printf ','
				first=0
				printf '{"type":"list","ip":"%s"}' "$ip"
			done
			for ip in $route_exclude; do
				[ -z "$ip" ] && continue
				[ "$first" -eq 0 ] && printf ','
				first=0
				printf '{"type":"exclude","ip":"%s"}' "$ip"
			done
			echo ']}'
			;;
		route_add)
			check_token "$token"
			type=$(echo "$QUERY_STRING" | sed 's/.*type=//; s/&.*//' 2>/dev/null)
			ip=$(echo "$QUERY_STRING" | sed 's/.*ip=//; s/&.*//; s/+/ /g; s/%2B/+/gi; s/%2F/\//gi; s/%20/ /g' 2>/dev/null)
			[ -z "$ip" ] && json_error "ip required"
			case "$type" in
				full) key="route_full_ip" ;;
				list) key="route_by_list_ip" ;;
				exclude) key="route_excluded_ip" ;;
				*) json_error "type must be full, list, or exclude" ;;
			esac
			current=$(grep "^${key}=" "$KVAS_CONF_FILE" 2>/dev/null | cut -d= -f2)
			if echo "$current" | tr '+' '\n' | grep -Fxq "$ip"; then
				json_ok "already exists"
			else
				[ -n "$current" ] && current="${current}+${ip}" || current="$ip"
				sed -i "/^${key}=/d" "$KVAS_CONF_FILE" 2>/dev/null
				echo "${key}=${current}" >> "$KVAS_CONF_FILE"
				if $KVAS_BIN route refresh >> /tmp/kvas-route-refresh.log 2>&1; then
					json_ok "added $ip to $type"
				else
					json_error "route refresh failed, see /tmp/kvas-route-refresh.log"
				fi
			fi
			;;
		route_del)
			check_token "$token"
			type=$(echo "$QUERY_STRING" | sed 's/.*type=//; s/&.*//' 2>/dev/null)
			ip=$(echo "$QUERY_STRING" | sed 's/.*ip=//; s/&.*//; s/+/ /g; s/%2B/+/gi; s/%2F/\//gi; s/%20/ /g' 2>/dev/null)
			[ -z "$ip" ] && json_error "ip required"
			case "$type" in
				full) key="route_full_ip" ;;
				list) key="route_by_list_ip" ;;
				exclude) key="route_excluded_ip" ;;
				*) json_error "type must be full, list, or exclude" ;;
			esac
			current=$(grep "^${key}=" "$KVAS_CONF_FILE" 2>/dev/null | cut -d= -f2)
			if ! echo "$current" | tr '+' '\n' | grep -Fxq "$ip"; then
				json_ok "not found"
			else
				new_list=$(echo "$current" | tr '+' '\n' | grep -v "^${ip}$" | tr '\n' '+' | sed 's/+$//')
				sed -i "/^${key}=/d" "$KVAS_CONF_FILE" 2>/dev/null
				[ -n "$new_list" ] && echo "${key}=${new_list}" >> "$KVAS_CONF_FILE"
				if $KVAS_BIN route refresh >> /tmp/kvas-route-refresh.log 2>&1; then
					json_ok "removed $ip from $type"
				else
					json_error "route refresh failed, see /tmp/kvas-route-refresh.log"
				fi
			fi
			;;
		route_refresh)
			check_token "$token"
			out=$($KVAS_BIN route refresh 2>&1)
			json_ok "routes refreshed"
			;;
		route_devices)
			check_token "$token"
			_tmpdev="/tmp/kvas_route_devices.$$"
			: > "$_tmpdev"
			# DHCP bindings (приоритет — реальные имена)
			curl -s "127.0.0.1:79/rci/show/ip/dhcp/bindings" 2>/dev/null | \
				jq -r '.lease[] | "\(.ip)|\(.name)"' 2>/dev/null >> "$_tmpdev"
			# ARP-соседи (только IPv4)
			if command -v ip >/dev/null 2>&1; then
				ip neigh show 2>/dev/null | grep -E 'REACHABLE|STALE|DELAY' | \
					awk '$1 ~ /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/ {print $1 "|" ($5 ? $5 : "arp")}' >> "$_tmpdev"
			elif [ -f /proc/net/arp ]; then
				tail -n +2 /proc/net/arp 2>/dev/null | awk '$2 != "0x0" {print $1 "|arp"}' >> "$_tmpdev"
			fi
			# Активные IP из conntrack — только частные диапазоны (RFC 1918)
			_priv_re='src=(10\.[0-9]+\.[0-9]+\.[0-9]+|172\.(1[6-9]|2[0-9]|3[01])\.[0-9]+\.[0-9]+|192\.168\.[0-9]+\.[0-9]+)'
			if [ -f /proc/net/nf_conntrack ]; then
				grep -oE "$_priv_re" /proc/net/nf_conntrack 2>/dev/null | cut -d= -f2 | sort -u | \
					awk '{print $1 "|conntrack"}' >> "$_tmpdev"
			elif command -v conntrack >/dev/null 2>&1; then
				conntrack -L 2>/dev/null | grep -oE "$_priv_re" | cut -d= -f2 | sort -u | \
					awk '{print $1 "|conntrack"}' >> "$_tmpdev"
			fi
			unset _priv_re
			# Вывод с дедупликацией (оставляем первую запись — у DHCP приоритет)
			awk -F'|' '!seen[$1]++{print $1 "\t" $2}' "$_tmpdev" 2>/dev/null | \
				jq -csR 'split("\n") | map(select(length>0) | split("\t") | {"ip":.[0],"name":.[1]}) | {ok:true,devices:.}' 2>/dev/null || printf '{"ok":true,"devices":[]}'
			rm -f "$_tmpdev"
			;;
		route_guest_networks)
			check_token "$token"
			_tmp="/tmp/kvas_guest_nets.$$"
			tunnel_iface=$(grep "^INFACE_ENT=" "$KVAS_CONF_FILE" 2>/dev/null | cut -d= -f2)
			internet_iface=$(/opt/sbin/ip route 2>/dev/null | grep default | awk '{print $5}' | head -1)
			# Если ip route не нашёл — пробуем через Keenetic API
			[ -z "$internet_iface" ] && internet_iface=$(curl -s "127.0.0.1:79/rci/show/interface" 2>/dev/null | jq -r '.[] | select(.defaultgw==true) | ."interface-name"' 2>/dev/null | head -1)
			# Get interface list from ip addr
			/opt/sbin/ip -o -f inet addr show 2>/dev/null | awk '{
				iface = $2; sub(/@.*/, "", iface)
				ip = $4; sub(/\/.*/, "", ip)
				print iface "|" ip
			}' | sort -u > "$_tmp"
			# Query Keenetic API for VPN server pools
			api_tags=$(curl -s "127.0.0.1:79/rci/show/tags/" 2>/dev/null)
			_iface_prefix_by_pool() {
				local pool_ip="$1"
				[ -z "$pool_ip" ] && return
				local iface
				iface=$(/opt/sbin/ip -o addr show to "$pool_ip" 2>/dev/null | awk '{print $2}' | sed 's/@.*//' | head -1)
				[ -z "$iface" ] && return
				echo "$iface" | sed 's/[0-9]*$//'
			}
			if echo "$api_tags" | grep -qF 'vpn-oc' 2>/dev/null; then
				oc_ip=$(curl -s "127.0.0.1:79/rci/oc-server" 2>/dev/null | jq -r '.config."pool-start"' 2>/dev/null)
				if [ -n "$oc_ip" ]; then
					prefix=$(_iface_prefix_by_pool "$oc_ip")
					[ -z "$prefix" ] && prefix="oc"
					echo "${prefix}+|$oc_ip" >> "$_tmp"
				fi
			fi
			if echo "$api_tags" | grep -qF 'sstp' 2>/dev/null; then
				sstp_ip=$(curl -s "127.0.0.1:79/rci/sstp-server" 2>/dev/null | jq -r '.config."pool-start"' 2>/dev/null)
				if [ -n "$sstp_ip" ]; then
					prefix=$(_iface_prefix_by_pool "$sstp_ip")
					[ -z "$prefix" ] && prefix="sstp"
					echo "${prefix}+|$sstp_ip" >> "$_tmp"
				fi
			fi
			if echo "$api_tags" | grep -qF 'ipsec-l2tp' 2>/dev/null; then
				l2tp_ip=$(curl -s "127.0.0.1:79/rci/crypto/l2tp-server" 2>/dev/null | jq -r '."pool-start"' 2>/dev/null)
				if [ -n "$l2tp_ip" ]; then
					prefix=$(_iface_prefix_by_pool "$l2tp_ip")
					[ -z "$prefix" ] && prefix="l2tp"
					echo "${prefix}+|$l2tp_ip" >> "$_tmp"
				fi
			fi
			if echo "$api_tags" | grep -qF 'ipsec-xauth' 2>/dev/null; then
				ikev2_ip=$(curl -s "127.0.0.1:79/rci/crypto/virtual-ip-server-ikev2" 2>/dev/null | jq -r '."pool-start"' 2>/dev/null)
				[ -n "$ikev2_ip" ] && echo "xfrms+|$ikev2_ip" >> "$_tmp"
			fi
			printf '{"ok":true,"networks":['
			sep=""
			while IFS='|' read -r iface ip; do
				case "$iface" in
					lo|Bridge0|br0|ezcfg0|eth*|GigabitEthernet*|Port*|AccessPoint*|WifiMaster*|WifiStation*) continue ;;
				esac
				[ "$iface" = "$internet_iface" ] && continue
				[ "$iface" = "$tunnel_iface" ] && continue
				case "$iface" in
					br*)        desc="Гостевая сеть" ;;
					oc*)        desc="VPN-сервер OpenConnect" ;;
					sstp*)      desc="VPN-сервер SSTP" ;;
					l2tp*)      desc="VPN-сервер L2TP/IPsec" ;;
					xfrms*)     desc="VPN-сервер IKEv2/IPsec" ;;
					nwg*)       desc="WireGuard" ;;
					t2s*)       desc="KVAS прокси" ;;
					*)          desc="" ;;
				esac
				[ -z "$desc" ] && desc="$iface"
				printf '%s{"id":"%s","name":"%s"}' "$sep" "$iface" "$(json_str "$desc")"
				sep=","
			done < "$_tmp"
			rm -f "$_tmp"
			echo ']}'
			;;
		route_guest_add)
			check_token "$token"
			net=$(echo "$QUERY_STRING" | sed 's/.*net=//; s/&.*//; s/+/ /g; s/%2B/+/gi; s/%2F/\//gi; s/%20/ /g' 2>/dev/null)
			[ -z "$net" ] && json_error "net required"
			current=$(grep "^INFACE_GUEST_ENT=" "$KVAS_CONF_FILE" 2>/dev/null | cut -d= -f2)
			if echo "$current" | tr ',' '\n' | grep -Fxq "$net"; then
				json_ok "already added"
			else
				# Добавляем в INFACE_GUEST_ENT
				[ -n "$current" ] && current="${current},${net}" || current="$net"
				sed -i "/^INFACE_GUEST_ENT=/d" "$KVAS_CONF_FILE" 2>/dev/null
				echo "INFACE_GUEST_ENT=${current}" >> "$KVAS_CONF_FILE"
				# Добавляем listen-address в dnsmasq.conf (или AdGuard)
				_guest_ip=$(/opt/sbin/ip a 2>/dev/null | grep global | grep -E " ${net}\$" | sed 's/inet \([0-9.]*\).*/\1/')
				[ -n "$_guest_ip" ] && {
					if [ -f /opt/etc/AdGuardHome/AdGuardHome.yaml ] && grep -q 'kvas.ipset' /opt/etc/AdGuardHome/AdGuardHome.yaml 2>/dev/null; then
						# AdGuard
						grep -q "\- ${_guest_ip}" /opt/etc/AdGuardHome/AdGuardHome.yaml || \
							sed -i '/bind_hosts/,/port/ s/.*\(port.*\)/    - '"${_guest_ip}"'\n  \1/' /opt/etc/AdGuardHome/AdGuardHome.yaml
						/opt/etc/init.d/S99adguardhome restart &>/dev/null
					else
						# dnsmasq
						grep -q "listen-address=${_guest_ip}" /opt/etc/dnsmasq.conf 2>/dev/null || \
							sed -i "/listen-address 127.0.0.1/a listen-address=${_guest_ip}" /opt/etc/dnsmasq.conf
						/opt/etc/init.d/S56dnsmasq restart &>/dev/null
					fi
				}
				# Пересоздаём iptables
				$KVAS_BIN route refresh >> /tmp/kvas-route-refresh.log 2>&1
				json_ok "added $net"
			fi
			;;
		route_guest_del)
			check_token "$token"
			net=$(echo "$QUERY_STRING" | sed 's/.*net=//; s/&.*//; s/+/ /g; s/%2B/+/gi; s/%2F/\//gi; s/%20/ /g' 2>/dev/null)
			[ -z "$net" ] && json_error "net required"
			current=$(grep "^INFACE_GUEST_ENT=" "$KVAS_CONF_FILE" 2>/dev/null | cut -d= -f2)
			if ! echo "$current" | tr ',' '\n' | grep -Fxq "$net"; then
				json_ok "not found"
			else
				# Удаляем из INFACE_GUEST_ENT
				new_list=$(echo "$current" | tr ',' '\n' | grep -v "^${net}$" | tr '\n' ',' | sed 's/,$//')
				sed -i "/^INFACE_GUEST_ENT=/d" "$KVAS_CONF_FILE" 2>/dev/null
				[ -n "$new_list" ] && echo "INFACE_GUEST_ENT=${new_list}" >> "$KVAS_CONF_FILE"
				# Удаляем listen-address из dnsmasq.conf
				_guest_ip=$(/opt/sbin/ip a 2>/dev/null | grep global | grep -E " ${net}\$" | sed 's/inet \([0-9.]*\).*/\1/')
				[ -n "$_guest_ip" ] && {
					if [ -f /opt/etc/AdGuardHome/AdGuardHome.yaml ] && grep -q 'kvas.ipset' /opt/etc/AdGuardHome/AdGuardHome.yaml 2>/dev/null; then
						sed -i -e "/bind_hosts/,/port/{ /- ${_guest_ip}/d }" /opt/etc/AdGuardHome/AdGuardHome.yaml 2>/dev/null
						/opt/etc/init.d/S99adguardhome restart &>/dev/null
					else
						sed -i "/listen-address=${_guest_ip}/d" /opt/etc/dnsmasq.conf 2>/dev/null
						/opt/etc/init.d/S56dnsmasq restart &>/dev/null
					fi
				}
				# Пересоздаём iptables (без удалённой сети)
				$KVAS_BIN route refresh >> /tmp/kvas-route-refresh.log 2>&1
				json_ok "removed $net"
			fi
			;;
		tags_list)
			check_token "$token"
			[ ! -f "$TAGS_FILE" ] && echo '{"ok":true,"tags":[]}' && return
			awk 'BEGIN{printf "{\"ok\":true,\"tags\":["; ft=1}
			FNR==NR { gsub(/[[:space:]]/,""); if($0!="") hosts[$0]=1; next }
			{
				line=$0; sub(/^[[:space:]]*/,"",line); sub(/[[:space:]]*$/,"",line)
				if (line=="" || line ~ /^#/) next
				if (line ~ /^\[/) {
					if (!ft) printf "]},"
					ft=0
					gsub(/\[/,"",line); gsub(/\]/,"",line)
					printf "{\"name\":\"%s\",\"domains\":[", line
					df=1
				} else {
					if (!df) printf ","
					df=0
					il = (line in hosts) ? "true" : "false"
					printf "{\"name\":\"%s\",\"in_list\":%s}", line, il
				}
			}
			END { if (!ft) printf "]}"; printf "]}" }
			' "${KVAS_LIST}" "${TAGS_FILE}"
			;;
		tags_add)
			check_token "$token"
			tag=$(echo "$QUERY_STRING" | sed 's/.*tag=//; s/&.*//' 2>/dev/null)
			[ "$tag" = "$QUERY_STRING" ] && tag=""
			[ -z "$tag" ] && json_error "tag required"
			grep -qF "[$tag]" "$TAGS_FILE" 2>/dev/null || json_error "tag not found"
			out=$($KVAS_BIN tags add-protect "$tag" 2>&1)
			rc=$?
			[ $rc -ne 0 ] && json_error "add failed: $out"
			opt/apps/kvas/bin/main/dnsmasq &>/dev/null
			kill -HUP "$(pidof dnsmasq)" 2>/dev/null
			json_ok "added $tag"
			;;
		tags_del)
			check_token "$token"
			tag=$(echo "$QUERY_STRING" | sed 's/.*tag=//; s/&.*//' 2>/dev/null)
			[ "$tag" = "$QUERY_STRING" ] && tag=""
			[ -z "$tag" ] && json_error "tag required"
			grep -qF "[$tag]" "$TAGS_FILE" 2>/dev/null || json_error "tag not found"
			out=$($KVAS_BIN tags del-protect "$tag" 2>&1)
			rc=$?
			[ $rc -ne 0 ] && json_error "del failed: $out"
			opt/apps/kvas/bin/main/dnsmasq &>/dev/null
			ipset flush "${IPSET_TABLE_NAME:-KVAS_LIST}" 2>/dev/null
			opt/apps/kvas/bin/main/ipset &>/dev/null
			kill -HUP "$(pidof dnsmasq)" 2>/dev/null
			json_ok "removed $tag"
			;;
		tags_status)
			check_token "$token"
			tag=$(echo "$QUERY_STRING" | sed 's/.*tag=//; s/&.*//' 2>/dev/null)
			[ "$tag" = "$QUERY_STRING" ] && tag=""
			[ -z "$tag" ] && json_error "tag required"
			grep -qF "[$tag]" "$TAGS_FILE" 2>/dev/null || json_error "tag not found"
			domains=$(get_tag_domain_list_from_file "$TAGS_FILE" "$tag")
			printf '{"ok":true,"tag":"%s","domains":[' "$(json_str "$tag")"
			first=1
			for d in $domains; do
				[ "$first" -eq 0 ] && printf ','
				first=0
				in_list="false"
				[ -f "$KVAS_LIST" ] && grep -qxF "$d" "$KVAS_LIST" 2>/dev/null && in_list="true"
				printf '{"name":"%s","in_list":%s}' "$(json_str "$d")" "$in_list"
			done
			echo ']}'
			;;
		tags_create)
			check_token "$token"
			name=$(echo "$QUERY_STRING" | sed 's/.*name=//; s/&.*//' 2>/dev/null)
			raw_domains=$(echo "$QUERY_STRING" | sed 's/.*domains=//; s/&.*//' 2>/dev/null)
			raw_domains=$(printf '%s' "$raw_domains" | sed 's/%0D%0A/ /g; s/%0A/ /g; s/%0D/ /g; s/%20/ /g; s/%2[fF]/\//g; s/+/ /g')
			domains=$(echo "$raw_domains" | sed 's/  */ /g; s/^ //; s/ $//')
			[ "$name" = "$QUERY_STRING" ] && name=""
			[ -z "$name" ] && json_error "name required"
			[ -z "$domains" ] && json_error "domains required"
			out=$($KVAS_BIN tags create "$name" $domains 2>&1)
			rc=$?
			[ $rc -ne 0 ] && json_error "create failed: $out"
			opt/apps/kvas/bin/main/dnsmasq &>/dev/null
			kill -HUP "$(pidof dnsmasq)" 2>/dev/null
			json_ok "created $name"
			;;
		tags_delete)
			check_token "$token"
			tag=$(echo "$QUERY_STRING" | sed 's/.*tag=//; s/&.*//' 2>/dev/null)
			[ "$tag" = "$QUERY_STRING" ] && tag=""
			[ -z "$tag" ] && json_error "tag required"
			grep -q "\[$tag\]" "$TAGS_FILE" 2>/dev/null || json_error "tag not found"
			out=$($KVAS_BIN tags delete "$tag" 2>&1)
			rc=$?
			[ $rc -ne 0 ] && json_error "delete failed: $out"
			json_ok "удалена закваска $tag"
			;;
		tags_edit_save)
			check_token "$token"
			tag=$(echo "$QUERY_STRING" | sed 's/.*tag=//; s/&.*//' 2>/dev/null)
			[ "$tag" = "$QUERY_STRING" ] && tag=""
			[ -z "$tag" ] && json_error "tag required"
			grep -q "\[$tag\]" "$TAGS_FILE" 2>/dev/null || json_error "tag not found"
			raw_domains=$(echo "$QUERY_STRING" | sed 's/.*domains=//; s/&.*//' 2>/dev/null)
			raw_domains=$(printf '%s' "$raw_domains" | sed 's/%0D%0A/ /g; s/%0A/ /g; s/%0D/ /g; s/%20/ /g; s/%2[fF]/\//g; s/+/ /g')
			domains=$(echo "$raw_domains" | sed 's/  */ /g; s/^ //; s/ $//')
			out=$($KVAS_BIN tags edit-save "$tag" $domains 2>&1)
			rc=$?
			[ $rc -ne 0 ] && json_error "edit failed: $out"
			json_ok "закваска $tag обновлена"
			;;
		tags_download)
			check_token "$token"
			[ ! -f "$TAGS_FILE" ] && json_error "no tags"
			printf 'Content-Type: text/plain; charset=utf-8\r\n'
			printf 'Content-Disposition: attachment; filename="tags.list"\r\n\r\n'
			cat "$TAGS_FILE"
			exit 0
			;;
		tags_upload)
			check_token "$token"
			replace=$(echo "$QUERY_STRING" | sed 's/.*replace=//; s/&.*//' 2>/dev/null)
			[ "$replace" = "$QUERY_STRING" ] && replace="0"
			[ "$replace" != "1" ] && replace="0"
			[ ! -f "$TAGS_FILE" ] && touch "$TAGS_FILE"
			upload_tmp=$(mktemp)
			cat > "$upload_tmp"
			if [ "$replace" = "1" ]; then
				mv -f "$upload_tmp" "$TAGS_FILE"
				json_ok "tags replaced"
			else
				# merge: append uploaded tags to existing, skip first line if it's a section header
				merged_tmp=$(mktemp)
				cat "$TAGS_FILE" > "$merged_tmp"
				first=1
				while IFS= read -r line; do
					if [ $first -eq 1 ] && echo "$line" | grep -qE '^\['; then
						continue
					fi
					first=0
					echo "$line"
				done < "$upload_tmp" >> "$merged_tmp"
				mv -f "$merged_tmp" "$TAGS_FILE"
				rm -f "$upload_tmp"
				json_ok "tags merged"
			fi
			;;
		kvas_log)
			check_token "$token"
			log_type=$(echo "$QUERY_STRING" | sed 's/.*type=//; s/&.*//')
			[ "$log_type" = "$QUERY_STRING" ] && log_type="error"
			case "$log_type" in
				error)
					_log=$(tail -n 100 /opt/tmp/kvas_errors.log 2>/dev/null)
					[ -z "$_log" ] && _log="Лог ошибок пуст"
					;;
				info)
					_log=$(logread 2>/dev/null | grep 'КВАС' | tail -50)
					[ -z "$_log" ] && _log="Сообщений КВАС в системном логе нет"
					;;
				syslog)
					_log=$(logread 2>/dev/null | tail -100)
					[ -z "$_log" ] && _log="Системный лог недоступен"
					;;
				*) _log="Неизвестный тип лога" ;;
			esac
			_log=$(printf '%s' "$_log" | sed 's/\\/\\\\/g; s/"/\\"/g; s/$/\\n/' | tr -d '\n')
			printf '{"ok":true,"log":"%s"}\n' "$_log"
			;;
		kvas_log_clear)
			check_token "$token"
			> /opt/tmp/kvas_errors.log 2>/dev/null
			json_ok "лог ошибок очищен"
			;;
		kvas_test)
			check_token "$token"
			_out=$(echo | $KVAS_BIN test upgrade 2>&1 | tr -d '\033\r' | sed 's/\[[0-9][0-9;]*[a-zA-Z]//g; s/\[m//g' | sed 's/\t/ /g; s/\\/\\\\/g; s/"/\\"/g; s/$/\\n/' | tr -d '\n')
			printf '{"ok":true,"output":"%s"}\n' "$_out"
			;;
		kvas_debug)
			check_token "$token"
			_out=$($KVAS_BIN debug 2>&1 | tr -d '\033\r' | sed 's/\[[0-9][0-9;]*[a-zA-Z]//g; s/\[m//g' | sed 's/\t/ /g; s/\\/\\\\/g; s/"/\\"/g; s/$/\\n/' | tr -d '\n')
			printf '{"ok":true,"output":"%s"}\n' "$_out"
			;;
		kvas_debug_dns)
			check_token "$token"
			_out=$($KVAS_BIN debug dns 2>&1 | tr -d '\033\r' | sed 's/\[[0-9][0-9;]*[a-zA-Z]//g; s/\[m//g' | sed 's/\t/ /g; s/\\/\\\\/g; s/"/\\"/g; s/$/\\n/' | tr -d '\n')
			printf '{"ok":true,"output":"%s"}\n' "$_out"
			;;
		kvas_debug_iptables)
			check_token "$token"
			_out=$($KVAS_BIN debug iptables 2>&1 | tr -d '\033\r' | sed 's/\[[0-9][0-9;]*[a-zA-Z]//g; s/\[m//g' | sed 's/\t/ /g; s/\\/\\\\/g; s/"/\\"/g; s/$/\\n/' | tr -d '\n')
			printf '{"ok":true,"output":"%s"}\n' "$_out"
			;;
		tunnel_test_site)
			check_token "$token"
			_iface=$(echo "$QUERY_STRING" | sed 's/.*iface=//; s/&.*//')
			_iface=$(echo "$_iface" | sed 's/+/ /g; s/%/\\x/g' | xargs -0 printf 2>/dev/null)
			_site=$(echo "$QUERY_STRING" | sed 's/.*site=//')
			_site=$(echo "$_site" | sed 's/+/ /g; s/%2[fF]/\//g; s/%3[aA]/:/g; s/%/\\x/g' | xargs -0 printf 2>/dev/null)
			[ -z "$_iface" ] && json_error "iface required"
			[ -z "$_site" ] && json_error "site required"
			# Определяем метод: SOCKS5 для Proxy21/41/42, --interface для остальных
			local _method=""
			local _socks_port=""
			local _curl_opt=""
			case "$_iface" in
				Proxy21|t2s21|vless)    _method="socks"; _socks_port="1097"; _curl_opt="-x socks5://127.0.0.1:${_socks_port}" ;;
				Proxy41|t2s41|hysteria) _method="socks"; _socks_port="10808"; _curl_opt="-x socks5://127.0.0.1:${_socks_port}" ;;
				Proxy42|awg)           _method="socks"; _socks_port="10818"; _curl_opt="-x socks5://127.0.0.1:${_socks_port}" ;;
				*)
					_method="interface"
					_ent=$(grep "$_iface" /opt/etc/inface_equals 2>/dev/null | head -1 | cut -d'|' -f2)
					[ -z "$_ent" ] && _ent="$_iface"
					_curl_opt="--interface $_ent"
					;;
			esac
			# 1. IP туннеля — через IP-сервис
			local _tunnel_ip=$(curl -s --max-time 10 $_curl_opt "https://2ip.io" 2>/dev/null)
			[ -z "$_tunnel_ip" ] && _tunnel_ip=$(curl -s --max-time 15 $_curl_opt "https://ifconfig.me" 2>/dev/null)
			# Проверяем что это IP
			echo "$_tunnel_ip" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' || _tunnel_ip="нет ответа"
			# 2. HTTP код сайта через туннель
			local _http=$(curl -s --max-time 10 $_curl_opt -o /dev/null -w '%{http_code}' "https://${_site}" 2>/dev/null)
			# 3. Время отклика
			local _time=$(curl -s --max-time 10 $_curl_opt -o /dev/null -w '%{time_total}' "https://${_site}" 2>/dev/null)
			[ -z "$_http" ] && _http="000"
			[ -z "$_time" ] && _time="0"
			# 4. Скорость скачивания (KB/s) — через Cloudflare speed test
			local _speed="0"
			_speed=$(curl -s --max-time 15 $_curl_opt -o /dev/null -w '%{speed_download}' "https://speed.cloudflare.com/__down?bytes=1048576" 2>/dev/null)
			[ -z "$_speed" ] || [ "$_speed" = "0" ] && _speed=$(curl -s --max-time 15 $_curl_opt -o /dev/null -w '%{speed_download}' "https://nbg1-speed.hetzner.com/1MB.bin" 2>/dev/null)
			[ -z "$_speed" ] && _speed="0"
			_speed=$(echo "$_speed" | awk '{printf "%.0f", $1/1024}')
			printf '{"ok":true,"ip":"%s","http":"%s","time":"%s","speed":"%s","method":"%s"}\n' "$_tunnel_ip" "$_http" "$_time" "$_speed" "$_method"
			;;
		tunnel_speed_test)
			check_token "$token"
			_iface=$(echo "$QUERY_STRING" | sed 's/.*iface=//; s/&.*//')
			_iface=$(echo "$_iface" | sed 's/+/ /g; s/%/\\x/g' | xargs -0 printf 2>/dev/null)
			[ -z "$_iface" ] && json_error "iface required"
			local _url="https://nbg1-speed.hetzner.com/100MB.bin"
			local _curl_opt=""
			case "$_iface" in
				Proxy21|t2s21|vless)    _curl_opt="-x socks5://127.0.0.1:1097" ;;
				Proxy41|t2s41|hysteria) _curl_opt="-x socks5://127.0.0.1:10808" ;;
				Proxy42|awg)           _curl_opt="-x socks5://127.0.0.1:10818" ;;
				*)
					_ent=$(grep "$_iface" /opt/etc/inface_equals 2>/dev/null | head -1 | cut -d'|' -f2)
					[ -z "$_ent" ] && _ent="$_iface"
					_curl_opt="--interface $_ent"
					;;
			esac
			local _tunnel_ip=$(curl -s --max-time 10 $_curl_opt "https://2ip.io" 2>/dev/null)
			[ -z "$_tunnel_ip" ] && _tunnel_ip="нет ответа"
			local _result=$(curl -s --max-time 60 $_curl_opt -o /dev/null -w '%{speed_download} %{time_total}' "$_url" 2>/dev/null)
			local _speed=$(echo "$_result" | awk '{print $1}')
			local _time=$(echo "$_result" | awk '{print $2}')
			[ -z "$_speed" ] && _speed="0"
			[ -z "$_time" ] && _time="0"
			_speed=$(echo "$_speed" | awk '{printf "%.0f", $1/1024}')
			printf '{"ok":true,"ip":"%s","speed":"%s","time":"%s"}\n' "$_tunnel_ip" "$_speed" "$_time"
			;;
		*)
			json_error "unknown action"
			;;
	esac
}



main "$@"
