#!/bin/bash

# OpenWrt/ImmortalWrt 自动安装脚本 for Proxmox VE 8.4.1
# 支持选择 LXC 或 VM，自动检测版本并下载镜像

# 设置默认值
LXC_START_ID=1001
VM_START_ID=2001

# 输出颜色定义
GREEN="\033[1;32m"
YELLOW="\033[1;33m"
RED="\033[1;31m"
RESET="\033[0m"

# 检查依赖
command -v curl >/dev/null 2>&1 || { echo -e "${RED}请先安装 curl${RESET}"; exit 1; }
command -v wget >/dev/null 2>&1 || { echo -e "${RED}请先安装 wget${RESET}"; exit 1; }

# 获取最新版本函数
get_latest_openwrt_version() {
    echo "获取 OpenWrt 最新版本号..."
    curl -s https://downloads.openwrt.org/releases/ | grep -oE '[0-9]+\.[0-9]+\.[0-9]+/' | tr -d '/' | sort -Vr | head -n1
}

get_latest_immortalwrt_version() {
    echo "获取 ImmortalWrt 最新版本号..."
    curl -s https://downloads.immortalwrt.org/releases/ | grep -oE '[0-9]+\.[0-9]+\.[0-9]+/' | tr -d '/' | sort -Vr | head -n1
}

# 选择系统
echo -e "选择要安装的操作系统："
echo "1) OpenWrt"
echo "2) ImmortalWrt"
read -p "请选择 [1/2]: " OS_CHOICE

if [[ $OS_CHOICE == "2" ]]; then
    OS_NAME="ImmortalWrt"
    VERSION=$(get_latest_immortalwrt_version)
    BASE_URL="https://downloads.immortalwrt.org/releases"
else
    OS_NAME="OpenWrt"
    VERSION=$(get_latest_openwrt_version)
    BASE_URL="https://downloads.openwrt.org/releases"
fi

# 选择容器类型
echo -e "\n选择虚拟机类型："
echo "1) LXC"
echo "2) VM"
read -p "请选择 [1/2]: " VM_TYPE

if [[ $VM_TYPE == "2" ]]; then
    TYPE="VM"
    VMID=$VM_START_ID
    IMAGE_NAME="${OS_NAME,,}-${VERSION}-x86-64-combined-ext4.img.gz"
    IMAGE_URL="${BASE_URL}/${VERSION}/targets/x86/64/${IMAGE_NAME}"
else
    TYPE="LXC"
    VMID=$LXC_START_ID
    IMAGE_NAME="${OS_NAME,,}-${VERSION}-x86-64-rootfs.tar.gz"
    IMAGE_URL="${BASE_URL}/${VERSION}/targets/x86/64/${IMAGE_NAME}"
fi

# 选择存储池
echo -e "\n🔍 请选择存储池："
echo "1) local-lvm"
echo "2) local"
echo "3) 其它"
read -p "选择存储池编号 [默认1]: " STORAGE_CHOICE
case $STORAGE_CHOICE in
    2) STORAGE="local";;
    3) read -p "请输入自定义存储池名称: " STORAGE;;
    *) STORAGE="local-lvm";;
esac

# 下载镜像
CACHE_DIR="/var/lib/vz/template/cache"
mkdir -p "$CACHE_DIR"
echo -e "\n🔍 下载 ${OS_NAME} 镜像：${IMAGE_URL}"
wget -O "${CACHE_DIR}/${IMAGE_NAME}" "$IMAGE_URL" || { echo -e "${RED}镜像下载失败！${RESET}"; exit 1; }

# 输入主机名
read -p "请输入主机名 [默认：${OS_NAME,,}-${VERSION}]: " HOSTNAME
HOSTNAME=${HOSTNAME:-${OS_NAME,,}-${VERSION}}

# 创建 LXC 或 VM
if [[ $TYPE == "LXC" ]]; then
    pct create $VMID "${CACHE_DIR}/${IMAGE_NAME}" \
        --hostname "$HOSTNAME" \
        --cores 2 \
        --memory 512 \
        --swap 0 \
        --rootfs ${STORAGE}:2 \
        --net0 name=eth0,bridge=vmbr0,ip=dhcp \
        --ostype unmanaged \
        --arch amd64 \
        --features nesting=1 \
        --unprivileged 0 || exit 1
    pct start $VMID
else
    qm create $VMID --name "$HOSTNAME" --memory 1024 --cores 2 --net0 virtio,bridge=vmbr0
    qm importdisk $VMID "${CACHE_DIR}/${IMAGE_NAME}" $STORAGE
    qm set $VMID --scsihw virtio-scsi-pci --scsi0 ${STORAGE}:vm-${VMID}-disk-0
    qm set $VMID --boot order=scsi0 --ostype l26 --serial0 socket --vga serial0
    qm start $VMID
fi

echo -e "\n${GREEN}[✔] ${OS_NAME} ${VERSION} ${TYPE} 安装完成，ID为 ${VMID}${RESET}"
