#!/bin/bash

echo "Обновление и установка необходимых пакетов..."
apt update && apt install -y jq

# Установка Xray
bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install

# Определяем директорию скрипта
SCRIPT_DIR=/usr/local/etc/xray

# Генерируем переменные
xray_uuid_vrv=$(xray uuid)

# Российские домены для обхода блокировок
domains=(
    "st.ozone.ru"
    "stats.vk-portal.net" 
    "sun6-21.userapi.com"
    "sun6-20.userapi.com"
    "avatars.mds.yandex.net"
    "queuev4.vk.com"
    "sun6-22.userapi.com"
    "sync.browser.yandex.net"
    "top-fwz1.mail.ru"
    "ad.mail.ru"
    "eh.vk.com"
    "akashi.vk-portal.net"
    "mc.yandex.ru"
    "kino.yandex.ru"
    "music.yandex.ru"
    "sso.vk.com"
)

# Выбираем случайные домены для разных портов
xray_dest_vrv=${domains[$RANDOM % ${#domains[@]}]}
xray_dest_vrv222=${domains[$RANDOM % ${#domains[@]}]}

# Убедимся что домены разные
while [ "$xray_dest_vrv" = "$xray_dest_vrv222" ]; do
    xray_dest_vrv222=${domains[$RANDOM % ${#domains[@]}]}
done

key_output=$(xray x25519)
xray_privateKey_vrv=$(echo "$key_output" | awk -F': ' '/PrivateKey/ {print $2}')
xray_publicKey_vrv=$(echo "$key_output" | awk -F': ' '/PublicKey/ {print $2}')

xray_shortIds_vrv=$(openssl rand -hex 8)
xray_sspasw_vrv=$(openssl rand -base64 15 | tr -dc 'A-Za-z0-9' | head -c 20)
ipserv=$(hostname -I | awk '{print $1}')

# Экспортируем переменные для envsubst
export xray_uuid_vrv xray_dest_vrv xray_dest_vrv222 xray_privateKey_vrv xray_publicKey_vrv xray_shortIds_vrv xray_sspasw_vrv

# Создаем JSON конфигурацию
cat << 'EOF' | envsubst > "$SCRIPT_DIR/config.json"
{
    "dns": {
        "servers": [
            "https+local://8.8.4.4/dns-query",
            "https+local://8.8.8.8/dns-query", 
            "https+local://1.1.1.1/dns-query",
            "localhost"
        ]
    },
    "log": {
        "loglevel": "none",
        "dnsLog": false
    },
    "routing": {
        "rules": [
            {
                "domain": [
                    "geosite:category-ads",
                    "geosite:win-spy"
                ],
                "outboundTag": "block"
            },
            {
                "ip": [
                    "geoip:private"
                ],
                "outboundTag": "block",
                "type": "field"
            }
        ]
    },
    "inbounds": [
        {
            "tag": "VLESStcpREALITY",
            "listen": "0.0.0.0",
            "port": 443,
            "protocol": "vless",
            "settings": {
                "flow": "xtls-rprx-vision",
                "clients": [
                    {
                        "flow": "xtls-rprx-vision",
                        "id": "${xray_uuid_vrv}"
                    }
                ],
                "decryption": "none"
            },
            "streamSettings": {
                "network": "raw",
                "security": "reality",
                "realitySettings": {
                    "show": false,
                    "target": "${xray_dest_vrv}",
                    "xver": 0,
                    "SpiderX": "/",
                    "serverNames": [
                        "${xray_dest_vrv}",
                        "st.ozone.ru",
                        "stats.vk-portal.net",
                        "avatars.mds.yandex.net",
                        "sun6-21.userapi.com"
                    ],
                    "privateKey": "${xray_privateKey_vrv}",
                    "shortIds": [
                        "${xray_shortIds_vrv}"
                    ],
                    "limitFallbackUpload": {
                        "afterBytes": 0,
                        "bytesPerSec": 65536,
                        "burstBytesPerSec": 0
                    },
                    "limitFallbackDownload": {
                        "afterBytes": 5242880,
                        "bytesPerSec": 262144,
                        "burstBytesPerSec": 2097152
                    }
                }
            },
            "sniffing": {
                "enabled": true,
                "destOverride": [
                    "http",
                    "tls", 
                    "quic"
                ]
            }
        },
        {
            "tag": "Vless8443",
            "listen": "0.0.0.0",
            "port": 8443,
            "protocol": "vless",
            "settings": {
                "flow": "xtls-rprx-vision",
                "clients": [
                    {
                        "flow": "xtls-rprx-vision",
                        "id": "${xray_uuid_vrv}"
                    }
                ],
                "decryption": "none"
            },
            "streamSettings": {
                "network": "raw",
                "security": "reality",
                "realitySettings": {
                    "show": false,
                    "target": "${xray_dest_vrv222}",
                    "xver": 0,
                    "SpiderX": "/",
                    "serverNames": [
                        "${xray_dest_vrv222}",
                        "st.ozone.ru", 
                        "stats.vk-portal.net",
                        "avatars.mds.yandex.net",
                        "sun6-20.userapi.com"
                    ],
                    "privateKey": "${xray_privateKey_vrv}",
                    "shortIds": [
                        "${xray_shortIds_vrv}"
                    ],
                    "limitFallbackUpload": {
                        "afterBytes": 0,
                        "bytesPerSec": 65536,
                        "burstBytesPerSec": 0
                    },
                    "limitFallbackDownload": {
                        "afterBytes": 5242880,
                        "bytesPerSec": 262144,
                        "burstBytesPerSec": 2097152
                    }
                }
            },
            "sniffing": {
                "enabled": true,
                "destOverride": [
                    "http",
                    "tls",
                    "quic"
                ]
            }
        },
        {
            "tag": "ShadowsocksTCP",
            "listen": "0.0.0.0",
            "port": 2040,
            "protocol": "shadowsocks",
            "settings": {
                "clients": [
                    {
                        "password": "${xray_sspasw_vrv}",
                        "method": "chacha20-ietf-poly1305"
                    }
                ],
                "network": "tcp,udp"
            },
            "sniffing": {
                "enabled": true,
                "destOverride": [
                    "http",
                    "tls",
                    "quic"
                ]
            }
        }
    ],
    "outbounds": [
        {
            "protocol": "freedom",
            "tag": "direct",
            "settings": {
                "domainStrategy": "ForceIPv4"
            }
        },
        {
            "protocol": "blackhole",
            "tag": "block"
        }
    ]
}
EOF

# Перезапуск Xray
echo "Перезапуск Xray..."
systemctl restart xray
echo -e "Готово!\n"

# Формирование ссылок для ТГ
link1="vless://${xray_uuid_vrv}@${ipserv}:443?security=reality&sni=${xray_dest_vrv}&fp=chrome&pbk=${xray_publicKey_vrv}&sid=${xray_shortIds_vrv}&type=tcp&flow=xtls-rprx-vision&encryption=none&spx=%2F#VPN-vless-443"

link2="vless://${xray_uuid_vrv}@${ipserv}:8443?security=reality&sni=${xray_dest_vrv222}&fp=chrome&pbk=${xray_publicKey_vrv}&sid=${xray_shortIds_vrv}&type=tcp&flow=xtls-rprx-vision&encryption=none&spx=%2F#VPN-vless-8443"

ENCODED_STRING=$(echo -n "chacha20-ietf-poly1305:${xray_sspasw_vrv}" | base64)
link3="ss://$ENCODED_STRING@${ipserv}:2040#VPN-ShadowS-2040"

userID=$1
tgTOKEN=$2

if [ -n "$userID" ]; then
# Формируем сообщение
message="<b>VPN конфиги с российскими доменами:</b>

🚀 <b>Основной (443 порт):</b>
<code>$link1</code>
SNI: <code>${xray_dest_vrv}</code>

🔄 <b>Резервный (8443 порт):</b>  
<code>$link2</code>
SNI: <code>${xray_dest_vrv222}</code>

🔐 <b>Shadowsocks (2040 порт):</b>
<code>$link3</code>

<b>Рекомендуемые приложения:</b>
• <b>iOS</b>: Happ или v2rayTun
• <b>Android</b>: Happ или v2rayNG  
• <b>Windows</b>: Nekoray или Hiddify

Используются российские домены для лучшей обходимости блокировок.

<a href='https://github.com/xVRVx/autoXRAY'>Поддержать автора</a>.
"

# Отправка сообщения в Telegram
curl -s -X POST "https://api.telegram.org/bot$tgTOKEN/sendMessage" \
    -d chat_id="$userID" \
    -d text="$message" \
    -d parse_mode="HTML" \
    -d disable_web_page_preview=true
fi

echo -e "
\033[32m=== VPN конфиги с российскими доменами ===\033[0m

🚀 \033[33mОсновной (443 порт):\033[0m
$link1
SNI: ${xray_dest_vrv}

🔄 \033[33mРезервный (8443 порт):\033[0m  
$link2
SNI: ${xray_dest_vrv222}

🔐 \033[33mShadowsocks (2040 порт):\033[0m
$link3

\033[32mИспользуются популярные российские домены для обхода блокировок.\033[0m

Приложения: iOS - Happ, Android - v2rayNG, Windows - Nekoray

Поддержать автора: https://github.com/xVRVx/autoXRAY
"
