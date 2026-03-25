# xray_server

Репозиторий поднимает Xray на Ubuntu VPS с максимально простым сценарием запуска:

- `VLESS + XHTTP` через Cloudflare и домен
- `VLESS + REALITY + Vision` напрямую на тот же сервер
- хостовый `nginx` принимает `:443` и отправляет трафик:
  - запросы с IP Cloudflare в ветку `XHTTP`
  - остальной TCP-трафик в `REALITY`
- `xray` и маскировочный сайт (`filebrowser`) работают в Docker

## Что уже автоматизировано

- интерактивный `configure.sh` пошагово создает `.env`
- `install.sh` сам вызывает `configure.sh`, если конфиг еще не подготовлен
- скрипт ставит `docker` и `nginx-full`, если их нет
- генерирует `UUID`, `x25519` ключи REALITY, `shortId` и `xhttp path`, если вы не задали их вручную
- скачивает актуальные Cloudflare IP ranges
- рендерит конфиги `xray` и `nginx`
- создает self-signed origin certificate для домена
- поднимает контейнеры через `docker compose`

## Что нужно заранее

- Ubuntu 22.04+ или совместимый Debian-based VPS
- домен, который уже указывает на IP сервера
- запись домена для XHTTP должна быть включена через Cloudflare Proxy
- в Cloudflare для домена нужно включить `gRPC`
- входящий `443/tcp` должен быть открыт на сервере

## Быстрый старт

```bash
git clone <your-repo-url> xray_server
cd xray_server
bash ./configure.sh
sudo bash ./install.sh
```

Если хотите вообще без отдельного шага, можно сразу выполнить:

```bash
sudo bash ./install.sh
```

Если `DOMAIN` еще не задан, установщик сам откроет интерактивный wizard и создаст `.env`.

## Что спрашивает configure.sh

`configure.sh` пошагово спрашивает:

- домен для XHTTP через Cloudflare, например `vpn.example.com`
- `SNI` для REALITY, по умолчанию `www.microsoft.com`
- `DEST` для REALITY, по умолчанию `www.microsoft.com:443`
- каталог установки на сервере
- локальные порты `nginx`, `xray XHTTP`, `xray REALITY` и маскировочного сайта
- необязательные overrides для `UUID`, `XHTTP path`, `REALITY private/public key`, `shortId`

Если секретные поля оставить пустыми, `install.sh` сгенерирует их сам.

## Как выглядит поток установки

1. Клонируете репозиторий на сервер.
2. Запускаете `bash ./configure.sh` и отвечаете на вопросы wizard.
3. Проверяете DNS:
   - домен указывает на IP VPS
   - запись домена проксируется через Cloudflare
   - в Cloudflare включен `gRPC`
4. Запускаете `sudo bash ./install.sh`.
5. В конце получаете готовые клиентские параметры:
   - `UUID`
   - `XHTTP path`
   - `REALITY public key`
   - `REALITY shortId`
   - endpoint для прямого REALITY-подключения

## Файлы

- `configure.sh` - интерактивный CLI для создания `.env`
- `install.sh` - основной one-click установщик
- `docker-compose.yml` - контейнеры `xray` и `filebrowser`
- `templates/config.jsonc.tpl` - шаблон конфига `xray`
- `templates/nginx-http.conf.tpl` - HTTP/TLS ветка для XHTTP и маскировки
- `templates/nginx-stream.conf.tpl` - stream-маршрутизация по source IP
- `.env.example` - пример переменных окружения

## Переменные .env

Обязательная:

```dotenv
DOMAIN=vpn.example.com
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

## Где лежат результаты

После установки рабочие файлы находятся здесь:

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

Скрипт заново соберет конфиги, обновит Cloudflare IP ranges и перезапустит `nginx` и контейнеры.

## Важные замечания

- Для REALITY обычно используют IP сервера или отдельную DNS-запись без Cloudflare Proxy.
- Self-signed origin certificate подходит для режима Cloudflare `Full`.
- Если у вас включен `Full (strict)`, лучше заменить сертификат на Cloudflare Origin Certificate или другой доверенный origin cert.
- Если на сервере уже есть свой сложный `nginx`, скрипт добавит include для `/etc/nginx/stream-conf.d/*.conf` в `stream`-блок.
