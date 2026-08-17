#!/usr/bin/env bash
set -Eeuo pipefail

DEFAULT_WG_IF="${DEFAULT_WG_IF:-wg0}"
WG_IF="${WG_IF:-}"
WG_PORT="${WG_PORT:-}"
WG_NETWORK="${WG_NETWORK:-10.2.0.0/24}"
WG_SERVER_IP="${WG_SERVER_IP:-10.2.0.1}"
WG_CONF_DIR="${WG_CONF_DIR:-/etc/wireguard}"
CLIENT_CONF_DIR="${CLIENT_CONF_DIR:-./wireguard_clients}"
CLIENT_DNS="${CLIENT_DNS:-223.5.5.5}"
CLIENT_ALLOWED_IPS="${CLIENT_ALLOWED_IPS:-}"
LAN_ALLOWED_IPS="${LAN_ALLOWED_IPS:-}"
WG_LAN_INTERFACES="${WG_LAN_INTERFACES:-}"
ENDPOINT="${ENDPOINT:-}"
USE_CURRENT_IP="${USE_CURRENT_IP:-}"
COUNT="${COUNT:-}"

log() { printf '%s\n' "$*"; }
die() { printf '错误：%s\n' "$*" >&2; exit 1; }

prompt_default() {
  local name="$1" message="$2" default="$3" value="${!1:-}"
  if [[ -z "$value" && -t 0 ]]; then
    read -r -p "$message [$default]: " value || true
  fi
  printf -v "$name" '%s' "${value:-$default}"
}

prompt_required() {
  local name="$1" message="$2" value="${!1:-}"
  while [[ -z "$value" && -t 0 ]]; do
    read -r -p "$message: " value || true
  done
  [[ -n "$value" ]] || die "$message"
  printf -v "$name" '%s' "$value"
}

normalize_interface_list() {
  local raw="${1//,/ }" interface seen=" "
  local -a entries=() normalized=()
  read -r -a entries <<< "$raw"
  for interface in "${entries[@]}"; do
    interface="${interface%@*}"
    [[ "$interface" =~ ^[a-zA-Z0-9_.-]{1,15}$ ]] || return 1
    if [[ "$seen" != *" $interface "* ]]; then
      normalized+=("$interface")
      seen+="$interface "
    fi
  done
  ((${#normalized[@]} > 0)) || return 1
  printf '%s\n' "${normalized[*]}"
}

default_route_interface() {
  ip -4 route show default 2>/dev/null |
    awk '/default/ { for (i=1; i<=NF; i++) if ($i=="dev") { print $(i+1); exit } }' |
    awk -F@ '{print $1}'
}

show_available_interfaces() {
  local default_interface="$1" interface addresses marker
  log "可用的 IPv4 网卡："
  while IFS= read -r interface; do
    interface="${interface%@*}"
    [[ "$interface" != "lo" && "$interface" != "$WG_IF" ]] || continue
    addresses=$(ip -o -4 addr show dev "$interface" scope global 2>/dev/null | awk '{print $4}' | paste -sd ',' -)
    [[ -n "$addresses" ]] || addresses="无全局 IPv4 地址"
    marker=""
    [[ "$interface" == "$default_interface" ]] && marker="（默认出口）"
    printf '  - %-15s %-24s %s\n' "$interface" "$addresses" "$marker"
  done < <(ip -o link show | awk -F': ' '{print $2}')
}

select_lan_interfaces() {
  local default_interface selected normalized interface
  default_interface=$(default_route_interface)
  selected="$WG_LAN_INTERFACES"
  if [[ -z "$selected" ]]; then
    if [[ -t 0 ]]; then
      show_available_interfaces "$default_interface"
      read -r -p "请输入需要访问的内网网卡，可用逗号或空格分隔: " selected || true
    fi
  fi
  if [[ -z "$selected" ]]; then
    LAN_INTERFACES=()
    log "未选择内网网卡；公网默认网卡不会添加 NAT 规则。"
    return
  fi
  normalized=$(normalize_interface_list "$selected") || die "WG_LAN_INTERFACES 格式无效"
  read -r -a LAN_INTERFACES <<< "$normalized"
  for interface in "${LAN_INTERFACES[@]}"; do
    [[ "$interface" != "$WG_IF" ]] || die "物理网卡不能与 WireGuard 接口同名：$interface"
    [[ "$interface" != "$default_interface" ]] || die "不能选择公网默认网卡 $interface；该网卡只承载 Endpoint，不做 NAT"
    ip link show dev "$interface" &>/dev/null || die "网卡不存在：$interface"
  done
  WG_LAN_INTERFACES=$(IFS=,; printf '%s' "${LAN_INTERFACES[*]}")
  log "WireGuard 只向以下内网网卡转发：$WG_LAN_INTERFACES"
}

configure_client_routes() {
  local interface route detected="" compact
  if [[ -z "$LAN_ALLOWED_IPS" ]]; then
    for interface in "${LAN_INTERFACES[@]}"; do
      while IFS= read -r route; do
        [[ -n "$route" ]] || continue
        detected+="${detected:+,}$route"
      done < <(ip -4 route show dev "$interface" scope link | awk '$1 ~ /^[0-9]+\./ {print $1}')
    done
  fi
  LAN_ALLOWED_IPS="${LAN_ALLOWED_IPS:-$detected}"
  if [[ -t 0 && ${#LAN_INTERFACES[@]} -gt 0 ]]; then
    prompt_default LAN_ALLOWED_IPS "请输入客户端需要访问的内网网段（逗号分隔）" "$LAN_ALLOWED_IPS"
  fi
  CLIENT_ALLOWED_IPS="${CLIENT_ALLOWED_IPS:-$WG_NETWORK${LAN_ALLOWED_IPS:+,$LAN_ALLOWED_IPS}}"
  compact="${CLIENT_ALLOWED_IPS//[[:space:]]/}"
  [[ ",$compact," != *,0.0.0.0/0,* ]] || die "仅内网模式不允许 CLIENT_ALLOWED_IPS 包含 0.0.0.0/0"
  log "客户端仅路由以下网段：$CLIENT_ALLOWED_IPS"
}

firewall_config_lines() {
  local wg_interface="$1" network="$2" interface
  shift 2
  printf 'PostUp = iptables -C FORWARD -i %s -j ACCEPT 2>/dev/null || iptables -A FORWARD -i %s -j ACCEPT\n' "$wg_interface" "$wg_interface"
  printf 'PostUp = iptables -C FORWARD -o %s -j ACCEPT 2>/dev/null || iptables -A FORWARD -o %s -j ACCEPT\n' "$wg_interface" "$wg_interface"
  for interface in "$@"; do
    printf 'PostUp = iptables -t nat -C POSTROUTING -s %s -o %s -j MASQUERADE 2>/dev/null || iptables -t nat -A POSTROUTING -s %s -o %s -j MASQUERADE\n' "$network" "$interface" "$network" "$interface"
  done
  printf 'PostDown = iptables -C FORWARD -i %s -j ACCEPT 2>/dev/null && iptables -D FORWARD -i %s -j ACCEPT || true\n' "$wg_interface" "$wg_interface"
  printf 'PostDown = iptables -C FORWARD -o %s -j ACCEPT 2>/dev/null && iptables -D FORWARD -o %s -j ACCEPT || true\n' "$wg_interface" "$wg_interface"
  for interface in "$@"; do
    printf 'PostDown = iptables -t nat -C POSTROUTING -s %s -o %s -j MASQUERADE 2>/dev/null && iptables -t nat -D POSTROUTING -s %s -o %s -j MASQUERADE || true\n' "$network" "$interface" "$network" "$interface"
  done
}

client_ip_for_index() {
  local network="$1" server="$2" wanted="$3"
  local base="${network%.*}" server_last="${server##*.}" last found=0
  for last in $(seq 1 254); do
    [[ "$last" -ne "$server_last" ]] || continue
    found=$((found + 1))
    if [[ "$found" -eq "$wanted" ]]; then
      printf '%s.%s\n' "$base" "$last"
      return
    fi
  done
  return 1
}

valid_ipv4() {
  local octet
  local -a octets=()
  IFS='.' read -r -a octets <<< "$1"
  ((${#octets[@]} == 4)) || return 1
  for octet in "${octets[@]}"; do
    [[ "$octet" =~ ^[0-9]+$ ]] || return 1
    ((10#$octet <= 255)) || return 1
  done
}

validate_configuration() {
  local network_address="${WG_NETWORK%/*}"
  [[ "$WG_IF" =~ ^[a-zA-Z0-9_.-]{1,15}$ ]] || die "WireGuard 接口名无效：$WG_IF"
  [[ "$WG_PORT" =~ ^[0-9]+$ ]] && ((WG_PORT >= 1 && WG_PORT <= 65535)) || die "监听端口必须在 1-65535 之间"
  [[ "$WG_NETWORK" =~ ^[^/]+/24$ ]] || die "当前版本仅支持 IPv4 /24 WireGuard 子网"
  valid_ipv4 "$network_address" || die "WireGuard 子网无效：$WG_NETWORK"
  valid_ipv4 "$WG_SERVER_IP" || die "WireGuard 服务端地址无效：$WG_SERVER_IP"
  [[ "${network_address##*.}" == 0 && "${network_address%.*}" == "${WG_SERVER_IP%.*}" ]] || die "WG_SERVER_IP 不在 WG_NETWORK 中"
  ((10#${WG_SERVER_IP##*.} >= 1 && 10#${WG_SERVER_IP##*.} <= 254)) || die "WG_SERVER_IP 不能是网络或广播地址"
  [[ "$COUNT" =~ ^[0-9]+$ ]] && ((COUNT >= 1 && COUNT <= 253)) || die "客户端数量必须在 1-253 之间"
}

install_dependencies() {
  [[ -r /etc/os-release ]] || die "无法检测系统发行版"
  . /etc/os-release
  case "$ID" in
    ubuntu|debian)
      apt-get update
      DEBIAN_FRONTEND=noninteractive apt-get install -y wireguard iproute2 iptables curl
      ;;
    centos|rhel|rocky|almalinux|ol|fedora)
      local manager="yum"
      command -v dnf &>/dev/null && manager="dnf"
      [[ "$ID" == fedora ]] || "$manager" install -y epel-release || true
      "$manager" install -y wireguard-tools iproute iptables curl
      ;;
    *) die "不支持的发行版：$ID" ;;
  esac
}

enable_ipv4_forwarding() {
  if [[ "$(sysctl -n net.ipv4.ip_forward)" != 1 ]]; then
    printf 'net.ipv4.ip_forward=1\n' > /etc/sysctl.d/99-wireguard-forward.conf
    sysctl -p /etc/sysctl.d/99-wireguard-forward.conf
  fi
}

resolve_endpoint() {
  local detected=""
  [[ -z "$ENDPOINT" ]] || return
  prompt_default USE_CURRENT_IP "是否自动检测当前公网 IPv4 作为客户端 Endpoint？[Y/n]" Y
  if [[ "$USE_CURRENT_IP" =~ ^[Yy]$ ]]; then
    detected=$(curl -4fsS --max-time 10 https://api.ipify.org 2>/dev/null || true)
    if [[ -n "$detected" ]]; then
      ENDPOINT="$detected"
      log "检测到公网 IP：$ENDPOINT"
      return
    fi
  fi
  prompt_required ENDPOINT "请输入服务器公网 IP 或域名"
}

stop_and_backup_existing() {
  local config="$WG_CONF_DIR/$WG_IF.conf"
  if ip link show dev "$WG_IF" &>/dev/null; then
    wg show "$WG_IF" &>/dev/null || die "接口 $WG_IF 已存在但不是 WireGuard 接口"
    wg-quick down "$WG_IF"
  fi
  if [[ -f "$config" ]]; then
    cp -a "$config" "$config.bak.$(date +%Y%m%d%H%M%S)"
    log "已备份现有配置：$config"
  fi
}

write_configuration() {
  local server_private="$1" server_public="$2"
  local config="$WG_CONF_DIR/$WG_IF.conf" network="${WG_NETWORK%/*}"
  local index name ip private public psk
  umask 077
  mkdir -p "$WG_CONF_DIR" "$CLIENT_CONF_DIR"
  chmod 700 "$WG_CONF_DIR" "$CLIENT_CONF_DIR"
  cat > "$config" <<EOF
[Interface]
Address = $WG_SERVER_IP/24
ListenPort = $WG_PORT
PrivateKey = $server_private
EOF
  firewall_config_lines "$WG_IF" "$WG_NETWORK" "${LAN_INTERFACES[@]}" >> "$config"
  for index in $(seq 1 "$COUNT"); do
    name="client$index"
    ip=$(client_ip_for_index "$network" "$WG_SERVER_IP" "$index") || die "WireGuard 子网地址不足"
    private=$(wg genkey)
    public=$(printf '%s' "$private" | wg pubkey)
    psk=$(wg genpsk)
    cat > "$CLIENT_CONF_DIR/$name.conf" <<EOF
[Interface]
PrivateKey = $private
Address = $ip/24
DNS = $CLIENT_DNS

[Peer]
PublicKey = $server_public
PresharedKey = $psk
Endpoint = $ENDPOINT:$WG_PORT
AllowedIPs = $CLIENT_ALLOWED_IPS
PersistentKeepalive = 25
EOF
    cat >> "$config" <<EOF

[Peer]
PublicKey = $public
PresharedKey = $psk
AllowedIPs = $ip/32
EOF
  done
  chmod 600 "$config" "$CLIENT_CONF_DIR"/*.conf
}

main() {
  local server_private server_public
  [[ "$EUID" -eq 0 ]] || die "请使用 root 权限运行此脚本"
  prompt_default WG_IF "请输入 WireGuard 接口名称" "$DEFAULT_WG_IF"
  prompt_default WG_PORT "请输入 WireGuard 监听端口" 51820
  prompt_default COUNT "请输入要生成的客户端数量" 1
  validate_configuration
  log "正在安装 WireGuard 及网络工具..."
  install_dependencies
  enable_ipv4_forwarding
  select_lan_interfaces
  configure_client_routes
  resolve_endpoint
  stop_and_backup_existing
  server_private=$(wg genkey)
  server_public=$(printf '%s' "$server_private" | wg pubkey)
  write_configuration "$server_private" "$server_public"
  wg-quick up "$WG_IF"
  systemctl enable "wg-quick@$WG_IF"
  log ""
  log "✔ WireGuard 安装与配置完成！"
  log "接口名称：$WG_IF"
  log "内网转发/NAT 网卡：${WG_LAN_INTERFACES:-无}"
  log "客户端路由：$CLIENT_ALLOWED_IPS"
  log "客户端配置目录：$CLIENT_CONF_DIR"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
