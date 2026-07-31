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

## Adblock-фиксы (сессия 2026-08-01, v344–v347)

### 7. kvas adblock on зависал на «Удаляем хосты, находящиеся в защищенном списке»

**Проблема**: `remove_white_hosts()` (main/adblock) строил гигантский regex из **всего** `/opt/etc/kvas.list` (`exclude_com=".*.$(cat kvas.list | tr -d '*' | sed ':a;N;$!ba;s/\n/$|.*./g')$"`) и гонял `grep -vE` по hosts-файлу — на BusyBox квадратично (27с на 1.5K записей × 1M строк; у пользователя список больше → «зависание»).  
**Фикс**: awk-фильтр с хэш-таблицей и перебором всех суффиксов хоста — **1:1 совпадение** со старым regex, 2с:
```awk
NR==FNR { gsub(/\*/, "", $0); if ($0 !~ /^#/ && $0 != "") wl[$0]=1; next }
{ host=$2; keep=1; h=host
  while (h != "") { if (h in wl) { keep=0; break }; h=substr(h,2) }
  if (keep) print }
```
**Файлы**: `bin/main/adblock` (`remove_white_hosts`, ~строки 145-164) + `bin/libs/adblock` (`ads_remove_white_hosts`, ~строки 229-248).

### 8. Загрузка источников падала при неудачном curl

**Проблема**: если `curl` не скачал источник (нет соединения / GitHub rate-limit с HTML), `/opt/tmp/hosts.tmp` не создавался → `cat` падал («can't open /opt/tmp/hosts.tmp»).  
**Фикс**: после curl проверка `[ ! -s "${TMP_FILE}" ]` → источник пишется в `/opt/tmp/kvas.err.log` и пропускается (как HTML-ошибки).  
**Файл**: `bin/main/adblock`, `load_adblock_hosts()`.

### 9. Семантика `kvas adblock add/del` перевернута + новый постоянный список block.list

**Проблема**: `kvas adblock add <host>` добавлял домен в **список исключений** (`exception.list`, белый список) — т.е. убирал из блокировки, что неочевидно. А `del` из-за бага правил **не тот файл** (sed по `ADBLOCK_HOSTS_FILE` вместо `ADBLOCK_LIST_EXCEPTION`), поэтому домен не возвращался в блокировку.  
**Фикс (v346-v347)**: семантика перевернута:
- `kvas adblock add <host>` — добавляет в постоянный `/opt/etc/adblock/block.list` + сразу в `ads.kvas.list`, и **убирает домен из `exception.list`**; перезапуск dnsmasq.
- `kvas adblock del <host>` — удаляет из `block.list`, `ads.kvas.list` и `exception.list`.
- `block.list` подхватывается при каждом обновлении: `main/adblock` в `add_regular_ads()` дописывает `sed 's/^/0.0.0.0 /' block.list` в hosts-файл — добавленные домены не теряются.

**Файлы**: `bin/libs/adblock` (`cmd_ads_add_host`, `cmd_ads_del_from_skip_list`), `bin/libs/main` (`ADBLOCK_BLOCK_FILE=/opt/etc/adblock/block.list`), `bin/main/adblock` (`add_regular_ads`).

### 10. mail.ru-реклама (rs.mail.ru, ads.vk.com) не покрывалась источниками

**Проблема**: ни StevenBlack, ни другие активные источники не содержали `rs.mail.ru` (лента-реклама mail.ru) и `ads.vk.com` (VK Ads). `rs.mail.ru` есть только в blocklistproject (закомментирован в sources.list), `ads.vk.com` — нигде.  
**Фикс**: домены зашиты в `add_regular_ads()` (`main/adblock`) — блокируются при каждом обновлении.

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
| **346** | v343 + external SOCKS5 на базе xray (не зашёл — заменён 3proxy в v347) |
| **347** | **v343 + external SOCKS5 via 3proxy** (`kvas proxy on\|off\|status\|passwd`) |
| **344** | v343 + adblock awk-fix + curl !-s (пересобранный корректно) |
| **345** | v344 + fix `kvas adblock del` (правил не тот файл) + rs.mail.ru/ads.vk.com в add_regular_ads |
| **346a** | v345 + перевёрнутая семантика adblock add/del + block.list |
| **347a** | v346 + add/del чистят exception.list (итоговый рабочий adblock) |

**Примечание**: версии 346/347 совпадают с номерами из прокси-фичи — разные ветки правок шли параллельно и обе использовали номера. Итоговый adblock-fix — в `kvas_1.1.9_beta-10-347_all.ipk` (файл от 2026-08-01).

## External SOCKS5 Proxy (v347, на базе 3proxy)

### Зачем 3proxy
xray-вариант (v346) не зашёл: внешние клиенты с SOCKS5 auth (Chrome) не подключались (ERR_UNEXPECTED_PROXY_AUTH). По статье форума Keenetic (forum.keenetic.ru/topic/3543) рабочая схема — 3proxy. Доступ извне через KeenDNS без проброса портов.

### Исполнение
- **3proxy** слушает на `0.0.0.0:<port>` (по умолч. 1080), `auth strong`, пароли в `/opt/etc/3proxy/passwd`
- **Routing по KVAS_LIST** через `allow`+`parent`:
  - `allow * * *<домены KVAS_LIST> * CONNECT,UDPASSOC` → `parent 1000 socks5 127.0.0.1 1097` (туннель)
  - `allow * * * * CONNECT,UDPASSOC` → direct
- **Внутренний xray (1097) не трогается** — работает как раньше
- Конфиг: `/opt/etc/3proxy/3proxy.cfg`, авто-перезагрузка через `monitor`
- **3proxy ставится автоматически** при `kvas proxy on` (`opkg install 3proxy`), если не установлен
- **Миграция с v346**: `_proxy_ext_cleanup_xray()` удаляет лишний proxy-ext/direct из xray.json
- Пароль генерируется автоматически (md5 от timestamp) при `kvas proxy on`, если не задан

### Команды
- `kvas proxy on [port] [password]` — включить прокси (авто-установка 3proxy)
- `kvas proxy off` — выключить прокси (стоп 3proxy)
- `kvas proxy status` — статус
- `kvas proxy passwd <user> <pass>` — сменить логин/пароль

### Файлы
- `opt/apps/kvas/bin/libs/vless` — `proxy_ext_on/off/status/passwd`, `_proxy_ext_*`
- `opt/apps/kvas/bin/kvas` — `proxy)` case в CLI

## Родительский контроль в WebUI (v348)

**Идея**: вкладка «Родительский контроль» между «Маршрутизация» и «Мониторинг трафика» блокирует сайты через `kvas adblock add/del` (тот же механизм, что перманентный block.list). Домены резолвятся в 0.0.0.0.

**Изменения**:
- `index.html`:
  - Вкладка `tab-parental` (между route и monitor), карточка с `#parentalList` + `#parentalInput`.
  - Скрытая parental-карточка из tab-manage удалена (строки ~174-183).
  - `loadParentalList()` добавлен в `showMain()` (рядом с loadRouteLists).
  - JS `loadParentalList/parentalAdd/parentalDel` — уже были, формат ответа `{"ok":true,"sites":[...]}`.
- `manage.sh`:
  - `PARENTAL_LIST=/opt/etc/adblock/block.list` (строка 12).
  - `parental_add` = `$KVAS_BIN adblock add <domain>`; `parental_del` = `$KVAS_BIN adblock del <domain>`.
  - Старый механизм через `/opt/etc/hosts` (update_parental_hosts, строка 137) **удалён** — блокировка только через adblock.
  - `parental_list` по-прежнему читает PARENTAL_LIST (теперь block.list).

**Примечание**: PARENTAL_PAGE (`blocked.html`) больше не используется — блокировка идёт на 0.0.0.0, а не на страницу-заглушку.

### 12. v348 баг: кнопки «Добавить»/«Удалить» в parental не работали (TypeError)

**Проблема**: `parentalAdd()`/`parentalDel()` вызывали `apiBtn(url, null, cb)`. В `apiBtn` первым делом выполняется `loadingBtn(btn, true)`, а `loadingBtn` при `btn=null` падал на `btn._text` (TypeError) → `fetch` вообще не выполнялся, кнопки «не работали».
**Фикс (v349)**: добавить guard в `loadingBtn`: `if (!btn) return;`.
**Файл**: `index.html` — `loadingBtn()` (строка ~372).
**Версия**: `kvas_1.1.9_beta-10-349_all.ipk`.

### 13. v350: «Заблокировано» но сайт не блочит + долгий рестарт dnsmasq

**Симптомы**: WebUI пишет «Заблокировано», но домен открывается; блокировка нестабильна / долго ждать.

**Диагностика (роутер)**: механизм исправен — запись `0.0.0.0 <domain>` попадает в `/opt/etc/adblock/ads.kvas.list`, `dig <domain> @127.0.0.1 -p 9753 +short` → `0.0.0.0`, ПК через 192.168.4.1 → `nslookup` → `0.0.0.0`. Не срабатывал повторный add (ya.ru уже был в block.list).

**Причины**:
1. `cmd_ads_add_host` (libs/adblock) использовал `grep -q "${host}"` без точного совпадения по block.list → если домен уже в списке (или совпадает как подстрока) → warning «уже добавлен» → запись `0.0.0.0 <host>` в `ads.kvas.list` НЕ дописывалась, но WebUI всё равно показывал «Заблокировано».
2. `restart_dns_service` делал полный `S56dnsmasq restart` — с 514k-строк файлом ads.kvas.list это медленно.

**Фикс (v350, libs/adblock)**:
- `cmd_ads_add_host`: точная проверка `grep -qxF "${host}"` в block.list; домен в `ads.kvas.list` гарантируется отдельной проверкой `grep -qF "0.0.0.0 ${host}"` → дописывается при необходимости; рестарт вызывается всегда.
- `restart_dns_service`: вместо полного рестарта — `kill -HUP "$(pidof dnsmasq)"` (dnsmasq мгновенно перечитывает addn-hosts), fallback на `S56dnsmasq restart`.

**Версия**: `kvas_1.1.9_beta-10-350_all.ipk`.

### 14. v351: кнопки Adblock on/off + авто-включение adblock в родительском контроле

**Проблема**: если `kvas adblock on` не включён, в dnsmasq.conf нет `addn-hosts=/opt/etc/adblock/ads.kvas.list` → parental-домены в ads.kvas.list не читаются → родительский контроль не работает. Плюс `kvas adblock on` из CLI жёстко передаёт `ask` (задаёт вопросы) — для CGI не годится.

**Решение (v351)**:
- Вкладка «Родительский контроль»: блок статуса adblock + кнопки **Adblock on** / **Adblock off**.
- `manage.sh` новые actions (без вопросов, напрямую правят dnsmasq.conf):
  - `adblock_status` — `{"ok":true,"adblock":"on"/"off"}` (по наличию addn-hosts).
  - `adblock_on` — добавить `addn-hosts=/opt/etc/adblock/ads.kvas.list` в dnsmasq.conf (если нет); если ads.kvas.list отсутствует — сгенерировать `sh /opt/apps/kvas/bin/main/adblock`; рестарт dnsmasq.
  - `adblock_off` — `sed -i '/addn-hosts=.../d'` dnsmasq.conf + рестарт.
- `parental_add` — перед `kvas adblock add` авто-включает adblock (если выключен).
- `index.html` — `loadAdblockStatus()` в `showMain()`, JS `adblockOn/adblockOff`.

**Скорость**: задержка блокировки = время, которое dnsmasq тратит на перечитывание ads.kvas.list (~514k строк) по SIGHUP/рестарту. hostsdir (inotify) мог бы дать мгновенную блокировку, но рискованно — не внедрялось.

**Версия**: `kvas_1.1.9_beta-10-351_all.ipk`.

## Формат ipk
gzip(tar( debian-binary + control.tar.gz + data.tar.gz )), строки с LF.
