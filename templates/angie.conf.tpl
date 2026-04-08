user angie;
worker_processes auto;

error_log /var/log/angie/error.log notice;

events {
    worker_connections 1024;
}

http {
    access_log /var/log/angie/access.log;

    resolver 1.1.1.1;

    acme_client panel https://acme-v02.api.letsencrypt.org/directory;

    server {
        listen 80;
        listen [::]:80;
        server_name __PANEL_DOMAIN__;
        return 301 https://$host:__PANEL_PORT__$request_uri;
    }

    server {
        listen __PANEL_PORT__ ssl;
        listen [::]:__PANEL_PORT__ ssl;
        http2 on;

        server_name __PANEL_DOMAIN__;

        acme panel;
        ssl_certificate     $acme_cert_panel;
        ssl_certificate_key $acme_cert_key_panel;

        ssl_protocols              TLSv1.2 TLSv1.3;
        ssl_ciphers                TLS13_AES_128_GCM_SHA256:TLS13_AES_256_GCM_SHA384:TLS13_CHACHA20_POLY1305_SHA256:ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305;
        ssl_prefer_server_ciphers  on;
        ssl_stapling               on;
        ssl_stapling_verify        on;
        resolver                   1.1.1.1 valid=60s;
        resolver_timeout           2s;

        add_header X-Robots-Tag "noindex, nofollow, noarchive" always;

__PANEL_ALLOWLIST_RULES__

        location = / {
            return 404;
        }

        location ~* ^/(api|docs|redoc|openapi.json|statics|__MARZBAN_DASHBOARD_PATH__/) {
            proxy_pass                         http://unix:/var/lib/marzban/marzban.socket:;
            proxy_http_version                 1.1;
            proxy_set_header Host              $host;
            proxy_set_header X-Real-IP         $remote_addr;
            proxy_set_header X-Forwarded-For   $proxy_add_x_forwarded_for;
            proxy_set_header Forwarded         "for=$remote_addr";
            proxy_set_header X-Forwarded-Proto https;
        }

        location / {
            return 404;
        }
    }
}
