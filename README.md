# 基于Wireguard技术的虚拟内网搭建自动化脚本


### 第一步：安装Wireguard 建议使用debian或ubuntu

```
#root权限（若以root方式登录则跳过）
sudo -i

#安装wireguard软件
apt update
apt install wireguard resolvconf wget nano -y

#开启IP转发
echo "net.ipv4.ip_forward = 1" >> /etc/sysctl.conf
sysctl -p
```

### 第二步：下载并使用脚本

```
#下载脚本
wget https://raw.githubusercontent.com/help660vip/wireguard/refs/heads/main/setup-wireguard.sh
#编辑脚本
nano setup-wireguard.sh
#填上自己想要的端口 服务器端地址 客户端数量后按ctrl+x 然后按y 随后回车
#使用脚本
chmod +x setup-wireguard.sh && bash setup-wireguard.sh
```

### 第三步：使用并开启开机自启动

```
#复制文件
cp $(pwd)/wireguard_setup/wg0.conf /etc/wiregurad/wg0.conf
#使用生成的服务端文件
wg-quick up wg0
#配置开机自启（非必要）
systemctl enable wg-quick@wg
```



