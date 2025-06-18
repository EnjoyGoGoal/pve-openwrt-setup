#!/bin/bash
# =============================================================================
# Script Name: create_wrt_pve.sh
# Description: 一键安装 OpenWrt / ImmortalWrt 到 Proxmox VE（支持 LXC 和 VM）
# Author: EnjoyGoGoal
# Version: 1.4
# Updated: 2025-06-18
# License: MIT
# GitHub: https://github.com/EnjoyGoGoal
# =============================================================================

set -e

# ===== 默认配置 =====
LXC_ID=1001
DEFAULT_VM_ID=2001
CPUS=2
MEMORY=1024
ROOTFS_SIZE=2
DISK_SIZE="2G"
DEFAULT_BRIDGE="vmbr0"
CACHE_DIR="/var/lib/vz/template/cache"

# ===== 检查网络连接 =====
echo "[*] 检查网络连接..."
ping -c 1 -W 2 1.1.1.1 &>/dev/null || { echo "[✘] 无法连接互联网，请检查网络"; exit 1; }

# ===== 选择系统类型 =====
echo "请选择系统类型:"
select OS_TYPE in "openwrt" "immortalwrt"; do [[ -n "$OS_TYPE" ]] && break; done

# ===== 获取最新版本 =====
get_latest_version() {
  local base_url
  [[ "$1" == "openwrt" ]] && base_url="https://downloads.openwrt.org/releases/"
  [[ "$1" == "immortalwrt" ]] && base_url="https://downloads.immortalwrt.org/releases/"
  curl -s "$base_url" | grep -oP '\d+\.\d+\.\d+(?=/)' | sort -Vr | head -n 1
}
VERSION=$(get_latest_version "$OS_TYPE")
echo "[✔] 最新版本为：$VERSION"

# ===== 选择创建类型 =====
echo "请选择创建类型:"
select CREATE_TYPE in "LXC" "VM"; do [[ -n "$CREATE_TYPE" ]] && break; done

# ===== 选择桥接网卡 =====
echo "请选择桥接网卡（默认 vmbr0）："
AVAILABLE_BRIDGES=$(grep -o '^auto .*' /etc/network/interfaces | awk '{print $2}')
select BRIDGE in $AVAILABLE_BRIDGES "手动输入"; do
  [[ "$BRIDGE" == "手动输入" ]] && read -p "请输入网桥名称: " BRIDGE
  [[ -z "$BRIDGE" ]] && BRIDGE="$DEFAULT_BRIDGE"
  break
done

# ===== 存储选择 =====
echo "请选择存储位置："
STORES=$(pvesm status -content images | awk 'NR>1 {print $1}')
select STORAGE in $STORES "手动输入"; do
  [[ "$STORAGE" == "手动输入" ]] && read -p "请输入存储名称: " STORAGE
  [[ -n "$STORAGE" ]] && break
done

# ===== 获取 VM ID =====
get_vm_id() {
  local vm_id=$DEFAULT_VM_ID
  if qm status $vm_id >/dev/null 2>&1; then
    read -p "[!] 默认 VM ID $vm_id 已存在，是否继续使用？[Y/n]: " choice
    case "$choice" in
      n|N)
        while true; do
          read -p "请输入新的 VM ID（100-999）: " vm_id
          if [[ "$vm_id" =~ ^[1-9][0-9]{2}$ ]] && ! qm status "$vm_id" &>/dev/null; then
            VM_ID=$vm_id
            break
          else
            echo "[!] 无效或已存在的 VM ID"
          fi
        done
        ;;
      *)
        VM_ID=$vm_id
        ;;
    esac
  else
    VM_ID=$vm_id
  fi
}
[[ "$CREATE_TYPE" == "VM" ]] && get_vm_id

# ===== 创建 LXC 容器 =====
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

  if pct status $LXC_ID &>/dev/null; then
    echo "[!] LXC ID $LXC_ID 已存在，请手动处理或更换 ID"
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
    --unprivileged 0

  pct start $LXC_ID
  pct set $LXC_ID --onboot 1
  sleep 5
  IP=$(pct exec $LXC_ID -- ip -4 addr show eth0 | grep -oP '(?<=inet\s)\d+(\.\d+){3}' || true)
  echo "[✔] LXC 容器安装完成：ID=$LXC_ID, IP=${IP:-获取失败}"

# ===== 创建 VM =====
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
  gzip -d "$IMG_GZ" || { echo "[✘] 解压失败"; exit 1; }

  VM_NAME="${OS_TYPE}-vm-${VERSION//./-}"
  echo "[*] 创建 VM..."
  qm create $VM_ID \
    --name "$VM_NAME" \
    --description "Auto created $OS_TYPE $VERSION" \
    --machine q35 \
    --cpu host \
    --memory $MEMORY \
    --cores $CPUS \
    --net0 virtio,bridge=$BRIDGE \
    --scsihw virtio-scsi-pci

  echo "[*] 导入磁盘..."
  qm importdisk $VM_ID "$IMG" $STORAGE --format qcow2
  DISK_NAME=$(ls /var/lib/pve/images/$VM_ID/ | grep -E 'vm-[0-9]+-disk.*\.qcow2' | head -n 1)

  echo "[*] 配置磁盘启动..."
  qm set $VM_ID --sata0 $STORAGE:vm-$VM_ID-disk-0.qcow2
  qm resize $VM_ID sata0 $DISK_SIZE
  qm set $VM_ID --boot order=sata0
  qm set $VM_ID --serial0 socket --vga serial0
  qm set $VM_ID --onboot 1
  qm start $VM_ID

  echo "[✔] OpenWrt 虚拟机创建完成 (ID: $VM_ID)"
  qm config $VM_ID | grep -E "name|cpu|scsihw|boot|sata0|vga"
fi
