#!/bin/bash

VM_ID=1002
VM_NAME="openwrt-vm"
OPENWRT_VERSION="24.10.1"
STORAGE="local"
BRIDGE="vmbr0"
MEMORY="4096"
CPUS="2"
DISK_SIZE="2G"  # 修改为带单位的磁盘大小

cd /tmp
IMG="openwrt-${OPENWRT_VERSION}-x86-64-generic-ext4-combined.img"
IMG_URL="https://downloads.openwrt.org/releases/${OPENWRT_VERSION}/targets/x86/64/${IMG}.gz"
wget -O ${IMG}.gz ${IMG_URL}
gunzip ${IMG}.gz

# 创建虚拟机时直接添加磁盘
qm create $VM_ID --name $VM_NAME --memory $MEMORY --cores $CPUS \
    --net0 virtio,bridge=$BRIDGE \
    --sata0 $STORAGE:$DISK_SIZE  # 创建时直接添加SATA磁盘

# 导入磁盘到现有磁盘位置
qm importdisk $VM_ID $IMG $STORAGE -format qcow2

# 附加导入的磁盘到SATA接口
qm set $VM_ID --sata0 $STORAGE:vm-${VM_ID}-disk-0

# 设置启动顺序和其他参数
qm set $VM_ID --boot order=sata0
qm set $VM_ID --serial0 socket --vga serial0
qm start $VM_ID

echo "[✔] OpenWrt ${OPENWRT_VERSION} VM 创建完成"

# 自动安装 OpenClash（首次进入系统后执行）
cat << EOF

请在 OpenWrt 内运行以下命令以安装 OpenClash：

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

EOF
