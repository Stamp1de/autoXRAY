#!/bin/bash
# =============================================================================
# autoVPN.sh - Автоматическая настройка VPN сервера с обходом блокировок
# Версия: 2.0 (Декабрь 2025)
# 
# Улучшения относительно autoXRAY:
# - Мультипортовая конфигурация (443 + альтернативные порты)
# - XHTTP транспорт для обхода новых DPI-сигнатур
# - Shadowsocks-2022 как резервный протокол
# - Автоматический selfsteal с Let's Encrypt
# - Клиентский роутинг для РФ трафика
# - Резервные порты на случай блокировки 443
# =============================================================================

set -e

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Функция вывода сообщений
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[OK]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# =============================================================================
# Проверка аргументов
# =============================================================================
DOMAIN=$1

if [ -z "$DOMAIN" ]; then
    echo ""
    echo "╔════════════════════════════════════════════════════════════════════╗"
    echo "║              autoVPN - Установка VPN сервера v2.0                  ║"
    echo "╚════════════════════════════════════════════════════════════════════╝"
    echo ""
    echo "Использование: bash autoVPN.sh <ваш_домен>"
    echo ""
    echo "Пример: bash autoVPN.sh vpn.example.com"
    echo ""
    echo "Требования:"
    echo "  - Чистый Ubuntu 22/24 или Debian 11/12"
    echo "  - Домен с A-записью, указывающей на IP этого сервера"
    echo "  - Root доступ"
    echo ""
    exit 1
fi

# =============================================================================
# Проверка root прав
# =============================================================================
if [ "$EUID" -ne 0 ]; then
    log_error "Запустите скрипт от root: sudo bash autoVPN.sh $DOMAIN"
    exit 1
fi

# =============================================================================
# Проверка DNS
# =============================================================================
log_info "Проверка системы и DNS..."

apt update -qq
apt install -y -qq jq dnsutils curl wget openssl > /dev/null 2>&1

LOCAL_IP=$(hostname -I | awk '{print $1}')
DNS_IP=$(dig +short "$DOMAIN" | grep '^[0-9]' | head -1)

echo ""
log_info "IP сервера: $LOCAL_IP"
log_info "A-запись домена $DOMAIN: $DNS_IP"

if [ "$LOCAL_IP" != "$DNS_IP" ]; then
    log_warning "IP сервера ($LOCAL_IP) не совпадает с DNS ($DNS_IP)"
    log_warning "Убедитесь, что A-запись домена указывает на $LOCAL_IP"
    echo ""
    read -p "Продолжить установку? (y/N): " choice
    if [[ ! "$choice" =~ ^[Yy]$ ]]; then
        log_error "Установка отменена"
        exit 1
    fi
fi

# =============================================================================
# Установка зависимостей
# =============================================================================
log_info "Установка необходимых пакетов..."

apt install -y nginx certbot > /dev/null 2>&1
log_success "Nginx и Certbot установлены"

# =============================================================================
# Получение SSL сертификата
# =============================================================================
log_info "Получение SSL сертификата для $DOMAIN..."

# Остановим nginx если он запущен, чтобы certbot мог использовать порт 80
systemctl stop nginx 2>/dev/null || true

# Получаем сертификат в standalone режиме
certbot certonly --standalone -d "$DOMAIN" -m "admin@$DOMAIN" --agree-tos --non-interactive || {
    log_error "Не удалось получить SSL сертификат"
    log_error "Проверьте, что домен $DOMAIN указывает на этот сервер"
    log_error "И что порт 80 открыт в firewall"
    exit 1
}

log_success "SSL сертификат получен"

# =============================================================================
# Установка Xray
# =============================================================================
log_info "Установка Xray..."

bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install > /dev/null 2>&1
log_success "Xray установлен"

# =============================================================================
# Генерация ключей и паролей
# =============================================================================
log_info "Генерация криптографических ключей..."

UUID=$(xray uuid)
KEYS=$(xray x25519)
PRIVATE_KEY=$(echo "$KEYS" | awk -F': ' '/Private/ {print $2}')
PUBLIC_KEY=$(echo "$KEYS" | awk -F': ' '/Public/ {print $2}')
SHORT_ID=$(openssl rand -hex 8)
SS_PASSWORD=$(openssl rand -base64 32)
XHTTP_PATH=$(openssl rand -hex 4)
SUB_PATH=$(openssl rand -hex 10)
SOCKS_USER=$(openssl rand -hex 4)
SOCKS_PASS=$(openssl rand -hex 12)

# Альтернативные порты (не 443)
ALT_PORT_1=8443
ALT_PORT_2=2053
ALT_PORT_3=2083
SS_PORT=2087

log_success "Ключи сгенерированы"

# =============================================================================
# Создание веб-сайта для маскировки
# =============================================================================
log_info "Создание маскировочного сайта..."

WEB_PATH="/var/www/$DOMAIN"
mkdir -p "$WEB_PATH"

# Массивы для рандомизации
TITLES=("CloudSync" "DataHub" "SecureVault" "FileBox" "SyncDrive" "NetStorage" "QuickShare" "SafeCloud")
HEADERS=("Welcome to CloudSync" "Access Your DataHub" "Enter SecureVault" "FileBox Login" "SyncDrive Portal")
COLORS=("bg-blue-600" "bg-green-600" "bg-indigo-600" "bg-purple-600" "bg-teal-600")

TITLE=${TITLES[$RANDOM % ${#TITLES[@]}]}
HEADER=${HEADERS[$RANDOM % ${#HEADERS[@]}]}
COLOR=${COLORS[$RANDOM % ${#COLORS[@]}]}

cat > "$WEB_PATH/index.html" <<EOF
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>$TITLE</title>
    <script src="https://cdn.tailwindcss.com"></script>
</head>
<body class="flex items-center justify-center min-h-screen bg-gray-100">
    <div class="w-full max-w-md p-8 space-y-6 bg-white rounded-2xl shadow-md">
        <h2 class="text-2xl font-bold text-center text-gray-700">$HEADER</h2>
        <form action="#" method="POST" class="space-y-4">
            <div>
                <label for="email" class="block text-sm font-medium text-gray-600">Email</label>
                <input type="email" id="email" name="email" class="w-full p-2 mt-1 border rounded-lg focus:ring focus:ring-blue-200">
            </div>
            <div>
                <label for="password" class="block text-sm font-medium text-gray-600">Password</label>
                <input type="password" id="password" name="password" class="w-full p-2 mt-1 border rounded-lg focus:ring focus:ring-blue-200">
            </div>
            <button type="submit" class="w-full px-4 py-2 text-white $COLOR rounded-lg hover:opacity-90">
                Sign In
            </button>
        </form>
    </div>
</body>
</html>
EOF

log_success "Маскировочный сайт создан"

# =============================================================================
# Настройка Nginx
# =============================================================================
log_info "Настройка Nginx..."

cat > /etc/nginx/sites-available/default <<EOF
# Редирект HTTP -> HTTPS
server {
    listen 80;
    server_name $DOMAIN;
    
    location /.well-known/acme-challenge/ {
        root /var/www/html;
    }
    
    location / {
        return 301 https://\$host\$request_uri;
    }
}

# HTTPS сервер для fallback (Unix socket от Xray)
server {
    listen unix:/dev/shm/nginx.sock ssl http2 proxy_protocol;
    set_real_ip_from unix:;
    real_ip_header proxy_protocol;
    
    server_name $DOMAIN;
    root $WEB_PATH;
    index index.html;
    
    ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;
    ssl_prefer_server_ciphers on;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 1d;
    ssl_session_tickets off;
    
    location ~ /\.ht {
        deny all;
    }
}
EOF

systemctl enable --now nginx
systemctl restart nginx
log_success "Nginx настроен"

# =============================================================================
# Настройка Xray
# =============================================================================
log_info "Настройка Xray конфигурации..."

XRAY_CONFIG="/usr/local/etc/xray/config.json"

cat > "$XRAY_CONFIG" <<EOF
{
  "log": {
    "loglevel": "warning",
    "access": "/var/log/xray/access.log",
    "error": "/var/log/xray/error.log"
  },
  "dns": {
    "servers": [
      "https+local://8.8.8.8/dns-query",
      "https+local://1.1.1.1/dns-query",
      "localhost"
    ],
    "queryStrategy": "UseIPv4"
  },
  "inbounds": [
    {
      "tag": "vless-reality-443",
      "port": 443,
      "listen": "0.0.0.0",
      "protocol": "vless",
      "settings": {
        "clients": [{"id": "$UUID", "flow": "xtls-rprx-vision"}],
        "decryption": "none",
        "fallbacks": [{"dest": "3001", "xver": 0}]
      },
      "sniffing": {"enabled": true, "destOverride": ["http", "tls", "quic"]},
      "streamSettings": {
        "network": "raw",
        "security": "reality",
        "realitySettings": {
          "show": false,
          "xver": 1,
          "target": "/dev/shm/nginx.sock",
          "spiderX": "/",
          "shortIds": ["$SHORT_ID"],
          "privateKey": "$PRIVATE_KEY",
          "serverNames": ["$DOMAIN"]
        }
      }
    },
    {
      "tag": "vless-xhttp-alt",
      "port": $ALT_PORT_1,
      "listen": "0.0.0.0",
      "protocol": "vless",
      "settings": {
        "clients": [{"id": "$UUID"}],
        "decryption": "none"
      },
      "sniffing": {"enabled": true, "destOverride": ["http", "tls", "quic"]},
      "streamSettings": {
        "network": "xhttp",
        "security": "reality",
        "xhttpSettings": {
          "mode": "auto",
          "path": "/$XHTTP_PATH"
        },
        "realitySettings": {
          "show": false,
          "fingerprint": "chrome",
          "serverNames": ["$DOMAIN"],
          "privateKey": "$PRIVATE_KEY",
          "shortIds": ["$SHORT_ID"]
        }
      }
    },
    {
      "tag": "vless-xhttp-3001",
      "port": 3001,
      "listen": "127.0.0.1",
      "protocol": "vless",
      "settings": {
        "clients": [{"id": "$UUID"}],
        "decryption": "none"
      },
      "sniffing": {"enabled": true, "destOverride": ["http", "tls", "quic"]},
      "streamSettings": {
        "network": "xhttp",
        "xhttpSettings": {"mode": "auto", "path": "/$XHTTP_PATH"}
      }
    },
    {
      "tag": "vless-reality-alt2",
      "port": $ALT_PORT_2,
      "listen": "0.0.0.0",
      "protocol": "vless",
      "settings": {
        "clients": [{"id": "$UUID", "flow": "xtls-rprx-vision"}],
        "decryption": "none"
      },
      "sniffing": {"enabled": true, "destOverride": ["http", "tls", "quic"]},
      "streamSettings": {
        "network": "raw",
        "security": "reality",
        "realitySettings": {
          "show": false,
          "fingerprint": "chrome",
          "serverNames": ["$DOMAIN"],
          "privateKey": "$PRIVATE_KEY",
          "shortIds": ["$SHORT_ID"],
          "spiderX": "/"
        }
      }
    },
    {
      "tag": "vless-reality-alt3",
      "port": $ALT_PORT_3,
      "listen": "0.0.0.0",
      "protocol": "vless",
      "settings": {
        "clients": [{"id": "$UUID", "flow": "xtls-rprx-vision"}],
        "decryption": "none"
      },
      "sniffing": {"enabled": true, "destOverride": ["http", "tls", "quic"]},
      "streamSettings": {
        "network": "raw",
        "security": "reality",
        "realitySettings": {
          "show": false,
          "fingerprint": "firefox",
          "serverNames": ["$DOMAIN"],
          "privateKey": "$PRIVATE_KEY",
          "shortIds": ["$SHORT_ID"],
          "spiderX": "/"
        }
      }
    },
    {
      "tag": "shadowsocks-2022",
      "port": $SS_PORT,
      "listen": "0.0.0.0",
      "protocol": "shadowsocks",
      "settings": {
        "method": "2022-blake3-chacha20-poly1305",
        "password": "$SS_PASSWORD",
        "network": "tcp,udp"
      },
      "sniffing": {"enabled": true, "destOverride": ["http", "tls", "quic"]}
    },
    {
      "tag": "socks5-proxy",
      "port": 10443,
      "listen": "0.0.0.0",
      "protocol": "socks",
      "settings": {
        "auth": "password",
        "udp": true,
        "accounts": [{"user": "$SOCKS_USER", "pass": "$SOCKS_PASS"}]
      }
    }
  ],
  "outbounds": [
    {"tag": "direct", "protocol": "freedom", "settings": {"domainStrategy": "ForceIPv4"}},
    {"tag": "block", "protocol": "blackhole"}
  ],
  "routing": {
    "domainStrategy": "IPIfNonMatch",
    "rules": [
      {"ip": ["geoip:private"], "outboundTag": "block"},
      {"protocol": ["bittorrent"], "outboundTag": "block"},
      {"domain": ["geosite:category-ads", "geosite:win-spy"], "outboundTag": "block"},
      {"domain": ["geosite:category-ru"], "outboundTag": "direct"}
    ]
  }
}
EOF

# Создаем директорию для логов
mkdir -p /var/log/xray
chmod 755 /var/log/xray

systemctl enable xray
systemctl restart xray
log_success "Xray настроен и запущен"

# =============================================================================
# Генерация ссылок для клиентов
# =============================================================================
log_info "Генерация конфигов для клиентов..."

# VLESS Reality на 443 (основной)
LINK_443="vless://${UUID}@${DOMAIN}:443?security=reality&type=tcp&flow=xtls-rprx-vision&sni=${DOMAIN}&fp=chrome&pbk=${PUBLIC_KEY}&sid=${SHORT_ID}&spx=%2F#VLESS-Reality-443"

# VLESS XHTTP на альтернативном порту (рекомендуется при блокировках)
LINK_XHTTP="vless://${UUID}@${DOMAIN}:${ALT_PORT_1}?security=reality&type=xhttp&path=%2F${XHTTP_PATH}&mode=auto&sni=${DOMAIN}&fp=chrome&pbk=${PUBLIC_KEY}&sid=${SHORT_ID}&spx=%2F#VLESS-XHTTP-${ALT_PORT_1}"

# VLESS Reality на альтернативных портах
LINK_ALT2="vless://${UUID}@${DOMAIN}:${ALT_PORT_2}?security=reality&type=tcp&flow=xtls-rprx-vision&sni=${DOMAIN}&fp=chrome&pbk=${PUBLIC_KEY}&sid=${SHORT_ID}&spx=%2F#VLESS-Reality-${ALT_PORT_2}"

LINK_ALT3="vless://${UUID}@${DOMAIN}:${ALT_PORT_3}?security=reality&type=tcp&flow=xtls-rprx-vision&sni=${DOMAIN}&fp=firefox&pbk=${PUBLIC_KEY}&sid=${SHORT_ID}&spx=%2F#VLESS-Reality-${ALT_PORT_3}"

# Shadowsocks 2022
SS_ENCODED=$(echo -n "2022-blake3-chacha20-poly1305:${SS_PASSWORD}" | base64 -w 0)
LINK_SS="ss://${SS_ENCODED}@${DOMAIN}:${SS_PORT}#Shadowsocks-2022"

# =============================================================================
# Создание страницы подписки
# =============================================================================

# JSON подписка с роутингом для клиентов
cat > "$WEB_PATH/${SUB_PATH}.json" <<SUBJSON
[
  {
    "log": {"loglevel": "warning"},
    "dns": {"servers": ["https://8.8.8.8/dns-query", "https://1.1.1.1/dns-query"], "queryStrategy": "UseIPv4"},
    "routing": {
      "domainStrategy": "IPIfNonMatch",
      "rules": [
        {"domain": ["geosite:category-ads", "geosite:win-spy"], "outboundTag": "block"},
        {"protocol": ["bittorrent"], "outboundTag": "direct"},
        {"domain": ["geosite:private", "geosite:category-ru", "geosite:yandex", "geosite:vk", "geosite:microsoft", "geosite:apple"], "outboundTag": "direct"},
        {"ip": ["geoip:private", "geoip:ru"], "outboundTag": "direct"}
      ]
    },
    "inbounds": [
      {"tag": "socks-in", "protocol": "socks", "listen": "127.0.0.1", "port": 10808, "settings": {"udp": true}},
      {"tag": "http-in", "protocol": "http", "listen": "127.0.0.1", "port": 10809}
    ],
    "outbounds": [
      {
        "tag": "proxy",
        "protocol": "vless",
        "settings": {"vnext": [{"address": "$DOMAIN", "port": $ALT_PORT_1, "users": [{"id": "$UUID", "encryption": "none"}]}]},
        "streamSettings": {
          "network": "xhttp",
          "security": "reality",
          "xhttpSettings": {"mode": "auto", "path": "/$XHTTP_PATH"},
          "realitySettings": {"fingerprint": "chrome", "serverName": "$DOMAIN", "publicKey": "$PUBLIC_KEY", "shortId": "$SHORT_ID", "spiderX": "/"}
        }
      },
      {"tag": "direct", "protocol": "freedom"},
      {"tag": "block", "protocol": "blackhole"}
    ],
    "remarks": "VLESS-XHTTP-$ALT_PORT_1"
  }
]
SUBJSON

# HTML страница с конфигами
cat > "$WEB_PATH/${SUB_PATH}.html" <<HTMLPAGE
<!DOCTYPE html>
<html lang="ru">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="robots" content="noindex, nofollow">
<title>VPN Configs</title>
<style>
body { font-family: monospace; background: #0d1117; color: #c9d1d9; padding: 20px; max-width: 900px; margin: 0 auto; }
h2 { color: #58a6ff; border-bottom: 1px solid #30363d; padding-bottom: 10px; }
h3 { color: #7ee787; margin-top: 25px; }
.config-box { background: #161b22; border: 1px solid #30363d; border-radius: 8px; padding: 15px; margin: 10px 0; display: flex; align-items: center; gap: 10px; }
.config-text { flex: 1; overflow-x: auto; white-space: nowrap; color: #7ee787; font-size: 13px; }
.copy-btn { background: #21262d; color: #c9d1d9; border: 1px solid #30363d; padding: 10px 20px; border-radius: 6px; cursor: pointer; font-weight: bold; transition: all 0.2s; }
.copy-btn:hover { background: #7ee787; color: #0d1117; }
.info { background: #1f2937; border-left: 4px solid #58a6ff; padding: 15px; margin: 15px 0; border-radius: 0 8px 8px 0; }
.warning { background: #3d2c00; border-left: 4px solid #d29922; padding: 15px; margin: 15px 0; border-radius: 0 8px 8px 0; }
.btn-group { display: flex; flex-wrap: wrap; gap: 10px; margin: 15px 0; }
.btn { flex: 1; min-width: 200px; background: #21262d; color: #58a6ff; border: 1px solid #58a6ff; padding: 12px; text-align: center; border-radius: 8px; text-decoration: none; font-weight: bold; }
.btn:hover { background: #58a6ff; color: #0d1117; }
</style>
<script>
function copyText(id, btn) {
    const text = document.getElementById(id).innerText;
    navigator.clipboard.writeText(text).then(() => {
        btn.innerText = 'Скопировано!';
        btn.style.background = '#7ee787';
        btn.style.color = '#0d1117';
        setTimeout(() => { btn.innerText = 'Копировать'; btn.style.background = ''; btn.style.color = ''; }, 2000);
    });
}
</script>
</head>
<body>

<h2>🔐 VPN Конфигурации</h2>

<div class="warning">
<strong>⚠️ Важно:</strong> Если порт 443 заблокирован вашим провайдером, используйте конфиги на альтернативных портах ($ALT_PORT_1, $ALT_PORT_2, $ALT_PORT_3) или Shadowsocks.
</div>

<h3>📱 Ссылка на подписку (с роутингом РФ → напрямую)</h3>
<div class="config-box">
    <div class="config-text" id="sub">https://$DOMAIN/${SUB_PATH}.json</div>
    <button class="copy-btn" onclick="copyText('sub', this)">Копировать</button>
</div>

<div class="btn-group">
    <a href="happ://add/https://$DOMAIN/${SUB_PATH}.json" class="btn">⚡ Добавить в HAPP</a>
    <a href="https://www.happ.su/main/ru" target="_blank" class="btn">⬇️ Скачать HAPP</a>
</div>

<h3>🟢 VLESS XHTTP Reality — порт $ALT_PORT_1 (рекомендуется)</h3>
<div class="info">Современный транспорт, лучше обходит DPI. Используйте при проблемах с 443 портом.</div>
<div class="config-box">
    <div class="config-text" id="c1">$LINK_XHTTP</div>
    <button class="copy-btn" onclick="copyText('c1', this)">Копировать</button>
</div>

<h3>🔵 VLESS Reality — порт 443 (стандартный)</h3>
<div class="config-box">
    <div class="config-text" id="c2">$LINK_443</div>
    <button class="copy-btn" onclick="copyText('c2', this)">Копировать</button>
</div>

<h3>🟡 VLESS Reality — порт $ALT_PORT_2 (резервный)</h3>
<div class="config-box">
    <div class="config-text" id="c3">$LINK_ALT2</div>
    <button class="copy-btn" onclick="copyText('c3', this)">Копировать</button>
</div>

<h3>🟠 VLESS Reality — порт $ALT_PORT_3 (резервный, Firefox)</h3>
<div class="config-box">
    <div class="config-text" id="c4">$LINK_ALT3</div>
    <button class="copy-btn" onclick="copyText('c4', this)">Копировать</button>
</div>

<h3>⚫ Shadowsocks 2022 — порт $SS_PORT</h3>
<div class="info">Резервный протокол. Работает когда VLESS блокируется.</div>
<div class="config-box">
    <div class="config-text" id="c5">$LINK_SS</div>
    <button class="copy-btn" onclick="copyText('c5', this)">Копировать</button>
</div>

<h3>✈️ SOCKS5 Proxy (для Telegram)</h3>
<div class="config-box">
    <div class="config-text" id="c6">server=$DOMAIN port=10443 user=$SOCKS_USER pass=$SOCKS_PASS</div>
    <button class="copy-btn" onclick="copyText('c6', this)">Копировать</button>
</div>
<div class="btn-group">
    <a href="https://t.me/socks?server=$DOMAIN&port=10443&user=$SOCKS_USER&pass=$SOCKS_PASS" class="btn">✈️ Добавить в Telegram</a>
</div>

<h2 style="margin-top: 40px;">📲 Рекомендуемые приложения</h2>
<ul>
<li><strong>iOS/macOS:</strong> Happ, v2rayTun, FoXray</li>
<li><strong>Android:</strong> Happ, v2rayTun, v2rayNG</li>
<li><strong>Windows:</strong> Happ, v2rayN, Nekoray</li>
<li><strong>Linux:</strong> v2rayN, Nekoray</li>
</ul>

<h2 style="margin-top: 40px;">🛡️ При проблемах с подключением</h2>
<ol>
<li>Попробуйте другой порт (XHTTP на $ALT_PORT_1 или альтернативные)</li>
<li>Используйте Shadowsocks как резервный вариант</li>
<li>Смените приложение-клиент</li>
<li>Проверьте, не блокирует ли ваш провайдер конкретные порты</li>
</ol>

</body>
</html>
HTMLPAGE

log_success "Страницы конфигов созданы"

# =============================================================================
# Настройка firewall
# =============================================================================
log_info "Проверка firewall..."

if command -v ufw &> /dev/null; then
    ufw allow 80/tcp > /dev/null 2>&1
    ufw allow 443/tcp > /dev/null 2>&1
    ufw allow $ALT_PORT_1/tcp > /dev/null 2>&1
    ufw allow $ALT_PORT_2/tcp > /dev/null 2>&1
    ufw allow $ALT_PORT_3/tcp > /dev/null 2>&1
    ufw allow $SS_PORT/tcp > /dev/null 2>&1
    ufw allow $SS_PORT/udp > /dev/null 2>&1
    ufw allow 10443/tcp > /dev/null 2>&1
    log_success "UFW правила добавлены"
fi

# =============================================================================
# Настройка автообновления сертификата
# =============================================================================
log_info "Настройка автообновления сертификата..."

# Certbot уже настраивает cron/systemd timer автоматически
systemctl enable certbot.timer 2>/dev/null || true
log_success "Автообновление сертификата настроено"

# =============================================================================
# Включение BBR
# =============================================================================
log_info "Проверка TCP BBR..."

CURRENT_CC=$(sysctl net.ipv4.tcp_congestion_control 2>/dev/null | awk '{print $3}')
if [ "$CURRENT_CC" != "bbr" ]; then
    echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
    echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
    sysctl -p > /dev/null 2>&1
    log_success "BBR включен"
else
    log_success "BBR уже включен"
fi

# =============================================================================
# Финальный вывод
# =============================================================================
echo ""
echo "╔════════════════════════════════════════════════════════════════════════════╗"
echo "║                    ✅ УСТАНОВКА ЗАВЕРШЕНА УСПЕШНО!                        ║"
echo "╚════════════════════════════════════════════════════════════════════════════╝"
echo ""
echo -e "${GREEN}📄 Страница с конфигами:${NC}"
echo -e "   ${YELLOW}https://$DOMAIN/${SUB_PATH}.html${NC}"
echo ""
echo -e "${GREEN}📥 Ссылка на подписку (для Happ, v2rayN):${NC}"
echo -e "   ${YELLOW}https://$DOMAIN/${SUB_PATH}.json${NC}"
echo ""
echo "─────────────────────────────────────────────────────────────────────────────"
echo ""
echo -e "${BLUE}🔗 Конфиги для ручного добавления:${NC}"
echo ""
echo -e "${GREEN}VLESS XHTTP (порт $ALT_PORT_1) — рекомендуется:${NC}"
echo "$LINK_XHTTP"
echo ""
echo -e "${GREEN}VLESS Reality (порт 443):${NC}"
echo "$LINK_443"
echo ""
echo -e "${GREEN}VLESS Reality (порт $ALT_PORT_2):${NC}"
echo "$LINK_ALT2"
echo ""
echo -e "${GREEN}VLESS Reality (порт $ALT_PORT_3):${NC}"
echo "$LINK_ALT3"
echo ""
echo -e "${GREEN}Shadowsocks 2022 (порт $SS_PORT):${NC}"
echo "$LINK_SS"
echo ""
echo "─────────────────────────────────────────────────────────────────────────────"
echo ""
echo -e "${BLUE}📲 Приложения:${NC}"
echo "   iOS/macOS: Happ, v2rayTun"
echo "   Android: Happ, v2rayTun, v2rayNG"  
echo "   Windows: Happ, v2rayN, Nekoray"
echo ""
echo -e "${YELLOW}💡 Совет: Если порт 443 заблокирован — используйте XHTTP на порту $ALT_PORT_1${NC}"
echo ""
