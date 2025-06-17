#!/bin/bash
set -euo pipefail

# ════════════════════════════
#  函数：判断设备类型
# ════════════════════════════
check_device_type() {
    echo "🔍 判断设备类型..."
    if [ -d /sys/class/dmi/id ]; then
        DEVICE_TYPE="VM"
        if [ -f /sys/class/dmi/id/product_name ]; then
            PROD_NAME=$(cat /sys/class/dmi/id/product_name)
            if [[ "$PROD_NAME" == "KVM" || "$PROD_NAME" == "QEMU" || "$PROD_NAME" == "VMware" ]]; then
                DEVICE_TYPE="VM"
            else
                DEVICE_TYPE="Physical"
            fi
        fi
    else
        DEVICE_TYPE="Physical"
    fi
    echo "→ 当前设备类型: $DEVICE_TYPE"
}

# ════════════════════════════
#  函数：获取最新版本号
# ════════════════════════════
get_latest_version() {
    echo "🔍 获取 OpenWrt 和 ImmortalWrt 最新版本号..."
    
    OPENWRT_VERSION=$(curl -s https://downloads.openwrt.org/releases/ \
      | grep -Po 'href="\K\d+\.\d+\.\d+(?=/")' \
      | sort -V | tail -1)
    IMMORTALWRT_VERSION=$(curl -s https://downloads.immortalwrt.org/releases/ \
      | grep -Po 'href="\K\d+\.\d+\.\d+(?=/")' \
      | sort -V | tail -1)
    
    echo "→ OpenWrt: $OPENWRT_VERSION"
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
        URL="https://downloads.immortalwrt.org/releases/${VER}/targets/x86/64/immortalwrt-${VER}-x86-64-generic-ext4-combined.img.gz"
    fi
    echo "🔍 下载 ${OS} 镜像：$URL"
    mkdir -p /var/lib/vz/template/cache
    wget -q -O /var/lib/vz/template/cache/${OS}-${VER}-generic-ext4-combined.img.gz "$URL" || { echo "镜像下载失败！"; exit 1; }
}

# ════════════════════════════
#  函数：创建并启动 LXC 容器
# ════════════════════════════
create_lxc() {
    local ID=$1 OS=$2 VER=$3
    local TMP="/var/lib/vz/template/cache/${OS}-${VER}-generic-ext4-combined.img.gz"
    echo "🚀 创建 LXC 容器 ID=$ID"
    
    pct create $ID "$TMP" \
      --hostname "${OS,,}-lxc" \
      --cores 2 --memory 4096 --swap 0 \
      --rootfs "${STORAGE}:2" \
      --net0 name=eth0,bridge=vmbr0,ip=dhcp \
      --ostype unmanaged --arch amd64 \
      --features nesting=1 --unprivileged 0 || { echo "创建 LXC 容器失败！"; exit 1; }

    pct set $ID --onboot 1
    pct start $ID || { echo "启动 LXC 容器失败！"; exit 1; }
    echo "✅ 容器已启动 (ID=$ID)"
}

# ════════════════════════════
#  函数：创建并启动 VM 虚拟机
# ════════════════════════════
create_vm() {
    local ID=$1 OS=$2 VER=$3
    local TMP="/var/lib/vz/template/cache/${OS}-${VER}-generic-ext4-combined.img.gz"
    echo "🚀 创建 VM 虚拟机 ID=$ID"

    qm create $ID --name "${OS,,}-vm" --memory 4096 --cores 2 --net0 virtio,bridge=vmbr0 || { echo "创建 VM 虚拟机失败！"; exit 1; }
    qm importdisk $ID "$TMP" local-lvm || { echo "导入磁盘失败！"; exit 1; }
    qm set $ID --scsihw virtio-scsi-pci --scsi0 local-lvm:vm-${ID}-disk-0
    qm set $ID --boot order=scsi0 --ostype l26 --serial0 socket --vga serial0
    qm start $ID || { echo "启动 VM 虚拟机失败！"; exit 1; }
    echo "✅ 虚拟机已启动 (ID=$ID)"
}

# ════════════════════════════
#  主流程
# ════════════════════════════
main() {
    check_device_type

    echo "选择系统：1) OpenWrt  2) ImmortalWrt"
    read -p "[1]: " ch; ch=${ch:-1}
    if [ "$ch" = "2" ]; then
        OS="ImmortalWrt"; VER=$IMMORTALWRT_VERSION
    else
        OS="OpenWrt";     VER=$OPENWRT_VERSION
    fi

    select_storage
    download_image $OS $VER

    echo "选择创建的类型：1) LXC  2) VM"
    read -p "[1]: " vm_type; vm_type=${vm_type:-1}
    read -p "请输入 ID [1001]: " CTID; CTID=${CTID:-1001}

    if pct status $CTID &>/dev/null || qm status $CTID &>/dev/null; then
        echo "ID $CTID 已存在，退出"; exit 1
    fi

    if [ "$vm_type" = "1" ]; then
        create_lxc $CTID $OS $VER
    else
        create_vm $CTID $OS $VER
    fi

    echo "[✔] $OS $VER 安装完成。"
}

main
