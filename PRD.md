# PRD: KVAS

**Версия:** 1.1.9_beta-10-610
**Дата:** 28.09.2026
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
C:\Users\Pavel\kvas\local_build\            ← SOT артефактов ipk (в т.ч. текущий 610)
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
- GitHub Release `v1.1.9` — единственное место, откуда `kvas upgrade` качает обновления. Upgrade берёт **старший номер** сборки: `sort -n | tail -1` по `beta-10-<N>`. Ассеты: …, 576, 600, …, 609, **610** (текущий).
- Название/описание релиза на GitHub **не трогать** (пишет пользователь).

## 4. Текущий статус (v610)

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
- **Сожжённые номера:** 577/578/579/591 (упаковка postinst в data)/592 (баг бота)/603 (опечатка `${_ch}` вместо `${_tl_ch}` в tg_send_long)/607 (не чинил tunnel_check: `myip.addr.tools` не резолвился у пользователя, нужен `2ip.io` как в диагностике). 608/609 — рабочие. Следующий = **611**.
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

## 5. Сетевая конфигурация

| Протокол | Интерфейс | SOCKS5 | Транспорт |
|----------|-----------|--------|-----------|
| VLESS | Proxy21 | 127.0.0.1:1097 | TCP 443 Reality |
| Hysteria | Proxy41 | 127.0.0.1:10808 | UDP 443 QUIC |
| AWG (wireproxy) | Proxy42 | 127.0.0.1:10818 | userspace SOCKS5 |

`RULE_PRIORITY=1778` (оригинал; значение 99 ломало Keenetic WG). Routing table = 200. fwmark kvas = 0xd1000.

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

## 13. Авторы

- KVAS: mail@zeleza.ru (оригинал qzeleza/kvas)
- Hysteria, kvas-awg: jobgomel
- Failover / fork: Anonimus2026
