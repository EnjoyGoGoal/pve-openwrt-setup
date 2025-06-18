#!/bin/bash
#!/bin/bash
# =============================================================================
# Script Name: create_wrt_pve.sh
# Description: 一键安装 OpenWrt / ImmortalWrt 到 Proxmox VE（支持 LXC 和 VM）
# Author: EnjoyGoGoal
# Created: 2025-06-18
# Version: 1.0
# License: MIT
# GitHub: https://github.com/EnjoyGoGoal
#
# ✅ 功能说明:
#   - 自动检测网络
#   - 自动获取最新版本
#   - 自动下载 rootfs 或镜像文件
#   - 支持手动选择桥接网卡、存储、系统类型、创建类型
#   - 支持 VM 和 LXC 自动部署
# =============================================================================

set -e

# ===== 默认配置 =====
LXC_ID=1001
VM_ID=2001
CPUS=2
MEMORY=4096
ROOTFS_SIZE=2
DEFAULT_BRIDGE="vmbr0"
CACHE_DIR="/var/lib/vz/template/cache"

# ===== 检查联网状态 =====
echo "[*] 正在检测网络连接..."
ping -c 1 -W 2 1.1.1.1 &>/dev/null || { echo "[✘] 无法连接互联网，请检查网络！"; exit 1; }

# ===== 选择系统类型 =====
echo "请选择系统类型:"
select OS_TYPE in "openwrt" "immortalwrt"; do [[ -n "$OS_TYPE" ]] && break; done

# ===== 获取最新版版本号 =====
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

# ===== 获取 rootfs 下载链接与本地路径 =====
if [[ "$CREATE_TYPE" == "LXC" ]]; then
  FILE_NAME="${OS_TYPE}-${VERSION}-lxc.tar.gz"
  [[ "$OS_TYPE" == "openwrt" ]] && DL_URL="https://downloads.openwrt.org/releases/${VERSION}/targets/x86/64/openwrt-${VERSION}-x86-64-rootfs.tar.gz"
  [[ "$OS_TYPE" == "immortalwrt" ]] && DL_URL="https://downloads.immortalwrt.org/releases/${VERSION}/targets/x86/64/immortalwrt-${VERSION}-x86-64-rootfs.tar.gz"
else
  FILE_NAME="${OS_TYPE}-${VERSION}-vm.img.gz"
  [[ "$OS_TYPE" == "openwrt" ]] && DL_URL="https://downloads.openwrt.org/releases/${VERSION}/targets/x86/64/openwrt-${VERSION}-x86-64-generic-ext4-combined.img.gz"
  [[ "$OS_TYPE" == "immortalwrt" ]] && DL_URL="https://downloads.immortalwrt.org/releases/${VERSION}/targets/x86/64/immortalwrt-${VERSION}-x86-64-generic-ext4-combined.img.gz"
fi
LOCAL_FILE="${CACHE_DIR}/${FILE_NAME}"

# ===== 下载镜像文件 =====
mkdir -p "$CACHE_DIR"
if [[ -f "$LOCAL_FILE" ]]; then
  echo "[✔] 镜像已存在：$LOCAL_FILE"
else
  echo "[↓] 下载镜像文件..."
  wget -O "$LOCAL_FILE" "$DL_URL" || { echo "[✘] 下载失败"; exit 1; }
fi

# ===== 选择网桥名称 =====
echo "请选择桥接网卡（默认 vmbr0）："
AVAILABLE_BRIDGES=$(grep -o '^auto .*' /etc/network/interfaces | awk '{print $2}')
select BRIDGE in $AVAILABLE_BRIDGES "手动输入"; do
  [[ "$BRIDGE" == "手动输入" ]] && read -p "请输入网桥名称: " BRIDGE
  [[ -z "$BRIDGE" ]] && BRIDGE="$DEFAULT_BRIDGE"
  break
done

# ===== 选择存储位置 =====
echo "请选择存储位置："
STORES=$(pvesm status -content images | awk 'NR>1 {print $1}')
select STORAGE in $STORES "手动输入"; do
  [[ "$STORAGE" == "手动输入" ]] && read -p "请输入存储名称: " STORAGE
  [[ -n "$STORAGE" ]] && break
done

# ===== 创建 LXC 容器 =====
if [[ "$CREATE_TYPE" == "LXC" ]]; then
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
  IP=$(pct exec $LXC_ID -- ip -4 addr show eth0 | grep -oP '(?<=inet\s)\d+(\.\d+){3}')
  echo "[✔] LXC 容器安装完成：ID=$LXC_ID, IP=$IP"

# ===== 创建虚拟机 VM =====
else
  if qm status $VM_ID &>/dev/null; then
    echo "[!] VM ID $VM_ID 已存在，请手动处理或更换 ID"
    exit 1
  fi

  echo "[*] 解压 VM 镜像..."
  IMG_FILE="${LOCAL_FILE%.gz}"
  gunzip -c "$LOCAL_FILE" > "$IMG_FILE"

  echo "[*] 创建 VM..."
  qm create $VM_ID \
    --name "${OS_TYPE}-vm" \
    --memory $MEMORY \
    --cores $CPUS \
    --net0 virtio,bridge=$BRIDGE \
    --serial0 socket --vga serial0 --ostype l26

  qm importdisk $VM_ID "$IMG_FILE" "$STORAGE" --format raw
  qm set $VM_ID --scsihw virtio-scsi-pci --scsi0 ${STORAGE}:vm-${VM_ID}-disk-0
  qm set $VM_ID --boot order=scsi0
  qm set $VM_ID --onboot 1
  qm start $VM_ID
  echo "[✔] VM 创建完成：ID=$VM_ID，已启动"
fi
