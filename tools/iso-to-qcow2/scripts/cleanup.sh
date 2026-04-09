#!/usr/bin/env bash
# =============================================================================
# cleanup.sh — 清理构建虚拟机，使 qcow2 镜像可被多实例复用
# 由 Packer shell provisioner 调用（最后一个 provisioner）
# 执行完成后虚拟机关机，Packer 完成 qcow2 文件输出
# =============================================================================
set -euo pipefail

echo "==> [cleanup] 开始镜像清理..."

# ---------- 1. 重置 cloud-init 状态 ----------
echo "==> [cleanup] 重置 cloud-init 状态..."
cloud-init clean --logs 2>/dev/null || true
# 删除 cloud-init 运行状态目录（确保下次启动时重新初始化）
rm -rf /var/lib/cloud/

# ---------- 2. 清空 machine-id（避免多实例 ID 冲突） ----------
echo "==> [cleanup] 清空 machine-id..."
truncate -s 0 /etc/machine-id
# 如果存在 /var/lib/dbus/machine-id，同步清空
if [[ -f /var/lib/dbus/machine-id ]]; then
  truncate -s 0 /var/lib/dbus/machine-id
fi

# ---------- 3. 删除 SSH host keys（每个实例启动时重新生成） ----------
echo "==> [cleanup] 删除 SSH host keys..."
rm -f /etc/ssh/ssh_host_*

# 配置 sshd 在首次启动时重新生成 host keys
# CentOS 7 的 sshd-keygen.service 会自动处理
systemctl enable sshd-keygen.service 2>/dev/null || true

# ---------- 4. 清理构建阶段的 SSH 配置（恢复安全设置） ----------
echo "==> [cleanup] 恢复 SSH 安全配置..."
# 禁用 root 密码登录（cloud-init 会通过 SSH key 登录）
sed -i 's/^PermitRootLogin yes/PermitRootLogin prohibit-password/' /etc/ssh/sshd_config
sed -i 's/^PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config

# ---------- 5. 清理网络配置（避免 MAC 地址绑定） ----------
echo "==> [cleanup] 清理网络配置..."
# 删除网卡 MAC 地址绑定，确保新实例能正确获取网络
for f in /etc/sysconfig/network-scripts/ifcfg-e*; do
  [[ -f "$f" ]] || continue
  sed -i '/^HWADDR/d' "$f"
  sed -i '/^UUID/d' "$f"
done
# 删除 udev 网络规则（避免网卡名称固定）
rm -f /etc/udev/rules.d/70-persistent-net.rules
rm -f /etc/udev/rules.d/75-persistent-net-generator.rules

# ---------- 6. 清理日志文件 ----------
echo "==> [cleanup] 清理日志文件..."
find /var/log -type f -exec truncate -s 0 {} \;
rm -rf /var/log/audit/audit.log
rm -rf /tmp/* /var/tmp/*

# ---------- 7. 清理 yum 缓存 ----------
echo "==> [cleanup] 清理 yum 缓存..."
yum clean all
rm -rf /var/cache/yum

# ---------- 8. 清理 bash history ----------
echo "==> [cleanup] 清理 bash history..."
unset HISTFILE
history -c
cat /dev/null > /root/.bash_history
# 清理其他用户的 history
find /home -name ".bash_history" -exec truncate -s 0 {} \; 2>/dev/null || true

# ---------- 9. 同步磁盘写入 ----------
echo "==> [cleanup] 同步磁盘..."
sync

echo "==> [cleanup] 镜像清理完成 ✅，准备关机..."

# ---------- 10. 关机（Packer 检测到关机后完成 qcow2 输出） ----------
shutdown -h now
