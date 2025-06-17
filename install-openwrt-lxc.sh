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

mkdir -p $(dirname $TEMPLATE)
wget -O $TEMPLATE $ROOTFS_URL

pct create $CT_ID $TEMPLATE \
  --hostname $CT_NAME \
  --cores $CPUS \
  --memory $MEMORY \
  --swap 0 \
  --rootfs ${STORAGE}:${ROOTFS_SIZE} \
  --net0 name=eth0,bridge=$BRIDGE,ip=dhcp \
  --ostype unmanaged \
  --arch amd64 \
  --features nesting=1 \
  --unprivileged 0

pct start $CT_ID

echo "[✔] OpenWrt ${OPENWRT_VERSION} LXC 容器安装完成。"
