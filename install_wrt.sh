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
#  函数：下载 LXC 镜像
# ════════════════════════════
download_lxc_image() {
    local OS=$1 VER=$2 URL
    if [ "$OS" = "OpenWrt" ]; then
        URL="https://downloads.openwrt.org/releases/${VER}/targets/x86/64/openwrt-${VER}-x86-64-rootfs.tar.gz"
    else
        URL="https://downloads.immortalwrt.org/releases/${VER}/targets/x86/64/immortalwrt-${VER}-x86-64-rootfs.tar.gz"
    fi
    echo "🔍 下载 ${OS} LXC 镜像：$URL"
    mkdir -p /var/lib/vz/template/cache
    wget -q -O /var/lib/vz/template/cache/${OS}-${VER}-rootfs.tar.gz "$URL"
}

# ════════════
