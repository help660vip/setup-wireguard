# WireGuard 自动安装与客户端配置脚本

本项目提供一键安装和配置 WireGuard 服务端及批量生成客户端配置的 Bash 脚本，适用于 Debian/Ubuntu、CentOS/RHEL/Fedora 系统。脚本可自动完成系统设置、软件安装、密钥生成、配置文件编写和服务启动等操作，大幅简化部署流程。

## 功能特性

* ​**自动化安装**​：检测系统发行版并调用对应包管理器（apt、dnf、yum）安装 WireGuard 及相关工具
* ​**系统配置**​：
  * 设置 DNS（默认为 223.5.5.5）
  * 启用 IPv4 转发
  * 备份原有 `/etc/resolv.conf`
* ​**密钥管理**​：自动生成服务器端和客户端的密钥对及预共享密钥（PSK）
* ​**配置生成**​：
  * 创建服务端配置（`/etc/wireguard/<iface>.conf`）
  * 批量生成客户端配置文件（`./wireguard_clients/clientX.conf`）
  * 自动添加 Peer 节点到服务端配置
* ​**网络设置**​：自动检测默认出口网卡并配置 iptables 转发与 NAT
* ​**服务管理**​：启动 WireGuard，并将 `wg-quick@<iface>` 服务设置为开机自启

## 环境要求

* ​**操作系统**​：
  * Debian 10+ / Ubuntu 18.04+
  * CentOS 7+ / RHEL 7+ / Fedora
* ​**权限**​：需以 `root` 用户或具备 `sudo` 权限执行脚本
* ​**依赖工具**​：
  * `bash`, `wg`, `iptables`, `iproute2`（或 `iproute`）
  * `curl`, `qrencode`, `resolvconf`

## 使用说明

1. ​**下载脚本**​：
   ```bash
   wget https://raw.githubusercontent.com/help660vip/wireguard/main/setup-wireguard.sh
   ```
2. ​**赋予执行权限**​：
   ```bash
   chmod +x setup_wireguard.sh
   ```
3. ​**运行脚本**​：
   ```bash
   sudo ./setup_wireguard.sh
   ```
4. ​**交互选项说明**​：
   * ​**WireGuard 接口名称**​：默认 `wg0`
   * ​**监听端口**​：默认 `51820`
   * ​**客户端数量**​：默认生成 1 个
   * ​**Endpoint 配置**​：可选择自动检测公网 IP 或手动输入域名/IP
5. ​**生成结果**​：
   * 服务端配置：`/etc/wireguard/<iface>.conf`
   * 客户端配置：`./wireguard_clients/client1.conf`、`client2.conf`…

## 示例

```bash
# 使用默认参数，一键部署
sudo ./setup_wireguard.sh

# 自定义接口名和客户端数量
sudo WG_IF=wg1 COUNT=3 ./setup_wireguard.sh
```

## 脚本参数（可选环境变量）

| 变量名            | 含义               | 默认值               |
| ------------------- | -------------------- | ---------------------- |
| WG\_IF            | WireGuard 接口名称 | wg0                  |
| WG\_PORT          | WireGuard 监听端口 | 51820                |
| WG\_NETWORK       | WireGuard 子网网段 | 10.2.0.0/24          |
| WG\_SERVER\_IP    | 服务端分配地址     | 10.2.0.1             |
| WG\_CONF\_DIR     | 服务端配置文件目录 | /etc/wireguard       |
| CLIENT\_CONF\_DIR | 客户端配置输出目录 | ./wireguard\_clients |

## 常见问题

* ​**无法获取公网 IP**​：脚本会提示手动输入 Endpoint
* ​**防火墙阻止 UDP**​：请确保服务器防火墙（如 `firewalld`、`ufw`）已放行 WireGuard 监听端口
* ​**IPv4 转发未生效**​：可手动检查 `/proc/sys/net/ipv4/ip_forward` 值，确认为 `1`

## 许可证

本项目遵循 MIT 许可证

---

> 若有问题或改进建议，欢迎提交 Issues 或 Pull Requests！
