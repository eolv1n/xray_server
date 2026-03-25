include __APP_DIR__/config/cloudflare-ips.conf;

map $is_cdn $xray_dest {
    0 127.0.0.1:__XRAY_REALITY_PORT__;
    1 127.0.0.1:__NGINX_HTTP_PORT__;
}

server {
    listen 443;
    proxy_pass $xray_dest;
    proxy_timeout 300s;
    proxy_connect_timeout 10s;
}
