#!/bin/bash
# =============================================================================
# Script Name: create_wrt_pve.sh
# Description: 一键安装 OpenWrt / ImmortalWrt 到 Proxmox VE（支持 LXC 和 VM）
# Author: EnjoyGoGoal
# Version: 1.5
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
CACHE_DIR="/var/lib/vz/template/cache"

# ===== 检查网络 =====
echo "[*] 检查网络连接..."
ping -c 1 -W 2 1.1.1.1 &>/dev/null || { echo "[✘] 无法连接互联网，请检查网络"; exit 1; }

# ===== 系统选择 =====
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

# ===== 类型选择 =====
echo "请选择创建类型:"
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
select_storage() {
    echo "请选择存储池："
    echo "1) local-lvm"
    echo "2) local"
    echo "3) 其它"
    read -p "存储池编号 [2]: " sc; sc=${sc:-2}
    case "$sc" in
        1) STORAGE="local-lvm" ;;
        2) STORAGE="local"    ;;
        3) read -p "请输入自定义存储池名称: " STORAGE ;;
        *) echo "无效选择" && exit 1 ;;
    esac
    echo "→ 存储池: $STORAGE"
}

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

# ===== 根据系统类型设置名称与描述 =====
if [[ "$CREATE_TYPE" == "VM" ]]; then
  [[ "$OS_TYPE" == "openwrt" ]] && VM_NAME="OpenWrt-${VERSION}" && VM_DESC="OpenWrt ${VERSION} 虚拟机"
  [[ "$OS_TYPE" == "immortalwrt" ]] && VM_NAME="ImmortalWrt-${VERSION}" && VM_DESC="ImmortalWrt ${VERSION} 虚拟机"
fi

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

# ===== 创建虚拟机 VM =====
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
  qm set $VM_ID --serial0 socket --vga serial0
  qm set $VM_ID --onboot 1
  qm start $VM_ID

  echo "[✔] $VM_NAME 安装完成 (ID: $VM_ID)"
  echo "[✔] 使用配置: CPU host, q35机型, VirtIO SCSI 控制器, SATA 接口"

  echo "[*] 验证 VM 配置:"
  qm config $VM_ID | grep -E "machine:|scsihw:|cpu:|sata0:|vga:|boot:|description:"

  # OpenClash 安装脚本
  cat << 'EOF' > /root/openclash-install.txt

opkg update
opkg install curl bash unzip iptables ipset coreutils coreutils-nohup luci luci-compat dnsmasq-full

cd /tmp
wget https://github.com/vernesong/OpenClash/releases/download/v0.45.128-beta/luci-app-openclash_0.45.128-beta_all.ipk
opkg install ./luci-app-openclash_0.45.128-beta_all.ipk

mkdir -p /etc/openclash
curl -Lo /etc/openclash/clash.tar.gz https://cdn.jsdelivr.net/gh/vernesong/OpenClash@master/core/clash-linux-amd64.tar.gz
tar -xzf /etc/openclash/clash.tar.gz -C /etc/openclash && rm /etc/openclash/clash.tar.gz

/etc/init.d/openclash enable
/etc/init.d/openclash start

opkg install parted
parted /dev/sda resizepart 2 100%
resize2fs /dev/sda2

EOF

  echo "[✔] OpenClash 安装说明已保存到：/root/openclash-install.txt"

fi
