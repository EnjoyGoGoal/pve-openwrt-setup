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

# 列出存储池，并确保正确显示存储池类型
select_storage() {
    echo "🔍 检测存储池..."
    
    # 获取存储池配置
    mapfile -t STS < <(grep -E '^[[:alnum:]-]+' /etc/pve/storage.cfg | awk '{print $1, $2}')

    if [ ${#STS[@]} -eq 0 ]; then
        echo "未检测到存储池"
        exit 1
    fi

    echo "可用存储池："
    # 列出存储池名称和类型
    for i in "${!STS[@]}"; do
        STORAGE_NAME=$(echo ${STS[$i]} | awk '{print $1}' | xargs)  # 清除多余的空格
        STORAGE_TYPE=$(echo ${STS[$i]} | awk '{print $2}' | xargs)  # 清除多余的空格
        # 输出存储池信息
        echo " $((i+1))). ${STORAGE_NAME} (${STORAGE_TYPE})"
    done

    read -p "选择存储池编号 [默认1]: " sc
    sc=${sc:-1}
    STORAGE_NAME=$(echo ${STS[$((sc-1))]} | awk '{print $1}' | xargs)  # 清除多余的空格
    STORAGE_TYPE=$(echo ${STS[$((sc-1))]} | awk '{print $2}' | xargs)  # 清除多余的空格
    STORAGE_NAME=$(echo $STORAGE_NAME | sed 's/.*(\(.*\))/\1/')  # 获取括号中的存储池名称
    
    echo "已选择存储池：$STORAGE_NAME ($STORAGE_TYPE)"
    
    # 存储池类型处理逻辑
    case "$STORAGE_TYPE" in
        dir)
            if [[ "$STORAGE_NAME" == "local" ]]; then
                echo "正在使用本地存储池：$STORAGE_NAME"
            else
                echo "未知的 dir 类型存储池，退出。"
                exit 1
            fi
            ;;
        esxi)
            echo "正在使用与 VMware ESXi 服务器连接的存储池：$STORAGE_NAME"
            # 这里可以添加额外的处理逻辑，针对 ESXi 存储池进行操作
            ;;
        *)
            echo "未知存储池类型：$STORAGE_TYPE，退出。"
            exit 1
            ;;
    esac
}

# 检查容器 ID 是否已存在
check_container_id() {
    local CT_ID=$1
    if pct status $CT_ID &>/dev/null; then
        echo "容器 ID $CT_ID 已存在，选择另一个容器 ID。"
        return 1
    fi
    return 0
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

    # 检查存储池
    select_storage

    # 获取镜像文件
    get_image_file $OS $VERSION

    # 获取并检查容器 ID
    read -p "请输入容器 ID（默认1001）: " CT_ID
    CT_ID=${CT_ID:-1001}
    check_container_id $CT_ID
    if [ $? -ne 0 ]; then
        read -p "请输入新的容器 ID: " CT_ID
        check_container_id $CT_ID
        if [ $? -ne 0 ]; then
            echo "无法找到有效的容器 ID，退出脚本。"
            exit 1
        fi
    fi

    # 创建并启动容器
    create_container $CT_ID $OS $VERSION
    start_container $CT_ID

    echo "[✔] $OS $VERSION LXC 容器安装完成。"
}

main
