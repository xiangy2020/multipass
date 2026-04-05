# 国内主流 Linux 发行版镜像使用指南

本文档介绍如何在 Multipass 中使用 CentOS Stream、TencentOS（TLinux）和麒麟（Kylin）镜像。

---

## 支持的发行版

| 发行版 | 别名 | 架构 | 状态 |
|--------|------|------|------|
| CentOS Stream 9 | `centos`, `centos-stream`, `centos:9`, `centos-stream:9` | x86_64, arm64 | ✅ 可用 |
| CentOS Stream 8 | `centos:8`, `centos-stream:8` | x86_64, arm64 | ✅ 可用 |
| TencentOS Server 3.x | `tencentos`, `tlinux` | x86_64, arm64 | ⏳ 待官方发布 Cloud 镜像 |
| 麒麟 V10（OpenKylin） | `kylin`, `kylinv10` | x86_64, arm64 | ⏳ 待官方发布 Cloud 镜像 |

---

## CentOS Stream

### 支持的版本

| 版本 | 别名 | 状态 |
|------|------|------|
| CentOS Stream 9（默认） | `centos`, `centos-stream`, `centos:9`, `centos-stream:9` | ✅ 可用 |
| CentOS Stream 8 | `centos:8`, `centos-stream:8` | ✅ 可用 |

### 快速启动

```bash
# 启动默认版本（Stream 9）
multipass launch centos

# 明确指定 Stream 9
multipass launch centos:9

# 启动 Stream 8
multipass launch centos:8

# 使用别名
multipass launch centos-stream
multipass launch centos-stream:8
```

### 配置腾讯软件源（国内用户推荐）

```bash
multipass launch centos --cloud-init \
  https://raw.githubusercontent.com/canonical/multipass/refs/heads/main/data/cloud-init-yaml/cloud-init-centos.yaml
```

编辑 `cloud-init-centos.yaml`，取消注释 `runcmd` 部分即可自动配置腾讯软件源：

```yaml
runcmd:
  - |
    mkdir -p /etc/yum.repos.d/backup
    mv /etc/yum.repos.d/CentOS-*.repo /etc/yum.repos.d/backup/ 2>/dev/null || true
    curl -o /etc/yum.repos.d/CentOS-Base.repo \
      https://mirrors.tencent.com/repo/centos9_base.repo
    yum clean all && yum makecache
```

### 默认用户

CentOS Stream GenericCloud 镜像的默认用户为 `centos`（部分版本为 `cloud-user`）。

### 腾讯软件源地址

| 用途 | URL |
|------|-----|
| CentOS 9 Base | `https://mirrors.tencent.com/repo/centos9_base.repo` |
| CentOS 8 Base | `https://mirrors.tencent.com/repo/centos8_base.repo` |
| CentOS 7 Base | `https://mirrors.tencent.com/repo/centos7_base.repo` |

---

## TencentOS（TLinux）

> ⚠️ **注意**：TencentOS 目前暂无公开的标准 qcow2 Cloud 镜像。`distribution-info.json` 中使用占位数据，待腾讯官方发布 Cloud 镜像后可正常使用。

### 快速启动（待 Cloud 镜像发布后可用）

```bash
# 启动 TencentOS 并自动配置腾讯软件源
multipass launch tencentos --cloud-init \
  https://raw.githubusercontent.com/canonical/multipass/refs/heads/main/data/cloud-init-yaml/cloud-init-tencentos.yaml

# 使用别名
multipass launch tlinux
```

### 腾讯软件源地址

| 版本 | 架构 | URL |
|------|------|-----|
| TencentOS 3.2 | x86_64 | `https://mirrors.tencent.com/tlinux/3.2/` |
| TencentOS 3.2 | aarch64 | `https://mirrors.tencent.com/tlinux/3.2/` |
| TencentOS 3.1 | x86_64 | `https://mirrors.tencent.com/tlinux/3.1/` |
| TencentOS 2.x | x86_64 | `https://mirrors.tencent.com/tlinux/2.6/` |

### 手动配置腾讯软件源（在已有 TencentOS 实例中）

```bash
# tlinux 3.2 x86_64
rpm -ivh --force \
  https://mirrors.tencent.com/tlinux/3.2/Updates/x86_64/RPMS/tencentos-release-3.2-4.tl3.x86_64.rpm
yum clean all && yum makecache

# tlinux 3.2 aarch64
rpm -ivh --force \
  https://mirrors.tencent.com/tlinux/3.2/Updates/aarch64/RPMS/tencentos-release-3.2-4.tl3.aarch64.rpm
yum clean all && yum makecache
```

---

## 麒麟（OpenKylin）

> ⚠️ **注意**：麒麟（OpenKylin）目前暂无公开的标准 qcow2 Cloud 镜像。`distribution-info.json` 中使用占位数据，待官方发布 Cloud 镜像后可正常使用。

### 快速启动（待 Cloud 镜像发布后可用）

```bash
# 启动麒麟 V10
multipass launch kylin --cloud-init \
  https://raw.githubusercontent.com/canonical/multipass/refs/heads/main/data/cloud-init-yaml/cloud-init-kylin.yaml

# 使用别名
multipass launch kylinv10
```

### 国内镜像源地址

| 镜像站 | URL |
|--------|-----|
| 阿里云 | `https://mirrors.aliyun.com/openkylin/` |
| 华为云 | `https://mirrors.huaweicloud.com/openkylin/` |

### 手动配置阿里云镜像源（在已有麒麟实例中）

```bash
# 备份原有 apt 源
cp /etc/apt/sources.list /etc/apt/sources.list.bak

# 配置阿里云镜像源
cat > /etc/apt/sources.list << 'EOF'
deb https://mirrors.aliyun.com/openkylin/ yangtze main restricted universe multiverse
deb https://mirrors.aliyun.com/openkylin/ yangtze-security main restricted universe multiverse
deb https://mirrors.aliyun.com/openkylin/ yangtze-updates main restricted universe multiverse
EOF

apt-get update
```

---

## 更新镜像元数据

使用 `distro-scraper` 工具可自动更新 `distribution-info.json` 中的镜像元数据：

```bash
cd tools/distro-scraper
pip install -e .
distro-scraper output.json
```

该工具会自动抓取所有已注册发行版（包括 CentOS、TencentOS、Kylin）的最新镜像信息。

---

## 相关文件

| 文件 | 说明 |
|------|------|
| `data/distributions/distribution-info.json` | 各发行版镜像元数据 |
| `data/cloud-init-yaml/cloud-init-centos.yaml` | CentOS cloud-init 配置 |
| `data/cloud-init-yaml/cloud-init-tencentos.yaml` | TencentOS cloud-init 配置（含腾讯软件源） |
| `data/cloud-init-yaml/cloud-init-kylin.yaml` | 麒麟 cloud-init 配置（含阿里云镜像源） |
| `tools/distro-scraper/scraper/scrapers/centos.py` | CentOS 镜像抓取器 |
| `tools/distro-scraper/scraper/scrapers/tencentos.py` | TencentOS 镜像抓取器 |
| `tools/distro-scraper/scraper/scrapers/kylin.py` | 麒麟镜像抓取器 |
