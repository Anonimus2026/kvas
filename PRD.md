# PRD: KVAS + Hysteria 2 + Failover

**Версия:** 1.1.9_beta-10-253 (последняя)
**Дата:** 24.07.2026
**Репозиторий:** https://github.com/Anonimus2026/kvas
**Release:** https://github.com/Anonimus2026/kvas/releases/tag/v1.1.9
**PR:** https://github.com/qzeleza/kvas/pull/318
**Оригинал:** https://github.com/qzeleza/kvas

---

## 1. Описание

VPN-клиент для Keenetic (Keenetic Ultra, aarch64, KeenOS 5.1.x) с поддержкой VLESS, Hysteria 2 и автоматическим переключением (failover).

## 2. Известные проблемы (ТРЕБУЮТ ИСПРАВЛЕНИЯ)

### Проблема 1: `kvas update` ломает dnsmasq
**Симптом:** После `kvas update` dnsmasq не стартует, интернет не работает.
**Причина:** `kvas uninstall yes` (вызывается из upgrade) останавливает и восстанавливает DNS через dnsmasq_install, который заменяет конфиг шаблоном с `@LOCAL_IP`/`@INFACE`/`@UPLEVEL_DNS` placeholders. Если placeholders не заменены — dnsmasq не стартует.
**Файл:** `opt/bin/main/setup` — cmd_uninstall(), строки 872-883 (восстановление DNS)
**Файл:** `opt/bin/libs/vpn` — dnsmasq_install() строка 1385+
**Нужно:** При upgrade НЕ трогать dnsmasq конфиг. Оставлять как есть.

### Проблема 2: `kvas hysteria new` не скачивает бинарник после настройки vless
**Симптом:** При setup нажал "2" (vless), настроил. Потом `kvas hysteria new` — бинарник не скачивается, "как будто нет интернета".
**Причина:** dns-override включён до setup, но dnsmasq может быть с битым конфигом → DNS не работает → GitHub недоступен.
**Файл:** `opt/bin/main/upgrade` строка 388 — dns-override включается ДО setup.
**Нужно:** Включать dns-override ПОСЛЕ того как dnsmasq точно работает.

### Проблема 3: `uninstall full` отключает интернет
**Симптом:** После `kvas uninstall full yes` интернет пропадает.
**Причина:** dnsmasq останавливается, конфиг удаляется, dns-override отключается, но dnsmasq не перезапускается с рабочим конфигом.
**Нужно:** После удаления убедиться что dnsmasq работает или dns-override отключён.

### Проблема 4 -- ИСПРАВЛЕНО: Failover daemon не автозапускается после перезагрузки (v250)
**Симптом:** Failover daemon был включен, после перезагрузки не стартует автоматически.
**Причина:** Флаг `/opt/etc/kvas-failover-enabled` существует, но daemon не запускается в S96kvas.
**Статус:** В процессе разработки. Логика автозапуска добавлена в S96kvas, но не работает корректно.

### Проблема 5 -- ИСПРАВЛЕНО: Web UI не автозапускается после перезагрузки (v250)
**Симптом:** Web UI был запущен, после перезагрузки не стартует автоматически.
**Причина:** Флаг `/opt/etc/kvas-monitor-web-enabled` существует, но сервис не запускается в S96kvas.
**Статус:** В процессе разработки. Логика автозапуска добавлена в S96kvas, но не работает корректно.

## 3. Где исходники

### Репозиторий
```
C:\Users\Pavel\kvas\kvas-original\         ← git clone форка
C:\Users\Pavel\kvas\kvas-original\opt\     ← исходники пакета (структура как в репозитории)
```

### Исходники для редактирования (актуальные v169)
```
C:\Users\Pavel\kvas\v138_extract\opt\apps\kvas\  ← файлы пакета (структура на роутере)
```

### Сборка
```
C:\Users\Pavel\kvas\build.sh               ← скрипт сборки (ipk)
C:\Users\Pavel\kvas\kvas-original\build.sh ← тот же скрипт в git
```

### Бэкапы
```
C:\Users\Pavel\kvas\kvas-final-v164.zip    ← бэкап v164
C:\Users\Pavel\kvas\backup_v210_pre\       ← бэкап v210 до правок (v138_extract)
C:\Users\Pavel\kvas\backup_v20260721-143200\ ← бэкап v210 после web UI (v138_extract)
C:\Users\Pavel\kvas\backup_v20260721-152038\ ← бэкап v210 финальный (v138_extract)
C:\Users\Pavel\kvas\kvas_1.1.9_beta-10-210_all.ipk  ← пакет
C:\Users\Pavel\kvas\kvas-builder-v156.tar  ← Docker образ (525MB)
C:\Users\Pavel\kvas\PRD.md                 ← этот файл
```

## 4. Как собирать

### НАДЁЖНЫЙ СПОСОБ — извлечение из рабочего ipk

**Правило:** ВСЁ делать внутри контейнера. Файлы НЕ копировать через Windows (ломает кодировку).

```powershell
# 0. Запустить Docker
docker start builder

# 1. Скопировать рабочий ipk в контейнер
docker cp C:\Users\Pavel\kvas\kvas_1.1.9_beta-10-<ПРЕДЫДУЩАЯ>_all.ipk builder:/tmp/kvas_base.ipk

# 2. Извлечь файлы ВНУТРИ контейнера (НЕ на хосте!)
docker exec -u root builder sh -c "rm -rf /tmp/extract && mkdir -p /tmp/extract && cd /tmp/extract && tar -xzf /tmp/kvas_base.ipk && tar -xzf data.tar.gz"

# 3. Убрать двойной opt (если есть)
docker exec -u root builder rm -rf /tmp/extract/opt/opt

# 4. Внести изменения ВНУТРИ контейнера
#    - Через sed/python
#    - Или скопировать изменённый файл: docker cp <файл> builder:/tmp/extract/opt/...

# 5. Проверить структуру
docker exec builder ls /tmp/extract/opt/
# Должно быть: apps  etc (без opt!)

# 6. Скопировать в директорию сборки
docker exec -u root builder sh -c "rm -rf /home/me/kvas/opt; cp -a /tmp/extract/opt/. /home/me/kvas/opt/"

# 7. Собрать ipk
docker exec -u root builder sh -c "cd /home/me/Entware && bash /tmp/build.sh <НОМЕР>"

# 8. Проверить (НЕ должно быть opt/opt/)
docker exec builder find /tmp/kvas-ipkg/opt -name "kvas"
# Должно быть: /tmp/kvas-ipkg/opt/apps/kvas/bin/kvas

# 9. Скопировать результат
docker cp builder:/tmp/kvas_output/kvas_1.1.9_beta-10-<НОМЕР>_all.ipk C:\Users\Pavel\kvas\
```

### КРИТИЧЕСКИ ВАЖНО
- **Файлы НЕ копировать через Windows** — PowerShell ломает heredoc, sed, кодировку
- **Все изменения делать через `docker exec`** или `docker cp` (только ipk файлы)
- **Двойной opt**: если `cp -a /tmp/extract/opt /home/me/kvas/opt` — создаётся `opt/opt/`. Правильно: `cp -a /tmp/extract/opt/. /home/me/kvas/opt/`

### Структура Docker
```
builder (контейнер, Entware SDK)
├── /home/me/kvas/opt/          ← исходники пакета
├── /home/me/Entware/           ← Entware SDK
├── /tmp/build.sh               ← скрипт сборки
├── /tmp/kvas_213_real.ipk      ← рабочий ipk для извлечения
└── /tmp/kvas_output/           ← результат сборки (ipk)
```

### build.sh — что делает
1. Создаёт ipkg структуру /tmp/kvas-ipkg/
2. Копирует файлы из /home/me/kvas/opt/ в /tmp/kvas-ipkg/opt/
3. Создаёт CONTROL/control (зависимости, версия)
4. Создаёт CONTROL/postinst (симлинки, права, директории, версия)
5. Запускает ipkg-build → /tmp/kvas_output/kvas_*.ipk

### Postinst (после установки пакета)
```
1. Создаёт /opt/bin/kvas (симлинк)
2. mkdir /opt/etc/dnsmasq.d, adblock, ndm/watch.d, xray, var/log
3. chmod -R +x bin/*, etc/init.d/*, etc/ndm/*
4. Записывает версию в kvas.conf (APP_VERSION, APP_RELEASE)
```

## 5. Текущий статус

| Компонент | Статус | Примечание |
|-----------|--------|------------|
| VLESS | ✓ | Reality, TCP 443, type=xhttp/grpc/tcp/ws |
| Hysteria | ✓ | QUIC+Salamander, UDP 443 |
| Failover | ✓ | Автопереключение vless↔hysteria |
| kvas setup | ✓ | Hysteria/Skip опции, deferred hysteria |
| kvas init | ✓ | 100-vpn-mark с env vars (v213) |
| kvas add | ✓ | ipset__fill_by_domain + update_ipset (v210) |
| kvas del | ✓ | Множественное удаление, удаление из ipset (v210) |
| kvas backup/restore | ✓ | Сохранение/восстановление всех конфигов (v210) |
| kvas route | ✓ | Интерактивное меню + гостевые сети |
| kvas monitor web UI | ✓ | Статус системы, VPN, Failover, Родительский контроль, Консоль |
| Родительский контроль | ✓ | Блокировка через /opt/etc/hosts, страница "Заблокировано" |
| Clean install | ✓ | Тоннели поднимаются (100-vpn-mark) |
| kvas monitor CLI | ✓ | Фильтры, статусы, автоустановка socat |

## 6. Сетевая конфигурация

| Протокол | Интерфейс | Порт | Транспорт |
|----------|-----------|------|-----------|
| VLESS | Proxy21 (Kvas-proxy-vless) | socks5://127.0.0.1:1097 | TCP 443 Reality |
| Hysteria | Proxy41 (Kvas-proxy-hysteria) | socks5://127.0.0.1:10808 | UDP 443 QUIC+Salamander |

## 7. Структура файлов пакета

```
opt/apps/kvas/
├── bin/
│   ├── kvas                          # Точка входа (396 строк)
│   ├── install_hysteria.sh
│   ├── backup_configs.sh
│   ├── restore_configs.sh
│   ├── libs/
│   │   ├── main                      # Основная библиотека (1448 строк)
│   │   ├── vpn                       # VPN + cmd_kvas_init (3558 строк)
│   │   ├── vless                     # VLESS парсинг (675 строк)
│   │   ├── hysteria                  # Менеджер Hysteria 2 (421 строка)
│   │   ├── failover                  # Автопереключение (428 строк)
│   │   ├── check                     # Диагностика (628 строк)
│   │   ├── route                     # Маршрутизация (633 строки)
│   │   ├── ndm, ndm_d, adblock, debug, hosts, keen_api, tags, update
│   │   └── vpn
│   └── main/
│       ├── setup                     # Установка/uninstall (911 строк)
│       ├── upgrade                   # Обновление (406 строк)
│       ├── check_vpn, update, upgrade, adblock, adguard, dnsmasq, ipset, ipset_domain
├── etc/
│   ├── conf/
│   │   ├── kvas.conf                 # Конфиг (APP_VERSION, DNS, порты, интерфейсы)
│   │   ├── kvas.list                 # Белый список доменов
│   │   ├── kvas.vless                # Шаблон vless конфига
│   │   ├── kvas.help                 # Справка
│   │   ├── dnsmasq.conf              # Шаблон dnsmasq (@LOCAL_IP, @INFACE, @UPLEVEL_DNS)
│   │   ├── tags.list, adblock.sources, shadowsocks.json, reserved.ip
│   ├── init.d/
│   │   ├── S96kvas                   # Автозапуск KVAS
│   │   ├── S97xray                   # Автозапуск Xray
│   │   └── S99adguard                # Автозапуск AdGuard
│   └── ndm/                          # NDM hooks (netfilter, ifstatechanged, ...)
└── hysteria/
    ├── bin/.gitkeep                  # Сюда ставится бинарник hysteria
    └── etc/
        ├── conf/env.sh               # Переменные (PROXY_LOCAL_IP, порты, имена интерфейсов)
        ├── conf/config.yaml          # Шаблон конфига hysteria
        ├── init.d/S99hysteria        # Автозапуск hysteria
        └── ndm/test_connection.sh    # Тест подключения
```

## 8. Ключевые файлы (для исправления проблем)

### upgrade flow (`opt/bin/main/upgrade`)
```
kvas update
  ├── Скачивает ipk с GitHub releases
  ├── kvas uninstall yes          ← ВОТ ТУТ проблема (строка 356)
  │   ├── save_backups
  │   ├── Останавливает сервисы
  │   ├── Удаляет интерфейсы (если full)
  │   ├── Восстанавливает DNS (dnsmasq_install) ← ЛОМАЕТ dnsmasq
  │   ├── Удаляет файлы
  │   └── opkg remove kvas
  ├── opkg install kvas.ipk
  ├── dns-override = true         ← ВОТ ТУТ проблема (строка 388-390)
  └── kvas setup
```

### dnsmasq_install (`opt/bin/libs/vpn`, строка 1385+)
```
dnsmasq_install():
  1. Копирует K56dnsmasq → S56dnsmasq (если есть)
  2. Устанавливает dnsmasq-full (если нет S56dnsmasq)
  3. Останавливает dnsmasq
  4. Заменяет /opt/etc/dnsmasq.conf шаблоном из пакета
  5. Заменяет @LOCAL_IP, @INFACE, @UPLEVEL_DNS
  6. Запускает cmd_kvas_init (если не install stage)
```

### cmd_uninstall (`opt/bin/main/setup`, строка 812+)
```
cmd_uninstall(rm_type, sure):
  ├── full: rm -f K56dnsmasq, K09dnscrypt-proxy2
  ├── develop: all_services_rm_develop_mode
  └── default: save_backups
  
  ├── Останавливает сервисы (hysteria, xray, adguard, shadowsocks)
  ├── [full only] Удаляет интерфейсы Proxy21/Proxy41
  ├── [full only] Очищает iptables
  ├── Восстанавливает DNS (dnsmasq/dnscrypt)
  ├── [full only] Отключает dns-override
  ├── Удаляет файлы kvas
  ├── opkg remove kvas
  └── [full only] Удаляет пакеты (xray, shadowsocks, dnscrypt, nano)
```

## 9. Команды

```bash
kvas setup                       # Настройка после установки
kvas ver                         # Версия пакета
kvas test                        # Проверка всех служб
kvas help                        # Справка

kvas vless new                   # Настройка VLESS (q — пропустить)
kvas hysteria new                # Настройка Hysteria 2 (auto-install)
kvas hysteria status             # Статус Hysteria 2
kvas hysteria test               # Тест проксирования

kvas failover on|off|status      # Управление failover
kvas failover primary <proto>    # Основной протокол (vless|hysteria)
kvas failover test               # Тест обоих каналов
kvas failover log [N]            # Лог

kvas vpn set vless               # Переключение на VLESS
kvas vpn set hysteria            # Переключение на Hysteria

kvas route                       # Интерактивное меню управления тоннелем
kvas route add full|list|exclude <IP>   # Добавить IP/подсеть/диапазон
kvas route del full|list|exclude <IP>   # Удалить IP/подсеть/диапазон
kvas route refresh               # Применить изменения
  # В меню:
  #   a — весь трафик устройства в тоннель
  #   b — только домены из kvas.list
  #   c — исключить из перехвата DNS/трафика
  #   d — удалить из всех списков
  #   n — добавить гостевую сеть (br1, br2...)
  #   N — удалить гостевую сеть из route_by_list_net
  #   r — перечитать конфиг

kvas monitor                     # Интерактивное меню мониторинга трафика
kvas monitor web                 # Запуск веб-интерфейса (http://keenetic:8085)
kvas monitor web stop            # Остановка веб-интерфейса
  # В меню: m — мониторить, l — лог с фильтрами, w/W — веб
  # В прямом эфире: f — фильтры (протокол, порт, устройство), q — выход
  # Web UI: выбор устройств, сортировка, статусы, фильтры, поиск, скачивание лога

kvas upgrade                     # Обновление пакета из GitHub
kvas update                      # Обновление ipset-списков и маршрутов
kvas uninstall full yes          # Полное удаление

# Логирование (v245)
kvas log error                   # Ошибки (фильтр [E])
kvas log error detail            # Полные ошибки из лог-файла
kvas log error 20                # Последние 20 ошибок
kvas log error clear             # Очистить лог
kvas log info                    # Информационные сообщения
```

## 10. Установка

```bash
opkg install kvas_1.1.9_beta-10-169_all.ipk --force-reinstall
kvas setup
kvas vless new                    # или
kvas hysteria new
kvas failover on
```

## 11. Как обновлять на GitHub

### Структура каталогов
```
C:\Users\Pavel\kvas\
├── kvas-original\               ← клон форка (git репозиторий)
│   └── opt\                     ← исходники в формате git
├── v138_extract\                ← исходники для редактирования (НЕ git)
│   └── opt\apps\kvas\           ← файлы в формате роутера
├── build.sh                     ← скрипт сборки
├── PRD.md                       ← этот файл
└── kvas_1.1.9_beta-10-164_all.ipk  ← пакет
```

### Авторизация (если разлогинился)
```powershell
$env:PATH = [System.Environment]::GetEnvironmentVariable("PATH", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("PATH", "User")
echo "ВАШ_ТОКЕН" | gh auth login --hostname github.com --git-protocol https --with-token
gh auth status
```

### Процесс обновления (шаг за шагом)

**Шаг 1: Редактирование**
Файлы редактируются в `v138_extract\opt\apps\kvas\...`

**Шаг 2: Сборка ipk**
```powershell
docker cp C:\Users\Pavel\kvas\v138_extract\opt builder:/home/me/kvas/opt
docker cp C:\Users\Pavel\kvas\build.sh builder:/tmp/build.sh
docker exec -u root builder sh -c "cd /home/me/Entware && bash /tmp/build.sh 164"
docker cp builder:/tmp/kvas_output/kvas_1.1.9_beta-10-164_all.ipk C:\Users\Pavel\kvas\
```

**Шаг 3: Копирование в git**
```powershell
Copy-Item -Recurse -Force C:\Users\Pavel\kvas\v138_extract\opt\apps\kvas\bin\* C:\Users\Pavel\kvas\kvas-original\opt\bin\
Copy-Item -Recurse -Force C:\Users\Pavel\kvas\v138_extract\opt\apps\kvas\etc\* C:\Users\Pavel\kvas\kvas-original\opt\etc\
Copy-Item -Recurse -Force C:\Users\Pavel\kvas\v138_extract\opt\apps\kvas\hysteria C:\Users\Pavel\kvas\kvas-original\opt\hysteria
Copy-Item -Force C:\Users\Pavel\kvas\build.sh C:\Users\Pavel\kvas\kvas-original\build.sh
```

**Шаг 4: Коммит и пуш**
```powershell
cd C:\Users\Pavel\kvas\kvas-original
git config core.autocrlf false        # ОДИН раз
git add -A
git diff -w --stat                     # проверка
git commit -m "fix: описание"
git push fork main
```

**Шаг 5: Загрузка ipk на GitHub**
```powershell
gh release upload v1.1.9 "C:\Users\Pavel\kvas\kvas_1.1.9_beta-10-164_all.ipk" --repo Anonimus2026/kvas --clobber
```

**Шаг 6: Обновление описания релиза**
```powershell
gh release edit v1.1.9 --repo Anonimus2026/kvas --title "Kvas v164" --body "..."
```

### Ссылки
- Форк: https://github.com/Anonimus2026/kvas
- Оригинал: https://github.com/qzeleza/kvas
- PR: https://github.com/qzeleza/kvas/pull/318
- Release: https://github.com/Anonimus2026/kvas/releases/tag/v1.1.9
- Токен: создайте новый на https://github.com/settings/tokens (scopes: repo, read:org)

### Важно
- Файлы редактируются в `v138_extract/`, копируются в `kvas-original/` для git
- `core.autocrlf false` — git не ломает переводы строк
- PR обновляется автоматически при пуше в main
- ipk загружается отдельно через `gh release upload`

## 12. Авторы

- KVAS: mail@zeleza.ru
- Hysteria: jobgomel
- Failover: Anonimus2026

## 13. Changelog

### v250 (24.07.2026)
- **FIX:** Failover daemon автозапуск после перезагрузки
- **FIX:** Web UI автозапуск после перезагрузки
- **FIX:** Tunnels work after reboot
- **FIX:** S96kvas loads monitor + failover libs, waits 10s for interfaces

### v245 (23.07.2026)
- **FIX:** `log_error` пишет `[E]` в лог-файл (а не только в syslog)
- **FIX:** `kvas log error` теперь фильтрует только ошибки `[E]`
- **FIX:** Failover daemon автозапуск после перезагрузки (флаг `/opt/tmp/kvas-failover-enabled`)
- **FIX:** Web UI автозапуск после перезагрузки (флаг `/opt/tmp/kvas-monitor-web-enabled`)
- **FIX:** CPU fix — `cmd_monitor_web_stop` убивает все дочерние процессы socat
- **NEW:** Команды `kvas log error detail`, `kvas log error clear`
- **NEW:** Сообщение о web UI при установке

### v240 (22.07.2026)
- **FIX:** Monitoring data.sh reverted to v215 (working)
- **FIX:** check_updates rewritten with awk (busybox compatible)
- **WORKING:** Monitoring + Management web UI

### v228 (21.07.2026)
- **NEW:** System status display (VPN reserve, failover, daemon status)
- **NEW:** Service status (Xray/Hysteria init.d)
- **CANONICAL BASE:** Все новые фичи добавляются поверх v228

### v213 (18.07.2026)
- **FIX:** 100-vpn-mark env vars (type=iptables, table=mangle)
- **FIX:** Clean install — тоннели поднимаются

### v210 (17.07.2026)
- **NEW:** kvas add/del множественное удаление
- **NEW:** kvas backup/restore
- **NEW:** Monitor web UI

### v253 (24.07.2026)
- **FIX:** S96kvas ���������� ����� ������������ � ��������� build.sh (���� ����������� S96kvas)
- **FIX:** �������� monitor � ������ ���������� SETUP_FINISHED � kvas
