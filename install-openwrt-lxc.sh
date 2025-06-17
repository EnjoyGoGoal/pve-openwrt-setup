#!/bin/bash

CT_ID=1001
CT_NAME="openwrt-lxc"
STORAGE="local-lvm"
ROOTFS_SIZE="2G"
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
  --rootfs ${STORAGE}:${ROOTFS_SIZE} \
  --net0 name=eth0,bridge=$BRIDGE,ip=dhcp \
  --ostype unmanaged \
  --features nesting=1 \
  --unprivileged 1

pct start $CT_ID

echo "[✔] LXC 容器安装完成，正在配置组件..."

pct exec $CT_ID -- sh -c "opkg update && opkg install curl ca-bundle tailscale"

pct exec $CT_ID -- sh -c '
curl -s -L https://github.com/AdguardTeam/AdGuardHome/releases/latest/download/AdGuardHome_linux_amd64.tar.gz | tar xz -C /tmp &&
/tmp/AdGuardHome/AdGuardHome -s install
'

pct exec $CT_ID -- sh -c "
opkg update && opkg install zerotier
/etc/init.d/zerotier enable && /etc/init.d/zerotier start
"

echo "[✔] Tailscale、AdGuardHome、ZeroTier 安装完成"
