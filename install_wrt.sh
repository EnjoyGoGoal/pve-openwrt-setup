#!/bin/bash

# 获取 OpenWrt 或 ImmortalWrt 版本
get_latest_version() {
    echo "🔍 获取 OpenWrt 最新版本号..."
    OPENWRT_VERSION=$(curl -s https://downloads.openwrt.org/releases/latest/ | grep -oP 'OpenWrt\s*\K[0-9.]+')
    echo "→ OpenWrt 最新版本：$OPENWRT_VERSION"
    
    echo "🔍 获取 ImmortalWrt 最新版本号..."
    IMMORTALWRT_VERSION=$(curl -s https://immortalwrt.org/releases/latest/ | grep -oP 'ImmortalWrt\s*\K[0-9.]+')
    echo "→ ImmortalWrt 最新版本：$IMMORTALWRT_VERSION"
}

# 选择存储池
select_storage() {
    echo "🔍 请选择存储池："
    echo "1) local-lvm"
    echo "2) local"
    echo "3) 其它"
    read -p "选择存储池编号 [默认1]: " sc
    sc=${sc:-1}

    case "$sc" in
        1)
            STORAGE_NAME="local-lvm"
            ;;
        2)
            STORAGE_NAME="local"
            ;;
        3)
            read -p "请输入自定义存储池名称: " STORAGE_NAME
            ;;
        *)
            echo "无效选择，退出。"
            exit 1
            ;;
    esac

    echo "已选择存储池：$STORAGE_NAME"
}

# 获取 OpenWrt 或 ImmortalWrt 镜像文件
get_image_file() {
    local OS=$1
    local VERSION=$2
    local URL

    if [ "$OS" == "OpenWrt" ]; then
        URL="https://downloads.openwrt.org/releases/$VERSION/targets/x86/64/openwrt-$VERSION-x86-64-rootfs.tar.gz"
    elif [ "$OS" == "ImmortalWrt" ]; then
        URL="https://downloads.immortalwrt.org/releases/$VERSION/targets/x86/64/immortalwrt-$VERSION-x86-64-rootfs.tar.gz"
    else
        echo "未知操作系统类型：$OS"
        exit 1
    fi

    echo "🔍 下载 $OS 镜像：$URL"
    wget -O /var/lib/vz/template/cache/$OS-$VERSION-rootfs.tar.gz $URL
}

# 创建容器
create_container() {
    local CT_ID=$1
    local OS=$2
    local VERSION=$3
    local TEMPLATE="/var/lib/vz/template/cache/$OS-$VERSION-rootfs.tar.gz"

    pct create $CT_ID $TEMPLATE \
        --hostname $OS-$VERSION \
        --cores 2 \
        --memory 4096 \
        --swap 0 \
        --rootfs $STORAGE_NAME:2 \
        --net0 name=eth0,bridge=vmbr0,ip=dhcp \
        --ostype unmanaged \
        --arch amd64 \
        --features nesting=1 \
        --unprivileged 0
}

# 启动容器
start_container() {
    local CT_ID=$1
    pct start $CT_ID
    echo "[✔] 容器已启动。"
}

# 主程序
main() {
    # 获取最新版本
    get_latest_version

    # 选择操作系统
    echo "选择要安装的操作系统："
    echo "1) OpenWrt"
    echo "2) ImmortalWrt"
    read -p "请选择 [1/2]: " os_choice
    if [ "$os_choice" == "1" ]; then
        OS="OpenWrt"
        VERSION=$OPENWRT_VERSION
    elif [ "$os_choice" == "2" ]; then
        OS="ImmortalWrt"
        VERSION=$IMMORTALWRT_VERSION
    else
        echo "无效的选择，退出脚本。"
        exit 1
    fi

    # 选择存储池
    select_storage

    # 获取镜像文件
    get_image_file $OS $VERSION

    # 获取并检查容器 ID
    read -p "请输入容器 ID（默认1001）: " CT_ID
    CT_ID=${CT_ID:-1001}
    if pct status $CT_ID &>/dev/null; then
        echo "容器 ID $CT_ID 已存在，选择另一个容器 ID。"
        exit 1
    fi

    # 创建并启动容器
    create_container $CT_ID $OS $VERSION
    start_container $CT_ID

    echo "[✔] $OS $VERSION LXC 容器安装完成。"
}

main
