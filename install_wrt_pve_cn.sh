#!/bin/bash
# =============================================================================
# Script Name: install_wrt_pve_cn.sh
# Description: 一键安装 OpenWrt / ImmortalWrt 到 Proxmox VE（支持 LXC 和 VM）
# Author: EnjoyGoGoal
# Version: 1.0
# Updated: 2025-06-18
# License: MIT
# GitHub: https://github.com/EnjoyGoGoal
# =============================================================================

set -e

# ===== 默认配置 =====
LXC_ID=1001
DEFAULT_VM_ID=2001
CPUS=2
MEMORY=4096
ROOTFS_SIZE=2
DISK_SIZE="2G"
DEFAULT_BRIDGE="vmbr0"
DEFAULT_STORAGE="local"
CACHE_DIR="/var/lib/vz/template/cache"

# ===== 检查网络 =====
echo "[*] 检查网络连接..."
ping -c 1 -W 2 1.1.1.1 &>/dev/null || { echo "[✘] 无法连接互联网，请检查网络"; exit 1; }

# ===== 系统选择 =====
echo "请选择系统类型（默认 OpenWrt）:"
select OS_TYPE in "openwrt" "immortalwrt"; do
  OS_TYPE=${OS_TYPE:-"openwrt"}  # 默认选择 openwrt
  break
done

# ===== 获取最新版本 =====
get_latest_version() {
  local base_url
  [[ "$1" == "openwrt" ]] && base_url="https://downloads.openwrt.org/releases/"
  [[ "$1" == "immortalwrt" ]] && base_url="https://downloads.immortalwrt.org/releases/"
  curl -s "$base_url" | grep -oP '\d+\.\d+\.\d+(?=/)' | sort -Vr | head -n 1
}
VERSION=$(get_latest_version "$OS_TYPE")
echo "[✔] 最新版本为：$VERSION"

# ===== 类型选择 =====
echo "请选择创建类型（默认 LXC）:"
select CREATE_TYPE in "LXC" "VM"; do
  CREATE_TYPE=${CREATE_TYPE:-"LXC"}  # 默认选择 LXC
  break
done

# ===== 存储池选择 =====
echo "请选择存储池（默认 local）:"
select STORAGE in "local" "local-lvm" "other"; do
  STORAGE=${STORAGE:-"local"}  # 默认选择 local
  break
done

# ===== 网桥选择 =====
echo "请选择桥接网卡（默认 vmbr0）:"
AVAILABLE_BRIDGES=$(grep -o '^auto .*' /etc/network/interfaces | awk '{print $2}')
select BRIDGE in $AVAILABLE_BRIDGES "手动输入"; do
  [[ "$BRIDGE" == "手动输入" ]] && read -p "请输入网桥名称: " BRIDGE
  [[ -z "$BRIDGE" ]] && BRIDGE="$DEFAULT_BRIDGE"  # 默认选择 vmbr0
  break
done

# ===== 获取 VM ID =====
get_vm_id() {
  local vm_id=$DEFAULT_VM_ID
  read -p "[*] 请提供 VM ID（默认为 $vm_id）： " vm_id_input
  VM_ID=${vm_id_input:-$vm_id}
}
[[ "$CREATE_TYPE" == "VM" ]] && get_vm_id

# ===== 根据系统类型设置名称与描述 =====
if [[ "$CREATE_TYPE" == "VM" ]]; then
  [[ "$OS_TYPE" == "openwrt" ]] && VM_NAME="OpenWrt-${VERSION}" && VM_DESC="OpenWrt ${VERSION} 虚拟机"
  [[ "$OS_TYPE" == "immortalwrt" ]] && VM_NAME="ImmortalWrt-${VERSION}" && VM_DESC="ImmortalWrt ${VERSION} 虚拟机"
fi

# ===== 创建 LXC 或 VM =====
if [[ "$CREATE_TYPE" == "LXC" ]]; then
  FILE_NAME="${OS_TYPE}-${VERSION}-lxc.tar.gz"
  [[ "$OS_TYPE" == "openwrt" ]] && DL_URL="https://downloads.openwrt.org/releases/${VERSION}/targets/x86/64/openwrt-${VERSION}-x86-64-rootfs.tar.gz"
  [[ "$OS_TYPE" == "immortalwrt" ]] && DL_URL="https://downloads.immortalwrt.org/releases/${VERSION}/targets/x86/64/immortalwrt-${VERSION}-x86-64-rootfs.tar.gz"
  LOCAL_FILE="${CACHE_DIR}/${FILE_NAME}"

  mkdir -p "$CACHE_DIR"
  if [[ -f "$LOCAL_FILE" ]]; then
    echo "[✔] 镜像已存在：$LOCAL_FILE"
  else
    echo "[↓] 下载镜像..."
    wget -O "$LOCAL_FILE" "$DL_URL" || { echo "[✘] 下载失败"; exit 1; }
  fi

  read -p "请输入 LXC ID（默认 1001）: " user_lxc_id
  LXC_ID="${user_lxc_id:-1001}"

  if pct status "$LXC_ID" &>/dev/null; then
    echo "[!] LXC ID $LXC_ID 已存在，请手动处理或更换 ID"
    exit 1
  fi

  LXC_NAME="${OS_TYPE}-${VERSION}"

  echo "[*] 创建 LXC 容器..."
  pct create "$LXC_ID" "$LOCAL_FILE" \
    --hostname "$LXC_NAME" \
    --cores $CPUS \
    --memory $MEMORY \
    --swap 0 \
    --rootfs ${STORAGE}:${ROOTFS_SIZE} \
    --net0 name=eth0,bridge=$BRIDGE,ip=dhcp \
    --ostype unmanaged \
    --arch amd64 \
    --features nesting=1 \
    --unprivileged 0

  pct start "$LXC_ID"
  pct set "$LXC_ID" --onboot 1
  sleep 5
  IP=$(pct exec "$LXC_ID" -- ip -4 addr show eth0 | grep -oP '(?<=inet\s)\d+(\.\d+){3}' || true)
  echo "[✔] LXC 容器安装完成：ID=$LXC_ID, 名称=$LXC_NAME, IP=${IP:-获取失败}"

else
  cd /tmp
  IMG="${OS_TYPE}-${VERSION}-x86-64-generic-ext4-combined.img"
  IMG_GZ="${IMG}.gz"
  BASE_DOMAIN="$( [[ "$OS_TYPE" == "openwrt" ]] && echo "downloads.openwrt.org" || echo "downloads.immortalwrt.org" )"
  IMG_URL="https://${BASE_DOMAIN}/releases/${VERSION}/targets/x86/64/${IMG_GZ}"

  echo "[*] 清理旧镜像文件..."
  rm -f "$IMG_GZ" "$IMG"

  echo "[↓] 下载镜像..."
  wget --no-verbose --show-progress -O "$IMG_GZ" "$IMG_URL" || { echo "[✘] 镜像下载失败"; exit 1; }

  echo "[*] 解压镜像..."
  if gzip -df "$IMG_GZ" 2>&1 | grep -q "decompression OK"; then
    echo "[✔] 解压完成（忽略警告）"
  else
    echo "[✘] 解压失败"
    exit 1
  fi

  echo "[*] 删除旧 VM（如存在）..."
  qm destroy $VM_ID --purge >/dev/null 2>&1 || true

  echo "[*] 创建虚拟机..."
  qm create $VM_ID --name "$VM_NAME" --machine q35 --memory $MEMORY --cores $CPUS \
    --net0 virtio,bridge=$BRIDGE \
    --scsihw virtio-scsi-single \
    --cpu host --description "$VM_DESC"

  echo "[*] 导入磁盘..."
  qm importdisk $VM_ID "$IMG" $STORAGE --format qcow2
  DISK_NAME=$(ls /var/lib/pve/images/$VM_ID/ | grep vm-$VM_ID-disk | head -n 1)
  [[ -z "$DISK_NAME" ]] && DISK_NAME="vm-$VM_ID-disk-0.qcow2"

  echo "[*] 配置磁盘..."
  qm set $VM_ID --sata0 $STORAGE:$VM_ID/$DISK_NAME
  qm resize $VM_ID sata0 $DISK_SIZE
  qm set $VM_ID --boot order=sata0
  qm set $VM_ID --serial0 socket
  qm set $VM_ID --onboot 1
  qm start $VM_ID

  echo "[✔] $VM_NAME 安装完成 (ID: $VM_ID)"
  echo "[✔] 使用配置: CPU host, q35机型, VirtIO SCSI 控制器, SATA 接口"

  echo "[*] 验证 VM 配置:"
  qm config $VM_ID | grep -E "machine:|scsihw:|cpu:|sata0:|vga:|boot:|description:"

fi
