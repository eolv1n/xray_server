# Безопасность

- каталог runtime по умолчанию: `/opt/xray-vps-setup`
- открытые входящие порты: `22/tcp`, `80/tcp`, `443/tcp`
- SSH лучше ограничить по IP, если это возможно
- доступ к панели можно дополнительно ограничить через `PANEL_ALLOWLIST`

## UFW

Пример, если SSH разрешен только с одного доверенного IP:

```bash
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw allow from <YOUR_PUBLIC_IP>/32 to any port 22 proto tcp
sudo ufw enable
sudo ufw status verbose
```

Если IP пока нестабилен:

```bash
sudo ufw allow 22/tcp
```

Потом доступ лучше сузить.

## SSH

Рекомендуемые значения для `/etc/ssh/sshd_config`:

```conf
PermitRootLogin no
PasswordAuthentication no
PubkeyAuthentication yes
ChallengeResponseAuthentication no
X11Forwarding no
```

После правок:

```bash
sudo sshd -t
sudo systemctl restart ssh
```

## PANEL_ALLOWLIST

Примеры:

```dotenv
PANEL_ALLOWLIST=203.0.113.10/32
PANEL_ALLOWLIST=203.0.113.10/32,198.51.100.0/24
```

Если `PANEL_ALLOWLIST` задан:

- только перечисленные IP смогут обращаться к HTTPS-поверхности домена
- остальные IP будут получать `403`
- корень домена тоже перестанет отдавать маскировочную страницу для заблокированных IP
- ответы панели будут содержать `X-Robots-Tag: noindex, nofollow, noarchive`

Важно:

- allowlist применяется ко всему домену, потому что панель и маскировочная страница работают на одном `DOMAIN`
- если включить allowlist слишком рано, можно закрыть доступ и к панели, и к обычной маске со своего IP

## Более безопасный доступ к панели

Если не хочется держать панель открытой даже по скрытому пути, лучше использовать:

- SSH-туннель
- VPN
- Cloudflare Access
- Tailscale
- WireGuard
- доверенный reverse proxy с аутентификацией
