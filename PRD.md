# PRD: KVAS

**Версия:** 1.1.9_beta-10-547
**Дата:** 22.09.2026
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
C:\Users\Pavel\kvas\kvas_1.1.9_beta-10-547_all.ipk  ← текущий релиз
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
- GitHub Release `v1.1.9` — единственное место, откуда `kvas upgrade` качает обновления. Assets: 512, 534, 546, **547** (upgrade берёт старший через jq sort).

## 4. Текущий статус (v547)

| Компонент | Статус |
|-----------|--------|
| VLESS (Reality, xhttp/grpc/tcp/ws) | ✓ |
| Hysteria 2 (QUIC) | ✓ |
| AmneziaWG / OpenConnect / WG | ✓ |
| Failover (3 канала: primary/secondary/tertiary) | ✓ работает |
| Web UI (статус, VPN, adblock, parental, закваски, диагностика, backup, upgrade) | ✓ |
| Backup / Restore (CLI + web upload) | ✓ |
| kvas upgrade (force-reinstall + rollback) | ✓ |
| Adblock + parental control | ✓ |
| Закваски tags (add/del/edit, web + CLI) | ✓ |

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
kvas vless new | hysteria new | hysteria status|test
kvas awg [install|new|test|start|stop|uninstall]
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
| tags.list в опубликованном ipk v546 | тестовые записи; **v547 собран чистым** (CLEAN) — больше не актуально |
| `kvas-original` vs upstream | diverged; git push — только через kvas-original |

## 12. Идея (не реализовано): Per-domain routing

Направлять разные домены через разные туннели (VLESS/AWG/Hysteria): несколько ipset + fwmark + table + правила KVAS_MARK, `kvas add x --tunnel awg`, колонка в web UI. Оценка рисков — iptables сложность, perf, MASQUERADE per-interface, HUP при смене туннеля домена.

## 13. Авторы

- KVAS: mail@zeleza.ru (оригинал qzeleza/kvas)
- Hysteria: jobgomel
- Failover / fork: Anonimus2026
