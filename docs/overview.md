---
doc_name: "Multipass 项目总览"
doc_type: "技术文档"
version: "v1.0"
generated_at: "2026-04-05 16:29:12"
project_root: "/Users/tompyang/Documents/code/multipass"
project_type: "general"
project_lang: "C++"
doc_status: "draft"
doc_depth: "standard"
analyzed_files:
  - "README.md"
  - "src/daemon/daemon.h"
  - "src/rpc/multipass.proto"
  - "include/multipass/virtual_machine.h"
  - "include/multipass/platform.h"
  - "include/multipass/constants.h"
  - "include/multipass/virtual_machine_factory.h"
  - "include/multipass/settings/settings.h"
  - "src/daemon/daemon_config.h"
---

# Multipass 项目总览

## 目录

- [项目简介](#项目简介)
- [核心特性](#核心特性)
- [支持平台与虚拟化后端](#支持平台与虚拟化后端)
- [快速上手](#快速上手)
- [项目结构概览](#项目结构概览)
- [核心概念](#核心概念)
- [技术栈](#技术栈)
- [许可证](#许可证)

---

## 项目简介

**Multipass** 是由 Canonical 开发的轻量级虚拟机管理器，支持 Linux、Windows 和 macOS 三大平台。它专为开发者设计，能够通过单条命令快速启动一个全新的 Ubuntu 环境。

Multipass 使用各平台的原生虚拟化技术（Linux 上的 KVM、Windows 上的 Hyper-V、macOS 上的 QEMU/Apple Virtualization Framework），以最小的开销运行虚拟机，并自动获取和更新 Ubuntu 镜像。

由于支持 cloud-init 元数据，开发者可以在笔记本或工作站上模拟小型云部署环境。

> **GitHub 仓库**：[https://github.com/canonical/multipass](https://github.com/canonical/multipass)
> **官方文档**：[https://canonical.com/multipass/docs](https://canonical.com/multipass/docs)

---

## 核心特性

| 特性 | 说明 |
|------|------|
| **跨平台支持** | 支持 Linux、macOS、Windows |
| **多虚拟化后端** | QEMU、KVM、Hyper-V、Apple VZ、VirtualBox |
| **cloud-init 支持** | 通过 cloud-init 自定义实例配置 |
| **镜像管理** | 自动获取和更新 Ubuntu 镜像，支持多个远程源 |
| **文件挂载** | 支持将主机目录挂载到虚拟机（SSHFS/原生挂载） |
| **快照功能** | 支持创建、恢复、删除虚拟机快照 |
| **实例克隆** | 支持克隆现有虚拟机实例 |
| **命令别名** | 支持创建实例内命令的主机别名 |
| **GUI 客户端** | 提供基于 Flutter 的图形界面客户端 |
| **gRPC 通信** | 客户端与守护进程通过 gRPC 进行通信 |
| **TLS 安全** | 客户端与守护进程之间使用 TLS 加密通信 |
| **设置系统** | 支持持久化配置，可通过 `get`/`set` 命令管理 |

---

## 支持平台与虚拟化后端

```
平台          默认后端              可选后端
─────────────────────────────────────────────
Linux         QEMU + KVM           VirtualBox
macOS         QEMU                 Apple VZ、VirtualBox
Windows       Hyper-V              VirtualBox
```

### 各后端说明

| 后端 | 平台 | 说明 |
|------|------|------|
| **QEMU** | Linux/macOS | 开源虚拟化，Linux 上结合 KVM 加速 |
| **KVM** | Linux | 内核级虚拟化，性能最优 |
| **Hyper-V** | Windows | Windows 原生虚拟化技术 |
| **Apple VZ** | macOS (Apple Silicon) | Apple Virtualization Framework，性能优异 |
| **VirtualBox** | Linux/macOS/Windows | 跨平台虚拟化，社区支持 |

---

## 快速上手

### 安装

```bash
# Linux（Snap）
sudo snap install multipass

# macOS（Homebrew，非官方支持）
brew install --cask multipass

# Windows/macOS：从 GitHub Releases 下载安装包
# https://github.com/canonical/multipass/releases
```

### 基本使用

```bash
# 查找可用镜像
multipass find

# 启动最新 Ubuntu LTS 实例
multipass launch lts

# 列出所有实例
multipass list

# 查看实例详情
multipass info <实例名>

# 连接到实例
multipass shell <实例名>

# 在实例内执行命令
multipass exec <实例名> -- <命令>

# 停止实例
multipass stop <实例名>

# 删除实例
multipass delete <实例名>

# 彻底清除已删除的实例
multipass purge
```

### 默认资源配置

| 资源 | 默认值 | 最小值 |
|------|--------|--------|
| CPU 核心数 | 1 | 1 |
| 内存 | 1 GB | 128 MB |
| 磁盘空间 | 5 GB | 512 MB |
| 启动超时 | 300 秒 | - |

---

## 项目结构概览

```
multipass/
├── src/                    # 核心源代码
│   ├── daemon/             # 守护进程（multipassd）
│   ├── client/             # 客户端
│   │   ├── cli/            # 命令行客户端（multipass）
│   │   ├── common/         # 客户端公共代码
│   │   └── gui/            # GUI 客户端（Flutter）
│   ├── platform/           # 平台抽象层
│   │   ├── backends/       # 虚拟化后端实现
│   │   │   ├── qemu/       # QEMU 后端
│   │   │   ├── hyperv/     # Hyper-V 后端
│   │   │   ├── applevz/    # Apple VZ 后端
│   │   │   ├── virtualbox/ # VirtualBox 后端
│   │   │   └── shared/     # 后端共享代码
│   │   ├── console/        # 控制台抽象
│   │   ├── logger/         # 平台日志
│   │   └── update/         # 更新提示
│   ├── rpc/                # gRPC 协议定义（.proto）
│   ├── ssh/                # SSH 客户端与 SFTP
│   ├── sshfs_mount/        # SSHFS 挂载实现
│   ├── settings/           # 配置持久化
│   ├── logging/            # 日志系统
│   ├── network/            # 网络工具（IP、下载）
│   ├── cert/               # TLS 证书管理
│   ├── image_host/         # 镜像源管理
│   ├── simplestreams/      # SimpleStreams 协议
│   ├── iso/                # cloud-init ISO 生成
│   ├── petname/            # 实例名称生成器
│   ├── process/            # 进程管理
│   ├── utils/              # 通用工具函数
│   └── xz_decoder/         # XZ 镜像解码
├── include/multipass/      # 公共头文件（接口定义）
├── data/                   # 数据文件（cloud-init 模板、发行版信息）
├── docs/                   # 文档
├── tests/                  # 测试代码
├── 3rd-party/              # 第三方依赖
└── packaging/              # 打包配置
```

---

## 核心概念

### 实例（Instance）
虚拟机实例是 Multipass 的核心管理对象。每个实例有唯一名称（自动生成或用户指定），包含独立的磁盘镜像、网络配置和运行状态。

**实例状态：**

| 状态 | 说明 |
|------|------|
| `off` | 关闭（未初始化） |
| `stopped` | 已停止 |
| `starting` | 正在启动 |
| `restarting` | 正在重启 |
| `running` | 运行中 |
| `delayed_shutdown` | 延迟关机中 |
| `suspending` | 正在挂起 |
| `suspended` | 已挂起 |
| `unknown` | 状态未知 |

### 镜像（Image）
Multipass 从 Ubuntu 官方 SimpleStreams 服务器获取镜像，支持多个远程源：
- `release`：Ubuntu 正式发布版
- `daily`：Ubuntu 每日构建版
- `snapcraft`：Snapcraft 专用镜像
- `core`：Ubuntu Core 镜像

### 快照（Snapshot）
快照是虚拟机在某一时刻的完整状态备份，支持树形结构（父子关系）。可以随时恢复到快照状态。

### 挂载（Mount）
支持将主机目录挂载到虚拟机内部，有两种模式：
- **Classic（SSHFS）**：通过 SSH 文件系统协议挂载，跨平台兼容
- **Native**：使用平台原生挂载机制（如 Windows 的 SMB）

### 别名（Alias）
允许在主机上创建快捷命令，直接执行虚拟机内的程序，无需手动 SSH 进入实例。

### 守护进程（Daemon）
`multipassd` 是后台服务进程，负责管理所有虚拟机实例。客户端（CLI/GUI）通过 gRPC 与守护进程通信。

---

## 技术栈

| 组件 | 技术 |
|------|------|
| **核心语言** | C++17 |
| **GUI 客户端** | Flutter/Dart |
| **构建系统** | CMake |
| **RPC 框架** | gRPC + Protocol Buffers |
| **Qt 框架** | Qt 6.9.x（网络、事件循环、设置） |
| **SSH 库** | libssh |
| **JSON 处理** | jsoncpp、Boost.JSON |
| **YAML 处理** | yaml-cpp |
| **TLS/证书** | OpenSSL |
| **包管理** | vcpkg（Windows/macOS）、系统包（Linux） |
| **测试框架** | Google Test |
| **CI/CD** | GitHub Actions |
| **Linux 打包** | Snap |
| **macOS/Windows 打包** | CPack |

---

## 许可证

本项目基于 **GNU General Public License v3.0** 开源。

所有贡献者必须签署 [Canonical 贡献者许可协议（CLA）](https://ubuntu.com/legal/contributors)。

---

*文档生成时间：2026-04-05 | 版本：v1.0*
