user angie;
worker_processes auto;

events {
    worker_connections 2048;
}

http {
    include       /etc/angie/mime.types;
    default_type  application/octet-stream;
    sendfile      on;
    keepalive_timeout 65;

    server {
        listen 80;
        server_name __XUI_PANEL_DOMAIN__ __XUI_MASK_DOMAIN__;

        location ^~ /.well-known/acme-challenge/ {
            root /var/www/certbot;
        }

        location / {
            return 301 https://$host$request_uri;
        }
    }

    server {
        listen 443 ssl;
        http2 on;
        server_name __XUI_PANEL_DOMAIN__;

        ssl_certificate     /etc/nginx/ssl/__XUI_PANEL_DOMAIN__/fullchain.pem;
        ssl_certificate_key /etc/nginx/ssl/__XUI_PANEL_DOMAIN__/privkey.pem;
        ssl_protocols       TLSv1.2 TLSv1.3;

        location / {
            proxy_pass         http://127.0.0.1:__XUI_PANEL_PORT__;
            proxy_http_version 1.1;
            proxy_set_header   Host $host;
            proxy_set_header   X-Real-IP $remote_addr;
            proxy_set_header   X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header   X-Forwarded-Proto $scheme;
        }
    }

    server {
        listen 443 ssl;
        http2 on;
        server_name __XUI_MASK_DOMAIN__;

        ssl_certificate     /etc/nginx/ssl/__XUI_MASK_DOMAIN__/fullchain.pem;
        ssl_certificate_key /etc/nginx/ssl/__XUI_MASK_DOMAIN__/privkey.pem;
        ssl_protocols       TLSv1.2 TLSv1.3;

        root  /var/www/html;
        index index.html;
    }
}
