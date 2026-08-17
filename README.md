<div align="center">

# ✨ WireGuard 一键部署脚本 ✨

一条 Bash 脚本完成 WireGuard 安装、服务端配置与多客户端生成。<br>
公网网卡只承载 WireGuard Endpoint，VPN 客户端仅访问指定内网。

[![Release](https://img.shields.io/github/v/release/help660vip/setup-wireguard?style=flat-square)](https://github.com/help660vip/setup-wireguard/releases)
[![Shell](https://img.shields.io/badge/Shell-Bash-4EAA25?style=flat-square&logo=gnu-bash&logoColor=white)](setup-wireguard.sh)
[![License](https://img.shields.io/badge/License-MIT-blue?style=flat-square)](#-许可证)

</div>

> [!IMPORTANT]
> 脚本会安装系统软件、启用 IPv4 转发、写入 `/etc/wireguard` 并管理 `wg-quick` 服务。请使用 `root` 权限运行，并确认云防火墙或安全组已放行所选 UDP 端口。

## 📖 支持情况

| 系统 / 能力 | 自动安装 | systemd 自启 | 内网网卡转发/NAT | 批量客户端 |
| --- | :---: | :---: | :---: | :---: |
| Debian 10+ / Ubuntu 18.04+ | ✅ | ✅ | ✅ | ✅ |
| CentOS 7+ / RHEL | ✅ | ✅ | ✅ | ✅ |
| Rocky / AlmaLinux / Oracle Linux | ✅ | ✅ | ✅ | ✅ |
| Fedora | ✅ | ✅ | ✅ | ✅ |

> 💡 双网卡场景中，默认路由所在的公网网卡只用于接收 WireGuard 连接，不添加 NAT；脚本仅对选中的内网网卡创建转发和 MASQUERADE 规则。

## 💿 安装

```bash
curl -O https://raw.githubusercontent.com/help660vip/setup-wireguard/main/setup-wireguard.sh
chmod +x setup-wireguard.sh
sudo ./setup-wireguard.sh
```

脚本会依次询问 WireGuard 接口名、监听端口、客户端数量、需要访问的内网网卡/网段以及公网 Endpoint。

## 🎈 特性

- 自动识别 Debian / Ubuntu / RHEL 系发行版并安装依赖
- 自动启用 IPv4 转发并配置 `wg-quick` 开机自启
- 自动识别公网默认网卡，但不在该网卡上添加 NAT
- 可选择一块或多块内网网卡，并自动识别其直连内网网段
- 仅为选中的内网网卡生成幂等的 iptables 转发与 NAT 规则
- 自动生成服务端密钥、客户端密钥和预共享密钥（PSK）
- 一次生成多个客户端配置，敏感文件权限默认设为 `600`
- 重新部署前自动停止现有接口并备份旧服务端配置
- 所有交互项都可通过环境变量传入，方便无人值守部署

## ⚙️ 配置

| 环境变量 | 说明 | 默认值 |
| --- | --- | --- |
| `WG_IF` | WireGuard 接口名称 | `wg0` |
| `WG_PORT` | WireGuard UDP 监听端口 | `51820` |
| `WG_NETWORK` | WireGuard IPv4 子网；当前支持 `/24` | `10.2.0.0/24` |
| `WG_SERVER_IP` | 服务端的 WireGuard 地址 | `10.2.0.1` |
| `WG_LAN_INTERFACES` | 需要访问的内网网卡，逗号或空格分隔 | 交互选择 |
| `LAN_ALLOWED_IPS` | 允许客户端访问的内网网段 | 从内网网卡自动识别 |
| `CLIENT_ALLOWED_IPS` | 完整客户端路由（高级覆盖项） | WireGuard 网段 + 内网网段 |
| `CLIENT_DNS` | 写入客户端配置的 DNS | `223.5.5.5` |
| `COUNT` | 生成的客户端数量 | `1` |
| `ENDPOINT` | 服务端公网 IP 或域名 | 自动检测公网 IPv4 |
| `USE_CURRENT_IP` | 是否自动检测公网 IP（`Y` / `n`） | `Y` |
| `WG_CONF_DIR` | 服务端配置目录 | `/etc/wireguard` |
| `CLIENT_CONF_DIR` | 客户端配置输出目录 | `./wireguard_clients` |

环境变量已设置时，脚本不会再次询问对应项目。

## 🎉 使用

### 交互式部署

```bash
sudo ./setup-wireguard.sh
```

选择网卡时可以输入多个名称：

```text
可用的 IPv4 网卡：
  - ens3            203.0.113.10/24          （默认出口）
  - ens4            192.168.10.2/24
请输入需要访问的内网网卡，可用逗号或空格分隔: ens4
```

### 双网卡：公网出口 + 内网访问

假设 `ens3` 是默认公网网卡，`ens4` 连接 `192.168.10.0/24` 内网。只指定 `ens4`：

```bash
sudo env \
  WG_LAN_INTERFACES="ens4" \
  LAN_ALLOWED_IPS="192.168.10.0/24" \
  ENDPOINT="vpn.example.com" \
  COUNT=3 \
  ./setup-wireguard.sh
```

生成的客户端 `AllowedIPs` 为 `10.2.0.0/24,192.168.10.0/24`。客户端只有这两个网段走 WireGuard，日常公网流量仍使用客户端自己的网络。

> [!NOTE]
> 公网默认网卡 `ens3` 不应加入 `WG_LAN_INTERFACES`，脚本也会拒绝该配置。若不填写 `LAN_ALLOWED_IPS`，脚本会从 `ens4` 的直连路由自动识别内网网段。

### 生成结果

| 内容 | 默认位置 |
| --- | --- |
| 服务端配置 | `/etc/wireguard/wg0.conf` |
| 客户端配置 | `./wireguard_clients/client1.conf`、`client2.conf`… |
| 旧服务端配置备份 | `/etc/wireguard/wg0.conf.bak.<时间>` |

部署完成后可检查状态：

```bash
sudo wg show
sudo systemctl status wg-quick@wg0
sudo iptables -t nat -S POSTROUTING
```

## ❓ 常见问题

### 客户端能握手，但无法访问内网

确认内网网卡出现在 `WG_LAN_INTERFACES` 中，并且目标内网网段包含在生成配置的 `AllowedIPs` 中。还需要检查服务器防火墙是否允许 `FORWARD` 链流量。

### 为什么客户端公网流量不经过 WireGuard

这是预期行为。本脚本采用仅内网模式，不生成 `0.0.0.0/0` 路由，也不会在服务器公网默认网卡上添加 NAT。

### 无法自动获取公网 IP

通过 `ENDPOINT="公网 IP 或域名"` 手动指定。若服务器位于路由器后方，还需把 WireGuard UDP 端口转发到服务器。

### 云服务器仍然无法连接

检查云平台安全组、系统防火墙和上级路由器是否已放行 `UDP/51820`（或自定义端口）。

## 📄 许可证

本项目采用 MIT 许可证。

---

如果脚本对你有帮助，欢迎 Star；问题和建议请提交 [Issue](https://github.com/help660vip/setup-wireguard/issues)。
