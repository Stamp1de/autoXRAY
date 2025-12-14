#!/bin/bash
# =============================================================================
# autoVPN-simple.sh - VLESS Reality БЕЗ домена 1
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

if [ "$EUID" -ne 0 ]; then
    log_error "Запустите от root: sudo bash autoVPN-simple.sh"
    exit 1
fi

echo ""
echo "╔══════════════════════════════════════════════════════════════════╗"
echo "║         autoVPN-simple - VLESS Reality без домена               ║"
echo "╚══════════════════════════════════════════════════════════════════╝"
echo ""

# Получение IP
log_info "Определение IP сервера..."
SERVER_IP=$(curl -s -4 ifconfig.me || curl -s -4 icanhazip.com || hostname -I | awk '{print $1}')
if [ -z "$SERVER_IP" ]; then
    log_error "Не удалось определить IP"
    exit 1
fi
log_success "IP сервера: $SERVER_IP"

# Установка
log_info "Установка зависимостей..."
apt update -qq
apt install -y curl wget openssl > /dev/null 2>&1
log_success "Готово"

log_info "Установка Xray..."
bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install > /dev/null 2>&1
log_success "Xray установлен"

# Генерация ключей
log_info "Генерация ключей..."

UUID=$(xray uuid)

# Новый формат вывода xray x25519:
# PrivateKey: xxx
# Password: xxx (это публичный ключ для клиента!)
KEYS_OUTPUT=$(xray x25519)
PRIVATE_KEY=$(echo "$KEYS_OUTPUT" | grep "PrivateKey" | awk '{print $2}')
PUBLIC_KEY=$(echo "$KEYS_OUTPUT" | grep "Password" | awk '{print $2}')

# Проверка
if [ -z "$PRIVATE_KEY" ] || [ -z "$PUBLIC_KEY" ]; then
    log_error "Ошибка генерации ключей"
    echo "Output: $KEYS_OUTPUT"
    exit 1
fi

SHORT_ID=$(openssl rand -hex 8)
SS_PASSWORD=$(openssl rand -base64 32)

log_success "UUID: $UUID"
log_success "Private Key: $PRIVATE_KEY"
log_success "Public Key: $PUBLIC_KEY"
log_success "Short ID: $SHORT_ID"

# SNI для маскировки
SNI_LIST=("www.microsoft.com" "www.yahoo.com" "www.samsung.com" "www.amd.com" "www.nvidia.com" "www.logitech.com")
SNI=${SNI_LIST[$RANDOM % ${#SNI_LIST[@]}]}
log_info "SNI: $SNI"

# Порты
PORT_MAIN=443
PORT_ALT1=8443
PORT_ALT2=2053
PORT_SS=2087

# Конфиг Xray
log_info "Создание конфигурации..."

mkdir -p /var/log/xray

cat > /usr/local/etc/xray/config.json << XRAYEOF
{
  "log": {
    "loglevel": "warning"
  },
  "inbounds": [
    {
      "tag": "vless-${PORT_MAIN}",
      "port": ${PORT_MAIN},
      "protocol": "vless",
      "settings": {
        "clients": [{"id": "${UUID}", "flow": "xtls-rprx-vision"}],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "tcp",
        "security": "reality",
        "realitySettings": {
          "dest": "${SNI}:443",
          "serverNames": ["${SNI}"],
          "privateKey": "${PRIVATE_KEY}",
          "shortIds": ["${SHORT_ID}"]
        }
      },
      "sniffing": {"enabled": true, "destOverride": ["http", "tls"]}
    },
    {
      "tag": "vless-${PORT_ALT1}",
      "port": ${PORT_ALT1},
      "protocol": "vless",
      "settings": {
        "clients": [{"id": "${UUID}", "flow": "xtls-rprx-vision"}],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "tcp",
        "security": "reality",
        "realitySettings": {
          "dest": "${SNI}:443",
          "serverNames": ["${SNI}"],
          "privateKey": "${PRIVATE_KEY}",
          "shortIds": ["${SHORT_ID}"]
        }
      },
      "sniffing": {"enabled": true, "destOverride": ["http", "tls"]}
    },
    {
      "tag": "vless-${PORT_ALT2}",
      "port": ${PORT_ALT2},
      "protocol": "vless",
      "settings": {
        "clients": [{"id": "${UUID}", "flow": "xtls-rprx-vision"}],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "tcp",
        "security": "reality",
        "realitySettings": {
          "dest": "${SNI}:443",
          "serverNames": ["${SNI}"],
          "privateKey": "${PRIVATE_KEY}",
          "shortIds": ["${SHORT_ID}"]
        }
      },
      "sniffing": {"enabled": true, "destOverride": ["http", "tls"]}
    },
    {
      "tag": "shadowsocks",
      "port": ${PORT_SS},
      "protocol": "shadowsocks",
      "settings": {
        "method": "2022-blake3-chacha20-poly1305",
        "password": "${SS_PASSWORD}",
        "network": "tcp,udp"
      }
    }
  ],
  "outbounds": [
    {"tag": "direct", "protocol": "freedom"},
    {"tag": "block", "protocol": "blackhole"}
  ],
  "routing": {
    "rules": [
      {"type": "field", "ip": ["geoip:private"], "outboundTag": "block"},
      {"type": "field", "protocol": ["bittorrent"], "outboundTag": "block"}
    ]
  }
}
XRAYEOF

log_success "Конфиг создан"

# Запуск
log_info "Запуск Xray..."
systemctl enable xray > /dev/null 2>&1
systemctl restart xray

sleep 2
if systemctl is-active --quiet xray; then
    log_success "Xray работает"
else
    log_error "Ошибка запуска!"
    journalctl -u xray -n 20
    exit 1
fi

# Firewall
if command -v ufw &> /dev/null; then
    ufw allow ${PORT_MAIN}/tcp > /dev/null 2>&1
    ufw allow ${PORT_ALT1}/tcp > /dev/null 2>&1
    ufw allow ${PORT_ALT2}/tcp > /dev/null 2>&1
    ufw allow ${PORT_SS}/tcp > /dev/null 2>&1
    ufw allow ${PORT_SS}/udp > /dev/null 2>&1
fi

# BBR
if ! grep -q "tcp_congestion_control=bbr" /etc/sysctl.conf 2>/dev/null; then
    echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
    echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
    sysctl -p > /dev/null 2>&1
fi

# Ссылки
LINK_MAIN="vless://${UUID}@${SERVER_IP}:${PORT_MAIN}?security=reality&encryption=none&type=tcp&flow=xtls-rprx-vision&sni=${SNI}&fp=chrome&pbk=${PUBLIC_KEY}&sid=${SHORT_ID}#Reality-${PORT_MAIN}"

LINK_ALT1="vless://${UUID}@${SERVER_IP}:${PORT_ALT1}?security=reality&encryption=none&type=tcp&flow=xtls-rprx-vision&sni=${SNI}&fp=chrome&pbk=${PUBLIC_KEY}&sid=${SHORT_ID}#Reality-${PORT_ALT1}"

LINK_ALT2="vless://${UUID}@${SERVER_IP}:${PORT_ALT2}?security=reality&encryption=none&type=tcp&flow=xtls-rprx-vision&sni=${SNI}&fp=chrome&pbk=${PUBLIC_KEY}&sid=${SHORT_ID}#Reality-${PORT_ALT2}"

SS_ENC=$(echo -n "2022-blake3-chacha20-poly1305:${SS_PASSWORD}" | base64 -w 0)
LINK_SS="ss://${SS_ENC}@${SERVER_IP}:${PORT_SS}#SS2022"

# Сохранение
cat > /root/vpn-configs.txt << CONFIGEOF
══════════════════════════════════════════════════════════════
VPN CONFIGS - Server: ${SERVER_IP} | SNI: ${SNI}
══════════════════════════════════════════════════════════════

VLESS Reality (порт ${PORT_MAIN}):
${LINK_MAIN}

VLESS Reality (порт ${PORT_ALT1}):
${LINK_ALT1}

VLESS Reality (порт ${PORT_ALT2}):
${LINK_ALT2}

Shadowsocks 2022 (порт ${PORT_SS}):
${LINK_SS}

══════════════════════════════════════════════════════════════
РУЧНАЯ НАСТРОЙКА:
══════════════════════════════════════════════════════════════
Address: ${SERVER_IP}
UUID: ${UUID}
Public Key (pbk): ${PUBLIC_KEY}
Short ID (sid): ${SHORT_ID}
SNI: ${SNI}
Flow: xtls-rprx-vision
Fingerprint: chrome
Security: reality
Network: tcp
══════════════════════════════════════════════════════════════
CONFIGEOF

# Вывод
echo ""
echo "╔════════════════════════════════════════════════════════════════════╗"
echo "║                    ✅ УСТАНОВКА ЗАВЕРШЕНА!                        ║"
echo "╚════════════════════════════════════════════════════════════════════╝"
echo ""
echo -e "${GREEN}Сервер:${NC} ${SERVER_IP}"
echo -e "${GREEN}SNI:${NC} ${SNI}"
echo ""
echo "═══════════════════════════════════════════════════════════════════════"
echo -e "${YELLOW}VLESS Reality — порт ${PORT_MAIN}:${NC}"
echo ""
echo -e "${GREEN}${LINK_MAIN}${NC}"
echo ""
echo "═══════════════════════════════════════════════════════════════════════"
echo -e "${YELLOW}VLESS Reality — порт ${PORT_ALT1} (если 443 блокируют):${NC}"
echo ""
echo -e "${GREEN}${LINK_ALT1}${NC}"
echo ""
echo "═══════════════════════════════════════════════════════════════════════"
echo -e "${YELLOW}VLESS Reality — порт ${PORT_ALT2}:${NC}"
echo ""
echo -e "${GREEN}${LINK_ALT2}${NC}"
echo ""
echo "═══════════════════════════════════════════════════════════════════════"
echo -e "${YELLOW}Shadowsocks 2022 — порт ${PORT_SS}:${NC}"
echo ""
echo -e "${GREEN}${LINK_SS}${NC}"
echo ""
echo "═══════════════════════════════════════════════════════════════════════"
echo ""
echo -e "Конфиги сохранены: ${BLUE}/root/vpn-configs.txt${NC}"
echo ""
echo -e "${YELLOW}Приложения: v2rayNG, Happ, Nekoray, v2rayN${NC}"
echo ""
