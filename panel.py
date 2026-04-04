#!/usr/bin/env python3
"""Minimal web panel for xray_server client management."""

from __future__ import annotations

import argparse
import json
import os
import re
import uuid
from datetime import datetime, timezone
from pathlib import Path
from typing import Dict, List
from urllib.parse import quote

try:
    import docker
except Exception:  # pragma: no cover
    docker = None

DEFAULT_CONFIG_DIR = Path("/app/config")
CLIENTS_FILE = Path(os.getenv("CLIENTS_FILE_PATH", DEFAULT_CONFIG_DIR / "clients.json"))
XRAY_CONFIG = Path(os.getenv("XRAY_CONFIG_PATH", DEFAULT_CONFIG_DIR / "config.jsonc"))
CLIENT_OUTPUT_DIR = Path(os.getenv("CLIENT_OUTPUT_DIR", "/app/client"))

CLIENTS_FILE.parent.mkdir(parents=True, exist_ok=True)
XRAY_CONFIG.parent.mkdir(parents=True, exist_ok=True)
CLIENT_OUTPUT_DIR.mkdir(parents=True, exist_ok=True)


def now_iso() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def sanitize_name(raw_name: str) -> str:
    value = re.sub(r"[^a-zA-Z0-9._-]+", "-", raw_name.strip())
    value = re.sub(r"-{2,}", "-", value).strip("-")
    return value[:64]


def load_clients() -> List[Dict[str, str]]:
    if not CLIENTS_FILE.exists():
        return []

    with CLIENTS_FILE.open("r", encoding="utf-8") as handle:
        data = json.load(handle)

    if isinstance(data, dict):
        clients = []
        for name, client in data.items():
            clients.append(
                {
                    "name": sanitize_name(name) or "client",
                    "uuid": client["uuid"],
                    "created_at": client.get("created_at", now_iso()),
                }
            )
        save_clients(clients)
        return clients

    return sorted(data, key=lambda item: item["name"].lower())


def save_clients(clients: List[Dict[str, str]]) -> None:
    ordered = sorted(clients, key=lambda item: item["name"].lower())
    temp_file = CLIENTS_FILE.with_suffix(".tmp")
    with temp_file.open("w", encoding="utf-8") as handle:
        json.dump(ordered, handle, indent=2)
        handle.write("\n")
    temp_file.replace(CLIENTS_FILE)


def build_xhttp_link(client: Dict[str, str]) -> str:
    domain = os.getenv("DOMAIN", "example.com")
    service_name = os.getenv("XRAY_GRPC_SERVICE_NAME", "grpc-demo")
    label = quote(f"gRPC-{client['name']}")
    return (
        f"vless://{client['uuid']}@{domain}:443"
        f"?encryption=none&security=tls&sni={domain}&alpn=h2"
        f"&type=grpc&serviceName={service_name}#{label}"
    )


def build_reality_link(client: Dict[str, str]) -> str:
    endpoint = os.getenv("REALITY_ENDPOINT", "<server-ip>")
    server_name = os.getenv("XRAY_REALITY_SERVER_NAME", "www.microsoft.com")
    public_key = os.getenv("XRAY_REALITY_PUBLIC_KEY", "")
    short_id = os.getenv("XRAY_REALITY_SHORT_ID", "")
    label = quote(f"REALITY-{client['name']}")
    return (
        f"vless://{client['uuid']}@{endpoint}:443"
        f"?encryption=none&flow=xtls-rprx-vision&security=reality"
        f"&sni={server_name}&fp=chrome&pbk={public_key}&sid={short_id}"
        f"&type=tcp#{label}"
    )


def sync_client_exports(clients: List[Dict[str, str]]) -> None:
    for client in clients:
        payload = {
            "name": client["name"],
            "uuid": client["uuid"],
            "xhttp_link": build_xhttp_link(client),
            "reality_link": build_reality_link(client),
            "created_at": client.get("created_at", now_iso()),
        }
        target = CLIENT_OUTPUT_DIR / f"{client['name']}.json"
        with target.open("w", encoding="utf-8") as handle:
            json.dump(payload, handle, indent=2)
            handle.write("\n")


def update_xray_config() -> None:
    clients = load_clients()
    if not XRAY_CONFIG.exists():
        raise FileNotFoundError(f"Missing Xray config: {XRAY_CONFIG}")

    with XRAY_CONFIG.open("r", encoding="utf-8") as handle:
        config = json.load(handle)

    simple_clients = [{"id": client["uuid"]} for client in clients]
    reality_clients = [{"id": client["uuid"], "flow": "xtls-rprx-vision"} for client in clients]

    for inbound in config.get("inbounds", []):
        if inbound.get("tag") == "xhttp-cdn-tls":
            inbound.setdefault("settings", {})["clients"] = simple_clients
        if inbound.get("tag") == "tcp-vless-reality-vision":
            inbound.setdefault("settings", {})["clients"] = reality_clients

    with XRAY_CONFIG.open("w", encoding="utf-8") as handle:
        json.dump(config, handle, indent=2)
        handle.write("\n")

    sync_client_exports(clients)


def restart_xray_container() -> None:
    if docker is None:
        return

    try:
        client = docker.from_env()
        container = client.containers.get("xray-server")
        container.restart(timeout=10)
    except Exception:
        pass


def sync_and_reload() -> None:
    update_xray_config()
    restart_xray_container()


def find_client(name: str) -> Dict[str, str] | None:
    for client in load_clients():
        if client["name"] == name:
            return client
    return None


PAGE_TEMPLATE = """
<!DOCTYPE html>
<html lang="ru">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>Xray Panel</title>
    <style>
        :root {
            --bg: #f4efe5;
            --card: rgba(255, 252, 246, 0.92);
            --ink: #1f2937;
            --muted: #6b7280;
            --line: rgba(31, 41, 55, 0.12);
            --accent: #bb3e03;
            --accent-dark: #9a3412;
            --accent-soft: rgba(187, 62, 3, 0.12);
        }
        * { box-sizing: border-box; }
        body {
            margin: 0;
            font-family: "Segoe UI", sans-serif;
            color: var(--ink);
            background:
                radial-gradient(circle at top left, rgba(212, 163, 115, 0.28), transparent 30%),
                radial-gradient(circle at bottom right, rgba(56, 189, 248, 0.18), transparent 28%),
                var(--bg);
        }
        .wrap { max-width: 1120px; margin: 0 auto; padding: 32px 18px 48px; }
        .hero, .card {
            background: var(--card);
            backdrop-filter: blur(12px);
            border: 1px solid var(--line);
            border-radius: 24px;
            box-shadow: 0 20px 45px rgba(15, 23, 42, 0.08);
        }
        .hero { padding: 28px; margin-bottom: 22px; }
        .hero h1 { margin: 0 0 10px; font-size: 32px; }
        .hero p { margin: 0; color: var(--muted); max-width: 760px; }
        .grid {
            display: grid;
            grid-template-columns: minmax(280px, 340px) 1fr;
            gap: 22px;
        }
        .card { padding: 22px; }
        .card h2 { margin: 0 0 16px; font-size: 22px; }
        .stats { display: grid; grid-template-columns: repeat(3, 1fr); gap: 12px; margin-top: 18px; }
        .stat {
            background: var(--accent-soft);
            border-radius: 18px;
            padding: 14px;
        }
        .stat strong { display: block; font-size: 24px; margin-bottom: 4px; }
        form { display: grid; gap: 12px; }
        input {
            width: 100%;
            border-radius: 14px;
            border: 1px solid var(--line);
            padding: 13px 14px;
            font-size: 15px;
            background: rgba(255, 255, 255, 0.7);
        }
        button, .button {
            appearance: none;
            border: 0;
            border-radius: 999px;
            padding: 11px 16px;
            font-size: 14px;
            color: white;
            background: linear-gradient(135deg, var(--accent), var(--accent-dark));
            text-decoration: none;
            cursor: pointer;
        }
        .button.secondary, .danger {
            background: white;
            color: var(--ink);
            border: 1px solid var(--line);
        }
        .danger { color: #991b1b; }
        .list {
            display: grid;
            gap: 14px;
        }
        .client {
            border: 1px solid var(--line);
            border-radius: 18px;
            padding: 16px;
            background: rgba(255, 255, 255, 0.62);
        }
        .client-top {
            display: flex;
            gap: 12px;
            justify-content: space-between;
            align-items: start;
            margin-bottom: 12px;
        }
        .client h3 { margin: 0 0 4px; font-size: 19px; }
        .meta, .hint { color: var(--muted); font-size: 14px; }
        code, textarea {
            font-family: "SFMono-Regular", Consolas, monospace;
            font-size: 13px;
        }
        .linkbox {
            width: 100%;
            min-height: 88px;
            border: 1px solid var(--line);
            border-radius: 14px;
            padding: 12px;
            background: rgba(255,255,255,0.75);
        }
        .actions {
            display: flex;
            flex-wrap: wrap;
            gap: 10px;
            margin-top: 12px;
        }
        .inline { display: inline; }
        @media (max-width: 900px) {
            .grid { grid-template-columns: 1fr; }
            .stats { grid-template-columns: 1fr; }
        }
    </style>
</head>
<body>
    <div class="wrap">
        <section class="hero">
            <h1>Xray control panel</h1>
            <p>Панель управляет клиентами для двух способов подключения: <strong>VLESS + XHTTP</strong> через Cloudflare и <strong>VLESS + REALITY</strong> напрямую. После добавления или удаления клиента конфиг Xray обновляется и контейнер перезапускается автоматически.</p>
            <div class="stats">
                <div class="stat"><strong>{{ clients|length }}</strong><span>клиентов</span></div>
                <div class="stat"><strong>{{ domain }}</strong><span>домен XHTTP</span></div>
                <div class="stat"><strong>{{ reality_endpoint }}</strong><span>REALITY endpoint</span></div>
            </div>
        </section>

        <div class="grid">
            <section class="card">
                <h2>Новый клиент</h2>
                <form method="post" action="{{ url_for('add_client') }}">
                    <input type="text" name="name" placeholder="Например: iphone-alex" required>
                    <button type="submit">Сгенерировать UUID и добавить</button>
                </form>
                <p class="hint">Имя используется как метка клиента и как имя файла в каталоге `client/`.</p>
            </section>

            <section class="card">
                <h2>Клиенты</h2>
                <div class="list">
                    {% for client in clients %}
                    <article class="client">
                        <div class="client-top">
                            <div>
                                <h3>{{ client.name }}</h3>
                                <div class="meta">UUID: <code>{{ client.uuid }}</code></div>
                                <div class="meta">Создан: {{ client.created_at }}</div>
                            </div>
                            <div class="actions">
                                <a class="button secondary" href="{{ url_for('client_config', name=client.name) }}">Открыть</a>
                                <form class="inline" method="post" action="{{ url_for('remove_client') }}">
                                    <input type="hidden" name="name" value="{{ client.name }}">
                                    <button class="danger" type="submit">Удалить</button>
                                </form>
                            </div>
                        </div>
                        <div class="meta">XHTTP</div>
                        <textarea class="linkbox" readonly>{{ client.xhttp_link }}</textarea>
                        <div class="meta">REALITY</div>
                        <textarea class="linkbox" readonly>{{ client.reality_link }}</textarea>
                    </article>
                    {% else %}
                    <div class="hint">Пока нет клиентов. Добавьте первый профиль слева.</div>
                    {% endfor %}
                </div>
            </section>
        </div>
    </div>
</body>
</html>
"""


DETAIL_TEMPLATE = """
<!DOCTYPE html>
<html lang="ru">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>{{ client.name }} | Xray Panel</title>
    <style>
        body { margin: 0; font-family: "Segoe UI", sans-serif; background: #f4efe5; color: #1f2937; }
        .wrap { max-width: 960px; margin: 0 auto; padding: 24px 18px 42px; }
        .card {
            background: rgba(255, 252, 246, 0.92);
            border: 1px solid rgba(31, 41, 55, 0.12);
            border-radius: 24px;
            padding: 24px;
            box-shadow: 0 20px 45px rgba(15, 23, 42, 0.08);
        }
        h1 { margin-top: 0; }
        .meta { color: #6b7280; margin-bottom: 18px; }
        .block { margin-top: 18px; }
        .label { font-size: 14px; color: #6b7280; margin-bottom: 8px; }
        textarea {
            width: 100%;
            min-height: 120px;
            border-radius: 14px;
            border: 1px solid rgba(31, 41, 55, 0.12);
            padding: 12px;
            background: white;
            font-family: "SFMono-Regular", Consolas, monospace;
            font-size: 13px;
        }
        a { color: #bb3e03; text-decoration: none; }
    </style>
</head>
<body>
    <div class="wrap">
        <div class="card">
            <a href="{{ url_for('index') }}">Назад к списку</a>
            <h1>{{ client.name }}</h1>
            <div class="meta">UUID: <code>{{ client.uuid }}</code></div>
            <div class="block">
                <div class="label">VLESS + XHTTP</div>
                <textarea readonly>{{ client.xhttp_link }}</textarea>
            </div>
            <div class="block">
                <div class="label">VLESS + REALITY</div>
                <textarea readonly>{{ client.reality_link }}</textarea>
            </div>
        </div>
    </div>
</body>
</html>
"""

def create_app():
    from flask import Flask, redirect, render_template_string, request, url_for

    app = Flask(__name__)

    @app.route("/")
    def index():
        clients = load_clients()
        enriched = []
        for client in clients:
            enriched.append(
                {
                    **client,
                    "xhttp_link": build_xhttp_link(client),
                    "reality_link": build_reality_link(client),
                }
            )

        return render_template_string(
            PAGE_TEMPLATE,
            clients=enriched,
            domain=os.getenv("DOMAIN", "example.com"),
            reality_endpoint=os.getenv("REALITY_ENDPOINT", "<server-ip>"),
        )

    @app.route("/add_client", methods=["POST"])
    def add_client():
        name = sanitize_name(request.form.get("name", ""))
        if not name:
            return "Client name is required", 400

        clients = load_clients()
        if any(client["name"] == name for client in clients):
            return "Client already exists", 400

        clients.append({"name": name, "uuid": str(uuid.uuid4()), "created_at": now_iso()})
        save_clients(clients)
        sync_and_reload()
        return redirect(url_for("index"))

    @app.route("/remove_client", methods=["POST"])
    def remove_client():
        name = request.form.get("name", "")
        clients = [client for client in load_clients() if client["name"] != name]
        save_clients(clients)
        sync_and_reload()
        return redirect(url_for("index"))

    @app.route("/client/<name>")
    def client_config(name: str):
        client = find_client(name)
        if client is None:
            return "Client not found", 404

        enriched = {
            **client,
            "xhttp_link": build_xhttp_link(client),
            "reality_link": build_reality_link(client),
        }
        return render_template_string(DETAIL_TEMPLATE, client=enriched)

    return app


def cli() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--sync-config", action="store_true")
    args = parser.parse_args()

    if args.sync_config:
        update_xray_config()
        return 0

    app = create_app()
    app.run(host="0.0.0.0", port=5000, debug=False)
    return 0


if __name__ == "__main__":
    raise SystemExit(cli())
