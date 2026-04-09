# Заметки По Безопасности

## Рекомендуемая База

- Каталог runtime по умолчанию: `/opt/xray-vps-setup`
- Открытые входящие порты:
  - `22/tcp`
  - `80/tcp`
  - `443/tcp`
- Доступ по SSH лучше ограничить по IP, если это возможно
- Доступ к панели можно дополнительно ограничить через `PANEL_ALLOWLIST` или через доверенный прокси/туннель

## Базовая Настройка UFW

Пример, если SSH разрешен только с одного доверенного публичного IP:

```bash
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw allow from <YOUR_PUBLIC_IP>/32 to any port 22 proto tcp
sudo ufw enable
sudo ufw status verbose
```

Если IP пока нестабилен, можно временно разрешить SSH шире:

```bash
sudo ufw allow 22/tcp
```

После этого доступ лучше сузить.

## Усиление SSH

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

## Ограничение Доступа К Панели

Репозиторий поддерживает необязательный IP allowlist через `PANEL_ALLOWLIST`.

Примеры:

```dotenv
PANEL_ALLOWLIST=203.0.113.10/32
PANEL_ALLOWLIST=203.0.113.10/32,198.51.100.0/24
```

Поведение:

- если `PANEL_ALLOWLIST` задан, только перечисленные IP смогут обращаться к HTTPS-поверхности домена
- остальные IP будут получать `403`
- при включенном allowlist корень домена тоже перестает отдавать маскировочную страницу для заблокированных IP
- ответы панели помечаются заголовком `X-Robots-Tag: noindex, nofollow, noarchive`

Важно:

- allowlist применяется к общему домену, потому что панель и маскировочная страница работают на одном `DOMAIN`
- если включить allowlist слишком рано, можно случайно закрыть доступ и к панели, и к обычной маске с собственного IP

## Более Безопасный Доступ К Панели

Если не хочется держать панель открытой даже по скрытому пути, лучше использовать один из вариантов ниже:

- SSH-туннель
- VPN
- Cloudflare Access
- Tailscale
- WireGuard
- доверенный reverse proxy с аутентификацией

Это безопаснее, чем оставлять панель доступной для всех IP даже при скрытом URL.
