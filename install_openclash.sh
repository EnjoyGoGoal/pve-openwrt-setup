#!/bin/bash

# 检查是否为 root 用户运行脚本
if [ "$(id -u)" -ne "0" ]; then
    echo "请使用 root 权限运行此脚本!"
    exit 1
fi

# 更新软件源列表
echo "正在更新软件源..."
opkg update

# 安装 OpenClash 依赖
echo "正在安装 luci-app-openclash..."
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
