#!/bin/bash
# =============================================================================
# Script Name: create_wrt_pve.sh
# Description: 一键安装 OpenWrt / ImmortalWrt 到 Proxmox VE（支持 LXC 和 VM）
# Author: EnjoyGoGoal
# Version: 1.6
# Updated: 2025-06-18
# License: MIT
# GitHub: https://github.com/EnjoyGoGoal
# =============================================================================

set -e

# ===== 默认配置 =====
LXC_ID=1001
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

# ===== 默认系统选择 =====
OS_TYPE="openwrt"
echo "[✔] 默认系统选择: $OS_TYPE"
echo "是否更改系统选择? (默认选择: openwrt)"
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

# ===== 类型选择 =====
CREATE_TYPE="LXC"
echo "[✔] 默认创建类型: LXC"
echo "是否更改创建类型? (默认选择: LXC)"
select CREATE_TYPE in "LXC" "VM"; do [[ -n "$CREATE_TYPE" ]] && break; done

# ===== 网桥选择 =====
echo "请选择桥接网卡（默认 vmbr0）："
AVAILABLE_BRIDGES=$(grep -o '^auto .*' /etc/network/interfaces | awk '{print $2}')
select BRIDGE in $AVAILABLE_BRIDGES "手动输入"; do
  [[ "$BRIDGE" == "手动输入" ]] && read -p "请输入网桥名称: " BRIDGE
  [[ -z "$BRIDGE" ]] && BRIDGE="$DEFAULT_BRIDGE"
  break
done

# ===== 存储池选择 =====
echo "请选择存储池（默认 local）："
select STORAGE in "local" "local-lvm" "其他"; do
  [[ -n "$STORAGE" ]] && break
done
STORAGE="${STORAGE:-$DEFAULT_STORAGE}"

# ===== 获取 LXC ID =====
if pct status $LXC_ID &>/dev/null; then
  echo "[!] LXC ID $LXC_ID 已存在，请手动处理或更换 ID"
  exit 1
fi

# ===== 创建 LXC 容器 =====
if [[ "$CREATE_TYPE" == "LXC" ]]; then
  FILE_NAME="${OS_TYPE}-${VERSION}-lxc.tar.gz"
  DL_URL="https://downloads.openwrt.org/releases/${VERSION}/targets/x86/64/openwrt-${VERSION}-x86-64-rootfs.tar.gz"
  LOCAL_FILE="${CACHE_DIR}/${FILE_NAME}"

  mkdir -p "$CACHE_DIR"
  if [[ -f "$LOCAL_FILE" ]]; then
    echo "[✔] 镜像已存在：$LOCAL_FILE"
  else
    echo "[↓] 下载镜像..."
    wget -O "$LOCAL_FILE" "$DL_URL" || { echo "[✘] 下载失败"; exit 1; }
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

fi
