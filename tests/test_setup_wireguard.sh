#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source "$ROOT_DIR/setup-wireguard.sh"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_equal() {
  [[ "$2" == "$1" ]] || fail "$3 (expected: $1, actual: $2)"
}

assert_contains() {
  [[ "$1" == *"$2"* ]] || fail "$3 (missing: $2)"
}

normalized=$(normalize_interface_list 'ens3, ens4 ens3 eth0@if5')
assert_equal 'ens3 ens4 eth0' "$normalized" 'interface list normalization'

if normalize_interface_list 'ens3;reboot' >/dev/null 2>&1; then
  fail 'unsafe interface names must be rejected'
fi

rules=$(firewall_config_lines wg0 10.2.0.0/24 ens4)
assert_contains "$rules" 'POSTROUTING -s 10.2.0.0/24 -o ens4 -j MASQUERADE' 'LAN NAT rule'
if [[ "$rules" == *'-o ens3 '* ]]; then
  fail 'public interface must not receive NAT rules'
fi
assert_equal 3 "$(grep -c '^PostUp' <<< "$rules")" 'PostUp rule count'
assert_equal 3 "$(grep -c '^PostDown' <<< "$rules")" 'PostDown rule count'

ip() {
  [[ "$*" == '-4 route show dev ens4 scope link' ]] || return 1
  printf '192.168.10.0/24 proto kernel scope link src 192.168.10.2\n'
}
LAN_INTERFACES=(ens4)
LAN_ALLOWED_IPS=''
CLIENT_ALLOWED_IPS=''
configure_client_routes >/dev/null
assert_equal '10.2.0.0/24,192.168.10.0/24' "$CLIENT_ALLOWED_IPS" 'client routes must only contain VPN and LAN networks'

if (
  LAN_INTERFACES=()
  CLIENT_ALLOWED_IPS='10.2.0.0/24, 0.0.0.0/0'
  configure_client_routes >/dev/null 2>&1
); then
  fail 'full-tunnel client routes must be rejected'
fi

TEST_TMP=$(mktemp -d)
trap 'rm -rf -- "$TEST_TMP"' EXIT
wg() {
  case "$1" in
    genkey) printf 'client-private\n' ;;
    pubkey) cat >/dev/null; printf 'client-public\n' ;;
    genpsk) printf 'client-psk\n' ;;
    *) return 1 ;;
  esac
}
WG_CONF_DIR="$TEST_TMP/server"
CLIENT_CONF_DIR="$TEST_TMP/clients"
WG_IF=wg0
WG_PORT=51820
WG_SERVER_IP=10.2.0.1
COUNT=1
ENDPOINT=vpn.example.com
LAN_INTERFACES=(ens4)
write_configuration server-private server-public
server_config=$(<"$WG_CONF_DIR/wg0.conf")
client_config=$(<"$CLIENT_CONF_DIR/client1.conf")
assert_contains "$server_config" '-o ens4 -j MASQUERADE' 'generated server config must NAT the LAN interface'
if [[ "$server_config" == *'-o ens3 '* ]]; then
  fail 'generated server config must leave the public interface untouched'
fi
assert_contains "$client_config" 'AllowedIPs = 10.2.0.0/24,192.168.10.0/24' 'generated client config must only route VPN and LAN networks'

assert_equal 10.2.0.2 "$(client_ip_for_index 10.2.0.0 10.2.0.1 1)" 'default first client address'
assert_equal 10.2.0.1 "$(client_ip_for_index 10.2.0.0 10.2.0.2 1)" 'custom server address skip'
assert_equal 10.2.0.3 "$(client_ip_for_index 10.2.0.0 10.2.0.2 2)" 'address allocation continuation'

valid_ipv4 192.168.1.1 || fail 'valid IPv4 address rejected'
if valid_ipv4 192.168.1.999; then
  fail 'invalid IPv4 address accepted'
fi

printf 'PASS: setup-wireguard helper tests\n'
