# Security Notes

## Recommended Defaults

- Runtime directory: `/opt/silentbridge`
- Open ports only:
  - `22/tcp`
  - `80/tcp`
  - `443/tcp`
- Restrict SSH by source IP whenever possible
- Restrict panel access by IP allowlist or place it behind a trusted access proxy

## UFW Baseline

Example with SSH allowed only from one trusted public IP:

```bash
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw allow from <YOUR_PUBLIC_IP>/32 to any port 22 proto tcp
sudo ufw enable
sudo ufw status verbose
```

If your IP is not stable yet, you can temporarily allow SSH more broadly:

```bash
sudo ufw allow 22/tcp
```

Then tighten it later.

## SSH Hardening

Recommended `/etc/ssh/sshd_config` values:

```conf
PermitRootLogin no
PasswordAuthentication no
PubkeyAuthentication yes
ChallengeResponseAuthentication no
X11Forwarding no
```

After edits:

```bash
sudo sshd -t
sudo systemctl restart ssh
```

## Panel Exposure

The repository supports an IP allowlist for the panel vhost through `PANEL_ALLOWLIST`.

Examples:

```dotenv
PANEL_ALLOWLIST=127.0.0.1/32
PANEL_ALLOWLIST=203.0.113.10/32
PANEL_ALLOWLIST=203.0.113.10/32,198.51.100.0/24
```

Behavior:

- when set, only listed IPs can reach the panel vhost
- all other IPs receive `403`
- panel root path returns `404`
- response includes `X-Robots-Tag: noindex, nofollow, noarchive`

## Reverse Access Proxy

If you do not want to expose the panel directly on the same public surface as the edge domain, place `app.<domain>` behind one of these:

- SSH tunnel
- VPN
- Cloudflare Access
- Tailscale / WireGuard
- trusted reverse proxy with authentication

That is safer than keeping the panel publicly reachable from all IPs.
