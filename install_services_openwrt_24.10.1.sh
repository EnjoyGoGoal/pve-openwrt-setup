#!/bin/sh
set -e

echo "🛠️ 正在为 OpenWrt 24.10.1 安装 Tailscale、AdGuardHome、ZeroTier..."

# 更新软件源
echo "🔄 更新软件源并安装基础依赖..."
opkg update
opkg install curl wget ca-bundle ca-certificates iptables ip6tables kmod-tun kmod-ipt-nat kmod-ipt6tables kmod-ipt-core base-files bash libustream-mbedtls

# 安装 Tailscale
echo "🚀 安装 Tailscale..."
opkg install tailscale tailscaled
/etc/init.d/tailscaled enable
/etc/init.d/tailscaled start

echo "✅ Tailscale 安装完成！请手动运行以下命令进行登录："
echo "  tailscale up --accept-routes --advertise-exit-node"

# 安装 ZeroTier
echo "🌐 安装 ZeroTier..."
opkg install zerotier
/etc/init.d/zerotier enable
/etc/init.d/zerotier start

echo "✅ ZeroTier 启动完成。请登录 https://my.zerotier.com 绑定设备到你的网络。"

# 安装 AdGuardHome
echo "🧰 准备安装 AdGuardHome..."

AGH_VERSION=$(curl -s https://api.github.com/repos/AdguardTeam/AdGuardHome/releases/latest | grep tag_name | cut -d '"' -f 4)
AGH_URL="https://github.com/AdguardTeam/AdGuardHome/releases/download/${AGH_VERSION}/AdGuardHome_linux_amd64.tar.gz"

cd /tmp
wget -O agh.tar.gz "$AGH_URL"
tar -xzf agh.tar.gz
cd AdGuardHome
./AdGuardHome -s install

# 设置自启
/etc/init.d/AdGuardHome enable
/etc/init.d/AdGuardHome start

echo "✅ AdGuardHome 安装完成。默认管理页面地址为：http://<你的OpenWrt IP>:3000"

echo ""
echo "🎉 全部组件安装完成！"
echo "📌 后续建议："
echo " - 打开 http://<设备IP>:3000 设置 AdGuardHome"
echo " - 手动执行 tailscale up 登录 Tailscale"
echo " - 登录 ZeroTier 控制台绑定设备"
