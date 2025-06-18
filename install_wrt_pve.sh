#!/bin/bash
# =============================================================================
# Script Name: create_wrt_pve.sh
# Description: 一键安装 OpenWrt / ImmortalWrt 到 Proxmox VE（支持 LXC 和 VM）
# Version: 1.4
# Author: EnjoyGoGoal
# License: MIT
# =============================================================================

set -e

LXC_ID=1001
VM_ID=2001
VM_NAME="openwrt-vm"
CPUS=2
MEMORY=4096
ROOTFS_SIZE=2
DISK_SIZE="2G"
DEFAULT_BRIDGE="vmbr0"
CACHE_DIR="/var/lib/vz/template/cache"

echo "[*] 检查网络连接..."
ping -c 1 -W 2 1.1.1.1 &>/dev/null || { echo "[✘] 无法连接互联网"; exit 1; }

echo "请选择系统类型:"
select OS_TYPE in "openwrt" "immortalwrt"; do [[ -n "$OS_TYPE" ]] && break; done

get_latest_version() {
  local base_url
  [[ "$1" == "openwrt" ]] && base_url="https://downloads.openwrt.org/releases/"
  [[ "$1" == "immortalwrt" ]] && base_url="https://downloads.immortalwrt.org/releases/"
  curl -s "$base_url" | grep -oP '\d+\.\d+\.\d+(?=/)' | sort -Vr | head -n 1
}
VERSION=$(get_latest_version "$OS_TYPE")
echo "[✔] 最新版本为 $VERSION"

echo "请选择创建类型:"
select CREATE_TYPE in "LXC" "VM"; do [[ -n "$CREATE_TYPE" ]] && break; done

echo "请选择桥接网卡（默认 vmbr0）："
AVAILABLE_BRIDGES=$(grep -o '^auto .*' /etc/network/interfaces | awk '{print $2}')
select BRIDGE in $AVAILABLE_BRIDGES "手动输入"; do
  [[ "$BRIDGE" == "手动输入" ]] && read -p "请输入网桥名称: " BRIDGE
  [[ -z "$BRIDGE" ]] && BRIDGE="$DEFAULT_BRIDGE"
  break
done

echo "请选择存储位置："
STORES=$(pvesm status -content images | awk 'NR>1 {print $1}')
select STORAGE in $STORES "手动输入"; do
  [[ "$STORAGE" == "手动输入" ]] && read -p "请输入存储名称: " STORAGE
  [[ -n "$STORAGE" ]] && break
done

# === LXC 创建流程 ===
if [[ "$CREATE_TYPE" == "LXC" ]]; then
  FILE_NAME="${OS_TYPE}-${VERSION}-lxc.tar.gz"
  [[ "$OS_TYPE" == "openwrt" ]] && DL_URL="https://downloads.openwrt.org/releases/${VERSION}/targets/x86/64/openwrt-${VERSION}-x86-64-rootfs.tar.gz"
  [[ "$OS_TYPE" == "immortalwrt" ]] && DL_URL="https://downloads.immortalwrt.org/releases/${VERSION}/targets/x86/64/immortalwrt-${VERSION}-x86-64-rootfs.tar.gz"
  LOCAL_FILE="${CACHE_DIR}/${FILE_NAME}"

  mkdir -p "$CACHE_DIR"
  if [[ -f "$LOCAL_FILE" ]]; then
    echo "[✔] 使用本地缓存镜像：$LOCAL_FILE"
  else
    echo "[↓] 下载镜像..."
    wget -O "$LOCAL_FILE" "$DL_URL" || { echo "[✘] 下载失败"; exit 1; }
  fi

  if pct status $LXC_ID &>/dev/null; then
    echo "[!] LXC ID $LXC_ID 已存在，请更换 ID"
    exit 1
  fi

  echo "[*] 创建 LXC 容器..."
  pct create $LXC_ID "$LOCAL_FILE" \
    --hostname "${OS_TYPE}-lxc" \
    --cores $CPUS \
    --memory $MEMORY \
    --swap 0 \
    --rootfs ${STORAGE}:${ROOTFS_SIZE} \
    --net0 name=eth0,bridge=$BRIDGE,ip=dhcp \
    --ostype unmanaged \
    --arch amd64 \
    --features nesting=1 \
    --unprivileged 0 \
    --description "${OS_TYPE} ${VERSION}"

  pct start $LXC_ID
  pct set $LXC_ID --onboot 1
  sleep 5
  IP=$(pct exec $LXC_ID -- ip -4 addr show eth0 | grep -oP '(?<=inet\s)\d+(\.\d+){3}')
  echo "[✔] LXC 容器完成：ID=$LXC_ID, IP=$IP"

# === VM 创建流程 ===
else
  IMG="openwrt-${VERSION}-x86-64-generic-ext4-combined.img"
  [[ "$OS_TYPE" == "immortalwrt" ]] && IMG="immortalwrt-${VERSION}-x86-64-generic-ext4-combined.img"
  IMG_GZ="${IMG}.gz"
  BASE_DOMAIN="$( [[ "$OS_TYPE" == "openwrt" ]] && echo "downloads.openwrt.org" || echo "downloads.immortalwrt.org" )"
  IMG_URL="https://${BASE_DOMAIN}/releases/${VERSION}/targets/x86/64/${IMG_GZ}"

  cd /tmp
  rm -f "$IMG" "$IMG_GZ"

  echo "[↓] 下载镜像..."
  wget --no-verbose --show-progress -O "$IMG_GZ" "$IMG_URL" || { echo "[✘] 镜像下载失败"; exit 1; }

  echo "[*] 解压镜像..."
  gunzip -c "$IMG_GZ" > "$IMG" || { echo "[✘] 解压失败"; exit 1; }

  echo "[*] 创建 VM..."
  qm create $VM_ID \
    --name $VM_NAME \
    --description "${OS_TYPE} ${VERSION}" \
    --machine q35 \
    --memory $MEMORY \
    --cores $CPUS \
    --net0 virtio,bridge=$BRIDGE \
    --scsihw virtio-scsi-single

  echo "[*] 导入磁盘..."
  qm importdisk $VM_ID "$IMG" "$STORAGE" --format qcow2

  if [[ "$STORAGE" =~ local-lvm ]]; then
    DISK="scsi0"
    qm set $VM_ID --$DISK $STORAGE:vm-$VM_ID-disk-0
  else
    DISK="sata0"
    DISK_NAME=$(ls /var/lib/vz/images/$VM_ID/ | grep vm-$VM_ID-disk | head -n 1)
    qm set $VM_ID --$DISK $STORAGE:$VM_ID/$DISK_NAME
    qm resize $VM_ID $DISK $DISK_SIZE
  fi

  qm set $VM_ID --boot order=$DISK --serial0 socket --vga serial0
  qm start $VM_ID

  echo "[✔] VM 创建完成: ID=$VM_ID"
  echo "[✔] 配置验证:"
  qm config $VM_ID | grep -E "machine:|scsihw:|${DISK}:|boot:|description:"

  cat << EOF

下一步建议：
1. 登录系统后安装 OpenClash：
   opkg update
   opkg install curl bash unzip iptables ipset coreutils-nohup luci luci-compat dnsmasq-full
   cd /tmp
   wget https://github.com/vernesong/OpenClash/releases/download/v0.45.128-beta/luci-app-openclash_0.45.128-beta_all.ipk
   opkg install ./luci-app-openclash_0.45.128-beta_all.ipk

2. 安装 clash 核心：
   mkdir -p /etc/openclash
   curl -Lo /etc/openclash/clash.tar.gz https://cdn.jsdelivr.net/gh/vernesong/OpenClash@master/core/clash-linux-amd64.tar.gz
   tar -xzf /etc/openclash/clash.tar.gz -C /etc/openclash && rm /etc/openclash/clash.tar.gz
   /etc/init.d/openclash enable
   /etc/init.d/openclash start

EOF

fi
