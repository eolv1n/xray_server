# xray_server

Репозиторий собирает схему из спека в готовую one-click установку для Ubuntu VPS:

- `VLESS + XHTTP` через Cloudflare и домен
- `VLESS + REALITY + Vision` напрямую на тот же сервер
- внешний `nginx` на хосте принимает `:443` и роутит трафик:
  - запросы с IP Cloudflare идут в TLS/xHTTP ветку
  - весь остальной TCP идёт в REALITY
- `xray` и маскировочный сайт (`filebrowser`) работают в Docker

## Что делает `install.sh`

Скрипт:

- ставит `docker` и `nginx-full`, если их ещё нет
- генерирует `UUID`, `x25519` ключи REALITY, `shortId` и секретный `xhttp path`
- скачивает актуальные Cloudflare IP ranges
- рендерит конфиги `xray` и `nginx`
- создаёт self-signed origin certificate для домена
- поднимает контейнеры через `docker compose`

## Требования

- Ubuntu 22.04+ или совместимый Debian-based сервер
- домен уже направлен на VPS
- для XHTTP домен должен быть проксирован через Cloudflare
- в Cloudflare для домена нужно включить gRPC

## Быстрый старт

```bash
git clone <your-repo-url> xray_server
cd xray_server
cp .env.example .env
```

Откройте `.env` и как минимум задайте:

```dotenv
DOMAIN=your-domain.example
```

Дальше запуск:

```bash
sudo bash ./install.sh
```

После завершения скрипт выведет готовые параметры для клиента:

- `UUID`
- `XHTTP path`
- `REALITY public key`
- `REALITY shortId`
- IP/endpoint для прямого REALITY-подключения

## Файлы

- `install.sh` - основной one-click установщик
- `docker-compose.yml` - контейнеры `xray` и `filebrowser`
- `templates/config.jsonc.tpl` - шаблон конфига `xray`
- `templates/nginx-http.conf.tpl` - HTTP/TLS ветка для XHTTP и маскировки
- `templates/nginx-stream.conf.tpl` - stream-маршрутизация по source IP
- `.env.example` - переменные окружения и необязательные overrides

## Переменные `.env`

Обязательная:

```dotenv
DOMAIN=your-domain.example
```

Необязательные:

```dotenv
XRAY_UUID=
XRAY_XHTTP_PATH=
XRAY_REALITY_PRIVATE_KEY=
XRAY_REALITY_PUBLIC_KEY=
XRAY_REALITY_SHORT_ID=
XRAY_REALITY_SERVER_NAME=www.microsoft.com
XRAY_REALITY_DEST=www.microsoft.com:443
APP_DIR=/opt/xray_server
NGINX_HTTP_PORT=8443
XRAY_XHTTP_PORT=12777
XRAY_REALITY_PORT=12888
CLOAK_PORT=18080
```

Если значения секретов пустые, `install.sh` сгенерирует их сам.

## Как это работает

`nginx` на хосте слушает `443/tcp` в `stream`-режиме.

- Если источник трафика принадлежит Cloudflare, соединение уходит на локальный TLS listener `127.0.0.1:8443`
- Там `nginx` обслуживает:
  - `/SECRET_PATH` -> `grpc_pass` в `xray`
  - `/` -> маскировочный `filebrowser`
- Если IP не из Cloudflare, поток сразу передаётся в `xray REALITY`

Так можно держать XHTTP over CDN и direct REALITY на одном порту `443`.

## Где лежат результаты установки

После запуска скрипта рабочие файлы находятся здесь:

- `/opt/xray_server/docker-compose.yml`
- `/opt/xray_server/.env`
- `/opt/xray_server/config/config.jsonc`
- `/opt/xray_server/config/cloudflare-ips.conf`
- `/opt/xray_server/certs/origin.crt`
- `/opt/xray_server/certs/origin.key`
- `/etc/nginx/conf.d/xray-http.conf`
- `/etc/nginx/stream-conf.d/xray-stream.conf`

## Повторный запуск

Если вы поменяли `.env`, просто снова выполните:

```bash
sudo bash ./install.sh
```

Скрипт перерендерит конфиги, обновит Cloudflare IP ranges и перезапустит `nginx` и контейнеры.

## Важные замечания

- Для REALITY обычно используется IP сервера или отдельная DNS-запись без Cloudflare proxy.
- Self-signed origin certificate подходит для режима Cloudflare `Full`, но если у вас `Full (strict)`, замените сертификат на Cloudflare Origin Certificate или другой доверенный origin cert.
- Если на сервере уже есть свой сложный `nginx`-конфиг, скрипт добавит в `/etc/nginx/nginx.conf` отдельный `stream` блок с include для `/etc/nginx/stream-conf.d/*.conf`.
