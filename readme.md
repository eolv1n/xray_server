# xray_server

Репозиторий готовит сервер по схеме `Akiyamov/xray-vps-setup/install_in_docker.md`, но с локальными скриптами для установки и обновления.

## Что здесь получается

- `VLESS + REALITY + Vision` на `443`
- `Marzban` как панель
- `Angie` как локальный TLS-фасад на `127.0.0.1:4123`
- один домен для клиента, панели и маскировочной страницы
- скрытый путь для панели
- скрытый путь для подписок

## Схема

- клиент подключается к `DOMAIN:443`
- `Xray` принимает `REALITY`
- обычный TLS-трафик передается на `127.0.0.1:4123`
- на `127.0.0.1:4123` работает `Angie`
- `Angie` отдает маскировочную страницу и проксирует `Marzban`

То есть:

- `REALITY dest` должен быть `127.0.0.1:4123`
- панель не должна жить на отдельном порту

## Что автоматизировано

- `configure.sh` создает `.env`
- `install.sh` сам вызывает `configure.sh`, если конфига еще нет
- ставятся `docker.io` и `docker compose v2`
- генерируются `UUID`, `x25519` ключи и `shortId`
- генерируются логин и пароль администратора `Marzban`
- генерируются скрытые пути панели и подписок
- загружается `Xray-core`
- рендерятся конфиги `Angie`, `Marzban` и `Xray`
- стек запускается через `docker compose`
- хост `Marzban` настраивается через API после старта

## Что нужно заранее

- VPS на Ubuntu 22.04+ или совместимом Debian-based дистрибутиве
- открытые `80/tcp` и `443/tcp`
- один домен, который уже указывает на VPS

Если сервер совсем чистый, можно сначала прогнать bootstrap-скрипт:

```bash
sudo bash ./bootstrap-server.sh
```

Он:

- обновляет систему
- создает sudo-пользователя
- ставит `git`, `curl`, `docker`, `docker compose`, `ufw`, `fail2ban`
- отключает root login по SSH
- оставляет парольный SSH только для нового пользователя
- открывает в `ufw` только `22`, `80`, `443`

Это именно базовая подготовка сервера перед клоном и установкой репозитория.
SSH-ключ лучше добавить сразу после этого и только потом отключать `PasswordAuthentication`.

Пример:

```dotenv
DOMAIN=vpn.example.net
```

## DNS

Нужна одна `A`-запись:

```text
vpn.example.net -> <IP_вашего_VPS>
```

Также проверьте:

- чтобы не осталось `AAAA`-записей на чужой IPv6
- чтобы домен резолвился на IP текущего VPS

## Быстрый старт

Если VPS уже подготовлен:

```bash
git clone <your-repo-url> xray_server
cd xray_server
bash ./configure.sh
sudo bash ./install.sh
```

Или сразу:

```bash
sudo bash ./install.sh
```

Если VPS чистый и вы хотите повторить базовую настройку с нуля:

```bash
apt update && apt install -y git curl
git clone <your-repo-url> xray_server
cd xray_server
sudo bash ./bootstrap-server.sh
```

## Что спрашивает configure.sh

- домен `DOMAIN`
- каталог установки
- образ `Marzban`
- необязательные overrides для `UUID`, ключей, `shortId`, логина и пароля панели

Если секретные поля оставить пустыми, `install.sh` сгенерирует их сам.

## Как проходит установка

1. Клонируете репозиторий на сервер.
2. Запускаете `bash ./configure.sh`.
3. Проверяете, что `DOMAIN` уже смотрит на VPS.
4. Запускаете `sudo bash ./install.sh`.
5. Получаете URL панели, логин, пароль, `UUID`, `PBK`, `shortId`.

## Файлы

- `configure.sh` - интерактивный генератор `.env`
- `install.sh` - основной установщик
- `docker-compose.yml` - контейнеры `Angie` и `Marzban`
- `templates/angie.conf.tpl` - шаблон локального TLS-фасада
- `templates/xray.json.tpl` - шаблон `REALITY` конфига для `Marzban`
- `templates/marzban.env.tpl` - переменные окружения панели
- `templates/mask.html.tpl` - маскировочная страница
- `templates/subscription-index.html.tpl` - шаблон страницы подписки
- `install-subscription-assets.sh` - установка и обновление шаблонов подписки
- `.env.example` - пример переменных окружения

## Переменные .env

Минимально:

```dotenv
DOMAIN=vpn.example.net
```

Опционально:

```dotenv
APP_DIR=/opt/xray-vps-setup
XRAY_UUID=
XRAY_PRIVATE_KEY=
XRAY_PUBLIC_KEY=
XRAY_SHORT_ID=
MARZBAN_USER=
MARZBAN_PASS=
MARZBAN_DASHBOARD_PATH=
MARZBAN_SUBSCRIPTION_PATH=
PANEL_ALLOWLIST=
XRAY_CORE_VERSION=26.2.6
XRAY_IMAGE_TAG=26.3.27
MARZBAN_IMAGE=gozargah/marzban:latest
```

## Где лежат файлы после установки

- `/opt/xray-vps-setup/docker-compose.yml`
- `/opt/xray-vps-setup/.env`
- `/opt/xray-vps-setup/angie.conf`
- `/opt/xray-vps-setup/marzban/.env`
- `/opt/xray-vps-setup/marzban/xray_config.json`
- `/opt/xray-vps-setup/xray-core`
- `/opt/xray-vps-setup/mask/index.html`

## Доступ к панели

После установки:

```text
https://DOMAIN/MARZBAN_DASHBOARD_PATH/
```

Логин и пароль печатаются в конце `install.sh`.

На корне домена открывается маскировочная страница, панель доступна по скрытому пути.

## Повторный запуск

Если меняли `.env`:

```bash
sudo bash ./install.sh
```

## Обновление шаблонов подписки

```bash
bash ./install-subscription-assets.sh
```

Скрипт ставит локальный шаблон по умолчанию, умеет скачивать альтернативные шаблоны по HTTPS и обновляет только нужные ключи в `Marzban`.

## Примечания

- сертификаты выпускает `Angie` через ACME после того, как `DOMAIN` начинает указывать на VPS
- `Xray` на `443` передает обычный TLS-трафик на локальный `Angie` по `127.0.0.1:4123`
- рекомендации по безопасности вынесены в `SECURITY.md`
