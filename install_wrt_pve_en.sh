#!/bin/bash
# =============================================================================
# Script Name: install_wrt_pve_en.sh
# Description: One-click deployment of OpenWrt / ImmortalWrt on Proxmox VE (LXC or VM)
# Author: EnjoyGoGoal
# Version: 1.6
# Updated: 2025-06-18
# License: MIT
# GitHub: https://github.com/EnjoyGoGoal
# =============================================================================

set -e

# ===== Default Config =====
LXC_ID=1001
DEFAULT_VM_ID=2001
CPUS=2
MEMORY=4096
ROOTFS_SIZE=2
DISK_SIZE="2G"
DEFAULT_BRIDGE="vmbr0"
DEFAULT_STORAGE="local"
CACHE_DIR="/var/lib/vz/template/cache"

# ===== Check Internet Connectivity =====
echo "[*] Checking internet connectivity..."
ping -c 1 -W 2 1.1.1.1 &>/dev/null || { echo "[✘] No internet connection, please check your network."; exit 1; }

# ===== Choose OS Type =====
echo "Select OS type (default is OpenWrt):"
select OS_TYPE in "openwrt" "immortalwrt"; do
  OS_TYPE=${OS_TYPE:-"openwrt"}
  break
done

# ===== Get Latest Version =====
get_latest_version() {
  local base_url
  [[ "$1" == "openwrt" ]] && base_url="https://downloads.openwrt.org/releases/"
  [[ "$1" == "immortalwrt" ]] && base_url="https://downloads.immortalwrt.org/releases/"
  curl -s "$base_url" | grep -oP '\d+\.\d+\.\d+(?=/)' | sort -Vr | head -n 1
}
VERSION=$(get_latest_version "$OS_TYPE")
echo "[✔] Latest version: $VERSION"

# ===== Choose Deployment Type =====
echo "Select deployment type (default is LXC):"
select CREATE_TYPE in "LXC" "VM"; do
  CREATE_TYPE=${CREATE_TYPE:-"LXC"}
  break
done

# ===== Choose Storage Pool =====
echo "Select storage pool (default is local):"
select STORAGE in "local" "local-lvm" "other"; do
  STORAGE=${STORAGE:-"local"}
  break
done

# ===== Choose Network Bridge =====
echo "Select network bridge (default is vmbr0):"
AVAILABLE_BRIDGES=$(grep -o '^auto .*' /etc/network/interfaces | awk '{print $2}')
select BRIDGE in $AVAILABLE_BRIDGES "Custom"; do
  [[ "$BRIDGE" == "Custom" ]] && read -p "Enter custom bridge name: " BRIDGE
  [[ -z "$BRIDGE" ]] && BRIDGE="$DEFAULT_BRIDGE"
  break
done

# ===== Get VM ID if Needed =====
get_vm_id() {
  local vm_id=$DEFAULT_VM_ID
  read -p "[*] Enter VM ID (default is $vm_id): " vm_id_input
  VM_ID=${vm_id_input:-$vm_id}
}
[[ "$CREATE_TYPE" == "VM" ]] && get_vm_id

# ===== Set Name and Description =====
if [[ "$CREATE_TYPE" == "VM" ]]; then
  [[ "$OS_TYPE" == "openwrt" ]] && VM_NAME="OpenWrt-${VERSION}" && VM_DESC="OpenWrt ${VERSION} Virtual Machine"
  [[ "$OS_TYPE" == "immortalwrt" ]] && VM_NAME="ImmortalWrt-${VERSION}" && VM_DESC="ImmortalWrt ${VERSION} Virtual Machine"
fi

# ===== Install LXC or VM =====
if [[ "$CREATE_TYPE" == "LXC" ]]; then
  FILE_NAME="${OS_TYPE}-${VERSION}-lxc.tar.gz"
  [[ "$OS_TYPE" == "openwrt" ]] && DL_URL="https://downloads.openwrt.org/releases/${VERSION}/targets/x86/64/openwrt-${VERSION}-x86-64-rootfs.tar.gz"
  [[ "$OS_TYPE" == "immortalwrt" ]] && DL_URL="https://downloads.immortalwrt.org/releases/${VERSION}/targets/x86/64/immortalwrt-${VERSION}-x86-64-rootfs.tar.gz"
  LOCAL_FILE="${CACHE_DIR}/${FILE_NAME}"

  mkdir -p "$CACHE_DIR"
  if [[ -f "$LOCAL_FILE" ]]; then
    echo "[✔] Image already exists: $LOCAL_FILE"
  else
    echo "[↓] Downloading image..."
    wget -O "$LOCAL_FILE" "$DL_URL" || { echo "[✘] Download failed."; exit 1; }
  fi

  read -p "Enter LXC ID (default 1001): " user_lxc_id
  LXC_ID="${user_lxc_id:-1001}"

  if pct status "$LXC_ID" &>/dev/null; then
    echo "[!] LXC ID $LXC_ID already exists. Please choose another or delete the existing one."
    exit 1
  fi

  LXC_NAME="${OS_TYPE}-${VERSION}"

  echo "[*] Creating LXC container..."
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
  echo "[✔] LXC container created: ID=$LXC_ID, Name=$LXC_NAME, IP=${IP:-Unavailable}"

else
  cd /tmp
  IMG="${OS_TYPE}-${VERSION}-x86-64-generic-ext4-combined.img"
  IMG_GZ="${IMG}.gz"
  BASE_DOMAIN="$( [[ "$OS_TYPE" == "openwrt" ]] && echo "downloads.openwrt.org" || echo "downloads.immortalwrt.org" )"
  IMG_URL="https://${BASE_DOMAIN}/releases/${VERSION}/targets/x86/64/${IMG_GZ}"

  echo "[*] Cleaning up old files..."
  rm -f "$IMG_GZ" "$IMG"

  echo "[↓] Downloading image..."
  wget --no-verbose --show-progress -O "$IMG_GZ" "$IMG_URL" || { echo "[✘] Download failed."; exit 1; }

  echo "[*] Extracting image..."
  if gzip -df "$IMG_GZ" 2>&1 | grep -q "decompression OK"; then
    echo "[✔] Extraction done (ignore warnings)"
  else
    echo "[✘] Extraction failed"
    exit 1
  fi

  echo "[*] Removing old VM if exists..."
  qm destroy $VM_ID --purge >/dev/null 2>&1 || true

  echo "[*] Creating VM..."
  qm create $VM_ID --name "$VM_NAME" --machine q35 --memory $MEMORY --cores $CPUS \
    --net0 virtio,bridge=$BRIDGE \
    --scsihw virtio-scsi-single \
    --cpu host --description "$VM_DESC"

  echo "[*] Importing disk..."
  qm importdisk $VM_ID "$IMG" $STORAGE --format qcow2
  DISK_NAME=$(ls /var/lib/pve/images/$VM_ID/ | grep vm-$VM_ID-disk | head -n 1)
  [[ -z "$DISK_NAME" ]] && DISK_NAME="vm-$VM_ID-disk-0.qcow2"

  echo "[*] Attaching disk..."
  qm set $VM_ID --sata0 $STORAGE:$VM_ID/$DISK_NAME
  qm resize $VM_ID sata0 $DISK_SIZE
  qm set $VM_ID --boot order=sata0
  qm set $VM_ID --serial0 socket
  qm set $VM_ID --onboot 1
  qm start $VM_ID

  echo "[✔] $VM_NAME installed successfully (ID: $VM_ID)"
  echo "[*] VM Config:"
  qm config $VM_ID | grep -E "machine:|scsihw:|cpu:|sata0:|vga:|boot:|description:"

  # ===== OpenClash Installation Note =====
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

  echo "[✔] OpenClash install instructions saved to: /root/openclash-install.txt"
fi
