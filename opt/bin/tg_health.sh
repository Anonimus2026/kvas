#!/bin/sh
# Периодическая проверка здоровья (P.8, событие health), cron.15min
. /opt/apps/kvas/bin/libs/tgq 2>/dev/null || exit 0
_probs=""
/opt/etc/init.d/S56dnsmasq status 2>/dev/null | grep -qi alive || _probs="${_probs}dnsmasq не работает; "
if [ "$(grep '^ADGUARD_ENABLE=' /opt/etc/kvas.conf 2>/dev/null | cut -d= -f2)" = "true" ]; then
	/opt/etc/init.d/S99adguardhome status 2>/dev/null | grep -qi alive || _probs="${_probs}AdGuard не работает; "
fi
_free_k=$(df /opt 2>/dev/null | awk 'NR==2{print $4}')
if [ -n "${_free_k}" ] && [ "${_free_k}" -lt 10240 ] 2>/dev/null; then
	_probs="${_probs}мало места в /opt (${_free_k}K); "
fi
_state=/opt/var/kvas/tg.health.state
if [ -n "${_probs}" ]; then
	_new="p:$(printf '%s' "${_probs}" | md5sum 2>/dev/null | cut -d' ' -f1)"
else
	_new="clean"
fi
_old=$(cat "${_state}" 2>/dev/null)
if [ -n "${_probs}" ] && [ "${_new}" != "${_old}" ]; then
	tg_notify health "Проблемы: ${_probs}"
elif [ -z "${_probs}" ] && [ -n "${_old}" ] && [ "${_old}" != "clean" ]; then
	tg_notify health "Все проверки снова в норме"
fi
mkdir -p /opt/var/kvas 2>/dev/null
echo "${_new}" > "${_state}" 2>/dev/null
exit 0
