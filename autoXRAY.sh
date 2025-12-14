#!/bin/bash
# =============================================================================
# autoVPN-simple.sh - Простая установка VLESS Reality БЕЗ домена
# 
# Маскировка под популярные сайты (Microsoft, Yahoo, и т.д.)
# Не требует: домен, SSL сертификат, Nginx
# =============================================================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[OK]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# =============================================================================
# Проверка root
# =============================================================================
if [ "$EUID" -ne 0 ]; then
    log_error "Запустите от root: sudo bash autoVPN-simple.sh"
    exit 1
fi

echo ""
echo "╔══════════════════════════════════════════════════════════════════╗"
echo "║         autoVPN-simple - VLESS Reality без домена               ║"
echo "║                    Декабрь 2025                                  ║"
echo "╚══════════════════════════════════════════════════════════════════╝"
echo ""

# =============================================================================
# Получение IP сервера
# =============================================================================
log_info "Определение IP сервера..."

SERVER_IP=$(curl -s -4 ifconfig.me || curl -s -4 icanhazip.com || hostname -I | awk '{print $1}')

if [ -z "$SERVER_IP" ]; then
    log_error "Не удалось определить IP сервера"
    exit 1
fi

log_success "IP сервера: $SERVER_IP"

# =============================================================================
# Установка зависимостей
# =============================================================================
log_info "Обновление системы и установка зависимостей..."

apt update -qq
apt install -y curl wget jq > /dev/null 2>&1

log_success "Зависимости установлены"

# =============================================================================
# Установка Xray
# =============================================================================
log_info "Установка Xray..."

bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install > /dev/null 2>&1

log_success "Xray установлен"

# =============================================================================
# Генерация ключей
# =============================================================================
log_info "Генерация криптографических ключей..."

UUID=$(xray uuid)
KEYS=$(xray x25519)
PRIVATE_KEY=$(echo "$KEYS" | awk -F': ' '/Private/ {print $2}')
PUBLIC_KEY=$(echo "$KEYS" | awk -F': ' '/Public/ {print $2}')
SHORT_ID=$(openssl rand -hex 8)

# Shadowsocks пароль
SS_PASSWORD=$(openssl rand -base64 32)

log_success "Ключи сгенерированы"

# =============================================================================
# Выбор SNI для маскировки
# =============================================================================
# Популярные сайты которые хорошо работают для Reality
# Важно: сайт должен поддерживать TLS 1.3 и H2
SNI_LIST=(
    "www.microsoft.com"
    "www.yahoo.com"
    "www.apple.com"
    "www.samsung.com"
    "www.amd.com"
    "www.nvidia.com"
    "cdn.cloudflare.com"
    "www.asus.com"
    "www.logitech.com"
)

# Выбираем случайный SNI
SNI=${SNI_LIST[$RANDOM % ${#SNI_LIST[@]}]}

log_info "Выбран SNI для маскировки: $SNI"

# =============================================================================
# Порты
# =============================================================================
# Основной порт - 443 (стандартный HTTPS)
# Альтернативные порты на случай блокировки 443
PORT_MAIN=443
PORT_ALT1=8443
PORT_ALT2=2053
PORT_SS=2087

# =============================================================================
# Создание конфигурации Xray
# =============================================================================
log_info "Создание конфигурации Xray..."

mkdir -p /var/log/xray
mkdir -p /usr/local/etc/xray

cat > /usr/local/etc/xray/config.json <<EOF
{
  "log": {
    "loglevel": "warning",
    "access": "/var/log/xray/access.log",
    "error": "/var/log/xray/error.log"
  },
  "dns": {
    "servers": [
      "https+local://8.8.8.8/dns-query",
      "https+local://1.1.1.1/dns-query"
    ],
    "queryStrategy": "UseIPv4"
  },
  "inbounds": [
    {
      "tag": "vless-reality-main",
      "port": $PORT_MAIN,
      "listen": "0.0.0.0",
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "$UUID",
            "flow": "xtls-rprx-vision"
          }
        ],
        "decryption": "none"
      },
      "sniffing": {
        "enabled": true,
        "destOverride": ["http", "tls", "quic"]
      },
      "streamSettings": {
        "network": "tcp",
        "security": "reality",
        "realitySettings": {
          "show": false,
          "dest": "$SNI:443",
          "xver": 0,
          "serverNames": ["$SNI"],
          "privateKey": "$PRIVATE_KEY",
          "shortIds": ["$SHORT_ID"]
        }
      }
    },
    {
      "tag": "vless-reality-alt1",
      "port": $PORT_ALT1,
      "listen": "0.0.0.0",
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "$UUID",
            "flow": "xtls-rprx-vision"
          }
        ],
        "decryption": "none"
      },
      "sniffing": {
        "enabled": true,
        "destOverride": ["http", "tls", "quic"]
      },
      "streamSettings": {
        "network": "tcp",
        "security": "reality",
        "realitySettings": {
          "show": false,
          "dest": "$SNI:443",
          "xver": 0,
          "serverNames": ["$SNI"],
          "privateKey": "$PRIVATE_KEY",
          "shortIds": ["$SHORT_ID"]
        }
      }
    },
    {
      "tag": "vless-reality-alt2",
      "port": $PORT_ALT2,
      "listen": "0.0.0.0",
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "$UUID",
            "flow": "xtls-rprx-vision"
          }
        ],
        "decryption": "none"
      },
      "sniffing": {
        "enabled": true,
        "destOverride": ["http", "tls", "quic"]
      },
      "streamSettings": {
        "network": "tcp",
        "security": "reality",
        "realitySettings": {
          "show": false,
          "dest": "$SNI:443",
          "xver": 0,
          "serverNames": ["$SNI"],
          "privateKey": "$PRIVATE_KEY",
          "shortIds": ["$SHORT_ID"]
        }
      }
    },
    {
      "tag": "shadowsocks",
      "port": $PORT_SS,
      "listen": "0.0.0.0",
      "protocol": "shadowsocks",
      "settings": {
        "method": "2022-blake3-chacha20-poly1305",
        "password": "$SS_PASSWORD",
        "network": "tcp,udp"
      },
      "sniffing": {
        "enabled": true,
        "destOverride": ["http", "tls", "quic"]
      }
    }
  ],
  "outbounds": [
    {
      "tag": "direct",
      "protocol": "freedom",
      "settings": {
        "domainStrategy": "UseIPv4"
      }
    },
    {
      "tag": "block",
      "protocol": "blackhole"
    }
  ],
  "routing": {
    "domainStrategy": "IPIfNonMatch",
    "rules": [
      {
        "type": "field",
        "ip": ["geoip:private"],
        "outboundTag": "block"
      },
      {
        "type": "field",
        "protocol": ["bittorrent"],
        "outboundTag": "block"
      },
      {
        "type": "field",
        "domain": ["geosite:category-ads"],
        "outboundTag": "block"
      }
    ]
  }
}
EOF

log_success "Конфигурация создана"

# =============================================================================
# Запуск Xray
# =============================================================================
log_info "Запуск Xray..."

systemctl enable xray > /dev/null 2>&1
systemctl restart xray

# Проверка статуса
sleep 2
if systemctl is-active --quiet xray; then
    log_success "Xray запущен и работает"
else
    log_error "Ошибка запуска Xray"
    systemctl status xray
    exit 1
fi

# =============================================================================
# Настройка firewall (если установлен)
# =============================================================================
if command -v ufw &> /dev/null; then
    log_info "Настройка UFW..."
    ufw allow $PORT_MAIN/tcp > /dev/null 2>&1
    ufw allow $PORT_ALT1/tcp > /dev/null 2>&1
    ufw allow $PORT_ALT2/tcp > /dev/null 2>&1
    ufw allow $PORT_SS/tcp > /dev/null 2>&1
    ufw allow $PORT_SS/udp > /dev/null 2>&1
    log_success "Firewall настроен"
fi

# =============================================================================
# Включение BBR
# =============================================================================
log_info "Проверка TCP BBR..."

if ! grep -q "net.ipv4.tcp_congestion_control=bbr" /etc/sysctl.conf; then
    echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
    echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
    sysctl -p > /dev/null 2>&1
    log_success "BBR включен"
else
    log_success "BBR уже включен"
fi

# =============================================================================
# Генерация ссылок
# =============================================================================

# VLESS Reality ссылки
LINK_MAIN="vless://${UUID}@${SERVER_IP}:${PORT_MAIN}?security=reality&encryption=none&type=tcp&flow=xtls-rprx-vision&sni=${SNI}&fp=chrome&pbk=${PUBLIC_KEY}&sid=${SHORT_ID}#VPN-Reality-${PORT_MAIN}"

LINK_ALT1="vless://${UUID}@${SERVER_IP}:${PORT_ALT1}?security=reality&encryption=none&type=tcp&flow=xtls-rprx-vision&sni=${SNI}&fp=chrome&pbk=${PUBLIC_KEY}&sid=${SHORT_ID}#VPN-Reality-${PORT_ALT1}"

LINK_ALT2="vless://${UUID}@${SERVER_IP}:${PORT_ALT2}?security=reality&encryption=none&type=tcp&flow=xtls-rprx-vision&sni=${SNI}&fp=firefox&pbk=${PUBLIC_KEY}&sid=${SHORT_ID}#VPN-Reality-${PORT_ALT2}"

# Shadowsocks ссылка
SS_ENCODED=$(echo -n "2022-blake3-chacha20-poly1305:${SS_PASSWORD}" | base64 -w 0)
LINK_SS="ss://${SS_ENCODED}@${SERVER_IP}:${PORT_SS}#Shadowsocks-2022"

# =============================================================================
# Сохранение конфигов в файл
# =============================================================================
CONFIG_FILE="/root/vpn-configs.txt"

cat > "$CONFIG_FILE" <<EOF
═══════════════════════════════════════════════════════════════════════════════
                         VPN КОНФИГУРАЦИИ
                     Сервер: $SERVER_IP
                     SNI маскировка: $SNI
═══════════════════════════════════════════════════════════════════════════════

▶ VLESS Reality — порт $PORT_MAIN (основной):
$LINK_MAIN

▶ VLESS Reality — порт $PORT_ALT1 (резервный):
$LINK_ALT1

▶ VLESS Reality — порт $PORT_ALT2 (резервный):
$LINK_ALT2

▶ Shadowsocks 2022 — порт $PORT_SS (если VLESS блокируют):
$LINK_SS

═══════════════════════════════════════════════════════════════════════════════
                         ПАРАМЕТРЫ ДЛЯ РУЧНОЙ НАСТРОЙКИ
═══════════════════════════════════════════════════════════════════════════════

Адрес сервера: $SERVER_IP
UUID: $UUID
Public Key: $PUBLIC_KEY
Short ID: $SHORT_ID
SNI: $SNI
Flow: xtls-rprx-vision
Fingerprint: chrome

Shadowsocks:
  Метод: 2022-blake3-chacha20-poly1305
  Пароль: $SS_PASSWORD
  Порт: $PORT_SS

═══════════════════════════════════════════════════════════════════════════════
                         ПРИЛОЖЕНИЯ ДЛЯ ПОДКЛЮЧЕНИЯ
═══════════════════════════════════════════════════════════════════════════════

iOS/macOS: Happ, v2rayTun, FoXray, Shadowrocket
Android:   Happ, v2rayTun, v2rayNG, NekoBox
Windows:   Happ, v2rayN, Nekoray, Invisible Man
Linux:     v2rayN, Nekoray

═══════════════════════════════════════════════════════════════════════════════
                         ЕСЛИ НЕ РАБОТАЕТ
═══════════════════════════════════════════════════════════════════════════════

1. Попробуйте другой порт (8443 или 2053 вместо 443)
2. Используйте Shadowsocks — он часто работает когда VLESS блокируют
3. Смените приложение-клиент
4. Перезапустите скрипт для генерации нового SNI

Перезапуск Xray: systemctl restart xray
Просмотр логов:  journalctl -u xray -f
Этот файл:       cat /root/vpn-configs.txt

═══════════════════════════════════════════════════════════════════════════════
EOF

# =============================================================================
# Финальный вывод
# =============================================================================
echo ""
echo "╔══════════════════════════════════════════════════════════════════════════════╗"
echo "║                      ✅ УСТАНОВКА ЗАВЕРШЕНА!                                ║"
echo "╚══════════════════════════════════════════════════════════════════════════════╝"
echo ""
echo -e "${GREEN}Сервер:${NC} $SERVER_IP"
echo -e "${GREEN}Маскировка под:${NC} $SNI"
echo ""
echo "────────────────────────────────────────────────────────────────────────────────"
echo ""
echo -e "${YELLOW}▶ VLESS Reality — порт $PORT_MAIN (скопируйте в приложение):${NC}"
echo ""
echo -e "${GREEN}$LINK_MAIN${NC}"
echo ""
echo "────────────────────────────────────────────────────────────────────────────────"
echo ""
echo -e "${YELLOW}▶ VLESS Reality — порт $PORT_ALT1 (если 443 заблокирован):${NC}"
echo ""
echo -e "${GREEN}$LINK_ALT1${NC}"
echo ""
echo "────────────────────────────────────────────────────────────────────────────────"
echo ""
echo -e "${YELLOW}▶ VLESS Reality — порт $PORT_ALT2 (резервный):${NC}"
echo ""
echo -e "${GREEN}$LINK_ALT2${NC}"
echo ""
echo "────────────────────────────────────────────────────────────────────────────────"
echo ""
echo -e "${YELLOW}▶ Shadowsocks 2022 — порт $PORT_SS (резервный протокол):${NC}"
echo ""
echo -e "${GREEN}$LINK_SS${NC}"
echo ""
echo "────────────────────────────────────────────────────────────────────────────────"
echo ""
echo -e "${BLUE}📱 Как подключиться:${NC}"
echo "   1. Установите приложение: Happ, v2rayNG, v2rayN или Nekoray"
echo "   2. Скопируйте ссылку выше"
echo "   3. Добавьте конфиг в приложение (обычно кнопка + или 'импорт из буфера')"
echo "   4. Подключитесь!"
echo ""
echo -e "${BLUE}📄 Все конфиги сохранены в:${NC} /root/vpn-configs.txt"
echo ""
echo -e "${YELLOW}⚠️  Если порт 443 заблокирован — используйте порт $PORT_ALT1 или $PORT_ALT2${NC}"
echo ""
