#!/bin/bash
set -euo pipefail

# ▬▬▬▬▬ 根据选择确定系统名和镜像名称 ▬▬▬▬▬
OS_NAME=""
IMAGE_URL=""
FILE_NAME=""

# ▬▬▬▬▬ 获取最新版本 ▬▬▬▬▬
get_latest_version() {
  echo "🔍 获取 OpenWrt 最新版本..."
  OPENWRT_VERSION=$(curl -s https://downloads.openwrt.org/releases/ | grep -Po 'href="\K[0-9.]+(?=/")' | sort -V | tail -1)
  echo "→ OpenWrt: $OPENWRT_VERSION"

  echo "🔍 获取 ImmortalWrt 最新版本..."
  IMMORTALWRT_VERSION=$(curl -s https://downloads.immortalwrt.org/releases/ | grep -Po 'href="\K[0-9.]+(?=/")' | sort -V | tail -1)
  echo "→ ImmortalWrt: $IMMORTALWRT_VERSION"
}

# ▬▬▬▬▬ 选择安装系统 ▬▬▬▬▬
select_os() {
  echo "选择安装的系统："
  echo "1) OpenWrt"
  echo "2) ImmortalWrt"
  read -p "请选择 [1/2]: " choice_os
  case $choice_os in
    2)
      OS_NAME="ImmortalWrt"
      VERSION=$IMMORTALWRT_VERSION
      ;;
    *)
      OS_NAME="OpenWrt"
      VERSION=$OPENWRT_VERSION
      ;;
  esac
}

# ▬▬▬▬▬ 选择 LXC 或 VM ▬▬▬▬▬
select_type() {
  echo "选择需要安装的类型："
  echo "1) LXC"
  echo "2) VM"
  read -p "请选择 [1/2]: " choice_type
  case $choice_type in
    2)
      DEVICE_TYPE="VM"
      ID=2001
      ;;
    *)
      DEVICE_TYPE="LXC"
      ID=1001
      ;;
  esac
}

# ▬▬▬▬▬ 选择存储池 ▬▬▬▬▬
select_storage() {
  echo "🔍 选择存储池："
  echo "1) local-lvm"
  echo "2) local"
  echo "3) 其他"
  read -p "选择存储池编号 [1]: " sc; sc=${sc:-1}
  case "$sc" in
    1) STORAGE="local-lvm" ;;
    2) STORAGE="local" ;;
    3) read -p "请输入自定义存储池名称: " STORAGE ;;
    *) echo "无效选择" && exit 1 ;;
  esac
  echo "→ 存储池: $STORAGE"
}

# ▬▬▬▬▬ 下载镜像 ▬▬▬▬▬
download_image() {
  if [[ $DEVICE_TYPE == "LXC" ]]; then
    FILE_NAME=${OS_NAME}-${VERSION}-rootfs.tar.gz
    if [[ $OS_NAME == "OpenWrt" ]]; then
      IMAGE_URL="https://downloads.openwrt.org/releases/${VERSION}/targets/x86/64/openwrt-${VERSION}-x86-64-rootfs.tar.gz"
    else
      IMAGE_URL="https://downloads.immortalwrt.org/releases/${VERSION}/targets/x86/64/immortalwrt-${VERSION}-x86-64-rootfs.tar.gz"
    fi
    mkdir -p /var/lib/vz/template/cache
    wget -q -O /var/lib/vz/template/cache/$FILE_NAME "$IMAGE_URL"
  else
    FILE_NAME=${OS_NAME}-${VERSION}-rootfs.img.gz
    if [[ $OS_NAME == "OpenWrt" ]]; then
      IMAGE_URL="https://downloads.openwrt.org/releases/${VERSION}/targets/x86/64/openwrt-${VERSION}-x86-64-rootfs.img.gz"
    else
      IMAGE_URL="https://downloads.immortalwrt.org/releases/${VERSION}/targets/x86/64/immortalwrt-${VERSION}-x86-64-rootfs.img.gz"
    fi
    mkdir -p /var/lib/vz/template/iso
    wget -q -O /var/lib/vz/template/iso/$FILE_NAME "$IMAGE_URL"
  fi
  echo "📁 镜像下载完成: $FILE_NAME"
}

# ▬▬▬▬▬ 执行 ▬▬▬▬▬
main() {
  get_latest_version
  select_os
  select_type
  select_storage
  download_image

  echo "🔧 准备创建 $DEVICE_TYPE ($OS_NAME $VERSION) ID=$ID"
  echo "# TODO: 根据类型进行创建操作"
}

main
