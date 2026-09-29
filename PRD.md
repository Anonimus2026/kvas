# PRD: KVAS

**Версия:** 1.1.9_beta-10-614
**Дата:** 29.09.2026
**Репозиторий:** https://github.com/Anonimus2026/kvas
**Release:** https://github.com/Anonimus2026/kvas/releases/tag/v1.1.9
**Оригинал:** https://github.com/qzeleza/kvas

Файл содержит только актуальную информацию по текущей версии. История версий — в git/GitHub releases.

---

## 1. Описание

VPN-клиент для Keenetic (aarch64, KeenOS 5.1.x) с поддержкой VLESS, Hysteria 2, AmneziaWG и автоматическим переключением каналов (failover). Плюс adblock, закваски (tags), маршрутизация, web UI, backup/restore.

## 2. Структура проекта (SOT)

```
C:\Users\Pavel\kvas\backup_v546\            ← канонический снимок исходников (bin, etc, awg, hysteria)
C:\Users\Pavel\kvas\local_build\            ← SOT артефактов ipk (в т.ч. текущий 614)
Docker builder: /tmp/kfix/opt/apps/kvas/    ← канон в контейнере (SOT + CONTROL версии)
/home/me/kvas/opt/                          ← синхронизировано с kfix
C:\Users\Pavel\kvas\archive\                ← старые скрипты/пакеты/источники (не SOT)
C:\Users\Pavel\kvas\kvas-original\          ← git clone форка Anonimus2026 (push target)
```

Правило: правки — только в SOT, затем сборка в Docker. Файлы не тянуть через Windows-копирование (ломает кодировку/heredoc).

## 3. Сборка

```powershell
docker start builder
# исходники уже в /tmp/kfix/opt/apps/kvas (или /home/me/kvas/opt — идентичны)
docker exec -u root builder sh -c "cd /home/me/Entware && scripts/ipkg-build /tmp/kfix /tmp/kvas_output"
docker cp builder:/tmp/kvas_output/kvas_1.1.9_beta-10-<НОМЕР>_all.ipk C:\Users\Pavel\kvas\
gh release upload v1.1.9 "C:\Users\Pavel\kvas\kvas_1.1.9_beta-10-<НОМЕР>_all.ipk" --repo Anonimus2026/kvas --clobber
```

- `/tmp/build.sh` устарел (целится в `/tmp/base312_build`) — использовать `ipkg-build` как выше.
- GitHub Release `v1.1.9` — единственное место, откуда `kvas upgrade` качает обновления. Upgrade берёт **старший номер** сборки: `sort -n | tail -1` по `beta-10-<N>`. Ассеты: …, 576, 600, …, 610, 611, 612, 613, **614** (текущий).
- Название/описание релиза на GitHub **не трогать** (пишет пользователь).

## 4. Текущий статус (v614)

| Компонент | Статус |
|-----------|--------|
| VLESS (Reality, xhttp/grpc/tcp/ws) | ✓ |
| Hysteria 2 (QUIC) | ✓ |
| AmneziaWG / OpenConnect / WG | ✓ |
| Failover (3 канала: primary/secondary/tertiary) | ✓ работает |
| Web UI (статус, VPN, adblock, parental, закваски, диагностика, backup, upgrade) | ✓ |
| Backup / Restore (CLI + web upload) | ✓ (v591+: ELF-check, `_restored`, nested tar, `_rc`) |
| kvas upgrade (force-reinstall + rollback) | ✓ |
| Adblock + parental control | ✓ |
| Закваски tags (add/del/edit, web + CLI) | ✓ |
| **Список 2 — вторая полоса (kvas2.list → KVAS_LIST2 → mark 0xd1001 → table 201)** | ✓ v612 + Keenetic-native tunnels (v614) |
| **Telegram P.8: уведомления (tg_notify + quiet hours)** | ✓ |
| **Telegram P.8+: interactive bot (English ASCII menu)** | ✓ tested /menu v600–601 |
| **Telegram: singleton бота + cron keepalive (tg_sender)** | ✓ |

### 4.1 Telegram-бот (P.8+)

- **Файлы:** `bin/tg_bot.sh`, `bin/libs/tgq`, `bin/tg_sender.sh`, `bin/tg_job.sh`, `bin/tg_health.sh`; cron: `cron.1min/tg_sender`, `cron.15min/tg_health`.
- **Конфиг:** `TG_ENABLED`, `TG_BOT_TOKEN`, `TG_CHAT_ID`, `TG_QUIET_START/END` (тихие часы), whitelist событий `failover|update_found|upgrade|tunnel|health|parental_expire` (v606: +`upgrade` — иначе «Обновление выполнено» из CLI/WebUI не доходило).
- **Сеть:** Telegram только через `tg_curl`/`tg_curl_to` (socks5h, порт из `tg_socks_port`, default 1097). long-poll getUpdates `timeout=25`, sendMessage fire-and-forget, RC=0 только при `"ok":true`.
- **Singleton:** atomic `mkdir` lock + pid re-verify + `kill -9` чужих; один EXIT-trap; TERM/INT/HUP → `exit 0`. Keepalive: `tg_sender` стартует бота, только если lock-каталога нет и 0 инстансов.
- **Меню:** English ASCII клавиатуры (`KB_MAIN` и др.): `Kvas.list|Tags` / `Diagnostics|Help`. Русская клавиатура в Telegram = sticky от старого ответа, пока не придёт новый reply_markup.
- **Лог:** `/opt/var/kvas/tg_bot.log` (`START/PRE/POLL/NMSG/MSG/REPLY/SHOW/SEND/SEND_RC/CMD_DONE`).
- **Критический баг v600:** в `case` busybox `|` — alternation, не литерал. `*|*` матчил всё → `${_rest#*|}` не двигал `_rest` → infinite loop в `tb_kb` (вис на `/menu`). Фикс: `*'|'*`.
- **Сожжённые номера:** 577/578/579/591 (упаковка postinst в data)/592 (баг бота)/603 (опечатка `${_ch}` вместо `${_tl_ch}` в tg_send_long)/607 (не чинил tunnel_check: `myip.addr.tools` не резолвился у пользователя, нужен `2ip.io` как в диагностике)/**612 (сломал основной список: dedup-счётчик в `ip4__add_routing_for_home` ловил строку `-j KVAS_MARK2` подстрокой `-j KVAS_MARK` → count=2 → цикл удалял прыжок lane1 br0)**. 608/609/610/611/613 — рабочие. Следующий = **615**.
- **/status (v605):** полный вывод — build, туннель (friendly name + state: state-file → Keenetic API probe → `?`), dnsmasq, AdGuard (только при `ADGUARD_ENABLE=true`), Xray, Hysteria, AmneziaWG, failover (mode+daemon), hosts count, free /opt. Раньше была только `build` + `Tunnel: ?` из пустого `tg.tunnel.state`.
- **Reload-watch fix (v606):** `upgTick` после релоада ждал `max(300, next-now)` = 300мс (next в прошлом) → `system_status` (opkg) не успевал вернуть новую версию → 10 релоадов подряд. Фикс: wait всегда 15с (`<5000 → 15000`, cap `15000`), стоп по смене версии успевает.
- **Bot update check (v606):** бот сам дёргает `tg_check_kvas_update` из основного цикла (общий rate-limit `tg.updcheck.ts` 1/h с `tg_health`) — релиз объявится даже без cron.15min.
- **Real tunnel probe (v608):** Web UI `tunnel_check` (manage.sh) при рабочем VLESS показывал «порт открыт, тоннель не проверен» — пробы ходили на внешний домен, который не резолвился у пользователя (v606 `socks5://`, v607 `socks5h://` + `--interface` — не помогло). Фикс: точная реплика диагностики (`tunnel_test_site`/`tg_job.sh site`): HTTPS через туннель на **`2ip.io`** (`socks5://`, `max-time 10`) + `ifconfig.me` фоллбэк; VLESS дополнительно — быстрая проба `--interface <t2s>` (`test_vless_proxy`-стиль); порт — последняя инстанция. Порт тоннельного SOCKS берётся из `hysteria/etc/conf/env.sh`.
- **Пакет v609 (порт jobgomel/kvas-hysteria + jobgomel/kvas-awg, все изменения; Web UI фиксы):**
  - **Hysteria:** версия GitHub через `Location`-заголовок `github.com/.../releases/latest` (fallback api.github.com → `app/v2.12.2`); новая команда `kvas hysteria add "hysteria2://..."` (без аргумента — чтение из stdin, обход 512-байт лимита ash; поддержка файла) — раньше install писал подсказку `kvas hysteria add`, но команды не существовала; `kvas hysteria log`; генерация конфига из шаблона `etc/conf/config.yaml` (теперь с `quic.init_to/keepalive_period`, `fast_open`, `lazy`); S99hysteria — лог `/var/log/hysteria.log` + вывод последних строк при падении + `status` + старт/стоп watchdog; **watchdog.sh** (30с: падение → рестарт, WAN-пинг, двойная socks5h-проба → рестарт); `check_space.sh` — чтение подтверждения из `/dev/tty` (EOF закрытого пайпа = «Установка отменена» — главный кандидат бага «бинарник не скачался»); `test_connection.sh` → 2ip.io/ifconfig.me.
  - **AWG:** профили ресурсов `kvas awg mode [eco|balanced|perf|auto]` (GOMAXPROCS/GOMEMLIMIT/GOGC/GODEBUG в `env.sh`, автоопределение по RAM/CPU, автоперезапуск); `kvas awg log`; B64-паддинг `=` до кратности 4 (генераторы опускают); подсказка по закрытому формату Amnezia (`AA…` zlib/JSON — экспорт .conf из приложения); S99awg переписан (env-лимиты, лог `/var/log/wireproxy.log`, watchdog, `status` с потоками/RSS, вывод лога при падении); **новые** `watchdog.sh`, `check_space.sh` (tty-fix), `conf/template.conf`; status показывает профиль и параметры обфускации; `test_connection.sh` → socks5h + 2ip.io/ifconfig.me.
  - **myip.addr.tools → 2ip.io** повсеместно: `libs/check` (16), `libs/failover` (3), `libs/vless` (`DOMAIN_FOR_CHECK` + test_vless_proxy), `libs/awg`, оба `test_connection.sh`, дефолтные `kvas.list`/`tags.list` и авто-добавление пробного хоста; вторая проба везде `ifconfig.me`.
  - **Web UI vless/hysteria «Failed to fetch»:** `vless_new`/`hysteria_new` теперь только запускают фоновый процесс (паттерн adguard_on: lock/rc/log в /tmp) и возвращают `{"pending":true}`; новый action **`vpn_progress`** (running/rc/log, лог режется до 7500 байт ДО экранирования); JS `vpnPoll` опрашивает каждые 4с до 4 мин и показывает полный вывод (включая «Распарсенные параметры VLESS») зелёным/красным по коду выхода. Причина: синхронный CGI висел в пайпе `kvas vless new | head` (фоновые процессы держали fd) либо упирался в таймаут httpd → браузер рвал соединение. `.catch()` теперь ставит `className='msg err'` (раньше тост оставался скрытым `display:none`).
  - **Web UI закваски:** относительные пути `opt/apps/kvas/bin/main/{dnsmasq,ipset}` → абсолютные `/opt/...` (не выполнялись); тосты по-русски («закваска «X» убрана из тоннеля» и т.п.) вместо `removed X`; таймаут `api()` для add/del/create/delete — 180с (del-protect с ребилдом ipset переставал укладываться в 60с).
- **Пакет v610 (Web UI профиль wireproxy + устойчивость установки hysteria):**
  - **Web UI: профиль ресурсов wireproxy** — в карточке «Настройка VPN» селект «Профиль wireproxy» (eco/balanced/perf/auto) + кнопка «Применить». Новый CGI-экшен `awg_mode`: без параметра — текущий `RESOURCE_PROFILE` из `awg/etc/conf/env.sh` (`{"ok":true,"profile":...}`), с параметром — валидация (eco|balanced|perf|auto) + `kvas awg mode <p>` (обновляет env и рестартует wireproxy, если запущен), ответ `{"ok":true,"profile":...,"output":...}`. Текущий профиль подтягивается при загрузке (`showMain → awgModeLoad`), результат показывается в `vpnSetupMsg`.
  - **`kvas hysteria install` не зависает на зеркалах:** curl зеркал получил `--speed-limit 5120 --speed-time 20` — мёртвое зеркало (нет прогресса 20с) обрывается сразу, вместо ожидания полных 120с (раньше требовался ^C); stderr каждой попытки выводится (`curl: (28) ...`), после всех зеркал — итоговая подсказка (github.com недоступен с роутера → смена DNS/VPN). Версия через Location/github API при недоступности GitHub падает в рабочий дефолт `app/v2.12.2` (валидный тег апстрима HyNetworks/hysteria, проверено).
  - **`kvas hysteria test` с автодиагностикой:** при провале в вывод допечатываются последние 12 строк `/var/log/hysteria.log` + подсказка про блокировку UDP/QUIC провайдером — причина (мёртвый сервер из ссылки, кривая ссылка, заложенный UDP) видна сразу, а не «прокси не отвечает».
- **Пакет v611 (Web UI закваски: фикс «Failed to fetch»):**
  - **`tags_add`/`tags_del` асинхронны** (тот же паттерн adguard_on/vless_new из v609): CGI только валидирует тег и запускает `tags add-protect`/`del-protect` + пересборку dnsmasq/ipset фоном (лок/rc/log `/tmp/kvas_tags_add.*`, `/tmp/kvas_tags_del.*`), отвечает `{"pending":true,"task":...}` немедленно. Причина бага: синхронный `del-protect` (домены по одному + `cmd_kvas_init`) длился дольше таймаута httpd — соединение рвалось на стороне сервера, браузер показывал «Failed to fetch», таймаут клиента 180с (v609) не спасал.
  - **`vpn_progress` расширен** задачами `tags_add`/`tags_del` (whitelist case в manage.sh); JS `vpnPoll` обобщён: опциональный `opts.msgEl` (по умолчанию `vpnSetupMsg`) и `opts.done` (по умолчанию `loadSystemStatus(); loadVpnInterfaces()`) — vless/hysteria-вызовы без 5-го аргумента работают как раньше.
   - **`tagsAdd`/`tagsDel` (index.html):** при `pending` стартует `vpnPoll(..., {msgEl:'tagsMsg', done:loadTags})` с прогрессом «Удаление «X» из тоннеля… (N×4с)» в `tagsMsg`; таймаут начального запроса 60с (сейчас ответ мгновенный).
- **Пакет v612 (Список 2 — вторая полоса; async Web UI; JSON-фикс монитора):**
  - **Список 2 (lane2):** файл `/opt/etc/kvas2.list` (`KVAS_LIST2_FILE`) → ipset `KVAS_LIST2` (`IPSET_TABLE2_NAME`) → mark `0xd1001` (`MARK2_NUM`) → цепочка `KVAS_MARK2` (`CHAIN_MARK2`, копия KVAS_MARK с исключением mark'ов lane1: `-m mark --mark 0xd1000 -j RETURN`; в цепочке lane1 — `-m mark --mark 0xd1001 -j RETURN` после restore, чтобы double-listed домены не перетирали mark) → ip rule 1777 `fwmark 0xd1001/0xd1001 lookup 201` (вставляется `-I PREROUTING` ПЕРЕД первым правилом `-j KVAS_MARK`) + fallback 1779 `lookup 200` (маска-семантика: 0xd1001 матчится и правилом 1778, поэтому трафик lane2 при легнутом тоннеле уходит в таблицу 200 и без 1779; правило 1779 — страховка при отсутствии 1778). Таблица 201 (`ROUTE_TABLE2_ID`): `default dev <iface>` (+ gateway-net и копия direct-роутов), via `ADDR_MAN` только для `current`; при отсутствии/down интерфейса lane2 таблица 201 **flush'ится** (`ip4__lane2__is_iface_up`: `ip -o link show | grep '<[^>]*UP'`). Тоннели: `LANE2_TUNNEL` (current|vless|hysteria|awg, default current), iface из `inface_equals` (`Proxy21|t2s21|vless` — по клиенту тоннеля: Proxy21/41/42). Телеметрия: `kvas list2 status` → `tunnel=/iface=/iface_up=/available=/entries=/mark=/table=`.
  - **CLI:** новый lib `bin/libs/list2` (`cmd_list2_*`: add/del/list/tunnel/tunnel-list/status + нормализация, валидация домен/IP/CIDR через `get_regexp_ip_or_range`, резолв доменов в ipset через `dns__get_ips_by_domain`, регенерация dnsmasq `ipset=/domain/KVAS_LIST2` + HUP); dispatch `list2)` в `bin/kvas` (bare → status); справка в `kvas.help` (раздел МАРШРУТИЗАЦИЯ + примеры).
  - **Интеграция:** `main/ipset` — вторая проходка из kvas2.list (с `-exist create`); `main/dnsmasq` — второй awk-пасс в `ipset_file`; `main/setup` — teardown lane2 в `clear_previous_version_net_rules`; ndm: `ip4__mark2__create_chain`/`ip4__mark2__add_routing_for_home`/`ip4__route2__add_table`/`ip4__rule2__*`/`ip4__rule2_fallback__*`/`ip4__ipset__create_list2|destroy_list2`/`ip4__lane2__*`, вызовы в `ip4_mark_vpn_network` (create+insert), `ip4__dns__add_routing_for_home` (+create_list2), `ip4_firewall_flush_vpn_rules` (jump KVAS_MARK2), `ip4__flush` (все 4 части — table/chain/jump/ipset); `etc/ndm/ndm` — бинарно идентичен `bin/libs/ndm`.
  - **Backup/Restore:** `kvas backup` копирует `kvas2.list`, `restore` возвращает его в `/opt/etc/kvas2.list` (+ пересборка через `cmd_kvas_init`).
  - **Async Web UI (10 кнопок):** `xray_install`, `awg_new` (link → `/tmp/kvas_awg_link.data`), `awg_new_b64` (decode sync → `/tmp/kvas_awg_b64.data`, bg `awg new`), `restore`, `adblock_on` (конфиг sync, `adblock`+`parental_regen`+restart — фоном), `route_refresh`, `kvas_test` (с `tg_notify` в bg), `kvas_debug`/`kvas_debug_dns`/`kvas_debug_iptables` — паттерн tags_add (touch lock → bg-команда → rc/log → `{"pending":true,"task":...}`), `vpn_progress` whitelist расширен на `list2_add`/`list2_del` + эти 10 задач; JS: pending → `vpnPoll(d.task, 0, btn, title, {msgEl, done})` с корректным `done`-колбэком (xray→xray+system status, adblock→adblock+parental, restore→system, refresh→route lists).
  - **JSON-фикс монитора:** `data.sh json_escape` (control-chars `\000-\010\013\015-\037\177`), экранирование вывода `test_resolve`; `manage.sh json_str` — тот же tr + awk-экранирование `\n` (multiline-вывод больше не рвёт JSON).
  - **Web UI (вкладка «Маршрутизация»):** карточка «Список 2 — вторая полоса» (селект тоннеля из `available`, статус iface/up/метка, ввод домен/IP/CIDR, список с ✕, `l2Msg`), JS `loadList2/list2Add/list2Del/list2Tunnel`, `showMain → loadList2()`; эндпоинты `list2_status/list2_list/list2_add/list2_del/list2_tunnel`.
  - **Сборка:** CONTROL `Version: 1.1.9_beta-10-612`, postinst fallback `_rel=612`; `etc/conf/kvas2.list` **не шиппится** (создаётся пустым при первом обращении, chmod 666).
- **Пакет v613 (регресс-фикс v612 + hysteria после обновления):**
  - **Главная регрессия v612 — «основной список сломался» (домашняя сеть br0 не маркируется):** в `ip4__add_routing_for_home` (`bin/libs/ndm`, ~:660) dedup-цикл `save_iptables | grep -c -- "-A PREROUTING .*${net_interface} .*${chain_name}"` — паттерн без якоря `$` матчил подстроку `KVAS_MARK` в строке `-j KVAS_MARK2` того же интерфейса br0 → count=2 → `-D PREROUTING … -j KVAS_MARK` удалял НАСТОЯЩИЙ прыжок lane1, пересоздание не происходило (осцилляция: прыжок то есть, то нет). Фикс: якорь `…${chain_name}\$"` (в двойных кавычках `\$` доходит до grep как `$`); строка `-j KVAS_MARK2` кончается на `KVAS_MARK2` → не матчится. Также `libs/check:183` (`kvas test`): счётчик `"${VPN_IPTABLES_CHAIN}"` без границы → считал строки `-A KVAS_MARK2` как ложное «ДОБАВЛЕНЫ»; фикс: `grep -c -- "-A ${VPN_IPTABLES_CHAIN} "` (только тело цепочки). Guard `--set-mark` в `ip4__mark__create_chain`/`ip4__mark2__create_chain` НЕ трогали: он никогда не матчит реальный вывод iptables-save (`--set-xmark`) → цепочки пересоздаются при каждом `ip4_mark_vpn_network`, что случайно обеспечивает пересоздание `ip rule`/таблиц после ребута.
  - **Hysteria после обновления не запускалась** («если была запущена — приходится `kvas hysteria restart`»): путь обновления через `kvas uninstall … yes` (`main/upgrade:343`, срабатывает при пустом `SETUP_FINISHED`) останавливает все службы (`cmd_uninstall` шаг 1), а обратно `all_services_restart` поднимал hysteria **только** при `INFACE_CLI ~ Proxy41|hysteria` — не матчил `t2s41` и не поднимал «второстепенную» hysteria (main=vless/awg). После `stop` снимается `ACTIVE_FLAG` → watchdog не восстанавливает службу сам. Фиксы (3 слоя): (1) `cmd_uninstall` перед `S99hysteria status`→stop пишет маркер `/opt/var/kvas/.hysteria_running`; (2) `all_services_restart` (`libs/vpn`) — паттерн `*Proxy41*|*t2s41*|*hysteria*` + потребление маркера (рестарт при любом INFACE_CLI); (3) `main/upgrade` — фикс состояния hysteria до обновления и восстановление (`S99hysteria start`) после `kvas init`, если служба упала; плюс case bounce-интерфейса расширен `t2s21|t2s41` (комментарий «VLESS/Hysteria — не трогаем» их не покрывал).
  - **Сборка:** CONTROL `Version: 1.1.9_beta-10-613`, postinst fallback `_rel=613`; изменённые файлы: `bin/libs/ndm` (+`etc/ndm/ndm`), `bin/libs/check`, `bin/libs/vpn`, `bin/main/setup`, `bin/main/upgrade`, `postinst`.
- **Пакет v614 (нативные тоннели Keenetic в Списке 2):**
  - **Фича:** в выбор тоннеля Списка 2 добавлены интерфейсы VPN, поднятые непосредственно в Keenetic (OpenVPN/SSTP/WireGuard/IKE/L2TP/PPTP/PPPOE/OpenConnect) — как у основного списка (lane1 следует за `INFACE_ENT`, `ip4__route__add_table` uses ADDR_MAN). Источник — `inface_equals` (`cli|ent|desc`, пишется `update_interface_name_list`: RCI `show interface` с типами OpenVPN,Wireguard,IKE,SSTP,PPPOE,L2TP,PPTP,Proxy,OpenConnect, кроме defaultgw).
  - **`bin/libs/list2`:** `cmd_list2__available` дописывает все `cli` из `INFACE_NAMES_FILE` кроме `shadowsocks` и `Proxy21|Proxy41|Proxy42` (они уже как vless/hysteria/awg) с дедупом; `cmd_list2_tunnel` принимает любой токен из `available` (membership-проверка `grep -qF`, хардкод-кейс `current|vless|hysteria|awg` больше не единственный вход).
  - **`bin/libs/ndm` (+`etc/ndm/ndm`):** `ip4__lane2__get_tunnel` — нативный cli подтверждается `awk '$1==cli'` в `inface_equals`, иначе fallback `current` (пустое значение прежних версий тоже → current); `ip4__lane2__get_iface` — cli (нативный или Proxy*) резолвится в системное имя `awk -F'|' -v c=cli '$1==c {print $2; exit}'` (раньше `grep "^cli|"` — regex-символы в id были бы интерпретированы); `ip4__route2__add_table` — `via ADDR_MAN` теперь и для нативных тоннелей (семантика lane1), только KVAS-алиасы (vless/hysteria/awg) остаются `default dev <iface>` без шлюза.
  - **Web UI/CGI:** `manage.sh list2_tunnel` — белый список `current|vless|hysteria|awg` заменён на charset-валидацию `^[A-Za-z0-9._-]+$` (членство в `available` проверяет lib, ошибка rc возвращается как раньше); селект `l2TunnelSel` строится из `available` — нативные тоннели появляются автоматически (label = raw id, `labels[t] || t`).
  - **Spare:** `inface_equals` может быть пуст/отсутствовать (скан не гонялся) — available деградирует до `current`+алиасов, не падает.
  - **Сборка:** CONTROL `Version: 1.1.9_beta-10-614`, postinst fallback `_rel=614`; изменённые файлы: `bin/libs/list2`, `bin/libs/ndm` (+`etc/ndm/ndm`), `bin/monitor/www/cgi-bin/manage.sh`, `etc/conf/kvas.help`, `postinst`.

## 5. Сетевая конфигурация

| Протокол | Интерфейс | SOCKS5 | Транспорт |
|----------|-----------|--------|-----------|
| VLESS | Proxy21 | 127.0.0.1:1097 | TCP 443 Reality |
| Hysteria | Proxy41 | 127.0.0.1:10808 | UDP 443 QUIC |
| AWG (wireproxy) | Proxy42 | 127.0.0.1:10818 | userspace SOCKS5 |

`RULE_PRIORITY=1778` (оригинал; значение 99 ломало Keenetic WG). Routing table = 200. fwmark kvas = 0xd1000.
Список 2 (lane2, v612): `RULE_PRIORITY2=1777` (fwmark 0xd1001 → table 201), `RULE_PRIORITY2_FALLBACK=1779` (fwmark 0xd1001 → table 200), цепочка `KVAS_MARK2`, table 201 flush'ится при down тоннеля lane2.

## 6. Структура пакета

```
opt/apps/kvas/
├── bin/
│   ├── kvas                    # CLI entry + lazy-load (_require)
│   ├── install_hysteria.sh, backup_configs.sh, restore_configs.sh
│   ├── libs/                   # main, vpn, vless, hysteria, failover, check,
│   │                           # route, ndm, adblock, awg, tags, debug, hosts, keen_api, update
│   └── main/                   # setup, upgrade, update, adblock, adguard, dnsmasq, ipset, ...
├── etc/
│   ├── conf/                   # kvas.conf, kvas.list, tags.list, dnsmasq.conf, ...
│   ├── init.d/                 # S96kvas, S97xray, S99adguard
│   └── ndm/                    # netfilter hooks (100-vpn-mark и др.)
├── awg/                        # wireproxy-awg: bin/, S99awg, env.sh (10818)
└── hysteria/                   # hysteria: bin/, S99hysteria, env.sh (10808), config.yaml
```

## 7. Основные команды

```bash
kvas setup | ver | test | help | init
kvas vless new | hysteria new|add|status|test|log
kvas awg [install|new|add|test|log|mode [eco|balanced|perf|auto]|start|stop|uninstall]
kvas failover on|off|status|test|log [N]|primary|secondary|tertiary
kvas vpn set <vless|hysteria|описание>
kvas route [add|del full|list|exclude <IP>|refresh]
kvas adblock on|off|add <host>|del <host>
kvas tags add|del|edit|create|delete ...
kvas monitor [web [stop]]
kvas upgrade [rollback] | update | uninstall [full] yes
kvas backup | restore
kvas log error [detail|clear|N] | info
kvas xray [core [версия]]
```

## 8. Upgrade / Rollback (фактическая логика, main/upgrade)

- Обычный upgrade: скачивание ipk с GitHub (старший asset) → `kvas uninstall <mode> yes` → `opkg install --force-reinstall` → пост-настройка.
- Rollback: `kvas upgrade rollback` — выбор из списка релизов на GitHub, тот же цикл установки.
- Ветка `force` / `full` — расширенные режимы (см. шапку upgrade).
- Web UI: кнопки «Обновить/Откатить» через `nohup sh -c '...'` (переживает exit CGI).

## 9. Failover (фактическое поведение, libs/failover)

- Демон проверяет PRIMARY/SECONDARY/TERTIARY каскадом (`run_failover_check`), при недоступности — `switch_to`.
- `switch_to`: лок-файл, фоновый блок `{ sleep 10; kvas vpn set; restart failover } &`, затем `stop_failover_daemon; exit 0` — **это дизайн**: текущий процесс чека завершается, переключение и рестарт демона идут в фоне. Работает.
- Ручной `kvas vpn set` при включённом failover обновляет PRIMARY — демон не «откатывает» выбор.
- Если активен интерфейс вне primary/secondary/tertiary — не трогает.
- `FAIL_THRESHOLD` читается/сохраняется/выводится (`kvas failover set threshold N`), но **в логику `run_failover_check` не встроен** — переключение после первой неудачной проверки. Порог — заглушка/конфиг без эффекта.

## 10. Web UI

- URL: `http://keenetic:8085` (`kvas monitor web`), CGI manage.sh + index.html.
- Auth: `auth` (пароль → md5 → token), далее `check_token` на большинстве endpoints.
- `set_pass` / `auth` — **без** check_token (осознанно: это вход/установка пароля; LAN-only, по решению пользователя).
- POST body (upload backup): handler в httpd.sh → `KVAS_POST_BODY`.
- Карточки: статус системы, VPN (vless/hysteria/awg), failover dropdowns, adblock, parental, закваски, route, диагностика (test/debug/логи), Xray core, upgrade/rollback, backup download/restore upload.

## 11. Известные особенности (не блокеры)

Всё перечисленное **работает** на текущем железе; пункты — для возможного тех. долга, не баги:

| Что | Факт |
|-----|------|
| `FAIL_THRESHOLD` | не влияет на логику switch (см. §9) |
| `&>` (bashism) | ~233 вхождения (vpn:106, check:22, setup:20...); на целевом busybox/ash роутера работает |
| `set_pass` без токена | SKIP by design (LAN) |
| `rm_tmp_cache` (upgrade:119) | `find / \| grep '/tmp' \| grep kvas \| xargs rm -rf` — грубо, но фильтруется по kvas; чистит tmp перед установкой |
| `/tmp/build.sh` | устарел, не использовать (§3) |
| tags.list в опубликованном ipk v546 | тестовые записи; **v549 собран чистым** (CLEAN) — больше не актуально |
| `kvas-original` vs upstream | diverged; git push — только через kvas-original |

## 12. Идея (не реализовано): Per-domain routing

Направлять разные домены через разные туннели (VLESS/AWG/Hysteria): несколько ipset + fwmark + table + правила KVAS_MARK, `kvas add x --tunnel awg`, колонка в web UI. Оценка рисков — iptables сложность, perf, MASQUERADE per-interface, HUP при смене туннеля домена.

**29.09.2026 — «тоннель per-закваске» (dropdown у каждой закваски) отклонён пользователем:** ненадёжно/непредсказуемо — расщепление закваски между тоннелями (домены через один, IP/CIDR из общего списка через другой), CONNMARK-старые сессии, порядок match-set в PREROUTING, миграция членов ipset. Не делать.

**29.09.2026 — принято вместо этого: «Список 2» (вторая полоса) — РЕАЛИЗОВАНО в v612:**
- Файл `/opt/etc/kvas2.list` — формат как kvas.list (домены + IP/CIDR, полный контроль); CLI `kvas list2 add|del|list|tunnel|tunnel-list|status`.
- ipset `KVAS_LIST2` → mark `0xd1001` → цепочка `KVAS_MARK2` (копия KVAS_MARK) → ip rule `fwmark 0xd1001/0xd1001 lookup 1777→201` + **fallback** `lookup 200` (тоннель лег → текущий, без утечки; два правила вместо `lookup 201 200` — совместимо с busybox `ip`).
- Тоннель lane2 **выбирается без привязки**: селект из настроенных тоннелей (`inface_equals` → Proxy21/41/42), ключ `LANE2_TUNNEL` в kvas.conf (default `current`); table 201 = `default dev <iface>`; при down тоннеля table 201 flush → fallback в 200.
- dnsmasq-генератор: домены списка 2 → `ipset=/domain/KVAS_LIST2`; `main/ipset` грузит IP/CIDR списка 2 в `KVAS_LIST2`.
- Web UI: **вкладка «Маршрутизация»**, карточка «Список 2 — вторая полоса» (селект тоннеля + список + add/del, всё async через `vpn_progress`).
- Закваски/список 1 не трогаются (lane1 = текущее поведение 1:1; двойные члены исключены RETURN-правилами в обеих цепочках). Открытых вопросов нет (решения 29.09.2026).

## 12.1. Идеи по улучшению (roadmap; решение пользователя 22.09.2026)

**Релиз остаётся v549.** P0-тест (v550–552, git `639077d`) — локально, в Release не пушить. Правки после отката на 549: `adblock_status` снова conf-based (on/off), AdGuard HTTP-check — порт из `bind_port` AdGuardHome.yaml (не хардкод 3000).

### Приоритеты

| Приоритет | Пункты | Статус решения |
|-----------|--------|----------------|
| P0 | 1 (статусы) + 5 (единый parental→AdGuard) + 7 (mobile) | 1+7 тестировались (v550–552); **5 подозревается в сломе adblock** — перед вливанием нужен smoke-test; 7 — «не очень представляю как будет» → отложить до явного ТЗ |
| P1 | 2 (failover-история) + 8 (уведомления) | **2 — нравится** (см. ниже); 8 — нужна расшифровка реализации до оценки |
| P2 | 6 (экспорт JSON) + 9 (changelog UI) | 6 — **уже есть** (download/restore backup); 9 — пользователь пишет в общих чертах на git, детальный changelog в UI не готов писать |
| P3 | 3 (QR/share) + 4 (parental) + 10 (security) | 4 — **нравится только «временные правила»**; 10 — **не нужно** |

### 1. Статусы и диагностика (низкая)

- Единый индикатор: зелёный/жёлтый/красный по VPN, AdGuard, dnsmasq, failover + тап → «что сломано и как чинить».
- **Сделано в тесте** v550–552 (не в релизе): 4 чипа, `health_details`, тап→диагностика.
- **Урок теста:** не врать статус (реальные проверки, не PID); порт AdGuard — из conf; `adblock_status` **не смешивать** с живостью dnsmasq (ломает on/off UI).

### 2. Failover: история и anti-flap — ★ нравится

- **История переключений:** последние N (время, с какой на какую, почему) + пуш/лог. Видно, что авто-переключение работает; меньше «само отвалилось».
- **Корзина при flapping:** после 3 переключений за 5 мин — заморозить primary + алерт.
- **Риск:** anti-flap пересечётся с `FAIL_THRESHOLD` (сейчас заглушка, §9) — тестировать на физическом обрыве.
- **Сложность:** средняя (демон failover + ротация лог-файла + UI-карточка).

### 3. Импорт/конфиги — QR / share-link (средняя)

- «Скопировать конфиг» / QR для vless/hysteria; массовый импорт по нескольким ссылкам.
- **Риски:** валидация чужих ссылок; **не логировать полные ключи**.
- **Решение:** в P3, когда база стабильна.

### 4. Родительский контроль — только временные правила ★

- **Берём:** «заблокировать X до 22:00» (таймер снятия правила).
- **Категории** (соцсети/порно/азарт) — отложить: тяжёлые списки на слабом CPU, риск ронять dnsmasq.
- **Сложность:** средняя (cron/at + parental.d).

### 5. AdGuard ↔ parental единый слой — аккуратно (P0-кандидат, риск)

- Сейчас два пути (dnsmasq / AdGuard) — источник багов; нужен слой «добавить домен в блок» с выбором бэкенда.
- **Внимание:** в P0-тесте изменения вокруг adguard/adblock **подозреваются в сломе включения/выключения adblock** (пользователь откатился на 549). Перед вливанием — smoke-test on/off в Docker/VM.
- **Сложность:** средняя/высокая.

### 6. Бэкап/переезд — уже есть

- Download backup + restore из файла — **реализовано** (CLI + web). Экспорт «всё в один JSON с секретами» — не требуется отдельно; при желании — шифровать/PIN.

### 7. Мобильный UI — отложить до ТЗ

- Тач-цели ≥44px, bottom-sheet — косметика; пользователь «не очень представляет как это будет».
- В тесте 552: `.hchip min-height:44px` — правка есть, **не в релизе**.
- **Решение:** не делать, пока не будет явного макета/сценария.

### 8. Уведомления / Telegram — ✅ реализовано (P.8, v588–601)

- **Готово:** `libs/tgq` (`tg_notify`, quiet hours, очередь, `tg_check_kvas_update`), interactive bot (`tg_bot.sh`, English ASCII menus, state machine), `tg_sender` (cron.1min + keepalive), `tg_health` (cron.15min + фоновый чек обновлений 1/h), `tg_job` (update/test/debug в фоне с ответом в чат).
- **UI:** Web UI → «Уведомления Telegram» (token, chat_id, quiet hours, события).
- **Авточек обновлений (v604):** `tg_health` раз в час вызывает `tg_check_kvas_update` (GitHub + dedup `tg.lastupd`) → `tg_notify update_found`. Раньше check_updates был только кнопкой Web UI — бот молчал о релизах.
- **Не логировать:** приватные ключи, полные конфиги, токен в cleartext.

### 9. Обновления / changelog — в общих чертах на git

- Changelog в UI + «что изменилось с моей версии» + откат на предыдущий ipk (512…549 уже лежат).
- **Решение:** пользователь не готов писать детальные changelog-и; достаточно **коротких сообщений коммитов/relnotes на GitHub** (как сейчас). UI-changelog — не делать.
- Откат ipk: уже частично есть (`upgrade rollback`); хранить пару «ipk + conf snapshot» — отложить.

### 10. Безопасность токена — не нужно

- Lockout, HTTPS, частая ротация — **отклонено** пользователем (LAN-oriented, работает).

### Сводка решений

| # | Тема | Решение |
|---|------|---------|
| 1 | Health UI | ✅ тест ok; в релиз — после стабилизации |
| 2 | Failover history + anti-flap | ★ делать (P1) |
| 3 | QR / mass import | P3 |
| 4 | Временные parental-правила | ★ делать; категории — нет |
| 5 | Единый parental→AdGuard | ⚠ smoke-test; риск слома adblock |
| 6 | JSON export | уже есть backup |
| 7 | Mobile polish | отложить до ТЗ |
| 8 | Telegram/webhook | ✅ P.8/P.8+ реализовано (v588–601) |
| 9 | Changelog UI | нет; git relnotes достаточно |
| 10 | Security token | не нужно |

## 12.2. На будущее: IPv6 («только через туннель», opt-in)

Записано 28.09.2026 по результатам консультации. Тест пользователь проведёт позже — задача не начата.

**Симптом-триггер:** мобильный Telegram не работает, десктопный — работает; пользователь спрашивал, могут ли IPv6-префиксы Telegram (`2001:b28:f23c::/48`, `2001:b28:f23d::/48`, `2001:b28:f23f::/48`, `2001:67c:4e8::/48`, `2a0a:f280::/32`) идти напрямую, минуя туннель.

**Факты по коду (диагноз 28.09.2026):**
- Маршрутизация только IPv4: `ip4_*` цепочки, ipset `KVAS_LIST` = `family inet`; IPv6-трафик правилами kvas не перехватывается вовсе.
- `ip6set_create_table()` (таблица `KVAS_LIST6`) объявлена в `etc/ndm/ndm:1371`, но нигде не вызывается; правил `ip6tables` в пакете нет.
- Защита от утечки есть только через гашение AAAA: dnscrypt `block_ipv6=true` + `ipv6_servers=false` (libs/vpn:2955-2957), shadowsocks `dns_ipv6=false`.
- Отключение IPv6 в setup закомментировано («с отключением IPv6 можно потерять провайдеров», main/setup:614-621); диагностика `hint__if_dns_ipv6` (libs/vpn:347).
- `IP_FILTER` (libs/main:108) — только IPv4: префиксы/подсети IPv6 в `kvas.list` **не принимаются**, т.е. хот-фикс «добавить IPv6-префиксы телеграма в список» без общей IPv6-работы невозможен.

**Рабочая гипотеза симптома (вероятнее IPv6):** телефон резолвит мимо роутера (Android Private DNS / iOS Encrypted DNS / DoH) → IP телеграма не попадают в `KVAS_LIST` → прямое соединение к 91.108.x.x/149.154.x.x блокируется провайдером → не работает; десктоп берёт DNS у роутера → через туннель. IPv6-путь возможен только если провайдер фактически даёт глобальный IPv6 (по словам пользователя — не даёт; тогда соединения по перечисленным префиксам физически не поднимаются).

**TODO-диагностика (пользователь, «тест позже»):** при подключённом телефоне `ipset list KVAS_LIST | grep -E '91\.108\.|149\.154\.'` (адресов нет → DNS ушёл мимо); на телефоне выключить Private DNS/DoH; `kvas debug` → `hint__if_dns_ipv6`; `kvas tags list telegram`/`add_tags telegram` — применён ли тег `[telegram]` (секция есть в tags.list:185-200, дефолтный kvas.list Telegram не содержит).

**План реализации (отдельная задача, opt-in, по умолчанию выключено):**
1. Поддержка IPv6-записей (CIDR6) в списке: `IP_FILTER`/`get_regexp_ip_or_range` + `ipset create KVAS_LIST6 family inet6` (оживить `ip6set_create_table`).
2. `ip6tables`: перехват DNS/соединений по IPv6 → маршрутизация через туннель (DNAT/mark → локальный socks как в IPv4) либо блок AAAA при выключенном туннеле.
3. Переключатель в kvas.conf (`IPV6_MODE=off|tunnel`), off = текущее поведение 1:1; включение — снятие `block_ipv6` только для туннельного пути.
4. Web UI: индикатор/переключатель; диагностика `hint__if_dns_ipv6` расширить.

**Оценка рисков:** при opt-in с дефолтом off существующий IPv4-путь не затрагивается (другие цепочки), поведение без изменений; риски — конфликт с родным IPv6-менеджментом NDM и апгрейды со старыми конфигами (новый ключ с дефолтом) — управляемые. Работа по IPv6 возможна только после диагностики выше (подтвердить, что проблема реально в IPv6, а не в DoH телефона).

## 13. Авторы

- KVAS: mail@zeleza.ru (оригинал qzeleza/kvas)
- Hysteria, kvas-awg: jobgomel
- Failover / fork: Anonimus2026
