# iso-to-qcow2 — ISO 镜像转 Multipass 兼容 qcow2 工具

基于 **Packer + QEMU** 的自动化工具，将普通 Linux ISO 安装镜像转换为内置 cloud-init 的 qcow2 格式 cloud image，可直接被 `multipass launch file://...` 使用。

## 目录结构

```
tools/iso-to-qcow2/
├── build.sh                  # 入口脚本（推荐使用此脚本）
├── http/                     # Kickstart / Preseed 无人值守安装配置
│   ├── centos7-ks.cfg        # CentOS 7 Kickstart 配置
│   └── tlinux-ks.cfg         # TencentOS Server Kickstart 配置
├── templates/                # Packer HCL 构建模板
│   ├── centos7.pkr.hcl       # CentOS 7 构建模板
│   └── tlinux.pkr.hcl        # TencentOS Server 构建模板
├── scripts/                  # Packer shell provisioner 脚本
│   ├── install-cloud-init.sh # 安装 cloud-init 及相关工具
│   └── cleanup.sh            # 镜像清理（machine-id、SSH keys 等）
└── output/                   # 构建产物目录（.gitignore 忽略 qcow2 文件）
    └── {distro}/
        ├── {distro}-cloud.qcow2
        ├── {distro}-cloud.qcow2.sha256
        └── manifest.json
```

## 环境依赖

| 工具 | 最低版本 | 安装方式 |
|------|---------|---------|
| [Packer](https://developer.hashicorp.com/packer/install) | ≥ 1.9.0 | `brew install packer`（macOS）/ 官网下载 |
| [QEMU](https://www.qemu.org/download/) | ≥ 7.0 | `brew install qemu`（macOS）/ `apt install qemu-system-x86`（Linux） |

> **macOS 用户**：需要 macOS 11+ 以使用 HVF 硬件加速，构建速度更快。
>
> **Linux 用户**：建议开启 KVM（`/dev/kvm` 存在），否则构建速度较慢。

## 快速开始

### 1. 安装依赖

```bash
# macOS
brew install packer qemu

# Ubuntu / Debian
sudo apt install -y qemu-system-x86 qemu-utils
wget https://releases.hashicorp.com/packer/1.11.0/packer_1.11.0_linux_amd64.zip
unzip packer_1.11.0_linux_amd64.zip && sudo mv packer /usr/local/bin/
```

### 2. 准备 ISO 文件

下载目标发行版的 ISO 文件：

```bash
# CentOS 7（推荐使用 Minimal 版本）
wget https://mirrors.tencent.com/centos/7/isos/x86_64/CentOS-7-x86_64-Minimal-2009.iso

# TencentOS Server 3.x（从腾讯软件源下载）
# https://mirrors.tencent.com/tlinux/3.1/iso/
```

### 3. 执行构建

```bash
cd tools/iso-to-qcow2

# 构建 CentOS 7 qcow2 镜像（跳过 ISO 校验）
./build.sh --distro centos7 --iso /path/to/CentOS-7-x86_64-Minimal-2009.iso

# 构建 CentOS 7 qcow2 镜像（带 SHA256 校验）
./build.sh --distro centos7 \
  --iso /path/to/CentOS-7-x86_64-Minimal-2009.iso \
  --checksum sha256:2b9d9e90b9e7dc93c06f9d6b5a4b70e0c4b5a4b70e0c4b5a4b70e0c4b5a4b70e

# 构建 TencentOS Server qcow2 镜像
./build.sh --distro tlinux --iso /path/to/TencentOS-Server-3.1-x86_64.iso
```

构建过程约需 **15~30 分钟**（取决于机器性能和网络速度）。

### 4. 使用镜像启动 Multipass 实例

```bash
# 查看构建产物
ls output/centos7/
# centos7-cloud.qcow2  centos7-cloud.qcow2.sha256  manifest.json

# 使用 file:// 协议启动 Multipass 实例
multipass launch file://$(pwd)/output/centos7/centos7-cloud.qcow2 \
  --name my-centos7 \
  --cpus 2 \
  --memory 2G \
  --disk 20G

# 连接到实例
multipass shell my-centos7
```

## 参数说明

| 参数 | 必填 | 说明 |
|------|------|------|
| `--distro` | ✅ | 目标发行版，支持：`centos7` \| `tlinux` |
| `--iso` | ✅ | ISO 文件路径（本地绝对路径或 `http://` URL） |
| `--checksum` | ❌ | ISO 文件 SHA256 校验值，格式：`sha256:xxxx`，默认 `none`（跳过校验） |

## 支持的发行版

| 发行版 | `--distro` 值 | Kickstart 文件 | Packer 模板 | 说明 |
|--------|--------------|---------------|------------|------|
| CentOS 7 | `centos7` | `http/centos7-ks.cfg` | `templates/centos7.pkr.hcl` | 标准 CentOS 7 Minimal |
| TencentOS Server | `tlinux` | `http/tlinux-ks.cfg` | `templates/tlinux.pkr.hcl` | 支持 2.x 和 3.x，自动配置腾讯软件源 |

## 可选：启用腾讯软件源

对于 CentOS 7，可在构建时通过环境变量启用腾讯软件源（国内网络推荐）：

```bash
# 方式一：通过环境变量传入（修改 Packer 模板中的 environment_vars）
# 编辑 templates/centos7.pkr.hcl，在 install-cloud-init.sh provisioner 中添加：
# environment_vars = ["USE_TENCENT_MIRROR=true"]

# 方式二：直接修改 scripts/install-cloud-init.sh 中的默认值
# 将 USE_TENCENT_MIRROR="${USE_TENCENT_MIRROR:-false}" 改为 true
```

TencentOS 构建时**默认启用**腾讯软件源（`mirrors.tencent.com/tlinux/`）。

## 构建流程说明

```
ISO 文件
  │
  ▼
Packer 启动 QEMU 虚拟机
  │  ├─ 内置 HTTP server 提供 Kickstart 文件
  │  └─ boot command 注入 ks=http://... 参数
  │
  ▼
Kickstart 无人值守安装（约 10~15 分钟）
  │  ├─ 最小化安装 @core
  │  ├─ 禁用 SELinux
  │  └─ 配置 SSH root 登录（仅构建阶段）
  │
  ▼
Packer SSH 连接成功，执行 Provisioner
  │
  ├─ scripts/install-cloud-init.sh
  │    ├─ 安装 cloud-init、cloud-utils-growpart、gdisk
  │    ├─ 启用 cloud-init systemd 服务
  │    └─ （可选）配置腾讯软件源
  │
  └─ scripts/cleanup.sh
       ├─ cloud-init clean --logs
       ├─ truncate -s 0 /etc/machine-id
       ├─ 删除 /etc/ssh/ssh_host_*
       ├─ 清理网络配置、日志、yum 缓存
       └─ shutdown -h now
  │
  ▼
Packer 输出 qcow2 文件
  │
  ▼
build.sh 生成 SHA256 校验文件
  │
  ▼
output/{distro}/{distro}-cloud.qcow2 ✅
```

## 为新发行版扩展构建模板

以添加 **Kylin V10** 支持为例：

### 步骤 1：创建 Kickstart 文件

```bash
cp http/centos7-ks.cfg http/kylin-ks.cfg
# 编辑 http/kylin-ks.cfg，根据 Kylin 的差异调整：
# - 包列表（如需要特定包）
# - %post 中的软件源配置
```

### 步骤 2：创建 Packer 模板

```bash
cp templates/centos7.pkr.hcl templates/kylin.pkr.hcl
# 编辑 templates/kylin.pkr.hcl，修改以下内容：
# - source "qemu" "kylin" { ... }（修改 source 名称）
# - vm_name = "kylin-cloud.qcow2"
# - http_port_min/max（避免端口冲突，如 8300-8399）
# - boot_command 中的 ks= 指向 kylin-ks.cfg
# - build { sources = ["source.qemu.kylin"] }
```

### 步骤 3：更新 build.sh（可选）

`build.sh` 会自动根据 `--distro` 参数查找 `templates/{distro}.pkr.hcl`，无需修改脚本。

### 步骤 4：测试构建

```bash
./build.sh --distro kylin --iso /path/to/Kylin-V10-x86_64.iso
```

## 常见问题

### Q: 构建时 SSH 连接超时（30 分钟）

**可能原因：**
1. ISO 文件路径错误或文件损坏
2. Kickstart 文件语法错误，安装过程卡住
3. 机器性能不足，安装时间超过 30 分钟

**排查方式：**
```bash
# 临时开启 VNC 查看安装进度（修改 Packer 模板）
# 将 headless = true 改为 headless = false
# 然后通过 VNC 客户端连接 localhost:5900
```

### Q: macOS 上构建报错 "HVF not available"

确认 macOS 版本 ≥ 11，且未在虚拟机内运行（嵌套虚拟化）。可将 `accelerator` 改为 `none` 使用软件模拟（速度较慢）。

### Q: 构建完成但 Multipass 无法启动镜像

确认镜像内 cloud-init 已正确安装并启用：
```bash
# 临时启动镜像检查（使用 QEMU 直接启动）
qemu-system-x86_64 -m 1G -drive file=output/centos7/centos7-cloud.qcow2,format=qcow2 -nographic
# 登录后检查：
systemctl status cloud-init
cloud-init --version
```
