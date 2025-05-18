
#!/bin/bash
set -euo pipefail

# ─────────────── 预设默认值 ───────────────
DEFAULT_WG_IF="wg0"
WG_NETWORK="10.2.0.0/24"
WG_SERVER_IP="10.2.0.1"
WG_CONF_DIR="/etc/wireguard"
CLIENT_CONF_DIR="./wireguard_clients"

# 1. 必须 root 权限运行
if [ "$EUID" -ne 0 ]; then
  echo "错误：请使用 root 权限运行此脚本。" >&2
  exit 1
fi

# 2. 询问 WireGuard 接口名，默认 wg0
read -p "请输入 WireGuard 接口名称 [默认$DEFAULT_WG_IF]: " WG_IF
WG_IF=${WG_IF:-$DEFAULT_WG_IF}

# 3. 设置系统 DNS，备份旧 resolv.conf
if [ -f /etc/resolv.conf ]; then
  cp /etc/resolv.conf /etc/resolv.conf.bak.$(date +%s)
fi
echo "nameserver 223.5.5.5" > /etc/resolv.conf
echo "已设置系统 DNS 为 223.5.5.5"

# 4. 询问 WireGuard 监听端口，默认51820
read -p "请输入 WireGuard 监听端口 [默认51820]: " WG_PORT
WG_PORT=${WG_PORT:-51820}

# 5. 检查并启用 IPv4 转发（如果没启用）
CURRENT=$(sysctl -n net.ipv4.ip_forward)
if [ "$CURRENT" -ne 1 ]; then
  echo "检测到 IPv4 转发未启用，正在启用..."
  echo "net.ipv4.ip_forward=1" > /etc/sysctl.d/99-wireguard-forward.conf
  sysctl --system
else
  echo "IPv4 转发已启用。"
fi

# 6. 检测系统发行版 & 包管理器
if [ -f /etc/os-release ]; then
  . /etc/os-release
  DISTRO=$ID
else
  echo "错误：无法检测系统发行版。" >&2
  exit 1
fi

case "$DISTRO" in
  ubuntu|debian)
    PKG_MGR="apt"
    ;;
  centos|rhel|fedora)
    if command -v dnf &>/dev/null; then
      PKG_MGR="dnf"
    else
      PKG_MGR="yum"
    fi
    ;;
  *)
    echo "错误：不支持的发行版：$DISTRO" >&2
    exit 1
    ;;
esac

echo "使用包管理器：$PKG_MGR"

# 7. 安装必要软件
echo "安装 WireGuard 及相关工具..."
if [ "$PKG_MGR" = "apt" ]; then
  apt update
  apt install -y wireguard iproute2 iptables resolvconf qrencode curl
else
  $PKG_MGR install -y epel-release
  $PKG_MGR install -y wireguard-tools iproute iptables qrencode curl
fi

# 8. 获取默认出口网卡，去除可能的 @ 后缀
DEF_IF=$(ip route get 8.8.8.8 | awk '{print $5; exit}')
DEF_IF=${DEF_IF%@*}
echo "检测到默认出口网卡：$DEF_IF"

# 9. 创建配置目录
mkdir -p "$WG_CONF_DIR" "$CLIENT_CONF_DIR"
chmod 700 "$WG_CONF_DIR"

# 10. 生成服务器密钥对
SERVER_PRIV=$(wg genkey)
SERVER_PUB=$(echo "$SERVER_PRIV" | wg pubkey)

# 11. 询问是否使用当前公网地址作为 Endpoint
read -p "是否使用当前公网地址作为客户端 Endpoint？[Y/n]: " USE_CUR
USE_CUR=${USE_CUR:-Y}

if [[ "$USE_CUR" =~ ^[Yy]$ ]]; then
  DETECTED_IP=$(curl -4 -s ifconfig.me || echo "")
  if [ -z "$DETECTED_IP" ]; then
    echo "无法获取公网 IP，请手动输入。"
    read -p "请输入服务器公网地址或域名: " ENDPOINT
  else
    echo "检测到公网 IP：$DETECTED_IP"
    ENDPOINT="$DETECTED_IP"
  fi
else
  read -p "请输入服务器公网地址或域名: " ENDPOINT
fi

# 12. 写入服务器配置文件
cat > "$WG_CONF_DIR/$WG_IF.conf" <<EOF
[Interface]
Address = $WG_SERVER_IP/24
ListenPort = $WG_PORT
PrivateKey = $SERVER_PRIV
PostUp   = iptables -A FORWARD -i $WG_IF -j ACCEPT; iptables -A FORWARD -o $WG_IF -j ACCEPT; iptables -t nat -A POSTROUTING -o $DEF_IF -j MASQUERADE
PostDown = iptables -D FORWARD -i $WG_IF -j ACCEPT; iptables -D FORWARD -o $WG_IF -j ACCEPT; iptables -t nat -D POSTROUTING -o $DEF_IF -j MASQUERADE
EOF
chmod 600 "$WG_CONF_DIR/$WG_IF.conf"

# 13. 询问客户端数量
read -p "请输入要生成的客户端数量 [1]: " COUNT
COUNT=${COUNT:-1}

# 14. 循环生成客户端配置并追加到服务器配置
for i in $(seq 1 "$COUNT"); do
  NAME="client$i"
  BASE_IP=$(echo "$WG_NETWORK" | awk -F '.' '{print $1"."$2"."$3}')
  IP="$BASE_IP.$((i+1))"
  PRIV=$(wg genkey)
  PUB=$(echo "$PRIV" | wg pubkey)
  PSK=$(wg genpsk)

  cat > "$CLIENT_CONF_DIR/$NAME.conf" <<EOF
[Interface]
PrivateKey = $PRIV
Address     = $IP/24
DNS         = 223.5.5.5

[Peer]
PublicKey           = $SERVER_PUB
PresharedKey        = $PSK
Endpoint            = $ENDPOINT:$WG_PORT
AllowedIPs          = $WG_NETWORK
PersistentKeepalive = 25
EOF

  chmod 600 "$CLIENT_CONF_DIR/$NAME.conf"

  cat >> "$WG_CONF_DIR/$WG_IF.conf" <<EOF

[Peer]
PublicKey    = $PUB
PresharedKey = $PSK
AllowedIPs   = $IP/32
EOF
done

# 15. 启动 WireGuard 并设置开机自启
wg-quick down "$WG_IF" 2>/dev/null || true
wg-quick up "$WG_IF"
systemctl enable "wg-quick@$WG_IF"

echo "✔ WireGuard 安装与配置完成！"
echo "接口名称：$WG_IF"
echo "客户端配置文件保存在：$CLIENT_CONF_DIR"
