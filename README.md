# 基于wireguard的虚拟内网搭建自动化脚本
首先推荐debian11或更高 ubuntu20.04或更高使用

第一步：安装软件包

#切换到root用户（若已经是root用户则省略这一步）
sudo -i
#安装wireguard软件
apt install wireguard resolvconf -y

#开启IP转发
echo "net.ipv4.ip_forward = 1" >> /etc/sysctl.conf
sysctl -p

第二步：下载并使用脚本
