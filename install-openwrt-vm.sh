#!/bin/bash

VM_ID=1002
VM_NAME="openwrt-vm"
OPENWRT_VERSION="24.10.1"
STORAGE="local"
BRIDGE="vmbr0"
MEMORY="4096"
CPUS="2"
DISK_SIZE="2G"  # 设置所需的磁盘大小

cd /tmp
IMG="openwrt-${OPENWRT_VERSION}-x86-64-generic-ext4-combined.img"
IMG_URL="https://downloads.openwrt.org/releases/${OPENWRT_VERSION}/targets/x86/64/${IMG}.gz"
wget -O ${IMG}.gz ${IMG_URL}
gunzip ${IMG}.gz

# 确保虚拟机不存在
qm destroy $VM_ID --purge >/dev/null 2>&1

# 创建虚拟机（仅基本配置）
qm create $VM_ID --name $VM_NAME --memory $MEMORY --cores $CPUS --net0 virtio,bridge=$BRIDGE

# 导入磁盘到存储
qm importdisk $VM_ID $IMG $STORAGE --format qcow2

# 获取实际创建的磁盘名称
DISK_NAME=$(ls /var/lib/vz/images/$VM_ID/ | grep vm-$VM_ID-disk | head -n 1)
if [ -z "$DISK_NAME" ]; then
    DISK_NAME="vm-$VM_ID-disk-0.qcow2"
fi

# 附加磁盘为SATA设备
qm set $VM_ID --sata0 $STORAGE:$VM_ID/$DISK_NAME

# 调整磁盘大小
echo "调整磁盘大小至 $DISK_SIZE..."
qm resize $VM_ID sata0 $DISK_SIZE

# 设置启动顺序和其他参数
qm set $VM_ID --boot order=sata0
qm set $VM_ID --serial0 socket --vga serial0

# 启动虚拟机
qm start $VM_ID

echo "[✔] OpenWrt ${OPENWRT_VERSION} VM 创建完成"
echo "[✔] 磁盘大小已调整为 $DISK_SIZE"

# 验证磁盘大小
echo "验证磁盘大小:"
qm config $VM_ID | grep sata0
qemu-img info /var/lib/vz/images/$VM_ID/$DISK_NAME | grep "virtual size"

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
