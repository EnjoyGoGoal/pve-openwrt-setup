#!/bin/bash

CT_ID=1001
CT_NAME="openwrt-lxc"
STORAGE="local"
ROOTFS_SIZE="2"
MEMORY="4096"
CPUS="2"
BRIDGE="vmbr0"
OPENWRT_VERSION="24.10.1"
ROOTFS_URL="https://downloads.openwrt.org/releases/${OPENWRT_VERSION}/targets/x86/64/openwrt-${OPENWRT_VERSION}-x86-64-rootfs.tar.gz"
TEMPLATE="/var/lib/vz/template/cache/openwrt-rootfs-${OPENWRT_VERSION}.tar.gz"

# 检查容器是否存在
if pct status $CT_ID &>/dev/null; then
  echo "[!] 容器 $CT_ID 已存在，请先删除或更换 CT_ID"
  exit 1
fi

# 下载 rootfs
mkdir -p $(dirname $TEMPLATE)
wget -O $TEMPLATE $ROOTFS_URL
if [ $? -ne 0 ]; then
  echo "[✘] RootFS 下载失败，请检查网络或 URL 是否有效。"
  exit 1
fi

# 创建容器
pct create $CT_ID $TEMPLATE \
  --hostname $CT_NAME \
  --cores $CPUS \
  --memory $MEMORY \
  --swap 0 \
  --roo
