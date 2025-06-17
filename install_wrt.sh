#!/bin/bash
set -euo pipefail

# 检查是否是 root 用户
[ "$(id -u)" != 0 ] && { echo "请用 root 执行"; exit 1; }

# 获取 OpenWrt 最新版本
echo "🔍 获取 OpenWrt 最新版本..."
OW_VER=$(curl -s https://downloads.openwrt.org/releases/ \
  | grep -Po 'href="\K\d+\.\d+\.\d+(?=/")' \
  | sort -V | tail -1)
[ -z "$OW_VER" ] && { echo "获取 OpenWrt 版本失败"; exit 1; }
echo "→ OpenWrt：$OW_VER"

# 获取 ImmortalWrt 最新版本
echo "🔍 获取 ImmortalWrt 最新版本..."
IW_VER=$(curl -s https://downloads.immortalwrt.org/releases/ \
  | grep -Po 'href="\K24\.10\.1(?=/")' \
  | sort -V | tail -1)
[ -z "$IW_VER" ] && { echo "获取 ImmortalWrt 版本失败"; exit 1; }
echo "→ ImmortalWrt：$IW_VER"

# 选择要安装的系统
echo -e "请选择安装的系统：\n 1) OpenWrt $OW_VER\n 2) ImmortalWrt $IW_VER"
read -p "> " ch
if [ "$ch" = "2" ]; then
    DIST="immortalwrt"; VER="$IW_VER"
    IMG_URL="https://downloads.immortalwrt.org/releases/${VER}/targets/x86/64/immortalwrt-${VER}-x86-64-rootfs.tar.gz"
else
    DIST="openwrt"; VER="$OW_VER"
    IMG_URL="https://downloads.openwrt.org/releases/${VER}/targets/x86/64/openwrt-${VER}-x86-64-rootfs.tar.gz"
fi

# 选择安装方式（LXC 或 VM）
echo -e "请选择安装方式：\n 1) LXC\n 2) VM"
read -p "> " m; m=${m:-1}
if [ "$m" = "2" ]; then MODE="vm"; START=2001; else MODE="lxc"; START=1001; fi

# 列出可用的存储池
mapfile -t STS < <(grep -E '^[[:alnum:]-]+' /etc/pve/storage.cfg | awk '{print $1}')
if [ ${#STS[@]} -eq 0 ]; then
    echo "未检测到存储池"; exit 1;
fi

echo "可用存储池："
for i in "${!STS[@]}"; do echo " $((i+1))). ${STS[i]}"; done
read -p "选择存储池编号 [默认1]: " sc; sc=${sc:-1}
STORAGE=${STS[$((sc-1))]}

# 下载镜像文件，如果镜像文件不存在
TPL="/var/lib/vz/template/cache/${DIST}-${VER}-x86-64-rootfs.tar.gz"
if [ ! -f "$TPL" ]; then
  echo "📥 正在下载镜像..."
  mkdir -p "$(dirname "$TPL")"
  wget -q -O "$TPL" "$IMG_URL"
  echo "✅ 下载完成"
else
  echo "✅ 镜像已存在：$TPL"
fi

# 获取并分配 LXC 或 VM 的 ID
get_id() {
  local id=$1
  while :; do
    if [ "$MODE" = "lxc" ] && [ ! -f "/etc/pve/lxc/${id}.conf" ]; then echo "$id"; return; fi
    if [ "$MODE" = "vm" ] && [ ! -f "/etc/pve/qemu-server/${id}.conf" ]; then echo "$id"; return; fi
    id=$((id+1))
  done
}
ID=$(get_id $START)
echo "→ 分配 ID：$ID"

# 创建 LXC 容器或 VM 实例
if [ "$MODE" = "lxc" ]; then
  pct create "$ID" "$TPL" \
    --hostname "${DIST}-lxc" \
    --cores 2 --memory 4096 --swap 0 \
    --rootfs "${STORAGE}:2" \
    --net0 name=eth0,bridge=vmbr0,ip=dhcp \
    --arch amd64 --features nesting=1 --unprivileged 0 --ostype unmanaged
  pct set "$ID" --onboot 1
  pct start "$ID"
  echo "✅ LXC 容器创建成功 (ID=$ID)"
else
  qm create "$ID" --name "${DIST}-vm" \
    --memory 4096 --cores 2 \
    --net0 virtio,bridge=vmbr0 \
    --boot order=ide0 --ostype l26
  qm importdisk "$ID" "$TPL" "$STORAGE"
  qm set "$ID" --ide0 "${STORAGE}:vm-${ID}-disk-0" \
              --boot order=ide0 --onboot 1
  qm start "$ID"
  echo "✅ VM 虚拟机创建成功 (ID=$ID)"
fi

echo "🎉 安装完成！"
echo "系统：${DIST}-${VER} | 类型：${MODE} | ID：${ID} | 存储池：${STORAGE}"
