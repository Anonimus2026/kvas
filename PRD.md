# PRD: KVAS

**Версия:** 1.1.9_beta-10-635
**Дата:** 06.10.2026
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
C:\Users\Pavel\kvas\local_build\            ← SOT артефактов ipk (в т.ч. текущий 635)
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
- GitHub Release `v1.1.9` — единственное место, откуда `kvas upgrade` качает обновления. Upgrade берёт **старший номер** сборки: `sort -n | tail -1` по `beta-10-<N>`. Ассеты: …, 576, 600, …, 610, 611, 612, 613, 614, 615, 616, 617, 618, 619, 620, 621, 622, 623, 624, 625, 626, 627, 628, 629, 630, 631, 632, 633, 634, **635** (текущий).
- Название/описание релиза на GitHub **не трогать** (пишет пользователь).

## 4. Текущий статус (v635)

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
| **Список 2 — вторая полоса (kvas2.list → KVAS_LIST2 → mark 0xd1001 → table 201)** | ✓ v612 + Keenetic-native tunnels (v614), labels/delete fix (v615), ipset rebuild + conntrack flush (v616), tg update button (v617), fill_domain add revert (v618) |
| **kvas del: удаление статики IP/CIDR из ipset + ct-flush (баг lane1-остатков)** | ✓ v618 |
| **Failover: фикс флапа при ручном AWG (рассинхрон desc/токен) + авто-миграция conf (вариант B) + дедуп TERTIARY** | ✓ v619 |
| **Telegram-бот: выбор тоннеля (Tunnels-меню, паритет с Web UI)** | ✓ v619 |
| **Профиль ресурсов wireproxy (RESOURCE_PROFILE и лимиты Go) переживает upgrade/rollback (merge) + backup/restore** | ✓ v620 |
| **Web «Состояние системы»: 3 службы (xray/hysteria/awg) + Старт/Стоп + Рестарт, строка AmneziaWG с профилем** | ✓ v620 (убрана дублирующая кнопка из «Настройка VPN») |
| **Кнопки служб реально работают: прямые `/opt/etc/init.d/…` в CGI (v620 «service_action: not found»), `service_action` honours action** | ✓ v621 |
| **xray arch: mipsel→mips32le (был big-endian mips32), + mips64le/mips64/riscv64/loong64** | ✓ v621 |
| **Кнопки на реальном устройстве: xray = S24xray → legacy S97xray → пакет, hysteria device → пакет; `service_action` pkg-fallback** | ✓ v622 (жалоба: `/opt/etc/init.d/S97xray: not found`) |
| **Селект «Профиль wireproxy» показывает текущий профиль (`awg_mode` GET guard)** | ✓ v622 (всегда был «balanced»; строка статуса читала верно) |
| **xray на LE-mips: эндianness по ELF-пробе (uname=mips → mips32le/mips64le), явные mipsel-ветки сохранены** | ✓ v623 (KN-1011: скачивался BE `mips32`, не запускался) |
| **Установка xray: `xray version`-проба скачанного бинарника ДО стопа демона (fail fast с URL)** | ✓ v623 (было: стоп → падение → restore, «Установлена версия:» пусто) |
| **`kvas test`: единый полный НЕинтерактивный отчёт для бота и Web UI (режим `auto`: +`kvas_list_ipset_check`, −интерактивный `ipset_site_visit_check`) + полная отправка в Telegram (без `tail -c 3500`) | ✓ v624 (жалоба: «вид kvas test отличается для бота, он не полный») |
| **Сборка: чистая установка без ошибок opkg** — из staging удалены 11 фиктивных пустых каталогов с обратными слэшами (`opt\apps\...`), которые попадали в `data.tar.gz` лишними записями и роняли `mkdir` в opkg с «Read-only file system» (баг сборки появился в цикле 624, был в 624 и 625; тест/verify не ловили — нет guard'а) | ✓ v626 (жалоба Nikolay: чистая установка 625 сыпет ошибками; 534 ставился чисто) |
| **Web UI «Состояние системы»: кнопки по одной оси рядом с текстом (`.row-main`, min-width 340px; на мобиле — блоком под текстом) + вид «Плитками» (сетка 3 карточек служб с крупными кнопками) с тумблером в шапке секции (localStorage) | ✓ v625 (жалоба на v624: на ПК кнопки у правого края — «промахнуться», на мобиле оторваны; просили «рядом как раньше, но выровнить») |
| **PRD §4.3: правило цепочек + backup/restore + актуальность справки** | ✓ v620/v621/v623/v624 |
| **Telegram: keepalive чинит stale-lock мёртвого поллера (bot никогда не перезапускался) + кнопка «Перезапуск бота» в попапе «Уведомления Telegram» + индикатор «бот работает/остановлен»** | ✓ v627 (жалоба: тест приходит, бот не реагирует на команды) |
| **Мониторинг: клиентский DNS-лог opt-dnsmasq включается реально (log-queries/log-facility в /opt/etc/dnsmasq.conf + рестарт S56dnsmasq; системный dnsmasq Keenetic не трогаем), кольцевой лог 256KB, дедуп событий и «+N новых», бейдж «н/д», conntrack-кэш фильтруется по выбранным ips, ARP по Flags ($3); Web «Отследить сайты (60 сек)» → домены в обход тоннеля (route_excluded_domains → ipset=/domain/KVAS_DESTINATION_EXCLUDED, regen + рестарт dnsmasq только при изменении, defer-refresh) или в закваску (host_add); мобильный список устройств в 1 колонку | ✓ v628 |
| **Мониторинг: JSON-безопасный data.sh — json_escape вырезает ВСЕ control-символы (сырой LF/TAB/FF из многострочного PTR dig ронял `r.json()`), `dig +short -x`/`nslookup` → `head -1`; media-правило «1 колонка device-list» перенесено ПОСЛЕ базовых правил (каскад: база `.device-list/.col3` L119-120 шла позже @media L88 → на мобиле оставалось 2/3 колонки); DNS-лог переживает затирание conf шаблоном `dnsmasq_install` (флаг web → re-append блока `# kvas-monitor`, `monitor web start` при ветке «уже запущен» тоже вызывает enable — раньше апгрейд оставлял `dns_log=false` навсегда); poll при ошибке парсинга печатает фрагмент сломанного payload (диагностика) | ✓ v629 (жалобы 628: «Expected ',' or ']' after array element…», «DNS-лог не активен», «Нет данных», «web-сервер не отвечает», 2 колонки на мобиле) |
| **Мониторинг: персистентный PTR-кэш `/tmp/kvas-ip-ptr.txt` (переживает poll; раньше build_ip_cache стирал IP_CACHE каждый цикл → re-dig всех dst каждые 5с с дефолтными таймаутами 5с×3 → CGI рвал httpd → intermittent «Failed to fetch») + `dig +time=1+tries=1` + nslookup только как fallback; `query[ANY]`-парсинг (query[HTTPS]/SVCB давал целую syslog-строку как domain — «не видит куда лезу»; трейс и CLI собирали только A/AAAA); guard `pollErrors >= MAX_POLL_ERRORS && monitoring` (стек in-flight fetch'ей писал «Мониторинг остановлен» 4×); strict IPv4 в reply/cached-маппинге (AAAA-ключи-мусор вида `2=`); last-wins дедуп кэша; debug `ptr_cache_size`/`dns_log_tail` | ✓ v630 (жалобы 629: «Failed to fetch» время от времени после установки, DNS-лента без доменов при работающих соединениях) |
| **Мониторинг (v631): мастер-чекбокс «выделить все» в шапке списка трейса (по умолчанию снят, indeterminate при частичном выборе); «→ в закваску» → диалог «существующая + новая» (поиск по закваскам, пресет = баз-домен последних двух меток) → одно действие `tags_trace_add`: активация доменов `$KVAS_BIN add` **ДО** записи секции (иначе `cmd_add_one_host` уходит в интерактивный `read_ynq` и возвращает 0 без добавления), затем `kvas tags create`/append с дедупом, счётчики created/list_*/tag_*; поиск по закваскам (имя + домены) на вкладке «Закваски» (`tagsFilter` переиспользуется в диалоге); фон шума: `action=dns_baseline` (домены из dns_live/DNS_LOG по выбранным ips) + снимок на момент включения трейса → приглушённая свёрнутая группа «Фон (N)», домены без трафика → бейдж «только DNS»; `"bytes"` из conntrack в JSON соединений (порог 100 B, dport 53 исключён) → «только с трафиком». Файлы: `index.html`, `cgi-bin/manage.sh`, `cgi-bin/data.sh`; CLI/libs не менялись, `kvas.help` без изменений (новых CLI-команд нет), новых файлов конфигов нет (`tags.list`/`kvas.list` уже в backup-списках), TG: существующее уведомление `kvas tags add` | ✓ v631 (жалоба 630: «→ в закваску» просто добавляет в список, нет «выделить все» и поиска по закваскам, фон и трафик не различаются) |
| **Мобильные переполнения Web UI (v632): строка результата трейса получила `flex-wrap:wrap`, счётчик с устройствами (`×N · ip1, ip2`) перестал быть `white-space:nowrap` (`flex:0 1 auto` + `word-break:break-all`) — после отслеживания список устройств в строке уезжал за вьюпорт и расширял страницу (`#traceResults` вне `.card`, без overflow-клиппинга); модалка «Добавить в закваску»: `min-width:0` у бокса/`#traceTagPickList`/инпута поиска (как flex-item она имела automatic min-size = min-content от длинных имён заквасок), `overflow:hidden` на оверлее, `word-break:break-all` в строках списка и `overflow-wrap:anywhere` в подсказке; defensive `flex-wrap` в `.status-bar`, шапке «Выделить все» и модалке `editTagOverlay` | ✓ v632 (жалоба 631: «после отслеживания поле устройства выходит за пределы мобильного вида, страница шире», «модалка добавления в закваску не вписывается в мобильный вид») |
| **Мобильный дропдаун устройств (v633): `.filters label` и `.filters select/input` получили `min-width:0; max-width:100%` (+`text-overflow:ellipsis` у select) — option вида `ip + длинное имя устройства` растягивал intrinsic-ширину `#filterDevice` до ширины содержимого и расширял мобильную страницу; flex-item label теперь жёстко ограничен шириной `.filters` | ✓ v633 (жалоба 632: «когда отмечаю устройство с длинным названием, дропдаун увеличивается и расширяет мобильный вид») |
| **Агрегатор VLESS (v634): пул голых `vless://`-ссылок (`/opt/etc/kvas.aggregator`, по одной на строку, # - комментарий) с полным тестом каждого кандидата (apply → xray restart → socks-проба на 2ip.io/ifconfig.me через IP_FILTER): sticky-переключение на первый живой, 3 неудачи подряд → dead, dead перепроверяются каждые 30 мин (cron.15min/aggregator, гейт AGG_RECHECK_SEC=1800, общий lock), смерть активного → авто-сдвиг с TG-уведомлением, пул исчерпан → fallback на снапшот ручного конфига (`/opt/etc/xray/kvas.json.manual`) + TG; управление в трёх местах: Web UI (карточка «Aggregator VLESS» в «Управлении», on/check CGI идут в фон, лог `/opt/var/kvas/agg.last.log`), CLI `kvas aggregator status/list/add/del/on/off/check/set` (help-секция), Telegram (`/aggregator`, клавиши Agg ON/OFF/Check, строка в `/status`); state `/opt/var/kvas/aggregator.state` (ENABLED/ACTIVE/LASTCHECK/FAIL_n/DEAD_n), пул в backup (`kvas.aggregator`), whitelist TG-событий +`aggregator` (только авто-события) | ✓ v634 (запрос v633: агрегатор VLESS-ссылок; решения юзера: голые ссылки по одной на строку / полный тест через прокси / sticky первый живой / dead=3 + recheck 30 мин / fallback снапшот ручного + TG / управление UI+CLI+бот) |
| **Горячий фикс агрегатора (v635): CGI-парсер `n` в `manage.sh`** — `apiBtn` дописывает `&token=` последним, а жадный `sed 's/.*n=//'` цеплялся за `n=` внутри `token=` и выдавал токен вместо номера сервера, поэтому Web UI при удалении/переключении отвечал `n required (1..pool)`; парсер в `agg_del|agg_set` и `agg_check` теперь привязан к `&n=` (`s/.*&n=//`), в test635 — регресс-тест парсера (в т.ч. воспроизведение ловушки на старом паттерне) | ✓ v635 (баг влит сразу после v634) |
| **Telegram P.8: уведомления (tg_notify + quiet hours)** | ✓ |
| **Telegram P.8+: interactive bot (English ASCII menu)** | ✓ tested /menu v600–601 |
| **Telegram: singleton бота + cron keepalive (tg_sender)** | ✓ |

### 4.1 Telegram-бот (P.8+)

- **Файлы:** `bin/tg_bot.sh`, `bin/libs/tgq`, `bin/tg_sender.sh`, `bin/tg_job.sh`, `bin/tg_health.sh`; cron: `cron.1min/tg_sender`, `cron.15min/tg_health`.
- **Конфиг:** `TG_ENABLED`, `TG_BOT_TOKEN`, `TG_CHAT_ID`, `TG_QUIET_START/END` (тихие часы), whitelist событий `failover|update_found|upgrade|tunnel|health|parental_expire` (v606: +`upgrade` — иначе «Обновление выполнено» из CLI/WebUI не доходило).
- **Сеть:** Telegram только через `tg_curl`/`tg_curl_to` (socks5h, порт из `tg_socks_port`, default 1097). long-poll getUpdates `timeout=25`, sendMessage fire-and-forget, RC=0 только при `"ok":true`.
- **Singleton:** atomic `mkdir` lock + pid re-verify + `kill -9` чужих; один EXIT-trap; TERM/INT/HUP → `exit 0`. Keepalive: `tg_sender` стартует бота, только если lock-каталога нет и 0 инстансов; **v627:** если lock есть, а pid в нём мёртв — stale-lock снимается и поллер стартует (раньше мёртвый lock блокировал автозапуск навсегда, ручной `rm -rf lock` не помогал). Также кнопка «Перезапуск бота» в Web UI (`tg_bot_restart`) и `bot_running` в `tg_get`.
- **Меню:** English ASCII клавиатуры (`KB_MAIN` и др.): `Kvas.list|Tags` / `Tunnels|Diagnostics|Help` (v619: +Tunnels — выбор тоннеля из бота). Русская клавиатура в Telegram = sticky от старого ответа, пока не придёт новый reply_markup.
- **Лог:** `/opt/var/kvas/tg_bot.log` (`START/PRE/POLL/NMSG/MSG/REPLY/SHOW/SEND/SEND_RC/CMD_DONE`).
- **Критический баг v600:** в `case` busybox `|` — alternation, не литерал. `*|*` матчил всё → `${_rest#*|}` не двигал `_rest` → infinite loop в `tb_kb` (вис на `/menu`). Фикс: `*'|'*`.
- **Сожжённые номера:** 577/578/579/591 (упаковка postinst в data)/592 (баг бота)/603 (опечатка `${_ch}` вместо `${_tl_ch}` в tg_send_long)/607 (не чинил tunnel_check: `myip.addr.tools` не резолвился у пользователя, нужен `2ip.io` как в диагностике)/**612 (сломал основной список: dedup-счётчик в `ip4__add_routing_for_home` ловил строку `-j KVAS_MARK2` подстрокой `-j KVAS_MARK` → count=2 → цикл удалял прыжок lane1 br0)**. 608/609/610/611/613/614/615/616/617/618/619/620/621/622/623/624/625/626/627/628/629/630/631/632/633/634/635 — рабочие. Следующий = **636**.
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
- **Пакет v615 (фикс удаления в Списке 2 + подписи тоннелей):**
  - **Баг: ✕ не удалял единственную запись** — `cmd_list2_del` делал `grep -Fxv host file > tmp && mv tmp file`: при единственной записи `grep -v` не выводит строк → rc=1 → `mv` не выполнялся → файл не менялся, но «Удалено» печаталось (Web показывал «удалено», запись оставалась). Фикс: rc-гард (`grep_rc <= 1` → mv; rc>1 → rm tmp + ошибка, список не затирается).
  - **Подписи тоннелей как в основном списке:** новая `cmd_list2__label` (описание из `inface_equals` field3, fallback field2 → токен; `current` → «текущий (<desc основного тоннеля>)»); `cmd_list2_status` отдаёт строки `label.<токен>=<описание>`; CGI собирает JSON-объект `names` через `json_str`; Web UI селект: `(d.names && d.names[t]) || labels[t] || t`; CLI `kvas list2 tunnel [-list]` показывает «токен — описание (интерфейс: …)».
  - **loadList2:** защита от гонки параллельных обновлений (`_l2Busy`/`_l2Again`: повторный вызов ставится в очередь и выполняется после завершения текущего — список/select не перемешиваются и не остаются пустыми).
  - **Отладка v615 (роутер):** правила 1777/1778/1779 и table 201 подтверждены (`default dev nocli0`, gateway-net `172.16.5.0/24 via 172.16.5.4`), трафик Списка 2 идёт через нативный тоннель — первое срабатывание выглядит как «долго ждал», т.к. dnsmasq/ipset догоняют после regen.
  - **Сборка:** CONTROL `Version: 1.1.9_beta-10-615`, postinst fallback `_rel=615`; изменённые файлы: `bin/libs/list2`, `bin/monitor/www/cgi-bin/manage.sh`, `bin/monitor/www/index.html`, `postinst`.
- **Пакет v616 (мгновенное применение Списка 2 после add/del):**
  - **Симптом:** после удаления адреса из Списка 2 трафик шёл через тоннель ещё 10+ минут. Две причины: (1) `cmd_list2__drop_domain` резолвит домен заново (через DNSCrypt/внешний DNS) и при CDN-ротации промахивается мимо IP, которые dnsmasq занес в ipset — набор не чистится; (2) марка полосы живёт в CONNMARK (`--save/restore-mark`), цепочки метят только NEW (`-m conntrack ! --ctstate NEW -j RETURN`) — действующие соединения (HTTP/2, QUIC в открытых вкладках) держат старую метку хоть час.
  - **Фикс:** `cmd_list2__rebuild` при удалении: сброс conntrack всех участников ipset + сброс conntrack всех записей с меткой `0xd1001` (покрывает уже вычищенные из набора, но живые), `ipset flush`, пересборка из `kvas2.list` (statics через `main/ipset`, домены — резолвом), HUP dnsmasq. `cmd_list2__flush_ct` (conntrack -D по dst/src, CIDR/диапазоны пропускаются) вызывается и при добавлении домена — новые соединения сразу получают метку.
  - `conntrack` в отсутствие утилиты — тихий пропуск (поведение прежнее, только медленнее).
  - **Отладка v616:** функциональный тест с фейковыми ipset/conntrack: удаление средней записи (stale-IP убран, остатки перезаполнены, 8.8.8.8 не тронут), добавление (ct сброшен), регресс одиночного удаления.
  - **Сборка:** CONTROL `Version: 1.1.9_beta-10-616`, postinst fallback `_rel=616`; изменённые файлы: `bin/libs/list2`, `postinst`.
- **Пакет v617 (Telegram-бот: кнопка обновления из фонового уведомления):**
  - **Баг:** фоновая проверка версии (`tg_check_kvas_update` → `tg_notify update_found`, cron/цикл бота) шлёт `[update_found] Доступно обновление...` **без клавиатуры и без state `update_confirm`** → ответ пользователя «Yes update» (кнопкой из главного клавиатурного ресайза или текстом) не матчился ни глобальным case, ни state-машиной → `Unknown. Use menu or /help`.
  - **Фикс (2 места):** `tg_sender.sh` — на событие `update_found` крепится reply-клавиатура `[["Yes update"],["No cancel"]]`; `tg_bot.sh` — глобальный обработчик в `tb_on_text` (до state-машины, только при пустом state или `update_confirm`): «Yes update» → `tb_check_update` → запуск job update (либо «up to date»), «No cancel» → clear state + меню. `/update`-сценарий не менялся.
  - **Сборка:** CONTROL `Version: 1.1.9_beta-10-617`, postinst fallback `_rel=617`; изменённые файлы: `bin/tg_bot.sh`, `bin/tg_sender.sh`, `postinst`.
- **Пакет v618 (возврат fill_domain add + удаление статики из основного списка):**
  - **Регрессия v616 (Список 2):** в `cmd_list2__fill_domain` правка v616 заменила `ipset -exist add` на `ipset del` (вместе с добавлением flush_ct) → add домена не наполнял `KVAS_LIST2` (работал только dnsmasq-тег при повторном DNS-запросе клиента — «появилось после обновления страницы»), а `cmd_list2__rebuild` при каждом удалении вычищал IP оставшихся доменов и ронял их conntrack — после операции удаления Список 2 ломался у остальных записей. Фикс: вернуть `ipset -exist add` (flush_ct при добавлении сохранён — действующие соединения должны встать в новую полосу).
  - **Баг `kvas del` (основной список):** ветка удаления всегда шла через `dns__get_ips_by_domain` — на IP-литерал kdig A-запрос возвращает пусто → `ipset del` не выполнялся: строка из `kvas.list` удалялась, а член `KVAS_LIST` с `timeout 0` (бессрочный, статика) оставался навсегда; conntrack не сбрасывался вообще. Следствие: пока домен был в Списке 2, цепочка KVAS_MARK2 перекрывала lane1; после удаления из Списка 2 PREROUTING матчил остаточный член → mark 0xd1000 → правило 1778 → таблица 200 → трафик «попадал в основной тоннель» при чистом kvas.list (диагностика: `ipset list KVAS_LIST` → `116.202.113.61 timeout 0`, файл по имени чист). Фикс: IP/диапазон/CIDR (по `get_regexp_ip_or_range`) удаляются напрямую `ipset -exist del` + `ct__flush_ips` — чистка идёт даже если строки в файле уже нет (застрявший член); для доменов добавлен ct-flush срезолвленных IP. Общий `ct__flush_ips()` вынесен в `libs/main` (`cmd_list2__flush_ct` делегирует).
  - **Отладка v618 (роутер, подтверждено пользователем):** dnscrypt и conntrack в порядке — не фактор; `KVAS_LIST` создан с `timeout 86400` (доменные члены самоистекают ≤24 ч, `timeout 0` — нет); ручная чистка `ipset del KVAS_LIST 116.202.113.61` + ct-flush → после удаления из Списка 2 exit-IP = провайдер (напрямую) — причина доказана вживую.
  - **Сборка:** CONTROL `Version: 1.1.9_beta-10-618`, postinst fallback `_rel=618`; изменённые файлы: `bin/libs/list2`, `bin/libs/main`, `bin/kvas`, `postinst`.
- **Пакет v619 (фикс флапа failover при ручном AWG + бот «Tunnels»):**
  - **Баг (диагноз §4.2 подтверждён данными роутера):** ручной выбор AWG писал в `kvas.failover.conf` desc `PRIMARY=Kvas-proxy-awg`, а `get_active_iface` для `Proxy42` жёстко возвращает токен `awg` → `active≠PRIMARY` навсегда → `awg==TERTIARY` → ветка tertiary каждые 30с: «восстановлен» → `switch_to` на тот же Proxy42 → «Демон запущен» → повтор (без FAIL_THRESHOLD/anti-flap в secondary/tertiary-ветках). Плюс `check_awg` не source'ил `$AWG_ENV` (127.0.0.1:10818 не подхватывались → проба могла всегда падать) и токен `awg` не принимался в `kvas vpn set`.
  - **Фиксы:** (1) `bin/kvas`: case `_new_primary` += `*Proxy42*|*t2s42*) _new_primary="awg"`; `vpn set` принимает `vless|hysteria|awg` — ветка awg: `iface_cli="${PROXY_AWG_NAME:-Proxy42}"` (lookup из `inface_equals`), старт `S99awg` зеркально hysteria, `PRIMARY="$proto"` → `awg`; XRAY_INIT-подмена сохраняется. (2) `libs/awg check_awg`: `[ -f "$AWG_ENV" ] && . "$AWG_ENV"` + guard `[ -z IP ] || [ -z PORT ] && return 1` (стиль `check_hysteria`). (3) `libs/failover`: `_fo_canon()` — awk-lookup desc (field3, с кавычками → без) в `inface_equals` → cli → токен `Proxy21→vless`, `Proxy41→hysteria`, `Proxy42→awg`, иначе значение как есть; применяется к PRIMARY/SECONDARY/TERTIARY в `load_failover_conf` (**вариант B** — существующий conf пользователя чинится автоматически при каждом чтении) + дедуп `TERTIARY==PRIMARY/SECONDARY → ""` в load и save (дропдауны UI не валидируют).
  - **Фича — Telegram-бот «Tunnels» (паритет с Web UI, по заявке пользователя):** `KB_MAIN` += `Tunnels`; `tb_show_tunnels` (шапка «current: <friendly>», кнопки из `tb_tunnel_lines`, `tb_state_set tunnels`); state `tunnels`: валидация выбора по списку (`grep -qxF`), `_tb_cli_of` (vless→Proxy21, hysteria→Proxy41, AmneziaWG/awg→Proxy42, иначе as-is), «Already active» при совпадении с `INFACE_CLI` из `kvas.conf`, иначе `tb_state_clear` + `tb_job vpn <cli>`; `tg_job.sh` mode `vpn` → `kvas vpn set <iface>` → результат (`tbf_strip`/tail 1500) с friendly-именем; команда `/tunnels`, `Back` из state → меню, help обновлён.
  - **Тест:** `test619.sh` — реальные вырезки `_fo_canon`/`load_failover_conf`/`check_awg`/`_tb_cli_of` из SOT (desc→канон в т.ч. legacy conf, дедуп tertiary, env-guard check_awg, маппинг бота) + структурные маркеры = **28/28, `TEST_RC=0`**; `PRECHECK_RC=0` (75 маркеров); `VERIFY_DONE`/`VERIFY_EXIT=0` (один проход).
  - **Сборка:** CONTROL `Version: 1.1.9_beta-10-619`, postinst fallback `_rel=619`; sha256 `6f30fa20b6cceede7a5c47c0bfdb5eb3533255b4364a83c783e33a69780e9114` (313 134 B); изменённые файлы: `bin/kvas`, `bin/libs/awg`, `bin/libs/failover`, `bin/tg_bot.sh`, `bin/tg_job.sh`, `postinst`.

### 4.2. Баг v619: флап failover при ручном AWG — диагноз ПОДТВЕРЖДЁН, ФИКС ВНЕСЁН (29.09.2026 → v619, 30.09.2026)

**Симптом (пользователь):** при принудительном выборе AWG socks5 (`t2s42`) при включённом failover — «автоматом переключает на vless, в итоге vless упал, помог `kvas init`»; затем — постоянные автопереключения каждые секунды, «файловер отключил и остался на одном» (vless «упал» один раз, воспроизводимость эпизодов `awg→vless` неясна — secondary менялся руками).

**Подтверждённые данные (роутер):**
- `inface_equals`: `Proxy42|t2s42|"Kvas-proxy-awg"` (пара `Proxy21|t2s21|"Kvas-proxy-vless"`, `Proxy41|t2s41|"Kvas-proxy-hysteria"`); `kvas.conf`: `INFACE_CLI=Proxy42`, `INFACE_ENT=t2s42`.
- `kvas.failover.conf`: `PRIMARY=Kvas-proxy-awg` (desc!), `SECONDARY=hysteria`, `TERTIARY=awg` (токен из available) — задано руками.
- Лог циклом: `Активен awg (второй резерв). Проверяем выше...` → `Kvas-proxy-awg восстановлен. Возврат.` → `SWITCH: awg -> Kvas-proxy-awg` → `Демон запущен` → повтор (история: непрерывный флап `awg→Kvas-proxy-awg`, `awg→hysteria`).

**Диагноз (код подтверждает гипотезу пользователя: «awg не учли в логике ручного указания»):**
1. **Рассинхрон имён одного канала:** ручной выбор/`failover set primary` в ветке `*` (`bin/kvas:595-602`) маппит только `Proxy21→vless`, `Proxy41→hysteria`, а для `Proxy42` пишет **desc `Kvas-proxy-awg`** (lookup `:599`); `get_active_iface` (`libs/failover:229-231`) для `Proxy42` возвращает **`awg`** (жёстко, перекрывая desc-ветку `:233-238`). → `PRIMARY=Kvas-proxy-awg` ≠ `Активный: awg` навсегда.
2. **Флап-цикл:** `active("awg") == TERTIARY("awg")` → ветка tertiary (`failover:478-490`) → «восстановлен» → `switch_to Kvas-proxy-awg` → `kvas vpn set` реально переключает на тот же Proxy42/t2s42 → активный снова `awg` → повтор. В ветках secondary/tertiary нет ни `FAIL_THRESHOLD`, ни anti-flap. Пробы primary идут через `check_tun_interface(t2s42)` (работает — «восстановлен»), эпизоды `awg→hysteria` — та же ветка при упавшей пробе.
3. **Путь Web UI:** селект шлёт `vpn_set&iface=t2s42` (`index.html:1612` — `opt.value` = ent) → та же ветка `*` → тот же рассинхрон; `proto=vless|hysteria` — отдельные кнопки, для AWG их нет.
4. **Побочный дефект:** `check_awg` (`libs/awg:497`) использует `PROXY_LOCAL_IP`/`PROXY_LOCAL_PORT_SOCKS`, но **не source'ит `$AWG_ENV`** (значения в `awg/etc/conf/env.sh`: 127.0.0.1:10818) — при `PRIMARY=awg` проба может всегда падать → вечный увод на hysteria. `check_hysteria` в том же lib env читает (`failover:266-269`) — аwg-нет.
5. **Мостик для switch:** токен `awg` в `kvas vpn set` не обрабатывается (ветка только `vless|hysteria`, `bin/kvas:489`) → после фикса (1) `switch_to awg` завершился бы ошибкой «Интерфейс 'awg' не найден» — нужен маппинг `awg→Proxy42` (как `vless→Proxy21`, `hysteria→Proxy41`).

**Фикс v619 (ВНЕСЁН — все 5 пунктов, см. «Пакет v619»):**
1. `bin/kvas` ветка `*`: case-ветка `_new_primary` += `*Proxy42*|*t2s42*) _new_primary="awg" ;;` (параллельно Proxy21/41).
2. `bin/kvas vpn set`: расширить `vless|hysteria` → `vless|hysteria|awg` (ветка `awg`: cli=Proxy42 lookup из `inface_equals`, старт `S99awg` зеркально hysteria; XRAIN_INIT-подмена сохраняется).
3. `libs/awg check_awg`: `. "$AWG_ENV"` + guard непустоты порта (как check_hysteria).
4. **Опция A (без миграции):** после обновления руками `kvas failover set primary awg`. **Опция B (рекомендуется):** нормализация desc→канон в `load_failover_conf` (desc из `inface_equals` для Proxy21/41/42 → vless/hysteria/awg) — чинит существующий conf пользователя автоматически.
5. Тест: precheck/verify grep-маркеры + функциональный тест (get_active_iface/canonical + check_awg c фейк-env).

**Фича-запрос пользователя:** в Telegram-боте нет выбора тоннеля (в Web UI есть) — хотелось бы выбирать тоннели из бота. **Вшита в v619** (Tunnels-меню, см. «Пакет v619»).

- **Пакет v620 (профиль ресурсов wireproxy переживает upgrade/backup + службы в «Состоянии системы»):**
  - **Баг (диагноз):** `awg/etc/conf/env.sh` (`RESOURCE_PROFILE/GOMAXPROCS/GOMEMLIMIT/GOGC/GODEBUG`) лежит ВНУТРИ пакета → `kvas upgrade`/`kvas rollback` через `opkg install --force-reinstall` (`main/upgrade`) перезаписывает его дефолтом `balanced` при КАЖДОМ обновлении (комментарий «конфиги /opt/etc сохраняются» для /opt/apps неверен); `backup_configs.sh`/`restore_configs.sh` никем не вызываются (мёртвые); `save_backups()`/`restore_backups()` (`main/setup`) сохраняли hysteria env, но НЕ awg env → после обновления Web всегда показывал «balanced» (индикатор `awg_mode` читает RESOURCE_PROFILE из env.sh).
  - **Фиксы:** (1) `libs/main` += `AWG_ENV_FILE`/`AWG_ENV_BACKUP` (зеркально hysteria). (2) `main/setup`: `save_backups()` += `backup_copy "${AWG_ENV_FILE}" ...`, `restore_backups()` += `restore_backup "${AWG_ENV_BACKUP}" ...` — цепочки `kvas backup`/`restore` и uninstall. (3) `main/upgrade`: до opkg-блока сохранение env в `/tmp/.kvas_upg_awg_env.$$`, после — **merge** 5 ресурсных переменных в новый env.sh (новые ключи пакета не затираются; общий код покрывает и upgrade, и rollback).
  - **Web — «Состояние системы» (по заявке пользователя):** строка «Служба AmneziaWG» (`sysAwgService` + `sysAwgProfile` «профиль: …»), inline-кнопки [Старт/Стоп][Рестарт] у трёх служб (JS `svcToggle`/`svcAct`/`svcSetBtn` по `xray_service`/`hysteria_service`/`awg_service`, вывод в `sysSvcMsg`); новое CGI-действие `tunnel_restart` (зеркально `tunnel_start`: `service_action S97xray/S99hysteria restart`, `$KVAS_BIN awg restart`, `*` → error); `system_status` += `awg_service` (not_installed по S99awg, иначе running/stopped по pidfile/pidof wireproxy) + `awg_profile` (RESOURCE_PROFILE, fallback `balanced`). Кнопка Старт/Стоп wireproxy в «Настройка VPN» (`awgToggleBtn`/`awgToggle`/`updateAwgToggleBtn`) **удалена** — дублировала службу; инпуты/«Обзор»/профиль/селекты остались.
  - **Правило (§4.3):** требование пользователя — при любом изменении функционала обходить все логические цепочки и проверять backup/restore — записано в **§4.3** (эталон ошибки = этот баг).
  - **Тест:** `test620.sh` — реальные срезы: merge-блок `main/upgrade` (perf/eco восстанавливается, новый ключ пакета сохраняется, не тронутая переменная остаётся), `backup_copy`+`restore_backup` (roundtrip awg env + отсутствие бэкапа не трогает файл), dispatch `tunnel_restart` (vless/Proxy21/hysteria/Proxy41/awg/Proxy42 + bogus + пустой/отсутствующий iface), чтение `awg_profile` в `system_status` (perf/пусто/fallback balanced) + регрессии v619 = **35/35, `TEST_RC=0`**; `PRECHECK_RC=0` (все маркеры, включая отсутствие `awgToggleBtn`); `VERIFY_DONE`/`V_RC=0` (один проход).
  - **Сборка:** CONTROL `Version: 1.1.9_beta-10-620`, postinst fallback `_rel=620`; sha256 `8bdb1743ff444e389b30c14293665f5d92042abd68a1118ef5c22a6d53528645` (313 988 B); изменённые файлы: `bin/libs/main`, `bin/main/setup`, `bin/main/upgrade`, `bin/monitor/www/cgi-bin/manage.sh`, `bin/monitor/www/index.html`, `postinst`.

- **Пакет v621 (ремонт кнопок служб + архитектура xray mipsel + правило справки):**
  - **Баг (диагноз, жалоба пользователя):** нажатие «Рестарт» → `manage.sh: line 1049: service_action: not found`. CGI никогда не source'ит `libs/main` (только фоновые подзадачи `adguard_on`/restore), а `service_action` определена там же → все кнопки Старт/Стоп/Рестарт у xray/hysteria падали (латентно: до v620 ветки vless/hysteria в `tunnel_start/stop` не вызывались из UI — использовался только awg). Плюс два смежных бага: `libs/main service_action()` хардкодила `-exec {} start` (аргумент действия игнорировался — все stop/restart-вызовы CLI фактически перезапускали сервис); `libs/vless _xray_detect_arch()` матчил `*mipsle*|*mipsel*` generic-веткой `*mips*` → арх `mips32` (big-endian) → качался не тот бинарник Xray.
  - **Фиксы:** (1) `manage.sh`: все 6 вызовов заменены на прямые `/opt/etc/init.d/S97xray start|stop|restart` и `/opt/etc/init.d/S99hysteria start|stop|restart` (в контейнере device подтверждены: S97xray через `rc.func`, S99hysteria/S99awg со своими case start/stop/restart; в CGI не осталось ни одного `service_action`; `service_action` в `bin/kvas`/`main/setup` — оставлена, CLI source'ит `libs/main`). (2) `libs/main service_action`: `-exec {} "${_action}"` — stop/restart доходят до скрипта. (3) `libs/vless _xray_detect_arch`: порядок веток `*mips64el*|*mips64le*` → `*mips64*` → `*mipsle*|*mipsel*` → `*mips*`, плюс `*riscv64*`/`*loong64*|*loongarch64*` (ассеты подтверждены по GitHub API XTLS/Xray-core v26.3.27: `Xray-linux-mips32le.zip`, `mips64le`, `mips64`, `riscv64`, `loong64`).
  - **PRD §4.3 п.4 (по заявке пользователя):** при изменении функционала обновлять справку — `etc/conf/kvas.help` (`kvas help`), help Telegram-бота, подсказки Web UI, PRD; grep новых ключей в справке наравне с кодом в precheck/verify.
  - **Тест:** `test621.sh` — реальные срезы dispatch `tunnel_start/stop/restart` (прямые init.d, подмена пути в срезе, фейковые init-скрипты: vless/failover-start, Proxy21, hysteria, awg, Proxy42, bogus, пустой iface, bash -n), `service_action` (stop/restart/start доходят до скрипта, пустой сервис rc=1), `_xray_detect_arch` (11 uname-кейсов через uname-stub) + регрессии v620 (merge/roundtrip/profile) и structural v619/v620 = **45/45, `TEST_RC=0`**; `PRECHECK_RC=0` (~115 маркеров, incl. `abs service_action` в CGI, прямые init.d-пути, `\\;` в libs/main, mips-порядок); `VERIFY_DONE`/`V_RC=0` (один проход).
  - **Сборка:** CONTROL `Version: 1.1.9_beta-10-621`, postinst fallback `_rel=621`; sha256 `32259134fc6bde7811b6b4e7e26630320d28e3cd98c20952930cbd6a2de0fc34` (314 034 B); изменённые файлы: `bin/monitor/www/cgi-bin/manage.sh`, `bin/libs/main`, `bin/libs/vless`, `postinst`.

- **Пакет v622 (кнопки служб на реальном устройстве: резолв S24xray/пакет + пакетный fallback; селект профиля wireproxy):**
  - **Баг 1 (диагноз, жалоба пользователя):** `manage.sh: line 1048: /opt/etc/init.d/S97xray: not found` при Стоп/Рестарт. Причина: `main/setup` source'ит `libs/vless` (строки 2-4), где `XRAY_INIT=/opt/etc/init.d/S24xray` → symlink на устройстве setup:620 создаёт **именем S24xray** (`ln -s /opt/apps/kvas/etc/init.d/S97xray ${XRAY_INIT}`), а путь `/opt/etc/init.d/S97xray` не существует никогда. Прямые вызовы v621 упирались в это имя; исторически `service_action S97xray` (find в /opt/etc/init.d) молча ничего не находил — find без совпадений exit 0 = ложный успех (цепочки `kvas vless set` (bin/kvas:556), setup:704, vpn:2592 и failover-ветка vpn:235 были latent-сломаны).
  - **Фиксы:** (1) CGI `run_service()`: первый существующий из кандидатов — для xray `/opt/etc/init.d/S24xray` → `/opt/etc/init.d/S97xray` → `/opt/apps/kvas/etc/init.d/S97xray`, для hysteria device-ссылка → пакетный путь; во всех 6 ветках dispatch (start/stop/restart), отсутствие всех кандидатов → сообщение в вывод. (2) `libs/main service_action`: если в `/opt/etc/init.d` нет совпадений — второй `find` по пакетным init.d-каталогам (`/opt/apps/kvas/{,hysteria/,awg/}etc/init.d/`), запуск первого найденного; нигде нет → rc=1 (вместо ложного 0). (3) `libs/vpn` failover-ветка xray: `_xinit="${XRAY_INIT:-}"` → если файла нет — пакетный путь.
  - **Баг 2 (диагноз):** в «Состоянии системы» строка «профиль: perf», а селект «Профиль wireproxy» — «balanced». `awg_mode` GET без параметра делал `sed 's/.*profile=//; s/&.*//'` БЕЗ guard: на `action=awg_mode` подстроки `profile=` нет → sed возвращал всю строку → `[ -z ]` ложно → SET-ветка → `json_error "unknown profile: action=awg_mode"` → `awgModeLoad` не получал `d.profile` → селект оставался на статическом `selected=balanced`. SET с `&profile=` работал → применение профиля меняло его, чтение — никогда. Фикс: `sed -n 's/.*[&?]profile=\([^&]*\).*/\1/p'` (guard &/?; идиома `[ "$_x" = "$QUERY_STRING" ]`, применяемая в tg-секциях этого же файла).
  - **Тест:** `test622.sh` — **74/74, `TEST_RC=0`**: dispatch-сценарии резолва кандидатов (устройство S24xray → legacy S97xray → пакет; hysteria device → пакет; проверка путей вызова через path-лог фейков, пакетный скрипт НЕ запускается когда есть device-ссылка), `service_action` (пакетный fallback, device-приоритет без двойного запуска, rc=1 когда нигде нет, аргумент действия), `awg_mode` (GET→perf, SET profile=eco применяется, bogus → ошибка), `_xinit`-резолв failover, arch-регрессия v621 (11 кейсов), merge/roundtrip/profile v620, structural; `PRECHECK_RC=0` (~120 маркеров, incl. отсутствие прямых `S97xray start/stop/restart` в CGI и старого sed-профиля); `VERIFY_DONE`/`V_RC=0` (один проход).
  - **Сборка:** CONTROL `Version: 1.1.9_beta-10-622`, postinst fallback `_rel=622`; sha256 `ebe6bd5fedf3db8168a7d0e06001a83ade89378e210437b6ffdd83455f67aad9` (314 267 B); изменённые файлы: `bin/monitor/www/cgi-bin/manage.sh`, `bin/libs/main`, `bin/libs/vpn`, `postinst`.

- **Пакет v623 (xray на little-endian mips: эндianness-проба по ELF + guard установки):**
  - **Баг (диагноз, жалоба):** KN-1011 (Giga, RU, архитектура mipsel): `kvas xray core v26.9.30` скачивал `Xray-linux-mips32.zip` (big-endian, 28,4M) → бинарник не запускался → «Установлена версия:» пусто → «Xray не запустился!» → restore из бэкапа. Причина: `_xray_detect_arch()` использовал только `uname -m`, а ядро на LE-mips-устройствах отдаёт **`mips`** без «el» (mipsel виден лишь в UI Keenetic) → ветка `*mips*` → `mips32` (BE). Фикс v621 (явный `*mipsel*` → mips32le) на реальном железе не срабатывал: uname никогда не содержал mipsel. Ассет `Xray-linux-mips32le.zip` присутствует в релизах Xray-core, включая v26.9.30 (проверено по GitHub API).
  - **Фиксы (bin/libs/vless):** (1) `_xray_elf_endian()` — читает ELF `e_ident[EI_DATA]` (байт 5: 1=LE, 2=BE) у хостового `/bin/busybox`/`/bin/sh` (`dd`+`printf`), возвращает le/be/пусто; (2) `_xray_detect_arch()`: неоднозначные `*mips64*`/`*mips*` резолвятся пробой (le → mips64le/mips32le, иначе BE-имена; проба недоступна → прежнее поведение), явные `*mipsel*|*mipsle*`/`*mips64el*|*mips64le*` ветки сохранены; (3) `_xray_guard_binary()` — исполняет скачанный `xray version` **до** остановки демона: не запускается → ошибка «Бинарник не запускается на этой архитектуре» + URL, выход без stop/backup/restore (раньше: стоп → установка → падение → restore).
  - **Сопутствующее:** hysteria/awg маппят все mips-варианты → mipsle (для LE Keenetic случайно верно) — не тронуты; справка/подсказки Web UI заявлений об архитектуре xray не содержат — без изменений (§4.3 п.4).
  - **Тест:** `test623.sh` — **79/79, `TEST_RC=0`**: реальная проба эндiности на хосте (→ le), арх-матрица с моками uname+probe (`mips/le→mips32le` — регрессия KN-1011, `mips/be→mips32`, `mipsel/be→mips32le` — явная ветка бьёт пробу, `mips64/le→mips64le`, 5 немипс-кейсов, unknown→пусто), guard (non-binary отклонён + URL в выводе, `/bin/true` принят, missing отклонён, позиция вызова ДО «Останавливаем xray»), все регрессии v620-622; `PRECHECK_RC=0` (~130 маркеров, порядок веток mipsle < mips в verify сохранён, CRLF-свип); `VERIFY_DONE`/`V_RC=0` (один проход).
  - **Сборка:** CONTROL `Version: 1.1.9_beta-10-623`, postinst fallback `_rel=623`; sha256 `fb1ba914275a6359e437b788884673aa50bb8f63bac39c8ff6cb81f93910047d` (314 452 B); изменённые файлы: `bin/libs/vless`, `postinst`.

- **Пакет v624 (единый полный неинтерактивный `kvas test` для бота и Web UI + выравнивание кнопок действий):**
  - **Диагноз 1 (жалоба: «вид kvas test отличается для бота, он не полный»):** два расхождения. (1) `tg_job.sh` test-кейс обрезал вывод `tail -c 3500` и слал через `tbj_send` (одно сообщение) → начало отчёта (заголовок, интернет, хосты, AdGuard, туннели) терялось — бот выглядел «неполным». (2) Контексты запускали РАЗНЫЕ режимы: бот — полный `kvas test` (интерактивный `ipset_site_visit_check` с 2× `pause` печатал бессмысленные «нажмите клавишу» в чат), веб (`manage.sh` action `kvas_test`) — `kvas test upgrade`, который пропускал и `kvas_list_ipset_check`.
  - **Фиксы:** (1) `libs/check cmd_state_checker`: новый режим **`auto`** — line 705 пропускает только интерактивный `ipset_site_visit_check`, line 690 (`kvas_list_ipset_check`) выполняется → полный неинтерактивный отчёт. (2) `tg_job.sh`: `kvas test auto` + полный вывод через `tbj_send_long` (чанкинг ~3500, без обрезки). (3) `manage.sh`: `test auto` вместо `test upgrade` → бот и веб дают ИДЕНТИЧНЫЙ отчёт. CLI `kvas test` без аргументов — прежний интерактивный полный режим (SSH); `main/upgrade:436 kvas test upgrade` — не тронут (post-upgrade — быстрый режим).
  - **Диагноз 2 (жалоба: «мобильная версия ад перфекциониста», кнопки Стоп/Старт/Рестарт):** кнопки служб/обновлений/чипов были отдельными flex-item'ами `.card-row` → при нехватке места каждый уезжал по отдельности (кнопки AmneziaWG и «Откатить» падали на новую строку без выравнивания, «Обновить» чипов — влево).
  - **Фиксы (`index.html`):** класс `.row-actions { margin-left: auto; display: inline-flex; gap: 6px; flex-shrink: 0; }` — группа кнопок прижата вправо (ПК = единая правая колонка), при переносе на мобильном уходит ЦЕЛИКОМ и выравнивается по правому краю. Применён к 3 строкам служб (span), строке «Обновления» (Проверить/Обновить KVAS/Откатить — одна группа) и кнопке «Обновить» чипов; старые inline-стили `margin-left:8px;display:inline-flex` удалены.
  - **Цепочки (§4.3):** флаг читается только в `cmd_state_checker` (пишет `bin/kvas:791 test|check) cmd_test_warning "${2}"`; читатели: `tg_job` test, `manage.sh kvas_test`, `main/upgrade:436` — оставлен). Справка/подсказки Web UI не менялись: `auto` — внутренний режим неинтерактивных контекстов, команда `kvas test` и кнопки UI прежние (§4.3 п.4 — без изменений).
  - **Тест:** `test624.sh` — **31/31, `TEST_RC=0`**: логика флагов на РЕАЛЬНЫХ строках source (auto → list-check да / site-visit нет; upgrade → оба нет; пусто → оба да), test-кейс tg_job (нарезка case-блока + фейк-kvas: аргумент `test auto`, полный отчёт 9060 байт с HEAD и TAIL, `tbj_send_long` использован, простой send — нет), cgi (`test auto` есть, `test upgrade` ушёл), index.html (CSS, 4 группы, старый inline ушёл, кнопки на месте), регрессии; `PRECHECK_RC=0` (~140 маркеров, incl. `abs 'tail -c 3500'`, `abs 'margin-left:8px;display:inline-flex'`); `VERIFY_DONE`/`V_RC=0` (один проход; в verify `sh -n` добавлен `bin/tg_job.sh`).
  - **Сборка:** CONTROL `Version: 1.1.9_beta-10-624`, postinst fallback `_rel=624`; sha256 `13dbe46af62c105df23f454e9475a802d46acc4f8ca3707eda8855b1a6f178b2` (314 515 B); изменённые файлы: `bin/libs/check`, `bin/tg_job.sh`, `bin/monitor/www/cgi-bin/manage.sh`, `bin/monitor/www/index.html`, `postinst`.

- **Пакет v625 (кнопки «рядом, но по оси» + плитки служб с переключателем вида):**
  - **Диагноз (жалоба на v624):** на ПК `margin-left:auto` увёл кнопки в дальний правый угол карточки («не очень смотрится и можно промахнуться»), на мобиле кнопки оторваны от текста («тоже странно»). Просьба: «пусть будет рядом как раньше, но выровнить»; предложение пользователя: «каждая служба отдельная карточка, на ПК круто, на мобиле прокрутка, вид менять в настройках».
  - **Фиксы (`index.html`):** (1) **ось `.row-main`** — контент каждой строки (label+value+доп) обёрнут в `<span class="row-main">` c `min-width: 340px`: кнопки стартуют вплотную (`margin-left: 8px`) после ОДНОЙ вертикальной оси — на ПК «рядом как раньше», но ровными столбиками; на ≤600px `.row-main`/`.row-actions` становятся `flex-basis:100%` — кнопки аккуратным блоком слева ПОД текстом. (2) **Плитки служб** — три строки обёрнуты в `#svcRows`; вид «Плитками» (класс `tiles`, default): `grid repeat(3,1fr)` карточек-рамок (≤900 → 2 колонки, ≤600 → 1), кнопки во всю ширину плитки (`flex:1`, min-height 38px), текст над кнопками; вид «Списком» = компактные строки. (3) **Тумблер** «Плитками/Списком» в шапке секции (`.card-title-row` + `.view-toggle`, активная кнопка `.primary`), выбор хранится в `localStorage.kvasSvcView`, применяется `applySvcView()` из `showMain()`. Реализация — чисто CSS+класс: один DOM, id статусов/кнопок (`sysXrayService`, `svcXrayBtn`, `sysAwgProfile`…) не дублируются — `loadSystemStatus`/`svcSetBtn`/`svcToggle` работают в обоих видах без правок JS.
  - **Цепочки (§4.3):** `#svcRows` оборачивает ТОЛЬКО три службы — `sysSvcMsg`, «Текущий туннель», «Обновления» остались вне (общие для обоих видов); чипы «Состояние сервисов» получили `row-main` (ось для «Обновить»); справка/подсказки не менялись (вид — локальная настройка UI) — §4.3 п.4 без изменений; новых файлов конфигов нет — backup/restore/upgrade не затронуты.
  - **Тест:** `test625.sh` — **43/43, `TEST_RC=0`**: регрессии v624 (флаги `auto` на реальных строках, полный отчёт бота 9060 B, cgi) + новые html-проверки (ось `row-main min-width:340`, отсутствие `margin-left:auto`, 5 обёрток `row-main`, mobile media, `#svcRows.tiles` grid, 3 колонки десктоп, `setSvcView`/`applySvcView` + 2 вызова, localStorage-ключ, обе кнопки тумблера, `card-title-row`, сохранность id служб/rollback/чипов, уход старого inline-стиля) + регрессии v619-623; `PRECHECK_RC=0` (~155 маркеров, включая `abs row-actions { margin-left: auto`); `VERIFY_DONE`/`V_RC=0` (один проход).
  - **Сборка:** CONTROL `Version: 1.1.9_beta-10-625`, postinst fallback `_rel=625`; sha256 `32a0640f01a8ef79538282264aba911350aec93731a9bfff2257f31fc58f14dc` (314 940 B); изменённые файлы: `bin/monitor/www/index.html`, `postinst`.

- **Пакет v626 (fix чистой установки: мусорные записи в data.tar.gz):**
  - **Диагноз (жалоба Nikolay):** при чистой установке 625 opkg выдал `Collected errors: * extract_archive: Cannot make dir /opt\apps\kvas\.../: Read-only file system` ×11 (в 534 ошибок нет; на самом деле баг был и в 624 — 621-623 чистые). **Причина:** в staging-дереве `/tmp/kfix` (docker builder) появились 11 пустых «сирот» — каталогов с обратными слэшами в именах (`opt\apps\kvas\bin`, `opt\apps\kvas\awg\etc\conf` и т.д., созданы в цикле 624 неизвестной командой). `ipkg-build` упаковал их в `data.tar.gz` (записи идут в конце, т.к. `opt\` сортируется после `opt/`); opkg при распаковке делал `mkdir /opt\apps\...` — путь внутри корня `/` (read-only на роутере) → EROFS. Файлы пакета при этом распаковывались нормально (те же каталоги есть и с прямыми слэшами), но чистая установка пестрила ошибками.
  - **Фикс:** 11 сирот удалены из `/tmp/kfix` (`stray_rm.sh`); контент пакета НЕ менялся (только `postinst` под `_rel=626` + control). **Guard'ы от регрессии:** `precheck626.sh` — `find /tmp/kfix -name '*\\*'` должен дать 0 (staging); `verify626.sh` — `tar -tzf data.tar.gz | grep -c '\'` должен дать 0 (архив, после распаковки). `chmod614.sh` mkdir не делает (проверено) — повторно сироты не появятся; если контейнер builder пересоздадут, staging соберётся заново и чисто.
  - **Цепочки (§4.3):** ни один поставляемый файл не менялся (кроме номера в postinst/control) — симлинки, backup/restore, справка без изменений; §4.3 п.4 без изменений.
  - **Тест:** `test626.sh` — **TEST_RC=0** (регрессии v624-625: флаги auto, полный отчёт бота, cgi, row-main/tiles маркеры, версии `_rel=626`/`Version: …-626`); `PRECHECK_RC=0` (~155 маркеров + новый staging-guard «no stray backslash paths»); `VERIFY_DONE`/`V_RC=0` (один проход, включая archive-guard «backslash entries: 0»).
  - **Сборка:** CONTROL `Version: 1.1.9_beta-10-626`, postinst fallback `_rel=626`; sha256 `14adb9745b78390cea9ac07b20f2f9975cc74241fc307c5d6131d13da637dca8` (314 665 B); изменённые файлы: только `postinst` (число) + `CONTROL/control`.

- **Пакет v627 (keepalive чинит stale-lock поллера бота + кнопка «Перезапуск бота» в Web UI):**
  - **Диагноз (жалоба Nikolay):** тест-уведомления приходят, но бот не реагирует на команды. Вывод: `ps` поллера пуст, при этом `/opt/var/kvas/tg_bot.lock` существует (pid=10158), настройки в порядке (`TG_ENABLED=true`, `TG_CHAT_ID`=tg_lastchat), лог до смерти: `POLL size=23` (= `{"ok":true,"result":[]}`) каждые ~26с, затем `Terminated` (терминал-таймаут). **Причина:** бот погиб и оставил stale-lock — keepalive в `tg_sender.sh:7` проверял только `[ ! -d lock ]` → поллер никогда не перезапускался (исходящая очередь при этом работала: тест шёл, т.к. sender — отдельный путь). Помогал только ручной `rm -rf lock/pid` + запуск `tg_bot.sh`.
  - **Фиксы:** (1) **`bin/tg_sender.sh` keepalive** — если lock существует: при непустом pid и неудачном `kill -0` stale-lock снимается (`rm -rf lock` + `rm -f tg_bot.pid`) и поллер стартует; пустой pid = бот считается стартующим (прежняя семантика сохранена); живой pid → не трогаем. (2) **`manage.sh`: `tg_get`** добавляет поле `bot_running` (ps-grep `tg_bot.sh`); **новый case `tg_bot_restart)`** (:2089-2113): check_token → guard `TG_ENABLED=true` → TERM всех `tg_bot.sh` → sleep 1 → kill -9 добить → rm lock/pid → старт `tg_bot.sh >> tg_bot.log` → sleep 1 → проверка `ps` → `json_ok "бот перезапущен — проверьте реакцию на /menu"` / `json_error "бот не стартовал — см. /opt/var/kvas/tg_bot.log"`. (3) **`index.html`**: кнопка **«Перезапуск бота»** (`tgBotRestart(btn)`, `apiBtn` 30с) прямо в попапе «Уведомления Telegram» (`tgPop`, рядом с «Сохранить/Тест» — по указанию пользователя, не рядом с иконкой); в `tgLoad` индикатор: «не настроено» / «уведомления выключены» / **«бот работает»** (#3fb950) / **«бот остановлен — нажмите „Перезапуск бота“»** (#f85149) по `bot_running`.
  - **Цепочки (§4.3):** `tg_sender.sh` (cron.1min) и `manage.sh tg_bot_restart` → lock/pid `tg_bot.sh`; `tg_get bot_running` ← `tgLoad`/`tgBotRestart` (index.html). Новых файлов конфигов нет — backup/restore/upgrade не затронуты; справка (`kvas.help`, help бота) не менялась: изменения только в Web UI (CLI-команд нет) — §4.3 п.4 без изменений.
  - **Тест:** `test627.sh` — **61/61, `TEST_RC=0`** (запуск с `-u root`): срез РЕАЛЬНОГО keepalive с моками (dead pid → снятие lock+старт; живой pid → без перезапуска, lock цел; пустой pid «st starting» → без перезапуска; lock отсутствует → старт) + статические маркеры `tg_bot_restart`/`bot_running`/`tgBotRestart`/«Перезапуск бота»/«бот остановлен» в cgi/html + регрессии v624-626 (флаги `auto`, полный отчёт бота, `row-main`/tiles, `_rel=627`); `PRECHECK_RC=0` (~160 маркеров, включая stale-lock-маркеры и `find … '*\\*'`=0); `VERIFY_DONE`/`V_RC=0` (один проход; `tg_sender.sh` добавлен в `sh -n`- и CRLF-свипы; archive-guard backslash entries: 0).
  - **Сборка:** CONTROL `Version: 1.1.9_beta-10-627`, postinst fallback `_rel=627`; sha256 `a9f548f5b2580fb72ebc7f5546c571c900934d28b9a85f579d3597f2d2736eb1` (315 306 B); изменённые файлы: `bin/tg_sender.sh`, `bin/monitor/www/cgi-bin/manage.sh`, `bin/monitor/www/index.html`, `postinst`.

### 4.3. Правило: логические цепочки и backup/restore при любых изменениях

При **ЛЮБОМ** изменении функционала (новая опция, параметр, служба, тоннель, файл конфигурации) обязательно:

1. **Обходить все логические цепочки объекта** — найти и проверить каждое место, где объект участвует:
   - CLI: `bin/kvas` + все `libs/*` / `main/*`;
   - Web UI: `index.html` + `cgi-bin/manage.sh` (все actions, где объект читается/пишется);
   - Telegram-бот: `tg_bot.sh`, `tg_job.sh`, `tg_sender.sh`;
   - failover (`libs/failover`: check/switch/load-conf/save-conf), watchdog (`hysteria/awg/etc/ndm/watchdog.sh`), cron, ndm-скрипты;
   - `main/upgrade` (обновление и rollback), `main/setup` (install/uninstall/backup/restore), `postinst`;
   - статусы/диагностика: `system_status`, `kvas test`/`kvas status`, `/status` бота, help/`kvas.help`.
   **Эталон ошибки — «забытый AWG socks5» (v619):** `check_awg` не source'ил env, токен `awg` не принимался в `vpn set`, desc vs token в failover-conf — одна непройденная цепочка = вечный флап failover.
2. **Проверять backup/restore и upgrade/rollback:** новый/изменённый конфиг обязан переживать `kvas backup`→`kvas restore` и `kvas upgrade`/`kvas rollback`:
   - файл добавить в `save_backups`/`restore_backups` (`main/setup`) + `*_BACKUP`-переменную в `libs/main`;
   - файлы **внутри пакета** (перезаписываются opkg) — сохранять/восстанавливать в `main/upgrade` вокруг `opkg install --force-reinstall`, **merge-способом** (только свои переменные, новые ключи пакета не затирать).
   **Эталон ошибки — env wireproxy (v620):** `awg/etc/conf/env.sh` не входил в backup → `RESOURCE_PROFILE` слетал на `balanced` при каждом обновлении.
3. **Фиксировать обход в PRD-блоке «Пакет vNNN»:** список мест (кто пишет → кто читает) + маркеры в precheck/verify + функциональные проверки цепочек.
4. **Обновлять справку (актуальность):** любое изменение CLI/функционала ⇒ обновить `etc/conf/kvas.help` (`kvas help`), help Telegram-бота (`tg_bot`/`kvas.help`), подсказки и описания в Web UI (`index.html`) — и этот PRD. Устаревшая справка хуже её отсутствия: пользователь вводит несуществующие опции и получает ложные ошибки. Проверка: grep новых ключей/действий в справке наравне с кодом (precheck/verify).

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

## 12.3. На будущее: Мастер удалённой раскатки сервера + TrustTunnel (исследование; записано 04.10.2026, не начато)

**Идея мастера (web UI kvas):** форма → фоновый джоб → готовые ссылки в kvas. Пользователь вводит: IP сервера, SSH логин/пароль, чекбоксы протоколов (vless / hysteria2 / awg), домен (поддомен FreeDNS), данные панели (логин/пароль генерируем, секретный `webBasePath`, выбор decoy). Итог: инбаунды созданы, ссылки `vless://`/`hysteria://`/`vpn://` импортированы в kvas (web-поля для них уже есть — `index.html:372-380`).

**Выбран форк панели: `kuzzrus/3x-ui-awg`** (fork MHSanaei/3x-ui): все 3 протокола в одной панели, AmneziaWG нативно в бинаре (`amneziawg-go`, без модуля ядра), настоящие ссылки `vpn://`, Hysteria2-inbound; маскировка панели: встроенный реверс-прокси (Настройки → Реверс-прокси: базовый путь → панель, путь подписки → sub-server, fallback → decoy — настоящий AdGuard Home либо 7 login-заглушек (Portainer/Pi-hole/OMV/Jellyfin/HA/Uptime Kuma/AdGuard), либо zip-сайт, либо прокси), REALITY fallback `target=127.0.0.1:<revproxy>`; аварийка `x-ui setting -disableFrontProxy`. Автоустановка штатная: `XUI_NONINTERACTIVE=1` (или пайп без TTY) → креды в `/etc/x-ui/install-result.env`, cloud-init в `deploy/`, REST API со Swagger + API-токены, проверка `.sha256`.

**Домен: FreeDNS (freedns.afraid.org), поддомен 3-го уровня.**
- A-запись — руками на `/subdomain/` (30 сек) либо автоматически через их старый HTTP/XML-RPC API (sha-hash аккаунта; DynDNS-эндпоинт `update.afraid.org`).
- Сертификат Let's Encrypt: **HTTP-01 работает** при открытом :80 и корректной A-записи (wildcard/DNS-01 невозможен — не владеем `afraid.org`, но он и не нужен).
- **Риск:** rate-limit LE на shared-доменах afraid.org (задокументированный абьюз чужими пользователями) → **стоп-контроль мастера: тестовый выпуск сертификата ПЕРЕД остальными шагами**; при отказе — ретрай либо режим «Вручную» + самоподпись (минус: браузер ругается → маскировка слабее).
- Пробный выпуск прогнать ДО раскатки панели (одна команда certbot/панели).

**Куда девается домен:** reverse-proxy (cert + хост), REALITY (`serverNames`/SNI/`dest`), подписка (`subURI` — HTTPS), поле `address` во всех клиентских ссылках.

**Чек-лист исследования перед реализацией (главные риски):**
1. SSH-бутстрап с busybox-роутера: `ssh` не передаёт пароль неинтерактивно → проверить `sshpass` в Entware / статический бинарь в пакет kvas / фолбэк «одна команда на ПК для установки pubkey». Пароль от чужого сервера не логировать и не хранить в открытом виде.
2. Выяснить, выставляются ли настройки реверс-прокси/decoy через REST API панели (Swagger), CLI `x-ui setting` или только правкой SQLite (хрупко между версиями) — **пункт №1 исследования кода форка**.
3. Таймауты: вся операция 2–5 минут → только async-джоб по готовому паттерну `vpn_progress` (`_lock/_rc/_log`, manage.sh:1003).
4. Порты: REALITY TCP 443 + hysteria2 UDP 443 сосуществуют (разные протоколы), AWG — свой UDP, панель 2053 наружу не выставлять, :80 нужен для LE.
5. Сбор ссылок через API панели: форматы ответов исследовать.
6. Альтернатива скрипту: `terraform-provider-threexui` (batonogov, Terraform Registry) — инбаунды/клиенты как код, `plan`/`apply`, GitOps; можно комбинировать (bootstrap-скрипт + terraform).

**TrustTunnel (AdGuard VPN, Apache-2.0, `github.com/TrustTunnel/TrustTunnel`) — отдельное исследование:**
- Протокол: HTTP/1.1 / HTTP/2 (CONNECT) / QUIC, Rust + Tokio; весь трафик = стандартный HTTPS-проксинг, TCP/UDP/ICMP туннелируются, батчинг на уровне HTTP-фреймов (нет head-of-line blocking на QUIC), TLS обязателен.
- **Не является Xray-протоколом → в 3x-ui/3x-ui-awg НЕ появится** (проверено: нет упоминаний в репо/issue). Ставится отдельным endpoint: `install.sh` → `/opt/trusttunnel`, `setup_wizard` (слушатель, users/rules, cert LE/self-signed), systemd, ссылки `tt://` deep-link / TOML / subscription URL.
- Клиент: TUN (system-wide) или SOCKS5, split-tunneling, kill switch; официальный CLI (Linux/macOS/Windows), GUI (iOS/Android); для Keenetic есть гайд `artemevsevev/TrustTunnel-Keenetic`.
- **Кандидат в kvas как «4-й канал»:** вопрос интеграции — подходит ли SOCKS5-режим клиента как исходящий канал kvas или нужна отдельная ветка в `libs/`; конфликт порта 443 с панелью/REALITY — второй IP либо иной порт (+ UDP под QUIC).
- Статус: только зафиксировано; не начато.

## 13. Авторы

- KVAS: mail@zeleza.ru (оригинал qzeleza/kvas)
- Hysteria, kvas-awg: jobgomel
- Failover / fork: Anonimus2026
