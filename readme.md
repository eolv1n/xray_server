# xray_server

Репозиторий готовит сервер по той же схеме, что и `Akiyamov/xray-vps-setup/install_in_docker.md`, но в виде локального управляемого проекта с автоматизацией установки.

## Что В Итоге Получается

- `VLESS + REALITY + Vision` на `443`
- `Marzban` как панель управления
- `Angie` как локальный TLS-фасад на `127.0.0.1:4123`
- один домен для клиента, панели и маскировочной страницы
- скрытый путь для панели `Marzban`
- скрытый путь для страницы подписок
- установка и перегенерация через локальные скрипты

## Целевая Схема

Рабочая схема такая:

- клиент подключается к `DOMAIN:443`
- `Xray` принимает `REALITY`
- обычный TLS-трафик уходит на `127.0.0.1:4123`
- на `127.0.0.1:4123` работает `Angie`
- `Angie` отдает маскировочную страницу и проксирует панель `Marzban`

Это значит:

- `REALITY dest` должен быть `127.0.0.1:4123`
- отдельные `edge.` и `app.` поддомены не нужны
- панель не должна жить на отдельном порту

## Что Уже Автоматизировано

- `configure.sh` подготавливает `.env`
- `install.sh` сам вызывает `configure.sh`, если конфиг еще не создан
- устанавливаются `docker.io` и `docker compose v2`
- генерируются `UUID`, `x25519` ключи и `shortId`
- генерируются логин и пароль администратора `Marzban`
- генерируются скрытые пути для панели и подписок
- загружается `Xray-core`
- рендерятся конфиги `Angie`, `Marzban` и `Xray`
- стек запускается через `docker compose`
- хост `Marzban` настраивается через API после старта
- при необходимости доступ к панели можно ограничить через `PANEL_ALLOWLIST`

## Что Нужно Заранее

- VPS на Ubuntu 22.04+ или другом совместимом Debian-based дистрибутиве
- открытые `80/tcp` и `443/tcp`
- один домен, уже указывающий на VPS

Пример:

```dotenv
DOMAIN=vpn.example.net
```

## DNS

Для этой схемы нужна только одна `A`-запись:

```text
vpn.example.net -> <IP_вашего_VPS>
```

Если раньше были записи вроде:

- `example.net -> <IP>`
- `edge.example.net -> <IP>`
- `app.example.net -> <IP>`

то для текущего репозитория лишние поддомены можно удалить, если они больше нигде не используются.

Проверьте также:

- чтобы не осталось `AAAA`-записей на чужой IPv6
- чтобы домен действительно резолвился на IP текущего VPS

## Быстрый Старт

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

## Что Спрашивает configure.sh

Скрипт спрашивает:

- домен `DOMAIN`
- каталог установки
- образ `Marzban`
- необязательные overrides для `UUID`, ключей, `shortId`, логина и пароля панели

Если секретные поля оставить пустыми, `install.sh` сгенерирует их сам.

## Как Проходит Установка

1. Клонируете репозиторий на сервер.
2. Запускаете `bash ./configure.sh`.
3. Проверяете, что `DOMAIN` уже смотрит на VPS.
4. Запускаете `sudo bash ./install.sh`.
5. Получаете:
- URL панели `Marzban`
- логин и пароль администратора
- `UUID`, `PBK`, `shortId`
- готовую основу для клиентского подключения через `Marzban`

## Структура Репозитория

- `configure.sh` - интерактивный генератор `.env`
- `install.sh` - основной установщик
- `docker-compose.yml` - контейнеры `Angie` и `Marzban`
- `templates/angie.conf.tpl` - шаблон локального TLS-фасада
- `templates/xray.json.tpl` - шаблон `REALITY` конфига для `Marzban`
- `templates/marzban.env.tpl` - переменные окружения панели
- `templates/mask.html.tpl` - маскировочная страница
- `templates/subscription-index.html.tpl` - локальный шаблон страницы подписки
- `install-subscription-assets.sh` - установка и обновление шаблонов подписки
- `.env.example` - пример переменных окружения

## Переменные .env

Минимально достаточно:

```dotenv
DOMAIN=vpn.example.net
```

Дополнительно можно задать:

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

## Где Лежат Результаты После Установки

- `/opt/xray-vps-setup/docker-compose.yml`
- `/opt/xray-vps-setup/.env`
- `/opt/xray-vps-setup/angie.conf`
- `/opt/xray-vps-setup/marzban/.env`
- `/opt/xray-vps-setup/marzban/xray_config.json`
- `/opt/xray-vps-setup/xray-core`
- `/opt/xray-vps-setup/mask/index.html`

## Как Зайти В Панель

После установки используйте адрес:

```text
https://DOMAIN/MARZBAN_DASHBOARD_PATH/
```

Логин и пароль администратора печатаются в конце `install.sh`.

На корне домена открывается маскировочная страница, а сама панель доступна только по скрытому пути.

## Повторный Запуск

Если вы меняли `.env`, достаточно снова выполнить:

```bash
sudo bash ./install.sh
```

Скрипт пересоберет конфиги и перезапустит стек.

## Шаблоны Страницы Подписки

Если нужно обновить только страницу подписки и клиентские шаблоны без полной переустановки:

```bash
bash ./install-subscription-assets.sh
```

Скрипт:

- ставит локальный шаблон страницы подписки по умолчанию
- умеет скачивать альтернативные шаблоны по HTTPS
- обновляет только нужные ключи в `Marzban` env
- не требует запускать внешний shell-скрипт напрямую

## Важные Замечания

- отдельные `edge.` и `app.` поддомены для этой схемы не нужны
- сертификаты выпускает `Angie` через ACME после того, как `DOMAIN` начинает указывать на VPS
- `Xray` на `443` передает обычный TLS-трафик на локальный `Angie` по `127.0.0.1:4123`
- рекомендации по безопасности, `ufw` и SSH вынесены в `SECURITY.md`
