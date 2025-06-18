#!/bin/bash

# 默认虚拟机ID
DEFAULT_VM_ID=1002
VM_NAME="openwrt-vm"
OPENWRT_VERSION="24.10.1"
STORAGE="local"
BRIDGE="vmbr0"
MEMORY="4096"
CPUS="2"
DISK_SIZE="2G"

# 检查虚拟机ID是否已存在
check_vm_id() {
    if qm status $1 >/dev/null 2>&1; then
        echo "虚拟机ID $1 已被使用！"
        return 1
    fi
    return 0
}

# 获取可用的虚拟机ID
get_vm_id() {
    local vm_id=$DEFAULT_VM_ID
    
    # 检查默认ID是否可用
    if check_vm_id $vm_id; then
        read -p "使用默认虚拟机ID $vm_id? [Y/n] " choice
        case "$choice" in
            n|N) 
                # 用户不想使用默认ID
                ;;
            *) 
                VM_ID=$vm_id
                echo "使用默认虚拟机ID: $VM_ID"
                return
                ;;
        esac
    fi
    
    # 提示输入新的ID
    while true; do
        read -p "请输入新的虚拟机ID (100-999): " vm_id
        if [[ ! $vm_id =~ ^[1-9][0-9]{2}$ ]]; then
            echo "错误：ID必须是100-999之间的数字"
            continue
        fi
        
        if check_vm_id $vm_id; then
            VM_ID=$vm_id
            echo "使用虚拟机ID: $VM_ID"
            break
        fi
    done
}

# 主程序开始
cd /tmp
IMG="openwrt-${OPENWRT_VERSION}-x86-64-generic-ext4-combined.img"
IMG_GZ="${IMG}.gz"
IMG_URL="https://downloads.openwrt.org/releases/${OPENWRT_VERSION}/targets/x86/64/${IMG_GZ}"

# 1. 获取虚拟机ID
get_vm_id

# 2. 清理旧文件
cleanup_files() {
    echo "清理旧文件..."
    [ -f "$IMG_GZ" ] && rm -f "$IMG_GZ" && echo "已删除 $IMG_GZ"
    [ -f "$IMG" ] && rm -f "$IMG" && echo "已删除 $IMG"
}
cleanup_files

# 3. 下载镜像
echo "正在下载 OpenWrt 镜像..."
wget --no-verbose --show-progress -O "$IMG_GZ" "$IMG_URL" 2>&1 | grep -E "100%|保存"

# 4. 解压镜像
echo "正在解压镜像..."
gzip -df "$IMG_GZ"  # -d 解压，-f 强制覆盖

# 5. 清理旧虚拟机配置
echo "清理旧虚拟机配置 (ID: $VM_ID)..."
qm destroy $VM_ID --purge >/dev/null 2>&1 && echo "已删除 VM $VM_ID"

# 6. 创建虚拟机
echo "创建虚拟机 (ID: $VM_ID)..."
qm create $VM_ID --name $VM_NAME --machine q35 --memory $MEMORY --cores $CPUS \
    --net0 virtio,bridge=$BRIDGE \
    --scsihw virtio-scsi-single

# 7. 导入磁盘
echo "导入磁盘..."
qm importdisk $VM_ID "$IMG" $STORAGE --format qcow2

# 8. 获取磁盘名称
DISK_NAME=$(ls /var/lib/vz/images/$VM_ID/ | grep vm-$VM_ID-disk | head -n 1)
if [ -z "$DISK_NAME" ]; then
    DISK_NAME="vm-$VM_ID-disk-0.qcow2"
fi

# 9. 附加磁盘
echo "附加磁盘..."
qm set $VM_ID --sata0 $STORAGE:$VM_ID/$DISK_NAME

# 10. 调整磁盘大小
echo "调整磁盘大小至 $DISK_SIZE..."
qm resize $VM_ID sata0 $DISK_SIZE

# 11. 设置启动选项
qm set $VM_ID --boot order=sata0
qm set $VM_ID --serial0 socket --vga serial0

# 12. 启动虚拟机
echo "启动虚拟机..."
qm start $VM_ID

echo "[✔] OpenWrt ${OPENWRT_VERSION} VM 创建完成 (ID: $VM_ID)"
echo "[✔] 使用配置: q35机型, VirtIO SCSI控制器, SATA磁盘接口"
echo "[✔] 磁盘大小已调整为 $DISK_SIZE"

# 扩展分区以使用全部磁盘空间
echo "扩展分区以使用全部磁盘空间:"
opkg install parted
parted /dev/sda resizepart 2 100%
resize2fs /dev/sda2

# 13. 验证配置
echo "验证虚拟机配置:"
qm config $VM_ID | grep -E "machine:|scsihw:|sata0:|vga:|boot:"

# 14. 后续安装指南
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
