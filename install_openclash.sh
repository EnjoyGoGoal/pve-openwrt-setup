#!/bin/bash

# 检查是否为 root 用户运行脚本
if [ "$(id -u)" -ne "0" ]; then
    echo "请使用 root 权限运行此脚本!"
    exit 1
fi

# 配置 OpenClash 的软件源（这里选择适合 x86 架构的版本）
echo "正在配置 OpenClash 软件源..."
echo "src/gz openwrt_clash https://github.com/vernesong/OpenClash/releases/download/1.7.0/openwrt-clash-1.7.0-x86_64.ipk" >> /etc/opkg/customfeeds.conf

# 更新软件源列表
echo "更新软件源列表..."
opkg update
echo "开始安装 OpenClash..."
# 安装 OpenClash 所需的依赖
echo "正在安装依赖..."
opkg install luci-app-openclash

# 启动 OpenClash 服务并设置开机启动
echo "正在启动 OpenClash 服务并设置为开机启动..."
/etc/init.d/openclash enable
/etc/init.d/openclash start

# 提示安装完成
echo "[✔] OpenClash 安装完成!"
echo "你可以通过 LuCI Web 界面访问配置 OpenClash。"
echo "访问地址: http://<你的路由器IP>/cgi-bin/luci"
echo "在 Web 界面中，你可以导入 Clash 配置文件或者手动配置。"
