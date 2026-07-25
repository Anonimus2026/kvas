#!/bin/sh
# CGI backend for KVAS Monitor Web UI
# HTTP headers are handled by httpd.sh.
# This script prints only the JSON body.

json_escape() {
	printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\t/\\t/g; s/\n/\\n/g'
}

DNS_LOG=/tmp/kvas-dns.log

# Build IP→domain cache from DNS log (one pass, fast)
IP_CACHE=/tmp/kvas-ip-cache.txt
build_ip_cache() {
	[ ! -f "$DNS_LOG" ] || [ ! -s "$DNS_LOG" ] && return
	: > "$IP_CACHE"
	# "reply <domain> is <IP>" — map resolved IP → domain
	grep ' is ' "$DNS_LOG" 2>/dev/null | grep -v '<CNAME>' | \
		sed -n 's/.*reply \([^ ]*\) is \([0-9][0-9.]*\).*/\2=\1/p' >> "$IP_CACHE"
	# "cached <domain> is <IP>" — same format
	grep ' is ' "$DNS_LOG" 2>/dev/null | grep -v '<CNAME>' | \
		sed -n 's/.*cached \([^ ]*\) is \([0-9][0-9.]*\).*/\2=\1/p' >> "$IP_CACHE"
	# "query[A] <domain> from <IP>" — map client IP → last queried domain
	grep 'query\[A\]' "$DNS_LOG" 2>/dev/null | \
		sed -n 's/.*query\[A\] \([^ ]*\) from \([0-9][0-9.]*\).*/\2=\1/p' >> "$IP_CACHE"
	# Deduplicate — keep last (most recent)
	if [ -s "$IP_CACHE" ]; then
		awk -F= '!seen[$1]++' "$IP_CACHE" > "${IP_CACHE}.tmp"
		mv "${IP_CACHE}.tmp" "$IP_CACHE"
	fi
}

# Resolve IP using cache then reverse DNS
cached_resolve() {
	local ip="$1"
	[ -z "$ip" ] && return
	[ -f "$IP_CACHE" ] && {
		local cached
		cached=$(grep "^${ip}=" "$IP_CACHE" 2>/dev/null | tail -1 | cut -d= -f2)
		[ -n "$cached" ] && [ "$cached" != "$ip" ] && echo "$cached" && return
	}
	local name=""
	if command -v dig >/dev/null 2>&1; then
		name=$(dig +short -x "$ip" 2>/dev/null | sed 's/\.$//')
	fi
	if [ -z "$name" ] && command -v nslookup >/dev/null 2>&1; then
		name=$(nslookup "$ip" 2>/dev/null | awk '/^Name:/ {a=1; next} a && /^Address/ {print $NF; exit}')
		[ -z "$name" ] && name=$(nslookup "$ip" 2>/dev/null | grep 'name = ' | sed "s/.*name = //; s/\.$//")
	fi
	[ -z "$name" ] && name="$ip"
	echo "${ip}=${name}" >> "$IP_CACHE" 2>/dev/null
	echo "$name"
}

# Find last DNS query from a client IP (for port 53 connections)
find_dns_query() {
	local client_ip="$1"
	[ -f "$DNS_LOG" ] || return
	grep "query\[A\].*from ${client_ip}$" "$DNS_LOG" 2>/dev/null | tail -1 | \
		sed -n 's/.*query\[A\] \([^ ]*\) from.*/\1/p'
}

print_connections_json() {
	_kvas_ips="$1"
	_kvas_filter_proto="$2"
	_kvas_filter_port="$3"
	_kvas_use_conntrack="${4:-1}"
	[ -z "$_kvas_ips" ] && echo -n '[]' && return

	build_ip_cache

	_kvas_ct_data=""
	if [ "$_kvas_use_conntrack" != "0" ]; then
		if [ -s /tmp/kvas-monitor/conntrack_live ]; then
			_kvas_ct_data=$(cat /tmp/kvas-monitor/conntrack_live 2>/dev/null)
		fi
		if [ -z "$_kvas_ct_data" ] && command -v conntrack >/dev/null 2>&1; then
			_kvas_conntrack_data=""
			for _kvas_ip in $(echo "$_kvas_ips" | tr ',' ' '); do
				_kvas_cline=$(conntrack -L -s "$_kvas_ip" 2>/dev/null | sort -u)
				[ -n "$_kvas_cline" ] && _kvas_conntrack_data="$_kvas_conntrack_data$_kvas_cline
"
				_kvas_cline=$(conntrack -L -d "$_kvas_ip" 2>/dev/null | sort -u)
				[ -n "$_kvas_cline" ] && _kvas_conntrack_data="$_kvas_conntrack_data$_kvas_cline
"
			done
			_kvas_ct_data=$_kvas_conntrack_data
		fi
		if [ -z "$_kvas_ct_data" ] && [ -f /proc/net/nf_conntrack ]; then
			_kvas_pat=$(echo "$_kvas_ips" | sed 's/\./\\./g; s/,/|/g')
			_kvas_ct_data=$(grep -E "src=${_kvas_pat}|dst=${_kvas_pat}" /proc/net/nf_conntrack 2>/dev/null)
		fi
	fi

	echo -n '['; _kvas_first=""
	if [ -n "$_kvas_ct_data" ]; then
		_kvas_sorted=$(echo "$_kvas_ct_data" | sort 2>/dev/null)
		set -f; _kvas_oldifs="$IFS"; IFS='
'
		for _kvas_line in $_kvas_sorted; do
			IFS="$_kvas_oldifs"; set +f
			[ -z "$_kvas_line" ] && continue
			_kvas_proto=$(echo "$_kvas_line" | awk '$1 ~ /^ipv/ {print $3; next} {print $1}')
			_kvas_src=$(echo "$_kvas_line" | tr ' ' '\n' | grep '^src=' | head -1 | cut -d= -f2)
			_kvas_dst=$(echo "$_kvas_line" | tr ' ' '\n' | grep '^dst=' | head -1 | cut -d= -f2)
			_kvas_sport=$(echo "$_kvas_line" | tr ' ' '\n' | grep '^sport=' | head -1 | cut -d= -f2)
			_kvas_dport=$(echo "$_kvas_line" | tr ' ' '\n' | grep '^dport=' | head -1 | cut -d= -f2)
			[ -z "$_kvas_src" ] && [ -z "$_kvas_dst" ] && continue
			if [ -n "$_kvas_filter_proto" ] && [ "$_kvas_filter_proto" != "all" ]; then
				_kvas_proto_low=$(echo "$_kvas_proto" | tr '[:upper:]' '[:lower:]')
				_kvas_filter_low=$(echo "$_kvas_filter_proto" | tr '[:upper:]' '[:lower:]')
				[ "$_kvas_proto_low" != "$_kvas_filter_low" ] && continue
			fi
			if [ -n "$_kvas_filter_port" ] && [ "$_kvas_filter_port" != "all" ]; then
				echo "$_kvas_line" | grep -qE "sport=${_kvas_filter_port}[^0-9]|dport=${_kvas_filter_port}[^0-9]" || continue
			fi
			_kvas_dname=""
			if [ "$_kvas_dport" = "53" ]; then
				_kvas_dname=$(find_dns_query "$_kvas_src")
			fi
			if [ -z "$_kvas_dname" ]; then
				_kvas_dname=$(cached_resolve "$_kvas_dst")
			fi
			printf '%s{"proto":"%s","src":"%s","sport":"%s","dst":"%s","dname":"%s","dport":"%s"}' \
				"$_kvas_first" \
				"$(json_escape "$_kvas_proto")" \
				"$(json_escape "$_kvas_src")" \
				"$(json_escape "$_kvas_sport")" \
				"$(json_escape "$_kvas_dst")" \
				"$(json_escape "$_kvas_dname")" \
				"$(json_escape "$_kvas_dport")"
			_kvas_first=,
		done
		IFS="$_kvas_oldifs"; set +f
	fi
	echo -n ']'
}

print_dns_json() {
	_kvas_ips="$1"
	[ -z "$_kvas_ips" ] && echo -n '[]' && return

	_kvas_dns_data=""
	if [ -s /tmp/kvas-monitor/dns_live ]; then
		for _kvas_ip in $(echo "$_kvas_ips" | tr ',' ' '); do
			_kvas_line=$(grep "from ${_kvas_ip}$" /tmp/kvas-monitor/dns_live 2>/dev/null | tail -50)
			[ -n "$_kvas_line" ] && _kvas_dns_data="$_kvas_dns_data$_kvas_line
"
		done
	fi
	if [ -z "$_kvas_dns_data" ] && [ -s "$DNS_LOG" ]; then
		for _kvas_ip in $(echo "$_kvas_ips" | tr ',' ' '); do
			_kvas_line=$(grep "from ${_kvas_ip}$" "$DNS_LOG" 2>/dev/null | tail -50)
			[ -n "$_kvas_line" ] && _kvas_dns_data="$_kvas_dns_data$_kvas_line
"
		done
	fi
	if [ -z "$_kvas_dns_data" ] && command -v logread >/dev/null 2>&1; then
		_kvas_dns_data=$(logread 2>/dev/null | grep "dnsmasq.*from" | tail -100)
	fi
	[ -z "$_kvas_dns_data" ] && echo -n '[]' && return

	echo -n '['
	_kvas_first=""
	_kvas_sorted=$(echo "$_kvas_dns_data" | sort -u)
	set -f; _kvas_oldifs="$IFS"; IFS='
'
	for _kvas_line in $_kvas_sorted; do
		IFS="$_kvas_oldifs"; set +f
		[ -z "$_kvas_line" ] && continue
		_kvas_query=$(echo "$_kvas_line" | sed -n 's/.*query\[A[^]]*\] \([^ ]*\) from.*/\1/p')
		[ -z "$_kvas_query" ] && _kvas_query=$(echo "$_kvas_line" | sed -n 's/.*reply \([^ ]*\) is.*/\1/p')
		[ -z "$_kvas_query" ] && _kvas_query=$(echo "$_kvas_line" | tr -s ' ')
		printf '%s{"raw":"%s","domain":"%s"}' \
			"$_kvas_first" \
			"$(json_escape "$_kvas_line")" \
			"$(json_escape "$_kvas_query")"
		_kvas_first=,
	done
	IFS="$_kvas_oldifs"; set +f
	echo -n ']'
}

# Check if device has recent DNS activity (last 30s)
device_has_activity() {
	_kvas_ip="$1"
	if [ -s /tmp/kvas-monitor/dns_live ] && grep -q "from ${_kvas_ip}$" /tmp/kvas-monitor/dns_live 2>/dev/null; then
		return 0
	fi
	if [ -s "$DNS_LOG" ] && grep -q "from ${_kvas_ip}$" "$DNS_LOG" 2>/dev/null; then
		return 0
	fi
	if command -v logread >/dev/null 2>&1; then
		logread 2>/dev/null | grep "dnsmasq.*from ${_kvas_ip}$" | head -1 | grep -q . && return 0
	fi
	return 1
}

print_devices_json() {
	local _kvas_sort="${1:-ip}"
	local _kvas_use_conntrack="${2:-1}"
	local _kvas_list=""
	if command -v curl >/dev/null 2>&1; then
		_kvas_bindings=$(curl -s --connect-timeout 3 127.0.0.1:79/rci/show/ip/dhcp/bindings 2>/dev/null)
		if [ -n "$_kvas_bindings" ] && echo "$_kvas_bindings" | grep -q '"lease"'; then
			if command -v jq >/dev/null 2>&1; then
				_kvas_list=$(echo "$_kvas_bindings" | jq -r '.lease[] | "\(.ip)|\(.name)"' 2>/dev/null)
			else
				_kvas_list=$(echo "$_kvas_bindings" | sed 's/.*"lease":\[//' | sed 's/\].*//' | \
					sed 's/},{/}\n{/g' | while IFS= read -r _kvas_entry; do
					_kvas_ip=$(echo "$_kvas_entry" | grep -o '"ip":"[^"]*"' | cut -d'"' -f4)
					_kvas_name=$(echo "$_kvas_entry" | grep -o '"name":"[^"]*"' | cut -d'"' -f4)
					[ -n "$_kvas_ip" ] && echo "${_kvas_ip}|${_kvas_name}"
				done)
			fi
		fi
	fi

	if [ -z "$_kvas_list" ] && command -v ip >/dev/null 2>&1; then
		_kvas_list=$(ip neigh show 2>/dev/null | grep -E 'REACHABLE|STALE|DELAY' | awk '{print $1 "|" $5}')
	fi

	if [ -z "$_kvas_list" ] && [ -f /proc/net/arp ]; then
		_kvas_list=$(tail -n +2 /proc/net/arp 2>/dev/null | awk '$2 != "0x0" {print $1 "|" $4}')
	fi

	if [ -z "$_kvas_list" ]; then
		echo -n '[]'
		return
	fi

	# Build active IP list from conntrack
	_kvas_ct_active=""
	if [ "$_kvas_use_conntrack" != "0" ]; then
		if [ -s /tmp/kvas-monitor/conntrack_live ]; then
			_kvas_ct_active=$(grep -o 'src=[0-9.]*' /tmp/kvas-monitor/conntrack_live 2>/dev/null | cut -d= -f2 | sort -u)
		fi
		if [ -z "$_kvas_ct_active" ] && command -v conntrack >/dev/null 2>&1; then
			_kvas_ct_active=$(conntrack -L 2>/dev/null | grep -o 'src=[0-9.]*' | cut -d= -f2 | sort -u)
		fi
		if [ -z "$_kvas_ct_active" ] && [ -f /proc/net/nf_conntrack ]; then
			_kvas_ct_active=$(grep -o 'src=[0-9.]*' /proc/net/nf_conntrack 2>/dev/null | cut -d= -f2 | sort -u)
		fi
	fi

	# Sort and add status/activity
	echo "$_kvas_list" | while IFS='|' read -r _kvas_ip _kvas_name; do
		# Build sort key: zero-padded IP or name
		_kvas_o1=$(echo "$_kvas_ip" | cut -d. -f1)
		_kvas_o2=$(echo "$_kvas_ip" | cut -d. -f2)
		_kvas_o3=$(echo "$_kvas_ip" | cut -d. -f3)
		_kvas_o4=$(echo "$_kvas_ip" | cut -d. -f4)
		_kvas_sortkey=$(printf "%03d.%03d.%03d.%03d" "$_kvas_o1" "$_kvas_o2" "$_kvas_o3" "$_kvas_o4")
		if [ "$_kvas_sort" = "name" ]; then
			_kvas_sortkey="$(echo "$_kvas_name" | tr '[:upper:]' '[:lower:]')|$_kvas_sortkey"
		fi
		printf "%s|%s|%s\n" "$_kvas_sortkey" "$_kvas_ip" "$_kvas_name"
	done | sort | while IFS='|' read -r _kvas_sk _kvas_ip _kvas_name; do
		[ -z "$_kvas_ip" ] && continue
		local _kvas_active="false"
		device_has_activity "$_kvas_ip" && _kvas_active="true"
		local _kvas_status="unknown"
		if [ -n "$_kvas_ct_active" ]; then
			echo "$_kvas_ct_active" | grep -Fxq "$_kvas_ip" 2>/dev/null && _kvas_status="active" || _kvas_status="idle"
		fi
		printf '{"ip":"%s","name":"%s","active":%s,"status":"%s"}\n' \
			"$(json_escape "$_kvas_ip")" \
			"$(json_escape "$_kvas_name")" \
			"$_kvas_active" \
			"$_kvas_status"
	done | awk 'BEGIN{printf"["; n=0} {if(n++) printf","; printf"%s",$0} END{printf"]"}'
}

action=$(echo "$QUERY_STRING" | sed 's/&.*//')

case "$action" in
	action=devices*)
		sort=$(echo "&$QUERY_STRING" | sed -n 's/.*[?&]sort=\([^&]*\).*/\1/p' 2>/dev/null)
		conntrack=$(echo "&$QUERY_STRING" | sed -n 's/.*[?&]conntrack=\([^&]*\).*/\1/p' 2>/dev/null)
		[ -z "$conntrack" ] && conntrack="1"
		print_devices_json "$sort" "$conntrack"
		;;
	action=data*)
		ips=$(echo "$QUERY_STRING" | sed 's/.*ips=//; s/&.*//; s/%2C/,/g' | sed 's/%20/ /g')
		proto=$(echo "&$QUERY_STRING" | sed -n 's/.*[?&]proto=\([^&]*\).*/\1/p' 2>/dev/null)
		port=$(echo "&$QUERY_STRING" | sed -n 's/.*[?&]port=\([^&]*\).*/\1/p' 2>/dev/null)
		conntrack=$(echo "&$QUERY_STRING" | sed -n 's/.*[?&]conntrack=\([^&]*\).*/\1/p' 2>/dev/null)
		[ -z "$conntrack" ] && conntrack="1"
		if [ -z "$ips" ]; then
			echo '{"error":"no ips specified","connections":[],"dns":[]}'
		else
			echo -n '{"connections":'
			print_connections_json "$ips" "$proto" "$port" "$conntrack"
			echo -n ',"dns":'
			print_dns_json "$ips"
			echo -n '}'
			echo
		fi
		;;
	action=status)
		echo -n '{'
		echo -n '"socat":'
		command -v socat >/dev/null 2>&1 && echo -n 'true' || echo -n 'false'
		echo -n ',"conntrack":'
		command -v conntrack >/dev/null 2>&1 && echo -n 'true' || echo -n 'false'
		echo -n ',"dns_log":'
		[ -s "$DNS_LOG" ] && echo -n 'true' || echo -n 'false'
		echo -n '}'
		echo
		;;
	action=debug)
		echo -n '{'
		echo -n '"path":"'
		json_escape "$PATH"
		echo -n '"'
		echo -n ',"has_conntrack_cmd":'
		command -v conntrack >/dev/null 2>&1 && echo -n 'true' || echo -n 'false'
		if command -v conntrack >/dev/null 2>&1; then
			echo -n ',"conntrack_path":"'
			json_escape "$(command -v conntrack 2>/dev/null)"
			echo -n '"'
			echo -n ',"conntrack_tcp_entries":'
			conntrack -L -s 10.0.0.1 2>/dev/null | wc -l
			echo -n ',"conntrack_total_entries":'
			conntrack -L 2>/dev/null | wc -l
		fi
		echo -n ',"has_proc_net_nf_conntrack":'
		[ -f /proc/net/nf_conntrack ] && echo -n 'true' || echo -n 'false'
		if [ -f /proc/net/nf_conntrack ]; then
			echo -n ',"proc_nf_conntrack_lines":'
			wc -l < /proc/net/nf_conntrack 2>/dev/null || echo -n '0'
		fi
		echo -n ',"has_monitor_cache":'
		[ -s /tmp/kvas-monitor/conntrack_live ] && echo -n 'true' || echo -n 'false'
		if [ -s /tmp/kvas-monitor/conntrack_live ]; then
			echo -n ',"monitor_cache_size":'
			wc -c < /tmp/kvas-monitor/conntrack_live 2>/dev/null || echo -n '0'
			echo -n ',"monitor_cache_lines":'
			wc -l < /tmp/kvas-monitor/conntrack_live 2>/dev/null || echo -n '0'
		fi
		echo -n ',"dns_log_exists":'
		[ -f "$DNS_LOG" ] && echo -n 'true' || echo -n 'false'
		echo -n ',"dns_log_size":'
		[ -f "$DNS_LOG" ] && wc -c < "$DNS_LOG" 2>/dev/null || echo -n '0'
		echo -n ',"dns_log_lines":'
		[ -f "$DNS_LOG" ] && wc -l < "$DNS_LOG" 2>/dev/null || echo -n '0'
		echo -n ',"has_logread":'
		command -v logread >/dev/null 2>&1 && echo -n 'true' || echo -n 'false'
		if command -v logread >/dev/null 2>&1; then
			echo -n ',"logread_dnsmasq_lines":'
			logread 2>/dev/null | grep -c 'dnsmasq.*from' 2>/dev/null || echo -n '0'
			echo -n ',"logread_dnsmasq_sample":"'
			json_escape "$(logread 2>/dev/null | grep 'dnsmasq.*from' | tail -3)"
			echo -n '"'
		fi
		echo -n ',"ip_cache_size":'
		[ -s "$IP_CACHE" ] && wc -l < "$IP_CACHE" 2>/dev/null || echo -n '0'
		echo -n ',"test_resolve_93.158.134.158":"'
		build_ip_cache 2>/dev/null
		echo -n "$(cached_resolve "93.158.134.158")"
		echo -n '"'
		echo -n ',"has_nslookup":'
		command -v nslookup >/dev/null 2>&1 && echo -n 'true' || echo -n 'false'
		if command -v nslookup >/dev/null 2>&1; then
			echo -n ',"nslookup_test":"'
			json_escape "$(nslookup 93.158.134.158 2>/dev/null | head -10)"
			echo -n '"'
		fi
		echo -n ',"has_dig":'
		command -v dig >/dev/null 2>&1 && echo -n 'true' || echo -n 'false'
		if command -v dig >/dev/null 2>&1; then
			echo -n ',"dig_test":"'
			json_escape "$(dig +short -x 93.158.134.158 2>/dev/null)"
			echo -n '"'
		fi
		echo -n '}'
		echo
		;;
	action=test_data*)
		ips=$(echo "$QUERY_STRING" | sed 's/.*ips=//; s/&.*//; s/%2C/,/g' | sed 's/%20/ /g')
		echo -n '{'
		echo -n '"ips":"'
		json_escape "$ips"
		echo -n '"'
		echo -n ',"active_src_ips":"'
		if [ -f /proc/net/nf_conntrack ]; then
			json_escape "$(grep -o 'src=[0-9.]*' /proc/net/nf_conntrack 2>/dev/null | cut -d= -f2 | sort -u | head -15 | tr '\n' ' ')"
		fi
		echo -n '"'
		echo -n ',"proc_match_count":'
		if [ -f /proc/net/nf_conntrack ] && [ -n "$ips" ]; then
			_kvas_pat=$(echo "$ips" | sed 's/\./\\./g; s/,/|/g')
			grep -c -E "src=${_kvas_pat}|dst=${_kvas_pat}" /proc/net/nf_conntrack 2>/dev/null || echo -n '0'
		else
			echo -n '0'
		fi
		echo -n ',"proc_match_sample":"'
		if [ -f /proc/net/nf_conntrack ] && [ -n "$ips" ]; then
			_kvas_pat=$(echo "$ips" | sed 's/\./\\./g; s/,/|/g')
			json_escape "$(grep -E "src=${_kvas_pat}|dst=${_kvas_pat}" /proc/net/nf_conntrack 2>/dev/null | head -5)"
		fi
		echo -n '"'
		echo -n ',"conntrack_cmd_match_count":'
		if command -v conntrack >/dev/null 2>&1 && [ -n "$ips" ]; then
			_kvas_total=0
			for _kvas_ip in $(echo "$ips" | tr ',' ' '); do
				_kvas_c=$(conntrack -L -s "$_kvas_ip" 2>/dev/null | wc -l)
				_kvas_total=$((_kvas_total + _kvas_c))
				_kvas_c=$(conntrack -L -d "$_kvas_ip" 2>/dev/null | wc -l)
				_kvas_total=$((_kvas_total + _kvas_c))
			done
			echo -n "$_kvas_total"
		else
			echo -n '0'
		fi
		echo -n ',"conntrack_cmd_sample":"'
		if command -v conntrack >/dev/null 2>&1 && [ -n "$ips" ]; then
			_kvas_sample=""
			for _kvas_ip in $(echo "$ips" | tr ',' ' '); do
				_kvas_sample="$_kvas_sample$(conntrack -L -s "$_kvas_ip" 2>/dev/null | head -3)
			"
				_kvas_sample="$_kvas_sample$(conntrack -L -d "$_kvas_ip" 2>/dev/null | head -3)
			"
			done
			json_escape "$_kvas_sample"
		fi
		echo -n '"'
		echo -n ',"ct_full_sample_head":"'
		if [ -f /proc/net/nf_conntrack ]; then
			json_escape "$(head -3 /proc/net/nf_conntrack 2>/dev/null)"
		fi
		echo -n '"'
		echo -n '}'
		echo
		;;
	*)
		echo '{"error":"unknown action"}'
		;;
esac
