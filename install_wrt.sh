#!/bin/bash
set -euo pipefail

# ↳ 确保 root 身份
[ "$(id -u)" != 0 ] && { echo "请用 root 运行"; exit 1; }

# ↳ 自动获取 OpenWrt 最新稳定版
echo "🔍 获取 OpenWrt 最新版本号..."
OW_VERSION=$(curl -s https://downloads.openwrt.org/releases/ | grep -Po 'href="\K\d+\.\d+\.\d+(?=/")' | sort -V | tail -1)
[ -z "$OW_VERSION" ] && { echo "获取 OpenWrt 版本失败"; exit 1; }
echo "→ OpenWrt 最新版本：${OW_VERSION}"

# ↳ 自动获取 ImmortalWrt 最新稳定版
echo "🔍 获取 ImmortalWrt 最新版本号..."
IW_VERSION=$(curl -s https://api.github.com/repos/immortalwrt/immortalwrt/releases/latest \
               | grep -Po '"tag_name":\s*"\K[^"]+')
[ -z "$IW_VERSION" ] && { echo "获取 ImmortalWrt 版本失败"; exit 1; }
echo "→ ImmortalWrt 最新版本：${IW_VERSION}"

# ↳ 选择系统
echo -e "请选择安装系统：\n 1) OpenWrt ${OW_VERSION}\n 2) ImmortalWrt ${IW_VERSION}"
read -p "> " choice
if [ "$choice" = "2" ]; then
  DIST="immortalwrt"
  VER="$IW_VERSION"
  IMG_URL="https://downloads.immortalwrt.org/releases/${VER}/targets/x86/64/immortalwrt-${VER}-x86-64-rootfs.tar.gz"
else
  DIST="openwrt"
  VER="$OW_VERSION"
  IMG_URL="https://downloads.openwrt.org/releases/${VER}/targets/x86/64/openwrt-${VER}-x86-64-rootfs.tar.gz"
fi

# ↳ 选择安装方式
echo -e "请选择安装方式：\n 1) LXC (默认)\n 2) VM"
read -p "> " m; m=${m:-1}
if [ "$m" = "2" ]; then MODE="vm"; START=2001; else MODE="lxc"; START=1001; fi

# ↳ 列出存储池选择
mapfile -t STS < <(grep -E '^[[:alnum:]-]+' /etc/pve/storage.cfg | awk '{print $1}')
[ ${#STS[@]} -eq 0 ] && { echo "未找到存储池"; exit 1; }
echo "可选存储池："
for i in "${!STS[@]}"; do echo " $((i+1))). ${STS[i]}"; done
read -p "选择编号（默认1）: " sc; sc=${sc:-1}
STORAGE=${STS[$((sc-1))]}

# ↳ 准备镜像下载
TPL="/var/lib/vz/template/cache/${DIST}-${VER}-x86-64-rootfs.tar.gz"
if [ ! -f "$TPL" ]; then
  echo "📦 下载镜像：${IMG_URL}"
  mkdir -p "$(dirname "$TPL")"
  wget -q -O "$TPL" "$IMG_URL"
  echo "✅ 下载完成"
else
  echo "✅ 镜像已存在：${TPL}"
fi

# ↳ 自动分配 ID
find_id(){
  local id=$1
  while true; do
    if [ "$MODE" = "lxc" ] && [ ! -f "/etc/pve/lxc/${id}.conf" ]; then echo "$id"; return; fi
    if [ "$MODE" = "vm" ] && [ ! -f "/etc/pve/qemu-server/${id}.conf" ]; then echo "$id"; return; fi
    id=$((id+1))
  done
}
ID=$(find_id $START)
echo "→ 使用 ID: $ID"

# ↳ 创建并启动实例
if [ "$MODE" = "lxc" ]; then
  pct create "$ID" "$TPL" \
    --hostname "${DIST}-lxc" \
    --cores 2 --memory 4096 --swap 0 \
    --rootfs "${STORAGE}:2" \
    --net0 name=eth0,bridge=vmbr0,ip=dhcp \
    --arch amd64 --features nesting=1 --unprivileged 0 --ostype unmanaged
  pct set "$ID" --onboot 1
  pct start "$ID"
  echo "✅ LXC 安装完成，ID = $ID"
else
  qm create "$ID" \
    --name "${DIST}-vm" \
    --memory 4096 --cores 2 \
    --net0 virtio,bridge=vmbr0 \
    --boot order=ide0 --ostype l26
  qm importdisk "$ID" "$TPL" "$STORAGE"
  qm set "$ID" --ide0 "${STORAGE}:vm-${ID}-disk-0" \
    --boot order=ide0 --onboot 1
  qm start "$ID"
  echo "✅ VM 安装完成，ID = $ID"
fi

echo "🎉 安装成功！系统=${DIST}-${VER}，类型=${MODE}，ID=${ID}，存储=${STORAGE}"
