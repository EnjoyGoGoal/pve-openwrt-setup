#!/bin/bash
set -euo pipefail

# 确保 root 权限
[ "$(id -u)" != "0" ] && { echo "请用 root 执行"; exit 1; }

# 获取 OpenWrt 最新稳定版本
echo "🔍 获取 OpenWrt 最新版本..."
OW_VER=$(curl -s https://downloads.openwrt.org/releases/ | grep -Po 'href="\K\d+\.\d+\.\d+(?=/")' | sort -V | tail -1)
[ -z "$OW_VER" ] && { echo "获取失败"; exit 1; }
echo "→ OpenWrt: $OW_VER"

# 获取 ImmortalWrt 最新稳定版本
echo "🔍 获取 ImmortalWrt 最新版本..."
IW_VER=$(curl -s https://downloads.immortalwrt.org/releases/ | grep -Po 'href="\K24\.10\.1(?=/")' | sort -V | tail -1)
[ -z "$IW_VER" ] && { echo "获取失败"; exit 1; }
echo "→ ImmortalWrt: $IW_VER"

# 用户选择系统
echo -e "请选择系统：\n 1) OpenWrt $OW_VER\n 2) ImmortalWrt $IW_VER"
read -p "> " CHOICE
if [ "$CHOICE" == "2" ]; then
  DIST="immortalwrt"; VER="$IW_VER"
  IMG_URL="https://downloads.immortalwrt.org/releases/${VER}/targets/x86/64/immortalwrt-${VER}-x86-64-rootfs.tar.gz"
else
  DIST="openwrt"; VER="$OW_VER"
  IMG_URL="https://downloads.openwrt.org/releases/${VER}/targets/x86/64/openwrt-${VER}-x86-64-rootfs.tar.gz"
fi

# 选择安装方式
echo -e "请选择安装方式：\n 1) LXC (默认)\n 2) VM"
read -p "> " M; M=${M:-1}
if [ "$M" = "2" ]; then MODE="vm"; START=2001; else MODE="lxc"; START=1001; fi

# 列出存储池
mapfile -t STS < <(grep -E '^[[:alnum:]-]+' /etc/pve/storage.cfg | awk '{print $1}')
[ ${#STS[@]} -eq 0 ] && { echo "未检测到存储"; exit 1; }
echo "可用存储："; for i in "${!STS[@]}"; do echo " $((i+1))). ${STS[i]}"; done
read -p "请选择存储编号 [默认1]: " SC; SC=${SC:-1}
STORAGE=${STS[$((SC-1))]}

# 准备镜像
TPL="/var/lib/vz/template/cache/${DIST}-${VER}-x86-64-rootfs.tar.gz"
if [ ! -f "$TPL" ]; then
  echo "📦 正在下载镜像..."
  mkdir -p "$(dirname "$TPL")"
  wget -q -O "$TPL" "$IMG_URL"
  echo "下载完成：$TPL"
else
  echo "✅ 镜像已存在"
fi

# 自动分配 ID
find_id(){
  local id=$1
  while :; do
    if [ "$MODE" = "lxc" ] && [ ! -f "/etc/pve/lxc/${id}.conf" ]; then echo "$id"; return; fi
    if [ "$MODE" = "vm" ] && [ ! -f "/etc/pve/qemu-server/${id}.conf" ]; then echo "$id"; return; fi
    id=$((id+1))
  done
}
ID=$(find_id $START)
echo "→ 使用 ID: $ID"

# 创建并启动
if [ "$MODE" = "lxc" ]; then
  pct create "$ID" "$TPL" \
    --hostname "${DIST}-lxc" \
    --cores 2 --memory 4096 --swap 0 \
    --rootfs "${STORAGE}:2" \
    --net0 name=eth0,bridge=vmbr0,ip=dhcp \
    --arch amd64 --features nesting=1 --unprivileged 0 --ostype unmanaged
  pct set "$ID" --onboot 1
  pct start "$ID"
  echo "✅ LXC 完成 (ID=$ID)"
else
  qm create "$ID" --name "${DIST}-vm" --memory 4096 --cores 2 \
     --net0 virtio,bridge=vmbr0 --boot order=ide0 --ostype l26
  qm importdisk "$ID" "$TPL" "$STORAGE"
  qm set "$ID" --ide0 "${STORAGE}:vm-${ID}-disk-0" --boot order=ide0 --onboot 1
  qm start "$ID"
  echo "✅ VM 完成 (ID=$ID)"
fi

echo "🎉 安装完成！系统=${DIST}-${VER}，类型=${MODE}，ID=${ID}，存储=${STORAGE}"
