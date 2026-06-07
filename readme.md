# xray_server

Репозиторий ориентирован на два пути установки:

- `Remnawave` (через upstream `eGamesAPI/remnawave-reverse-proxy`)
- `Clean 3x-ui + Angie` (Angie как маска и reverse proxy панели)

## Что здесь получается

- базовая безопасная подготовка Ubuntu-сервера
- `Remnawave panel + node + subscription-page` на одном VPS
- отдельная `Remnawave`-нода, которую можно подключить ко внешней панели
- `3x-ui + Angie` на одном VPS
- один понятный `.env` c доменами и email

## Поддерживаемая схема

Основной сценарий:

- `panel.example.com` - панель
- `sub.example.com` - страница подписки
- `example.com` - selfsteal-домен ноды

Для отдельной ноды:

- отдельный VPS
- отдельный домен ноды
- IP сервера панели
- `Secret Key` ноды из карточки редактирования ноды в панели

## Файлы

- `bootstrap-server.sh` - базовая подготовка сервера
- `install-remnawave.sh` - единая точка входа с выбором сценария
- `install-remnawave-panel-node.sh` - установка панели и ноды на один сервер
- `install-remnawave-node.sh` - установка отдельной ноды к существующей панели
- `install-3xui-angie.sh` - установка `3x-ui + Angie`
- `.env.example` - пример переменных окружения
- `SECURITY.md` - базовые рекомендации по безопасности

Старые `configure.sh` и `install.sh` оставлены как совместимые обертки на новый единый установщик.

## Базовая подготовка сервера

На чистом Ubuntu:

```bash
sudo bash ./bootstrap-server.sh
```

Скрипт:

- обновляет систему
- создает sudo-пользователя
- ставит `git`, `curl`, `docker`, `docker compose`, `ufw`, `fail2ban`
- ставит CLI network tooling: `iperf3`, `vnstat`, `iftop`, `nload`, `bmon`, `conntrack`, `net-tools`
- отключает `root`-логин по SSH
- оставляет парольный SSH для нового пользователя
- умеет сразу добавить первый публичный SSH-ключ
- применяет transport tuning профиля основной Xray-ноды: `bbr`, `fq`, `tcp_mtu_probing=1`, `tcp_slow_start_after_idle=0`
- включает `vm.overcommit_memory=1`, что полезно для `valkey`
- включает `vnstat`

Transport tuning закрепляется в:

```text
/etc/modules-load.d/xray-network-tuning.conf
/etc/sysctl.d/99-xray-network-tuning.conf
```

## Единая точка входа

Если хотите, чтобы пользователь просто выбрал путь из меню:

```bash
sudo bash ./install-remnawave.sh
```

Меню предлагает:

- `Panel + node on one server`
- `Node only for an existing panel`
- `Clean 3x-ui + Angie`
- `Server bootstrap only`

## DNS

Для single-server сценария нужны три A-записи на IP одного VPS:

```text
panel.example.com -> <VPS_IP>
sub.example.com   -> <VPS_IP>
example.com       -> <VPS_IP>
```

Для отдельной ноды:

```text
node2.example.com -> <SECOND_VPS_IP>
```

Для `3x-ui + Angie`:

```text
panel.example.com -> <VPS_IP>   # вход в 3x-ui через Angie
site.example.com  -> <VPS_IP>   # маска
```

## Настройка .env

Минимальный пример:

```dotenv
REMNAWAVE_PANEL_DOMAIN=panel.example.com
REMNAWAVE_SUB_DOMAIN=sub.example.com
REMNAWAVE_NODE_DOMAIN=example.com
LETSENCRYPT_EMAIL=admin@example.com
```

Для отдельной ноды дополнительно:

```dotenv
REMNAWAVE_PANEL_IP=203.0.113.10
REMNAWAVE_NODE_SECRET_KEY_FILE=/root/remnawave-node-secret.pem
```

Если не хотите хранить `Secret Key` в файле, можно использовать `REMNAWAVE_NODE_SECRET_KEY`, но для многострочного секрета файл обычно надежнее.

Опционально для single-server Remnawave:

```dotenv
# Установить шаблон страницы подписки legiz Orion после основной установки.
# Включено в .env.example, потому что это штатная схема этого репозитория.
REMNAWAVE_INSTALL_LEGIZ_ORION=1

# Включайте только если конкретный VPS уперся в Docker Hub rate limit.
REMNAWAVE_USE_IMAGE_MIRRORS=1
```

Для `3x-ui + Angie` дополнительно:

```dotenv
XUI_PANEL_DOMAIN=panel.example.com
XUI_MASK_DOMAIN=site.example.com
XUI_PANEL_PORT=2053
```

## Установка панели и ноды на одном сервере

```bash
cp .env.example .env
sudo bash ./install-remnawave.sh
```

Что делает обертка:

- проверяет DNS для panel/sub/node доменов
- клонирует `eGamesAPI/remnawave-reverse-proxy`
- на `Ubuntu 25.04` добавляет локальный патч совместимости к upstream-проверке ОС
- при `REMNAWAVE_USE_IMAGE_MIRRORS=1` патчит часть Docker-образов на GHCR/Public ECR до первого pull
- запускает upstream installer в неинтерактивном режиме
- получает сертификаты `Let's Encrypt`
- поднимает `Remnawave`, `node` и `subscription-page`
- при `REMNAWAVE_INSTALL_LEGIZ_ORION=1` ставит Orion-шаблон страницы подписки от legiz
- проверяет доступность frontend панели, логин администратора и состояние контейнеров

## Установка отдельной ноды ко внешней панели

Сначала в панели создайте ноду и откройте ее карточку редактирования. Оттуда понадобятся:

- selfsteal-домен этой ноды
- `Secret Key`

На втором сервере:

```bash
cp .env.example .env
sudo bash ./install-remnawave.sh
```

Скрипт:

- проверяет DNS домена ноды
- клонирует upstream-репозиторий
- запрашивает сертификат для домена ноды
- поднимает `remnanode` и локальный `nginx`
- открывает `2222/tcp` только для IP сервера панели

## После установки панели

Проверьте в интерфейсе:

- `Nodes` - нода должна быть online
- `Hosts` - должен быть создан host для selfsteal-домена
- `Users` - пользователю нужно выдать доступ, иначе подписка будет пустой
- `sub.example.com/` без short UUID может отдавать пустой ответ; реальная страница подписки открывается по ссылке пользователя вида `https://sub.example.com/<shortUuid>`

## Установка 3x-ui + Angie

```bash
cp .env.example .env
sudo bash ./install-remnawave.sh
```

Далее в меню выберите `Clean 3x-ui + Angie`.

Скрипт:

- ставит `3x-ui` (официальный install script)
- получает сертификаты `Let's Encrypt` для panel+mask доменов
- поднимает Angie в Docker на `:80/:443`
- проксирует `https://panel-domain` в локальный `3x-ui` порт
- отдает маску на `https://mask-domain`

## Важные оговорки

- upstream-режим `panel + node on one server` помечен авторами как не рекомендованный для production
- на практике схема работает, но ее лучше считать управляемым компромиссом, а не эталоном
- для нового прод-разворачивания предпочтительнее `Ubuntu 24.04`, даже если `25.04` удается завести локальным патчем
