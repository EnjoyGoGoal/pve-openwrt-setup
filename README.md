# Proxmox OpenWrt LXC 自动部署脚本

本脚本用于在 PVE 8.x 中快速部署 OpenWrt LXC 容器，基于官方 rootfs 构建，适用于测试 DNS、防火墙、Tailscale、AdGuardHome 等场景。

## ✅ 特性

- 自动下载最新 OpenWrt RootFS（默认版本：24.10.1）
- 创建特权 LXC 容器，支持全功能网络组件
- 开启 `nesting`，适配 Docker/Tailscale
- 支持 DHCP 自动获取 IP
- 开机自启设置

## 📦 使用方式

### 1. 下载脚本

```bash
git clone https://github.com/EnjoyGoGoal/openwrt-lxc-proxmox.git
cd openwrt-lxc-proxmox

或终端运行
curl -O https://raw.githubusercontent.com/EnjoyGoGoal/pve-openwrt-setup/main/install-openwrt-lxc.sh
bash ./install-openwrt-lxc.sh

启动openwrt后更改IP
然后更新软件
bash
opkg update
opkg list-upgradable | cut -f 1 -d ' ' | xargs opkg upgrade
opkg install luci-i18n-base-zh-cn
