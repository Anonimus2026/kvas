# KVAS Session Memory

## Ключевые исправления (сессия 2026-07-30)

### 1. VPN-трафик не идёт через KVAS_LIST на v25+ → v10-330+

**Проблема**: SSTP/OpenConnect клиенты (172.16.x.x) не маршрутизируются через KVAS_LIST.  
**Причина**: `RULE_PRIORITY=1778` в ndm — правило fwmark стоит **ниже** system rule 104 (`from all lookup 4098`), которая перехватывает трафик раньше.  
**Фикс**: `RULE_PRIORITY=1778` → `99` (чтобы правило fwmark стояло выше правила 104).  
**Файл**: `opt/apps/kvas/etc/ndm/ndm` + `opt/apps/kvas/bin/libs/ndm` (оба экземпляра).

### 2. Web UI: страница маршрутизации — «Известные устройства — Нет устройств»

**Проблема**: Вкладка «Маршрутизация» показывает «Нет устройств» в блоке известных устройств.  
**Причина**: В `manage.sh` у `action=route_devices` отсутствовал вывод `printf '{"ok":true,"devices":['` перед списком устройств → `JSON.parse` падал в catch.  
**Фикс**: Добавить `printf '{"ok":true,"devices":['` перед awk-выводом устройств.  
**Файл**: `opt/apps/kvas/bin/monitor/www/cgi-bin/manage.sh` (хэндлер `route_devices`).

### 3. Web UI: куча лишних IP (в т.ч. IPv6) в известных устройствах

**Проблема**: После фикса #2 устройства показывались, но с IPv6 адресами из ARP и публичными IP из conntrack.  
**Фиксы в `manage.sh` (`route_devices`)**:
- **ARP**: добавить фильтр `$1 ~ /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/` — только IPv4.
- **Conntrack**: добавить фильтр RFC 1918 — `_priv_re='src=(10\.[0-9]+\.[0-9]+\.[0-9]+|172\.(1[6-9]|2[0-9]|3[01])\.[0-9]+\.[0-9]+|192\.168\.[0-9]+\.[0-9]+)'` — только частные диапазоны.

**Версия с этими фиксами**: `kvas_1.1.9_beta-10-343_all.ipk`.

### 4. postinst не копирует ndm в libs

**Проблема**: На свежих прошивках (v10-330+) ndm используется из `/opt/apps/kvas/bin/libs/ndm`, но postinst базового ipk не копирует его туда из `/opt/apps/kvas/etc/ndm/ndm`.  
**Фикс**: Добавить `cp -f /opt/apps/kvas/etc/ndm/ndm /opt/apps/kvas/bin/libs/ndm` в postinst.  
**Реализовано**: В `mod331` скрипта сборки `build_fixed.ps1`.

### 5. conntrack flush при route refresh

**Проблема**: При обновлении маршрутов (`kvas route refresh`) сбрасывается вся таблица conntrack (`conntrack -D`), что разрывает активные соединения.  
**Фикс**: Удалить `conntrack -D` из `cmd_route_refresh` в файле route.  
**Реализовано**: В `mod332` скрипта сборки `build_fixed.ps1`.

### 6. data.sh: BusyBox sed не поддерживает \n

**Проблема**: В `data.sh` для парсинга DHCP bindings используется `sed 's/},{/}\n{/g'`. На BusyBox `\n` не интерпретируется как перевод строки.  
**Фикс**: Заменить sed на awk:  
```sh
awk -F'"' '/"ip":/ { ip = $4 } /"name":/ { name = $4; if (ip) { print ip "|" name; ip=""; name="" } }'
```  
**Примечание**: jq доступен на роутере, так что этот fallback используется редко, но на всякий случай.

## Скрипт сборки

**Файл**: `build_fixed.ps1` (в `%TEMP%\opencode\build_fixed.ps1`).  
**Исходники ipk**: `C:\Users\Pavel\AppData\Local\Temp\opencode\ipk_build\` (извлечено из v25).  
**Готовые ipk**: `C:\Users\Pavel\kvas\kvas_1.1.9_beta-10-{version}_all.ipk`.

### Варианты сборки
| Variant | Fixes |
|---------|-------|
| 331 | postinst cp ndm |
| 332 | postinst cp ndm + no conntrack flush |
| 340 | RULE_PRIORITY 99 |
| 341 | RULE_PRIORITY 99 + no conntrack flush |
| 342 | RULE_PRIORITY 99 + data.sh BusyBox fix |
| **343** | **RULE_PRIORITY 99 + route_devices JSON + ARP/conntrack filters** (рабочий) |

## Формат ipk
gzip(tar( debian-binary + control.tar.gz + data.tar.gz )), строки с LF.
