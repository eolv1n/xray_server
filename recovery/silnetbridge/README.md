# Silnet Bridge: recovery contract

Этот каталог задаёт восстановление **на новом VPS** из Git и отдельного
защищённого backup невоспроизводимого state. Скрипты этого каталога не
запускались на live-хосте. Проверенный live target на `2026-09-15` —
`185.232.84.65`, SSH `eol@...:22`, Ubuntu `25.04`, hostname `Edge-01`.
Для нового VPS предпочтителен поддерживаемый Ubuntu `24.04`; это смена host
profile, а не попытка воспроизвести старую ОС побайтно.

## Exact desired state

`lock.json` фиксирует upstream commit и digest шести образов, полученные из
live `docker image inspect`. Текущий live Compose находится в `/opt/remnawave`.
Его сервисы: `remnanode`, `remnawave`, `remnawave-db`, `remnawave-redis`,
`remnawave-nginx`, `remnawave-subscription-page`. Backend, PostgreSQL и Valkey
имеют Docker healthcheck; все шесть контейнеров работают с `restart: always`.
PostgreSQL использует volume `remnawave-db-data`, Valkey — `valkey-socket`.
Backend опубликован только на `127.0.0.1:3000,3001`, PostgreSQL —
`127.0.0.1:6767`, subscription page — `127.0.0.1:3010`.

TLS-домены: `panel.silnetbridge.com`, `sub.silnetbridge.com`,
`silnetbridge.com`. Nginx использует сертификаты из `/etc/letsencrypt/live`.
Reality/VLESS node служит домашнему Keenetic/Xray proxy-path. Текущий
PostgreSQL содержит таблицу `users` с `3` строками; это только контрольная
точка аудита, а restore сравнивает число с **свежим** backup. Retired
`node2.silnetbridge.com` на `89.124.100.230` в desired state не входит.
Независимый alert relay расположен в
`/home/eol/.local/bin/baloonz-telegram-relay`; forced-command SSH grants
содержатся в `/home/eol/.ssh/authorized_keys`.

Live subscription page не имеет `index.html` mount, поэтому Orion **отключён**
в этом recovery source. `yq` не требуется. Повторный запуск общего
`install-remnawave-panel-node.sh` с его текущим default `Orion=1` не
соответствует этому contract. Для rebuild upstream скачивают только по
commit из `lock.json`; branch `main`, Docker tag `latest` и внешние assets
без lock не допускаются. Проверить upstream перед использованием:

```bash
git clone https://github.com/eGamesAPI/remnawave-reverse-proxy.git /usr/local/src/remnawave-reverse-proxy
git -C /usr/local/src/remnawave-reverse-proxy checkout --detach cb70c45ca4fac7791bc2801f46e686023e86a4c4
test "$(git -C /usr/local/src/remnawave-reverse-proxy rev-parse HEAD)" = cb70c45ca4fac7791bc2801f46e686023e86a4c4
```

## Secret delivery и backup

Git содержит только lock, процедуры и проверки. `.env`, `nginx.conf`,
сертификаты и private keys, relay config, panel/node secrets, Telegram token,
JWT secrets, PostgreSQL data и пользовательские профили передаются отдельным
защищённым backup. `backup.sh /private/backup-dir` создаёт PostgreSQL custom
dump, globals, число users и tar с `/opt/remnawave` config,
`/etc/letsencrypt`, relay/SSH state. Каталог создаётся с `0700`, файлы с
`0600`; его нельзя помещать в checkout, синхронизируемые логи или обычное
artifact storage. Перед передачей в новый VPS backup должен быть зашифрован
в защищённом storage и сверён по `SHA256SUMS` после расшифровки. Секреты
проверяются оператором в private destination без вывода значений в отчёт.

На source VPS backup выполняют только в отдельное согласованное окно.
Текущий Git contract **не содержит** действительный backup; перед миграцией
его нужно создать и испытать на disposable replacement VPS. Целевой
`backup.sh` включает всю базу, поэтому users, nodes, hosts, Reality keys и
subscription UUID не создаются заново. `postgres-globals.sql` сохраняется
для анализа ролей; автоматический restore использует существующего
`POSTGRES_USER` и `--no-owner`, не применяя globals вслепую.

## Restore и acceptance

До cutover старый VPS и DNS остаются неизменными. На новом VPS сначала
установить Docker/Compose и Python 3, доставить Git checkout и защищённый
backup, затем выполнить:

```bash
SILNET_NEW_VPS_RECOVERY=new-vps-only sudo -E ./recovery/silnetbridge/restore.sh /private/backup-dir
```

`restore.sh` отказывается перезаписывать существующий `/opt/remnawave`,
проверяет hashes, разворачивает protected state, заменяет все шесть image
tags на digests из lock, проверяет Compose, поднимает PostgreSQL/Valkey,
восстанавливает dump и запускает остальные сервисы. `smoke.sh` проверяет
running/health всех сервисов, число users, backend health и панель через
локальный `--resolve`, то есть без DNS cutover.

Это минимальный machine-readable gate. Перед переключением DNS дополнительно
нужно проверить TLS, `443/tcp` Reality fallback и **реальный VLESS path** с
существующим клиентским профилем из protected state, subscription link
существующего пользователя, Keenetic direct/proxy comparison и доставку alert
через relay с доверенного sender. Проверять надо с внешней точки, потому что
local container health не доказывает доступность proxy-path. Secret URL/UUID
в отчёт не записывать. Relay forced-command grants следует сверить с
конкретными public keys sender; если IP/SSH policy нового VPS отличается,
обновить их до cutover, не ослабляя forced command.

`acceptance.json` задаёт обязательные machine-readable gates. Оператор
фиксирует для каждого gate только `true`/`false` в private `evidence.json`
**вне Git checkout** и выполняет
`python3 check-acceptance.py /private/evidence.json`. `local_restore=true`
ставится только после exit `0` от `smoke.sh`; внешние gates — только по
фактическим проверкам, а `rollback_ready` — после сохранения old DNS/route
target и доступа к старому VPS. Скрипт принимает cutover лишь когда все семь
значений равны `true`, не сохраняя секреты или клиентские URL.

## Rollback boundary

До подтверждения внешнего datapath и relay не менять DNS, Keenetic route и
старый VPS. При ошибке restore остановить/удалить только replacement VPS,
оставить old endpoint и DNS. После cutover хранить старый VPS, protected
backup и прежние DNS records до окна наблюдения; rollback — возврат DNS и
router target на old IP, затем повторный end-to-end smoke. Любые изменения
live `185.232.84.65` требуют отдельного maintenance согласования.
