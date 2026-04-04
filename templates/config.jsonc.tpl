{
  "log": {
    "access": "/var/log/xray/access.log",
    "error": "/var/log/xray/error.log",
    "loglevel": "warning"
  },
  "dns": {
    "servers": [
      "https://1.1.1.1/dns-query",
      "https://1.0.0.1/dns-query"
    ]
  },
  "routing": {
    "domainStrategy": "IPOnDemand",
    "rules": [
      {
        "inboundTag": [
          "xhttp-cdn-tls",
          "tcp-vless-reality-vision"
        ],
        "outboundTag": "block",
        "protocol": [
          "bittorrent"
        ]
      },
      {
        "inboundTag": [
          "xhttp-cdn-tls",
          "tcp-vless-reality-vision"
        ],
        "outboundTag": "block",
        "domain": [
          "regexp:.*\\.(ru|рф|by|kz|ir|cn)$"
        ]
      },
      {
        "inboundTag": [
          "xhttp-cdn-tls",
          "tcp-vless-reality-vision"
        ],
        "outboundTag": "block",
        "ip": [
          "geoip:ru",
          "geoip:by",
          "geoip:kz",
          "geoip:ir",
          "geoip:cn"
        ]
      },
      {
        "inboundTag": [
          "xhttp-cdn-tls",
          "tcp-vless-reality-vision"
        ],
        "outboundTag": "direct"
      }
    ]
  },
  "outbounds": [
    {
      "tag": "direct",
      "protocol": "freedom"
    },
    {
      "tag": "block",
      "protocol": "blackhole"
    }
  ],
  "inbounds": [
    {
      "tag": "xhttp-cdn-tls",
      "listen": "0.0.0.0",
      "port": 777,
      "protocol": "vless",
      "settings": {
        "decryption": "none",
        "clients": [
          {
            "id": "__XRAY_UUID__"
          }
        ]
      },
      "streamSettings": {
        "network": "grpc",
        "grpcSettings": {
          "serviceName": "__XRAY_GRPC_SERVICE_NAME__"
        }
      },
      "sniffing": {
        "enabled": true,
        "routeOnly": true,
        "destOverride": [
          "quic",
          "http",
          "tls"
        ]
      }
    },
    {
      "tag": "tcp-vless-reality-vision",
      "listen": "0.0.0.0",
      "port": 888,
      "protocol": "vless",
      "settings": {
        "decryption": "none",
        "clients": [
          {
            "flow": "xtls-rprx-vision",
            "id": "__XRAY_UUID__"
          }
        ]
      },
      "streamSettings": {
        "network": "raw",
        "security": "reality",
        "realitySettings": {
          "dest": "__XRAY_REALITY_DEST__",
          "serverNames": [
            "__XRAY_REALITY_SERVER_NAME__"
          ],
          "privateKey": "__XRAY_REALITY_PRIVATE_KEY__",
          "shortIds": [
            "",
            "__XRAY_REALITY_SHORT_ID__"
          ]
        }
      },
      "sniffing": {
        "enabled": true,
        "routeOnly": true,
        "destOverride": [
          "quic",
          "http",
          "tls"
        ]
      }
    }
  ]
}
