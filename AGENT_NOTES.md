# Заметки

- основные пути репозитория:
  - `Remnawave`
  - `Clean 3x-ui + Angie`
- для пользователя желательно один верхнеуровневый вход через `install-remnawave.sh`
- базовая схема single-server:
  - `panel.example.com` - панель
  - `sub.example.com` - subscription page
  - `example.com` - selfsteal домен ноды
- отдельная нода ставится на второй VPS и подключается к уже существующей панели

Актуальные переменные:

- `REMNAWAVE_PANEL_DOMAIN`
- `REMNAWAVE_SUB_DOMAIN`
- `REMNAWAVE_NODE_DOMAIN`
- `LETSENCRYPT_EMAIL`
- для second-node сценария:
  - `REMNAWAVE_PANEL_IP`
  - `REMNAWAVE_NODE_SECRET_KEY_FILE` или `REMNAWAVE_NODE_SECRET_KEY`

Операционно:

- рабочая копия upstream `remnawave-reverse-proxy` может жить отдельно, по умолчанию `/usr/local/src/remnawave-reverse-proxy`
- runtime single-server схемы: `/opt/remnawave`
- runtime отдельной ноды: `/opt/remnanode`
- `Ubuntu 24.04` предпочтительнее, но для `Ubuntu 25.04` сейчас нужен локальный патч проверки ОС у upstream installer
- upstream single-server путь следует считать компромиссным, а не идеальным production-эталоном
- legacy-ветка удалена из рабочего потока

DPI-диагностика:

- обвязка `dpi-ch` лежит в `tools/dpich`
- runner использует официальный Docker-образ `ghcr.io/hyperion-cs/dpich:latest`, исходники/бинарник в репозиторий не вендорятся
- результаты `--all` складываются в `dpich-results/`
- запускать проверку нужно из той сети, которую диагностируем; VPS-run описывает только egress самого VPS
- для IP/subnet/ASN/org targets указывать `--sni`, иначе SNI-зависимый сценарий может не воспроизвестись
