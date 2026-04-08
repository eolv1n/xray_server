# Agent Notes

## Current Production Layout

- Git working copy on server: `~/xray_server`
- Live runtime directory on server: `/opt/silentbridge`
- Live domains:
  - `edge.silnetbridge.com`
  - `app.silnetbridge.com`
- Live containers:
  - `xray-angie`
  - `xray-marzban`

## Important Operational Notes

- The live stack currently runs from `/opt/silentbridge`, not from `/opt/xray_panel`.
- The server clone `~/xray_server` is used as the control repository for updates and maintenance.
- Do not assume the server is clean before running `install.sh`; inspect `/opt/silentbridge` first.
- Avoid destructive reset of `/opt/silentbridge` unless the user explicitly asks for reinstall.
- The live `Marzban` custom templates directory is:
  - `/opt/silentbridge/marzban_lib/templates`
- The live subscription page template path is:
  - `/opt/silentbridge/marzban_lib/templates/subscription/index.html`

## Safe Update Pattern

1. Update this repository locally and push to GitHub.
2. On the server, update `~/xray_server`.
3. For cosmetic subscription changes, copy only the needed template into `/opt/silentbridge/marzban_lib/templates/...`.
4. Re-run full `install.sh` only when intentionally changing stack config or runtime assets.

## Backups Present On Server

- `~/xray_server/.codex-backup/env.before-cleanup`
- `~/xray_server/.codex-backup/server-local.diff`
