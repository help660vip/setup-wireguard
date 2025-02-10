#!/bin/bash

echo "本项目地址：https://github.com/help660vip/wireguard"
# 设置基础目录
BASE_DIR="$(pwd)/wireguard_setup"            # 创建的基础文件夹路径，位于当前目录下
SERVER_CONFIG="$BASE_DIR/wg0.conf"            # 服务器端的 WireGuard 配置文件路径
SERVER_PRIVATE_KEY_FILE="$BASE_DIR/server_privatekey"  # 服务器私钥文件
SERVER_PUBLIC_KEY_FILE="$BASE_DIR/server_publickey"    # 服务器公钥文件
CLIENTS_DIR="$BASE_DIR/clients"              # 客户端相关文件的根目录
KEYS_DIR="$CLIENTS_DIR/keys"                 # 存储客户端密钥的文件夹
CONFIGS_DIR="$CLIENTS_DIR/configs"           # 存储客户端配置文件的文件夹

# 创建文件夹结构
echo "创建文件夹结构..."
mkdir -p "$KEYS_DIR"
mkdir -p "$CONFIGS_DIR"

# 提示用户输入监听端口、公网IP和客户端数量
read -p "请输入服务器监听端口 (默认为 51820): " SERVER_LISTEN_PORT
SERVER_LISTEN_PORT=${SERVER_LISTEN_PORT:-51820}

read -p "请输入服务器的公网IP地址或经dns解析过的域名: " SERVER_PUBLIC_IP

# 客户端数量必须大于等于 1 且小于等于 253
while true; do
    read -p "请输入客户端数量 (默认为 50，最小 1，最大 253): " CLIENT_COUNT
    CLIENT_COUNT=${CLIENT_COUNT:-50}
    if [[ $CLIENT_COUNT -ge 1 && $CLIENT_COUNT -le 253 ]]; then
        break
    else
        echo "客户端数量必须大于等于 1 且小于等于 253，请重新输入。"
    fi
done

# 设置内网 IP 段
SUBNET="10.2.0.0/24"

# 生成服务器端密钥对
echo "生成服务器端密钥对..."
wg genkey | tee $SERVER_PRIVATE_KEY_FILE | wg pubkey > $SERVER_PUBLIC_KEY_FILE
SERVER_PRIVATE_KEY=$(cat $SERVER_PRIVATE_KEY_FILE)
SERVER_PUBLIC_KEY=$(cat $SERVER_PUBLIC_KEY_FILE)

# 创建并更新服务器配置文件
echo "生成并更新服务器配置文件 $SERVER_CONFIG..."
cat << EOF > $SERVER_CONFIG
[Interface]
Address = 10.2.0.1/24
PrivateKey = $SERVER_PRIVATE_KEY
ListenPort = $SERVER_LISTEN_PORT
EOF

# 清除旧的 [Peer] 配置部分（如果有的话）
echo "清除旧的服务器端 [Peer] 配置..."
sed -i '/^\[Peer\]/,$d' $SERVER_CONFIG

# 为每个客户端生成密钥对并生成配置文件
echo "为每个客户端生成密钥对和配置文件..."
for i in $(seq 1 $CLIENT_COUNT); do
  # 生成客户端密钥对
  CLIENT_PRIVATE_KEY_FILE="$KEYS_DIR/client${i}_privatekey"
  CLIENT_PUBLIC_KEY_FILE="$KEYS_DIR/client${i}_publickey"
  wg genkey | tee $CLIENT_PRIVATE_KEY_FILE | wg pubkey > $CLIENT_PUBLIC_KEY_FILE
  
  CLIENT_PRIVATE_KEY=$(cat $CLIENT_PRIVATE_KEY_FILE)
  CLIENT_PUBLIC_KEY=$(cat $CLIENT_PUBLIC_KEY_FILE)
  
  # 为每个客户端分配一个 /32 IP 地址
  CLIENT_IP="10.2.0.$((i + 1))"
  
  # 生成客户端配置文件
  CLIENT_CONFIG_FILE="$CONFIGS_DIR/client${i}_wg0.conf"
  cat << EOF > $CLIENT_CONFIG_FILE
[Interface]
Address = $CLIENT_IP/32
PrivateKey = $CLIENT_PRIVATE_KEY

[Peer]
PublicKey = $SERVER_PUBLIC_KEY
Endpoint = $SERVER_PUBLIC_IP:$SERVER_LISTEN_PORT
AllowedIPs = 10.2.0.0/24
PersistentKeepalive = 25
EOF
  
  # 更新服务器配置，添加客户端的 [Peer]
  cat << EOF >> $SERVER_CONFIG

[Peer]
PublicKey = $CLIENT_PUBLIC_KEY
AllowedIPs = $CLIENT_IP/32
EOF

  echo "客户端 ${i} 配置文件已生成: $CLIENT_CONFIG_FILE"
done

# 完成提示
echo "所有客户端配置文件已生成，服务器配置已更新。"
echo "所有文件保存在目录: $BASE_DIR"
