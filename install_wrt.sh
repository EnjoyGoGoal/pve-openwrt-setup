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
    mapfile -t STS < <(grep -E '^[[:alnum:]-]+' /etc/pve/storage.cfg | awk '{print $1, $2}')

    if [ ${#STS[@]} -eq 0 ]; then
        echo "未检测到存储池"; exit 1;
    fi

    echo "可用存储池："
    # 列出存储池名称和类型
    for i in "${!STS[@]}"; do
        STORAGE_NAME=$(echo ${STS[$i]} | awk '{print $1}')
        STORAGE_TYPE=$(echo ${STS[$i]} | awk '{print $2}')
        echo " $((i+1))). ${STORAGE_NAME} (${STORAGE_TYPE})"
    done

    read -p "选择存储池编号 [默认1]: " sc
    sc=${sc:-1}
    STORAGE_NAME=$(echo ${STS[$((sc-1))]} | awk '{print $1}')
