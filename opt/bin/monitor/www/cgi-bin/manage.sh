#!/bin/sh
# Management API for KVAS Web UI v2
# Actions: auth, hosts, vpn, failover, upgrade, backup, restore, update, kvas_list

PASS_FILE=/opt/kvas_web_pass
TOKEN_DIR=/tmp/kvas_web_tokens
KVAS_BIN=/opt/apps/kvas/bin/kvas
FAILOVER_CONF=/opt/etc/kvas.failover.conf
KVAS_LIST=/opt/etc/kvas.list
KVAS_CONF_FILE=/opt/etc/kvas.conf
PARENTAL_LIST=/opt/etc/kvas.blocked.list
PARENTAL_PAGE=/opt/apps/kvas/bin/monitor/www/blocked.html

json_str() { printf '%s' "$1" | jq -Rs '.' 2>/dev/null || printf '"%s"' "$1" | sed 's/"/\\"/g'; }
json_error() { printf '{"error":%s}\n' "$(json_str "$1")"; exit 0; }
json_ok()    { printf '{"ok":true,"msg":%s}\n' "$(json_str "$1")"; exit 0; }

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
	# Check which interface is configured as active VPN
	local inface_ent=$(grep "^INFACE_ENT=" /opt/etc/kvas.conf 2>/dev/null | cut -d= -f2)
	if [ -n "$inface_ent" ]; then
		# Check if it's a vless proxy interface
		case "$inface_ent" in
			*Proxy21*|*vless*) echo "vless"; return ;;
			*Proxy41*|*hysteria*) echo "hysteria"; return ;;
		esac
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
# Update hosts file for parental control
# Uses /opt/etc/hosts which is already configured in dnsmasq.conf (addn-hosts)
# Also adds iptables redirect so blocked domains show our blocked page
update_parental_hosts() {
	local hosts_file="/opt/etc/hosts"
	local router_ip=$(hostname -I 2>/dev/null | awk '{print $1}')
	[ -z "$router_ip" ] && router_ip="192.168.1.1"

	# Remove ALL old KVAS parental entries from hosts
	# Remove everything between "# KVAS Parental Control" markers
	sed -i '/# KVAS Parental Control/,/^#/ { /^# KVAS Parental Control/!/^#/!d; /^# KVAS Parental Control/d; }' "$hosts_file" 2>/dev/null
	# Also remove any orphaned entries (lines with router_ip that aren't in other sections)
	local _tmp=$(mktemp)
	awk -v rip="$router_ip" '
		/^# KVAS Parental Control/ { skip=1; next }
		/^#/ { skip=0 }
		!skip { print }
	' "$hosts_file" > "$_tmp" 2>/dev/null
	mv "$_tmp" "$hosts_file" 2>/dev/null

	# Clean up any old iptables rules (legacy)
	/opt/sbin/iptables -t nat -D PREROUTING -p tcp --dport 80 -j REDIRECT --to-port 8085 2>/dev/null


	if [ ! -f "$PARENTAL_LIST" ] || [ ! -s "$PARENTAL_LIST" ]; then
		# No blocked sites — just clean up
		if [ -f /opt/etc/init.d/S56dnsmasq ]; then
			/opt/etc/init.d/S56dnsmasq restart >/dev/null 2>&1
		fi
		return
	fi

	# Add blocked domains to hosts file
	echo "# KVAS Parental Control" >> "$hosts_file"
	while IFS= read -r line; do
		[ -z "$line" ] && continue
		[ "${line:0:1}" = "#" ] && continue
		echo "${router_ip} ${line}" >> "$hosts_file"
		echo "${router_ip} www.${line}" >> "$hosts_file"
	done < "$PARENTAL_LIST"

	# No iptables redirect needed - DNS blocking via /opt/etc/hosts is sufficient
	# Blocked domains resolve to router IP, browser shows connection refused or Keenetic page


	# Restart dnsmasq to pick up new hosts entries
	if [ -f /opt/etc/init.d/S56dnsmasq ]; then
		/opt/etc/init.d/S56dnsmasq restart >/dev/null 2>&1
	fi
}



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
			pass=$(echo "$QUERY_STRING" | sed 's/.*pass=//; s/&.*//' 2>/dev/null)
			[ "$pass" = "$QUERY_STRING" ] && pass=""
			[ -z "$pass" ] && json_error "pass required"
			[ ${#pass} -lt 4 ] && json_error "min 4 symbols"
			echo -n "$pass" | md5sum | awk '{print $1}' > "$PASS_FILE"
			json_ok "password set"
			;;
		auth)
			pass=$(echo "$QUERY_STRING" | sed 's/.*pass=//; s/&.*//' 2>/dev/null)
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
			printf '{"ok":true,"pkg":%s,"ver":%s,"mode":%s,"failover":%s,"vless":%s,"hysteria":%s,"hosts":%s,"xray_service":%s,"hysteria_service":%s}\n' \
				"$(json_str "$kvaspkg_name")" "$(json_str "$kvaspkg_ver")" "$(json_str "$vpn_mode")" "$(json_str "$failover")" \
				"$vless_running" "$hysteria_running" "$host_count" \
				"$(json_str "$xray_svc")" "$(json_str "$hysteria_svc")"
			;;
		hosts)
			check_token "$token"
			[ ! -f "$KVAS_LIST" ] && echo '{"ok":true,"hosts":[]}' && return
			printf '{"ok":true,"hosts":['
			first=1
			while IFS= read -r line; do
				[ -z "$line" ] && continue
				[ "$first" -eq 0 ] && printf ','
				first=0
				printf '%s' "$(json_str "$line")"
			done < "$KVAS_LIST"
			echo ']}'
			;;
		host_add)
			check_token "$token"
			domain=$(echo "$QUERY_STRING" | sed 's/.*domain=//; s/&.*//' 2>/dev/null)
			[ "$domain" = "$QUERY_STRING" ] && domain=""
			[ -z "$domain" ] && json_error "domain required"
			out=$($KVAS_BIN add "$domain" 2>&1)
			rc=$?
			[ $rc -ne 0 ] && json_error "add failed: $out"
			json_ok "added $domain"
			;;
		host_del)
			check_token "$token"
			domain=$(echo "$QUERY_STRING" | sed 's/.*domain=//; s/&.*//' 2>/dev/null)
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
				[ "$exit_code" != "0" ] && printf '{"ok":false,"error":"import failed","output":%s}\n' "$(json_str "$import_out")" && return
				printf '{"ok":true,"done":true,"output":%s}\n' "$(json_str "$import_out")"
			else
				lines=$(wc -l < /tmp/kvas_import_out.txt 2>/dev/null || echo 0)
				last_line=$(tail -1 /tmp/kvas_import_out.txt 2>/dev/null || echo "")
				printf '{"ok":true,"done":false,"lines":%s,"last":%s}\n' "$lines" "$(json_str "$last_line")"
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
			printf '{"ok":true,"mode":%s,"vless":%s,"hysteria":%s}\n' \
				"$(json_str "$vpn_mode")" "$vless_running" "$hysteria_running"
			;;
		tunnel_check)
			check_token "$token"
			vless_ok="false"
			hysteria_ok="false"
			command -v ss >/dev/null 2>&1 && {
				ss -tlnp 2>/dev/null | grep -q ":1097 " && vless_ok="true"
				ss -tlnp 2>/dev/null | grep -q ":10808 " && hysteria_ok="true"
			}
			[ "$vless_ok" = "false" ] && command -v netstat >/dev/null 2>&1 && netstat -tlnp 2>/dev/null | grep -q ":1097 " && vless_ok="true"
			[ "$hysteria_ok" = "false" ] && command -v netstat >/dev/null 2>&1 && netstat -tlnp 2>/dev/null | grep -q ":10808 " && hysteria_ok="true"
			printf '{"ok":true,"vless":%s,"hysteria":%s}\n' "$vless_ok" "$hysteria_ok"
			;;
		vpn_set)
			check_token "$token"
			proto=$(echo "$QUERY_STRING" | sed 's/.*proto=//; s/&.*//' 2>/dev/null)
			[ "$proto" = "$QUERY_STRING" ] && proto=""
			case "$proto" in
				vless|hysteria) ;;
				*) json_error "proto must be vless or hysteria" ;;
			esac
			out=$($KVAS_BIN vpn set "$proto" 2>&1)
			rc=$?
			[ $rc -ne 0 ] && json_error "switch failed: $out"
			json_ok "switched to $proto"
			;;
		failover_status)
			check_token "$token"
			failover_mode=$(get_failover_mode)
			[ -z "$failover_mode" ] && failover_mode="manual"
			primary="vless"
			interval=15
			threshold=2
			if [ -f "$FAILOVER_CONF" ]; then
				primary=$(grep "^PRIMARY=" "$FAILOVER_CONF" 2>/dev/null | cut -d= -f2)
				interval=$(grep "^CHECK_INTERVAL=" "$FAILOVER_CONF" 2>/dev/null | cut -d= -f2)
				threshold=$(grep "^FAIL_THRESHOLD=" "$FAILOVER_CONF" 2>/dev/null | cut -d= -f2)
			fi
			[ -z "$primary" ] && primary="vless"
			[ -z "$interval" ] && interval=15
			[ -z "$threshold" ] && threshold=2
			daemon_running=$(check_failover_daemon)
			printf '{"ok":true,"enabled":%s,"primary":%s,"interval":%s,"threshold":%s,"daemon":%s}\n' \
				"$(json_str "$failover_mode")" "$(json_str "$primary")" "$interval" "$threshold" "$daemon_running"
			;;
		failover)
			check_token "$token"
			cmd=$(echo "$QUERY_STRING" | sed 's/.*cmd=//; s/&.*//' 2>/dev/null)
			[ "$cmd" = "$QUERY_STRING" ] && cmd=""
			case "$cmd" in
				on|off)
					out=$($KVAS_BIN failover "$cmd" 2>&1)
					rc=$?
					[ $rc -ne 0 ] && json_error "failover $cmd failed: $out"
					json_ok "failover $cmd"
					;;
				status)
					out=$($KVAS_BIN failover status 2>&1)
					esc=$(printf '\033')
					out=$(echo "$out" | tr -d "$esc" | sed 's/\[[0-9;]*[a-zA-Z]//g')
					printf '{"ok":true,"data":%s}\n' "$(json_str "$out")"
					;;
				*) json_error "cmd must be on/off/status" ;;
			esac
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
			json_error "use CLI: kvas upgrade"
			;;
		check_update)
			check_token "$token"
			update_info=$(check_updates 2>/dev/null)
			printf '{"ok":true,"update":%s}\n' "$(json_str "$update_info")"
			;;
		backup)
			check_token "$token"
			out=$($KVAS_BIN backup 2>&1)
			rc=$?
			[ $rc -ne 0 ] && json_error "backup failed: $out"
			json_ok "backup done: $out"
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
		parental_list)
			check_token "$token"
			if [ ! -f "$PARENTAL_LIST" ]; then
				echo '{"ok":true,"sites":[]}'
				return
			fi
			printf '{"ok":true,"sites":['
			first=1
			while IFS= read -r line; do
				[ -z "$line" ] && continue
				[ "${line:0:1}" = "#" ] && continue
				[ "$first" -eq 0 ] && printf ','
				first=0
				printf '%s' "$(json_str "$line")"
			done < "$PARENTAL_LIST"
			echo ']}'
			;;
		parental_add)
			check_token "$token"
			domain=$(echo "$QUERY_STRING" | sed 's/.*domain=//; s/&.*//' 2>/dev/null)
			[ "$domain" = "$QUERY_STRING" ] && domain=""
			[ -z "$domain" ] && json_error "domain required"
			touch "$PARENTAL_LIST"
			# Check if already exists
			if grep -qF "$domain" "$PARENTAL_LIST" 2>/dev/null; then
				json_error "domain already blocked"
			fi
			echo "$domain" >> "$PARENTAL_LIST"
			# Update dnsmasq to redirect blocked domains
			update_parental_hosts
			json_ok "blocked $domain"
			;;
		parental_del)
			check_token "$token"
			domain=$(echo "$QUERY_STRING" | sed 's/.*domain=//; s/&.*//' 2>/dev/null)
			[ "$domain" = "$QUERY_STRING" ] && domain=""
			[ -z "$domain" ] && json_error "domain required"
			if [ ! -f "$PARENTAL_LIST" ]; then
				json_error "domain not found"
			fi
			sed -i "/^${domain}$/d" "$PARENTAL_LIST" 2>/dev/null
			update_parental_hosts
			json_ok "unblocked $domain"
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
			printf '{"ok":true,"full":%s,"list":%s,"exclude":%s,"guest_nets":%s}\n' \
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
				$KVAS_BIN route refresh >/dev/null 2>&1
				json_ok "added $ip to $type"
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
				$KVAS_BIN route refresh >/dev/null 2>&1
				json_ok "removed $ip from $type"
			fi
			;;
		route_refresh)
			check_token "$token"
			out=$($KVAS_BIN route refresh 2>&1)
			json_ok "routes refreshed"
			;;
		route_devices)
			check_token "$token"
			printf '{"ok":true,"devices":['
			first=1
			devices=$(curl -s "127.0.0.1:79/rci/show/ip/dhcp/bindings" 2>/dev/null | jq -r '.lease[] | "\(.ip)|\(.name)"' 2>/dev/null)
			if [ -n "$devices" ]; then
				echo "$devices" | awk -F'|' '{if(first++) printf ","; printf "{\"ip\":\"%s\",\"name\":\"%s\"}", $1, $2}'
			fi
			echo ']}'
			;;
		route_guest_networks)
			check_token "$token"
			_tmp="/tmp/kvas_guest_nets.$$"
			tunnel_iface=$(grep "^INFACE_ENT=" "$KVAS_CONF_FILE" 2>/dev/null | cut -d= -f2)
			internet_iface=$(/opt/sbin/ip route 2>/dev/null | grep default | awk '{print $5}' | head -1)
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
				printf '%s{"id":"%s","name":%s}' "$sep" "$iface" "$(json_str "$desc")"
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
				[ -n "$current" ] && current="${current},${net}" || current="$net"
				sed -i "/^INFACE_GUEST_ENT=/d" "$KVAS_CONF_FILE" 2>/dev/null
				echo "INFACE_GUEST_ENT=${current}" >> "$KVAS_CONF_FILE"
				$KVAS_BIN route refresh >/dev/null 2>&1
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
				new_list=$(echo "$current" | tr ',' '\n' | grep -v "^${net}$" | tr '\n' ',' | sed 's/,$//')
				sed -i "/^INFACE_GUEST_ENT=/d" "$KVAS_CONF_FILE" 2>/dev/null
				[ -n "$new_list" ] && echo "INFACE_GUEST_ENT=${new_list}" >> "$KVAS_CONF_FILE"
				$KVAS_BIN route refresh >/dev/null 2>&1
				json_ok "removed $net"
			fi
			;;
		*)
			json_error "unknown action"
			;;
	esac
}



main "$@"
