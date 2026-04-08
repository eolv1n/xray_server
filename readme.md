# silentbridge-xray

Репозиторий переводит стек на один основной сценарий:

- `VLESS + REALITY + Vision` на `443`
- `Marzban` как панель управления
- `Angie` как локальный HTTPS-фасад для сертификатов, маскировочной страницы и панели
- без `XHTTP`
- без Cloudflare-зависимости
- без stream-развилки по source IP

Архитектура опирается на подход `Akiyamov/xray-vps-setup`, но адаптирована под отдельные домены для edge и панели.

## Что уже автоматизировано

- `configure.sh` подготавливает `.env`
- `install.sh` сам вызывает `configure.sh`, если конфиг еще не создан
- установка `docker.io` и `docker compose v2`
- генерация `UUID`, `x25519` ключей, `shortId`
- генерация логина и пароля администратора `Marzban`
- генерация скрытого dashboard path и subscription path
- загрузка `Xray-core`
- рендер `Angie`, `Marzban` и `Xray` конфигов
- запуск стека через `docker compose`

## Что нужно заранее

- Ubuntu 22.04+ или совместимый Debian-based VPS
- открытые `80/tcp` и `443/tcp`
- два домена, которые уже указывают на VPS:
  - `EDGE_DOMAIN`, например `edge.silentbridge.com`
  - `PANEL_DOMAIN`, например `app.silentbridge.com`

## Быстрый старт

```bash
git clone <your-repo-url> silentbridge-xray
cd silentbridge-xray
bash ./configure.sh
sudo bash ./install.sh
```

Или одним шагом:

```bash
sudo bash ./install.sh
```

## Что спрашивает configure.sh

`configure.sh` спрашивает:

- домен для REALITY, например `edge.silentbridge.com`
- домен панели, например `app.silentbridge.com`
- каталог установки
- образ `Marzban`
- необязательные overrides для `UUID`, ключей, `shortId`, логина и пароля панели

Если секретные поля пустые, `install.sh` сгенерирует их автоматически.

## Как выглядит поток установки

1. Клонируете репозиторий на сервер.
2. Запускаете `bash ./configure.sh`.
3. Проверяете DNS для `EDGE_DOMAIN` и `PANEL_DOMAIN`.
4. Запускаете `sudo bash ./install.sh`.
5. Получаете:
   - URL панели `Marzban`
   - логин и пароль администратора
   - `UUID`, `PBK`, `shortId`
   - готовую `vless://` ссылку для клиента

## Файлы

- `configure.sh` - интерактивный генератор `.env`
- `install.sh` - основной установщик
- `docker-compose.yml` - контейнеры `Angie` и `Marzban`
- `templates/angie.conf.tpl` - HTTPS-фасад и ACME
- `templates/xray.json.tpl` - `REALITY` конфиг для `Marzban`
- `templates/marzban.env.tpl` - переменные панели
- `templates/mask.html.tpl` - маскировочная страница
- `.env.example` - пример переменных окружения

## Переменные .env

Обязательные:

```dotenv
EDGE_DOMAIN=edge.example.com
PANEL_DOMAIN=app.example.com
```

Опциональные:

```dotenv
APP_DIR=/opt/silentbridge
XRAY_UUID=
XRAY_PRIVATE_KEY=
XRAY_PUBLIC_KEY=
XRAY_SHORT_ID=
MARZBAN_USER=
MARZBAN_PASS=
MARZBAN_DASHBOARD_PATH=
MARZBAN_SUBSCRIPTION_PATH=
XRAY_CORE_VERSION=26.2.6
XRAY_IMAGE_TAG=26.3.27
MARZBAN_IMAGE=gozargah/marzban:latest
```

## Где лежат результаты

После установки рабочие файлы находятся здесь:

- `/opt/silentbridge/docker-compose.yml`
- `/opt/silentbridge/.env`
- `/opt/silentbridge/angie.conf`
- `/opt/silentbridge/marzban/.env`
- `/opt/silentbridge/marzban/xray_config.json`
- `/opt/silentbridge/xray-core`
- `/opt/silentbridge/mask/index.html`

## Доступ к панели

После установки используйте URL:

```text
https://PANEL_DOMAIN/MARZBAN_DASHBOARD_PATH/
```

Логин и пароль печатаются в конце `install.sh`.

## Повторный запуск

Если вы изменили `.env`, повторите:

```bash
sudo bash ./install.sh
```

Установщик пересоберет конфиги и перезапустит стек.

## Важные замечания

- для новой схемы Cloudflare не требуется
- `PANEL_DOMAIN` и `EDGE_DOMAIN` можно держать на одном IP
- сертификаты выпускаются контейнером `Angie` через ACME после того, как оба домена резолвятся на VPS
