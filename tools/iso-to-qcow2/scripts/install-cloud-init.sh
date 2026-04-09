#!/usr/bin/env bash
# =============================================================================
# install-cloud-init.sh — 在构建虚拟机中安装 cloud-init 及相关工具
# 由 Packer shell provisioner 调用，运行环境为 CentOS 7 / TencentOS
# =============================================================================
set -euo pipefail

echo "==> [install-cloud-init] 开始安装 cloud-init..."

# ---------- 可选：替换为腾讯软件源（国内网络环境推荐开启） ----------
# 将下面的 USE_TENCENT_MIRROR 设为 "true" 即可启用腾讯软件源
USE_TENCENT_MIRROR="${USE_TENCENT_MIRROR:-false}"

if [[ "$USE_TENCENT_MIRROR" == "true" ]]; then
  echo "==> [install-cloud-init] 配置腾讯软件源..."
  # 备份原有 repo 文件
  mkdir -p /etc/yum.repos.d/backup
  mv /etc/yum.repos.d/*.repo /etc/yum.repos.d/backup/ 2>/dev/null || true

  # 写入腾讯软件源（CentOS 7）
  cat > /etc/yum.repos.d/tencent-centos7.repo <<'EOF'
[base]
name=CentOS-$releasever - Base - mirrors.tencent.com
baseurl=https://mirrors.tencent.com/centos/$releasever/os/$basearch/
gpgcheck=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-CentOS-7

[updates]
name=CentOS-$releasever - Updates - mirrors.tencent.com
baseurl=https://mirrors.tencent.com/centos/$releasever/updates/$basearch/
gpgcheck=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-CentOS-7

[extras]
name=CentOS-$releasever - Extras - mirrors.tencent.com
baseurl=https://mirrors.tencent.com/centos/$releasever/extras/$basearch/
gpgcheck=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-CentOS-7

[epel]
name=Extra Packages for Enterprise Linux 7 - mirrors.tencent.com
baseurl=https://mirrors.tencent.com/epel/7/$basearch/
gpgcheck=0
EOF
  echo "==> [install-cloud-init] 腾讯软件源配置完成"
fi

# ---------- 更新系统 ----------
echo "==> [install-cloud-init] 更新系统软件包..."
yum -y update

# ---------- 安装 cloud-init 及相关工具 ----------
echo "==> [install-cloud-init] 安装 cloud-init、cloud-utils-growpart、gdisk..."
yum -y install \
  cloud-init \
  cloud-utils-growpart \
  gdisk \
  dracut-config-generic \
  dracut-norescue

# ---------- 验证 cloud-init 版本 ----------
CLOUD_INIT_VERSION=$(cloud-init --version 2>&1 | grep -oP '\d+\.\d+' | head -1 || echo "0.0")
echo "==> [install-cloud-init] cloud-init 版本：${CLOUD_INIT_VERSION}"

# 最低版本要求：18.x（CentOS 7 官方源通常为 18.x 或 19.x）
REQUIRED_MAJOR=18
ACTUAL_MAJOR=$(echo "$CLOUD_INIT_VERSION" | cut -d. -f1)
if [[ "$ACTUAL_MAJOR" -lt "$REQUIRED_MAJOR" ]]; then
  echo "⚠️  [WARN] cloud-init 版本 ${CLOUD_INIT_VERSION} 低于推荐版本 ${REQUIRED_MAJOR}.x，建议升级"
fi

# ---------- 启用 cloud-init 相关 systemd 服务 ----------
echo "==> [install-cloud-init] 启用 cloud-init systemd 服务..."
systemctl enable cloud-init-local.service
systemctl enable cloud-init.service
systemctl enable cloud-config.service
systemctl enable cloud-final.service

# ---------- 配置 cloud-init datasource ----------
# 告知 cloud-init 使用 NoCloud 和 ConfigDrive（Multipass 使用 NoCloud）
cat > /etc/cloud/cloud.cfg.d/99-datasource.cfg <<'EOF'
# Multipass 使用 NoCloud datasource 注入 cloud-init 配置
datasource_list: [ NoCloud, ConfigDrive, None ]
EOF

# ---------- 配置 cloud-init 默认用户 ----------
# 确保 cloud-init 能正确创建默认用户（centos）
grep -q "default_user" /etc/cloud/cloud.cfg || true
# CentOS 7 cloud.cfg 默认用户为 centos，保持不变

echo "==> [install-cloud-init] cloud-init 安装与配置完成 ✅"
