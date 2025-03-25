# WireGuard 自动化部署脚本

本项目提供一个 Bash 脚本，能够快速生成 WireGuard 服务器和多个客户端的配置文件，简化 VPN 配置过程。

## 📌 功能特点
- 自动创建 WireGuard 服务器和客户端配置
- 支持用户自定义监听端口和公网 IP
- 一键生成服务器密钥对与客户端密钥对
- 支持最多 253 个客户端的批量配置
- 服务器配置文件自动更新，无需手动添加 Peer

## 📂 目录结构
```
wireguard_setup/
│── wg0.conf              # 服务器 WireGuard 配置文件
│── server_privatekey      # 服务器私钥
│── server_publickey       # 服务器公钥
│── clients/
│   ├── keys/              # 客户端密钥存储
│   │   ├── client1_privatekey
│   │   ├── client1_publickey
│   ├── configs/           # 客户端配置文件存储
│   │   ├── client1_wg0.conf
│   │   ├── client2_wg0.conf
```

## 🚀 使用方法
### 1. 安装 WireGuard
在运行脚本之前，请确保您的系统已安装 WireGuard。
#### Ubuntu/Debian:
```bash
sudo apt update && sudo apt install -y wireguard
```
#### CentOS:
```bash
sudo yum install -y epel-release
sudo yum install -y wireguard-tools
```
#### Arch Linux:
```bash
sudo pacman -S wireguard-tools
```
#### macOS (使用 Homebrew):
```bash
brew install wireguard-tools
```

### 2. 克隆仓库
```bash
git clone https://github.com/help660vip/wireguard.git
cd wireguard
chmod +x setup_wireguard.sh
```

### 3. 运行脚本
```bash
./setup_wireguard.sh
```

### 4. 配置过程中需要输入的信息
- **服务器监听端口**（默认为 `51820`）
- **服务器公网 IP 或域名**
- **客户端数量**（默认为 `50`，范围 `1-253`）

### 5. 启动 WireGuard 服务器
```bash
sudo wg-quick up wg0
```

### 6. 客户端连接
将 `clients/configs/clientX_wg0.conf` 文件导入 WireGuard 客户端即可。

## 🔧 其他功能
### 生成客户端二维码（适用于移动端）
安装 `qrencode` 后，可以使用以下命令生成二维码：
```bash
qrencode -t ansiutf8 < clients/configs/client1_wg0.conf
```

## ⚠️ 注意事项
- **请妥善保管私钥文件**，避免泄露。
- **确保 WireGuard 内核模块已安装**，否则需要手动安装 WireGuard。
- **客户端数量超过 253 可能导致 IP 地址冲突**，如有更大需求，可修改子网配置。

## 📜 许可证
本项目基于 MIT 许可证开源，欢迎修改和优化。

## 📞 反馈与支持
如有问题或建议，请访问 [GitHub 项目地址](https://github.com/help660vip/wireguard) 提交 Issue。

