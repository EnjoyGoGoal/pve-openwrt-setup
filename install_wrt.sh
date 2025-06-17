#!/bin/bash
set -euo pipefail

# ════════════════════════════
#  函数：获取最新版本号
# ════════════════════════════
get_latest_version() {
    echo "🔍 获取 OpenWrt 最新版本号..."
    OPENWRT_VERSION=$(curl -s https://downloads.openwrt.org/releases/ \
      | grep -Po 'href="\K\d+\.\d+\.\d+(?=/")' \
      | sort -V | tail -1)
    echo "→ OpenWrt: $OPENWRT_VERSION"

    echo "🔍 获取 ImmortalWrt 最新版本号..."
    IMMORTALWRT_VERSION=$(curl -s https://downloads.immortalwrt.org/releases/ \
      | grep -Po 'href="\K\d+\.\d+\.\d+(?=/")' \
      | sort -V | tail -1)
    echo "→ ImmortalWrt: $IMMORTALWRT_VERSION"
}

# ════════════════════════════
#  函数：选择存储池
# ════════════════════════════
select_storage() {
    echo "请选择存储池："
    echo "1) local-lvm"
    echo "2) local"
    echo "3) 其它"
    read -p "存储池编号 [1]: " sc; sc=${sc:-1}
    case "$sc" in
        1) STORAGE="local-lvm" ;;
        2) STORAGE="local"    ;;
        3) read -p "请输入自定义存储池名称: " STORAGE ;;
        *) echo "无效选择" && exit 1 ;;
    esac
    echo "→ 存储池: $STORAGE"
}

# ════════════════════════════
#  函数：下载镜像
# ════════════════════════════
download_image() {
    local OS=$1 VER=$2 URL
    if [ "$OS" = "OpenWrt" ]; then
        URL="https://downloads.openwrt.org/releases/${VER}/targets/x86/64/openwrt-${VER}-x86-64-rootfs.tar.gz"
    else
        URL="https://downloads.immortalwrt.org/releases/${VER}/targets/x86/64/immortalwrt-${VER}-x86-64-rootfs.tar.gz"
    fi
    echo "🔍 下载 ${OS} 镜像：$URL"
    mkdir -p /var/lib/vz/template/cache
    wget -q -O /var/lib/vz/template/cache/${OS}-${VER}-rootfs.tar.gz "$URL"
}

# ════════════════════════════
#  函数：下载虚拟机镜像
# ════════════════════════════
download_vm_image() {
    local OS=$1 VER=$2 URL
    if [ "$OS" = "OpenWrt" ]; then
        URL="https://downloads.openwrt.org/releases/${VER}/targets/x86/64/openwrt-${VER}-x86-64-rootfs.img.gz"
    else
        URL="https://downloads.immortalwrt.org/releases/${VER}/targets/x86/64/immortalwrt-${VER}-x86-64-rootfs.img.gz"
    fi
    echo "🔍 下载 ${OS} 虚拟机镜像：$URL"
    mkdir -p /var/lib/vz/template/iso
    wget -q -O /var/lib/vz/template/iso/${OS}-${VER}-rootfs.img.gz "$URL"
}

# ════════════════════════════
#  函数：创建并启动 LXC
# ════════════════════════════
create_lxc() {
    local ID=$1 OS=$2 VER=$3
    local TMP="/var/lib/vz/template/cache/${OS}-${VER}-rootfs.tar.gz"
    echo "🚀 创建 LXC 容器 ID=$ID"
    pct create $ID "$TMP" \
      --hostname "${OS,,}-lxc" \
      --cores 2 --memory 4096 --swap 0 \
      --rootfs "${STORAGE}:2" \
      --net0 name=eth0,bridge=vmbr0,ip=dhcp \
      --ostype unmanaged --arch amd64 \
      --features nesting=1 --unprivileged 0
    pct set $ID --onboot 1
    pct start $ID
    echo "✅ 容器已启动 (ID=$ID)"
}

# ════════════════════════════
#  函数：创建并启动 VM
# ════════════════════════════
create_vm() {
    local ID=$1 OS=$2 VER=$3
    local TMP="/var/lib/vz/template/iso/${OS}-${VER}-rootfs.img.gz"
    echo "🚀 创建 VM 虚拟机 ID=$ID"
    qm create $ID --name "${OS,,}-vm" --memory 4096 --cores 2 --net0 virtio,bridge=vmbr0
    qm importdisk $ID "$TMP" $STORAGE
    qm set $ID --scsihw virtio-scsi-pci --ide2 $STORAGE:cloudinit
    qm set $ID --boot order=cd
    qm start $ID
    echo "✅ 虚拟机已启动 (ID=$ID)"
}

# ════════════════════════════
#  主流程
# ════════════════════════════
main() {
    get_latest_version

    echo "选择系统：1) OpenWrt  2) ImmortalWrt"
    read -p "[1]: " ch; ch=${ch:-1}
    if [ "$ch" = "2" ]; then
        OS="ImmortalWrt"; VER=$IMMORTALWRT_VERSION
    else
        OS="OpenWrt";     VER=$OPENWRT_VERSION
    fi

    select_storage

    # 选择镜像
    echo "选择容器类型：1) LXC  2) VM"
    read -p "[1]: " ct_or_vm; ct_or_vm=${ct_or_vm:-1}

    if [ "$ct_or_vm" = "2" ]; then
        download_vm_image $OS $VER
        VMID=$((2001))  # 从 2001 开始
        echo "请输入虚拟机 ID [默认：$VMID]: "
        read -p "VMID: " CTID; CTID=${CTID:-$VMID}
        create_vm $CTID $OS $VER
    else
        download_image $OS $VER
        LXCID=$((1001))  # 从 1001 开始
        echo "请输入容器 ID [默认：$LXCID]: "
        read -p "LXC ID: " CTID; CTID=${CTID:-$LXCID}
        create_lxc $CTID $OS $VER
    fi

    echo "[✔] $OS $VER 安装完成。"
}

main
