# Безопасность

- типовой runtime для single-server схемы: `/opt/remnawave`
- типовой runtime отдельной ноды: `/opt/remnanode`
- открытые входящие порты: `22/tcp`, `80/tcp`, `443/tcp`
- `2222/tcp` должен быть доступен только от IP сервера панели
- `root`-вход по SSH лучше держать выключенным

## SSH

Базовая рекомендуемая политика:

```conf
PermitRootLogin no
PasswordAuthentication yes
PubkeyAuthentication yes
KbdInteractiveAuthentication no
ChallengeResponseAuthentication no
X11Forwarding no
MaxAuthTries 3
```

Практический порядок:

1. Создайте пользователя, например `eol`.
2. Добавьте хотя бы один рабочий публичный ключ.
3. Проверьте вход ключом со всех нужных машин.
4. Только после этого отключайте `PasswordAuthentication`.

## UFW

Базовый вариант:

```bash
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow 22/tcp
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw enable
```

Для отдельной ноды дополнительно сузьте `2222/tcp` до IP панели:

```bash
sudo ufw allow from <PANEL_IP> to any port 2222 proto tcp
sudo ufw status verbose
```

Если есть стабильный домашний/офисный IP, SSH лучше тоже сузить до него.

## Fail2Ban

Хороший минимум для SSH:

```ini
[DEFAULT]
bantime = 1h
findtime = 10m
maxretry = 5
backend = systemd
banaction = ufw
ignoreip = 127.0.0.1/8 ::1 <YOUR_TRUSTED_IP>

[sshd]
enabled = true
port = 22
logpath = %(sshd_log)s
```

Важно:

- не забывайте добавить свой текущий IP в `ignoreip`, если активно тестируете парольный SSH
- перед ужесточением `fail2ban` полезно иметь доступ через консоль провайдера

## Panel Access

В single-server схеме у `Remnawave` панель живет на отдельном домене, например:

```text
https://panel.example.com/
```

Если не хочется держать панель открытой в интернет:

- SSH-туннель
- VPN
- Cloudflare Access
- Tailscale
- WireGuard
- reverse proxy с отдельной аутентификацией

## Sysctl

Для `valkey` лучше заранее включить:

```bash
sudo sysctl -w vm.overcommit_memory=1
```

И закрепить это в `/etc/sysctl.conf`.
