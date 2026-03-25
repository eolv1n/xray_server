server {
    listen 127.0.0.1:__NGINX_HTTP_PORT__ ssl http2;
    server_name __DOMAIN__;

    ssl_certificate __TLS_CERT__;
    ssl_certificate_key __TLS_KEY__;
    ssl_session_timeout 1d;
    ssl_session_cache shared:SSL:10m;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_prefer_server_ciphers off;

    location /__XRAY_XHTTP_PATH__ {
        client_max_body_size 0;
        grpc_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        grpc_set_header Host $host;
        grpc_pass grpc://127.0.0.1:__XRAY_XHTTP_PORT__;
    }

    location / {
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
        proxy_pass http://127.0.0.1:__CLOAK_PORT__;
    }
}
