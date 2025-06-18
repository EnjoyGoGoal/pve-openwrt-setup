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
IMG_GZ="${IMG}.gz"
IMG_URL="https://downloads.openwrt.org/releases/${OPENWRT_VERSION}/targets/x86/64/${IMG_GZ}"

# 清理旧文件（如果存在）
cleanup_files() {
    echo "清理旧文件..."
    [ -f "$IMG_GZ" ] && rm -f "$IMG_GZ" && echo "已删除 $IMG_GZ"
    [ -f "$IMG" ] && rm -f "$IMG" && echo "已删除 $IMG"
}

# 确保清理文件
cleanup_files

# 下载镜像（强制覆盖）
echo "正在下载 OpenWrt 镜像..."
wget --no-verbose --show-progress -O "$IMG_GZ" "$IMG_URL" 2>&1 | grep -E "100%|保存"

# 解压镜像（强制覆盖已存在文件）
echo "正在解压镜像..."
gzip -df "$IMG_GZ"  # -d 解压，-f 强制覆盖

# 确保虚拟机不存在
echo "清理旧虚拟机配置..."
qm destroy $VM_ID --purge >/dev/null 2>&1 && echo "已删除 VM $VM_ID"

# 创建虚拟机（使用q35机型）
echo "创建虚拟机..."
qm create $VM_ID --name $VM_NAME --machine q35 --memory $MEMORY --cores $CPUS \
    --net0 virtio,bridge=$BRIDGE \
    --scsihw virtio-scsi-single  # 使用VirtIO SCSI single控制器

# 导入磁盘到存储
echo "导入磁盘..."
qm importdisk $VM_ID "$IMG" $STORAGE --format qcow2

# 获取实际创建的磁盘名称
DISK_NAME=$(ls /var/lib/vz/images/$VM_ID/ | grep vm-$VM_ID-disk | head -n 1)
if [ -z "$DISK_NAME" ]; then
    DISK_NAME="vm-$VM_ID-disk-0.qcow2"
fi

# 附加磁盘为SATA设备
echo "附加磁盘..."
qm set $VM_ID --sata0 $STORAGE:$VM_ID/$DISK_NAME

# 调整磁盘大小
echo "调整磁盘大小至 $DISK_SIZE..."
qm resize $VM_ID sata0 $DISK_SIZE

# 设置启动顺序和其他参数
qm set $VM_ID --boot order=sata0
qm set $VM_ID --serial0 socket --vga serial0  # 使用串口控制台

# 启动虚拟机
echo "启动虚拟机..."
qm start $VM_ID

echo "[✔] OpenWrt ${OPENWRT_VERSION} VM 创建完成"
echo "[✔] 使用配置: q35机型, VirtIO SCSI控制器, SATA磁盘接口"
echo "[✔] 磁盘大小已调整为 $DISK_SIZE"

# 扩展分区以使用全部磁盘空间
echo "扩展分区以使用全部磁盘空间:"
opkg install parted
parted /dev/sda resizepart 2 100%
resize2fs /dev/sda2

# 验证配置
echo "验证虚拟机配置:"
qm config $VM_ID | grep -E "machine:|scsihw:|sata0:|vga:|boot:"

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
