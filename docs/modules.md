---
doc_name: "Multipass 模块详细文档"
doc_type: "技术文档"
version: "v1.0"
generated_at: "2026-04-05 16:29:12"
project_root: "/Users/tompyang/Documents/code/multipass"
project_type: "general"
project_lang: "C++"
doc_status: "draft"
doc_depth: "standard"
analyzed_files:
  - "src/daemon/"
  - "src/client/cli/cmd/"
  - "src/platform/backends/"
  - "src/ssh/"
  - "src/sshfs_mount/"
  - "src/settings/"
  - "src/logging/"
  - "src/network/"
  - "src/cert/"
  - "src/image_host/"
  - "src/simplestreams/"
  - "src/iso/"
  - "src/petname/"
  - "src/process/"
  - "src/utils/"
  - "src/xz_decoder/"
---

# Multipass 模块详细文档

## 目录

- [守护进程模块（daemon）](#守护进程模块daemon)
- [CLI 客户端模块（client/cli）](#cli-客户端模块clientcli)
- [GUI 客户端模块（client/gui）](#gui-客户端模块clientgui)
- [平台后端模块（platform/backends）](#平台后端模块platformbackends)
- [SSH 模块（ssh）](#ssh-模块ssh)
- [SSHFS 挂载模块（sshfs_mount）](#sshfs-挂载模块sshfs_mount)
- [配置模块（settings）](#配置模块settings)
- [日志模块（logging）](#日志模块logging)
- [网络模块（network）](#网络模块network)
- [证书模块（cert）](#证书模块cert)
- [镜像源模块（image_host）](#镜像源模块image_host)
- [SimpleStreams 模块（simplestreams）](#simplestreams-模块simplestreams)
- [ISO 生成模块（iso）](#iso-生成模块iso)
- [名称生成器模块（petname）](#名称生成器模块petname)
- [进程管理模块（process）](#进程管理模块process)
- [工具函数模块（utils）](#工具函数模块utils)
- [XZ 解码模块（xz_decoder）](#xz-解码模块xz_decoder)

---

## 守护进程模块（daemon）

**目录**：`src/daemon/`

守护进程是 Multipass 的核心服务，以 `multipassd` 进程运行，负责管理所有虚拟机实例的生命周期。

### 核心文件

| 文件 | 说明 |
|------|------|
| `daemon.h / daemon.cpp` | 守护进程主类，实现所有 RPC 方法 |
| `daemon_rpc.h / daemon_rpc.cpp` | gRPC 服务器封装，处理 RPC 请求分发 |
| `daemon_config.h / daemon_config.cpp` | 守护进程配置容器与构建器 |
| `daemon_main.cpp` | Linux/macOS 守护进程入口 |
| `daemon_main_win.cpp` | Windows 守护进程入口（Windows 服务） |
| `daemon_init_settings.h / .cpp` | 守护进程初始化配置 |
| `default_vm_image_vault.h / .cpp` | 默认镜像仓库实现 |
| `delayed_shutdown_timer.h / .cpp` | 延迟关机定时器 |
| `instance_settings_handler.h / .cpp` | 实例配置处理器（CPU/内存/磁盘调整） |
| `snapshot_settings_handler.h / .cpp` | 快照配置处理器 |
| `runtime_instance_info_helper.h / .cpp` | 运行时实例信息获取辅助 |
| `base_cloud_init_config.h` | cloud-init 基础配置 |

### Daemon 类主要职责

1. **实例生命周期管理**：创建、启动、停止、挂起、重启、删除、恢复实例
2. **镜像管理**：查找可用镜像，触发镜像更新
3. **挂载管理**：创建、维护、销毁文件系统挂载点
4. **快照管理**：创建、恢复、删除快照
5. **配置管理**：通过 Settings 系统管理守护进程和实例配置
6. **状态持久化**：将实例状态持久化到磁盘（JSON 格式）
7. **异步操作**：使用 Qt 的 `QFuture` 处理耗时操作

### 实例状态持久化

实例状态以 JSON 格式存储在数据目录中：
```
~/.local/share/multipassd/
├── vault/
│   ├── instances/
│   │   ├── <instance-name>/
│   │   │   ├── ubuntu-24.04-server-cloudimg-amd64.img  # 磁盘镜像
│   │   │   └── cloud-init-config.iso                   # cloud-init 配置
│   │   └── ...
│   └── images/                                          # 镜像缓存
└── multipassd-vm-instances.json                         # 实例配置
```

---

## CLI 客户端模块（client/cli）

**目录**：`src/client/cli/`

命令行客户端，提供 `multipass` 命令，通过 gRPC 与守护进程通信。

### 核心文件

| 文件 | 说明 |
|------|------|
| `main.cpp` | CLI 入口 |
| `client.h / client.cpp` | 客户端主类，注册所有命令 |
| `argparser.h / argparser.cpp` | 命令行参数解析器 |

### CLI 命令列表

| 命令 | 文件 | 说明 |
|------|------|------|
| `launch` | `cmd/launch.cpp` | 创建并启动新实例 |
| `start` | `cmd/start.cpp` | 启动已停止的实例 |
| `stop` | `cmd/stop.cpp` | 停止运行中的实例 |
| `suspend` | `cmd/suspend.cpp` | 挂起实例 |
| `restart` | `cmd/restart.cpp` | 重启实例 |
| `delete` | `cmd/delete.cpp` | 删除实例 |
| `purge` | `cmd/purge.cpp` | 彻底清除已删除实例 |
| `recover` | `cmd/recover.cpp` | 恢复已删除实例 |
| `shell` | `cmd/shell.cpp` | 连接到实例 Shell |
| `exec` | `cmd/exec.cpp` | 在实例内执行命令 |
| `transfer` | `cmd/transfer.cpp` | 在主机和实例间传输文件 |
| `mount` | `cmd/mount.cpp` | 挂载主机目录到实例 |
| `umount` | `cmd/umount.cpp` | 卸载挂载点 |
| `find` | `cmd/find.cpp` | 查找可用镜像 |
| `list` | `cmd/list.cpp` | 列出实例 |
| `info` | `cmd/info.cpp` | 显示实例详情 |
| `networks` | `cmd/networks.cpp` | 列出网络接口 |
| `snapshot` | `cmd/snapshot.cpp` | 创建快照 |
| `restore` | `cmd/restore.cpp` | 恢复快照 |
| `clone` | `cmd/clone.cpp` | 克隆实例 |
| `alias` | `cmd/alias.cpp` | 管理命令别名 |
| `aliases` | `cmd/aliases.cpp` | 列出所有别名 |
| `unalias` | `cmd/unalias.cpp` | 删除别名 |
| `get` | `cmd/get.cpp` | 获取配置项 |
| `set` | `cmd/set.cpp` | 设置配置项 |
| `authenticate` | `cmd/authenticate.cpp` | 认证客户端 |
| `version` | `cmd/version.cpp` | 显示版本信息 |
| `help` | `cmd/help.cpp` | 显示帮助信息 |
| `prefer` | `cmd/prefer.cpp` | 设置首选项 |
| `wait-ready` | `cmd/wait_ready.cpp` | 等待守护进程就绪 |

### 输出格式

CLI 支持多种输出格式（通过 `--format` 参数）：

| 格式 | 说明 |
|------|------|
| `table` | 表格格式（默认） |
| `json` | JSON 格式 |
| `csv` | CSV 格式 |
| `yaml` | YAML 格式 |

---

## GUI 客户端模块（client/gui）

**目录**：`src/client/gui/`

基于 **Flutter** 开发的图形界面客户端，通过 FFI（Foreign Function Interface）调用 C++ 库与守护进程通信。

### 技术栈

- **框架**：Flutter/Dart
- **通信**：通过 FFI 调用 C++ gRPC 客户端
- **平台支持**：Linux、macOS、Windows

### 主要功能

- 实例列表展示与管理
- 实例启动/停止/删除操作
- 系统托盘图标
- 实例 Shell 访问

---

## 平台后端模块（platform/backends）

**目录**：`src/platform/backends/`

各虚拟化后端的具体实现。

### QEMU 后端（qemu/）

**支持平台**：Linux、macOS

| 文件 | 说明 |
|------|------|
| `qemu_virtual_machine.h / .cpp` | QEMU 虚拟机实现 |
| `qemu_virtual_machine_factory.h / .cpp` | QEMU 工厂 |
| `qemu_vm_process_spec.h / .cpp` | QEMU 进程参数规格 |
| `qemu_img_utils.h / .cpp` | qemu-img 工具封装 |
| `qemu_snapshot.h / .cpp` | QEMU 快照实现 |
| `qemu_mount_handler.h / .cpp` | QEMU 挂载处理器 |
| `linux/dnsmasq_server.h / .cpp` | Linux 上的 DNS/DHCP 服务器 |
| `linux/firewall_config.h / .cpp` | Linux 防火墙配置（iptables/nftables） |
| `linux/bridge_helper.c` | 网桥辅助程序 |
| `macos/qemu_platform_macos.h / .cpp` | macOS QEMU 平台实现 |

**QEMU 虚拟机磁盘格式**：`qcow2`（支持快照、写时复制）

### Hyper-V 后端（hyperv/）

**支持平台**：Windows

| 文件 | 说明 |
|------|------|
| `hyperv_virtual_machine.h / .cpp` | Hyper-V 虚拟机实现 |
| `hyperv_virtual_machine_factory.h / .cpp` | Hyper-V 工厂（通过 PowerShell 管理） |
| `hyperv_snapshot.h / .cpp` | Hyper-V 快照实现 |

**特点**：通过 PowerShell 命令管理 Hyper-V 虚拟机。

### Apple VZ 后端（applevz/）

**支持平台**：macOS（Apple Silicon）

| 文件 | 说明 |
|------|------|
| `applevz_virtual_machine.h / .cpp` | Apple VZ 虚拟机实现 |
| `applevz_virtual_machine_factory.h / .cpp` | Apple VZ 工厂 |
| `applevz_bridge.h / .mm` | Apple Virtualization Framework 桥接（Objective-C++） |
| `applevz_wrapper.h / .cpp` | Apple VZ 包装器 |

**特点**：使用 Apple Virtualization Framework，性能优于 QEMU，仅支持 Apple Silicon。

### VirtualBox 后端（virtualbox/）

**支持平台**：Linux、macOS、Windows

| 文件 | 说明 |
|------|------|
| `virtualbox_virtual_machine.h / .cpp` | VirtualBox 虚拟机实现 |
| `virtualbox_virtual_machine_factory.h / .cpp` | VirtualBox 工厂（通过 VBoxManage 命令） |
| `virtualbox_snapshot.h / .cpp` | VirtualBox 快照实现 |

**特点**：通过 `VBoxManage` 命令行工具管理虚拟机。

### 共享后端代码（shared/）

| 文件 | 说明 |
|------|------|
| `base_virtual_machine.h / .cpp` | 虚拟机基类，提供通用实现 |
| `base_virtual_machine_factory.h / .cpp` | 工厂基类 |
| `base_snapshot.h / .cpp` | 快照基类 |
| `snapshot_description.h / .cpp` | 快照描述数据结构 |
| `sshfs_server_process_spec.h / .cpp` | SSHFS 服务器进程规格 |
| `linux/apparmor.h / .cpp` | Linux AppArmor 配置 |
| `linux/backend_utils.h / .cpp` | Linux 后端工具函数 |
| `linux/process_factory.h / .cpp` | Linux 进程工厂 |
| `macos/backend_utils.h / .cpp` | macOS 后端工具函数 |
| `windows/smb_mount_handler.h / .cpp` | Windows SMB 挂载处理器 |
| `windows/powershell.h / .cpp` | PowerShell 执行封装 |
| `windows/aes.h / .cpp` | AES 加密（Windows 密码保护） |

---

## SSH 模块（ssh）

**目录**：`src/ssh/`

提供 SSH 连接、命令执行和 SFTP 文件传输功能，基于 **libssh** 库。

### 核心文件

| 文件 | 说明 |
|------|------|
| `ssh_session.h / .cpp` | SSH 会话管理 |
| `ssh_client.h / .cpp` | SSH 客户端（交互式 Shell） |
| `ssh_process.h / .cpp` | SSH 远程进程执行 |
| `sftp_client.h / .cpp` | SFTP 客户端（文件传输） |
| `sftp_dir_iterator.h / .cpp` | SFTP 目录迭代器 |
| `sftp_utils.h / .cpp` | SFTP 工具函数 |
| `openssh_key_provider.h / .cpp` | OpenSSH 密钥提供者 |
| `ssh_client_key_provider.h / .cpp` | SSH 客户端密钥提供者 |

### SSH 密钥管理

- 守护进程为每个实例生成专用 SSH 密钥对
- 公钥通过 cloud-init 注入到实例
- 私钥存储在守护进程数据目录中

---

## SSHFS 挂载模块（sshfs_mount）

**目录**：`src/sshfs_mount/`

实现基于 SSHFS 的文件系统挂载（Classic 挂载模式）。

### 核心文件

| 文件 | 说明 |
|------|------|
| `sftp_server.h / .cpp` | SFTP 服务器实现（在主机上运行，提供文件访问） |
| `sshfs_mount.h / .cpp` | SSHFS 挂载管理 |
| `sshfs_mount_handler.h / .cpp` | 挂载处理器（实现 MountHandler 接口） |
| `sshfs_server.h / .cpp` | SSHFS 服务器进程管理 |

### 挂载工作原理

1. 守护进程在主机上启动 SFTP 服务器，监听主机目录
2. 通过 SSH 反向隧道，将 SFTP 服务暴露给虚拟机
3. 虚拟机内的 `sshfs` 客户端连接到 SFTP 服务器
4. 主机目录以文件系统形式挂载到虚拟机内

### UID/GID 映射

SSHFS 挂载支持 UID/GID 映射，解决主机和虚拟机用户 ID 不一致的问题：
- 主机 UID/GID → 虚拟机 UID/GID 的映射关系
- 通过 `MountMaps` 数据结构配置

---

## 配置模块（settings）

**目录**：`src/settings/`

提供持久化配置管理，基于 Qt 的 `QSettings`。

### 核心文件

| 文件 | 说明 |
|------|------|
| `settings.cpp` | Settings 单例实现 |
| `persistent_settings_handler.h / .cpp` | 持久化配置处理器（基于 QSettings） |
| `basic_setting_spec.h / .cpp` | 基础配置规格 |
| `bool_setting_spec.h / .cpp` | 布尔类型配置规格 |
| `custom_setting_spec.h / .cpp` | 自定义配置规格 |
| `wrapped_qsettings.h` | QSettings 包装器 |

### 配置文件位置

| 平台 | 守护进程配置 | 客户端配置 |
|------|-------------|-----------|
| Linux | `~/.config/multipassd/multipassd.conf` | `~/.config/multipass/multipass.conf` |
| macOS | `~/Library/Preferences/multipassd.conf` | `~/Library/Preferences/multipass.conf` |
| Windows | 注册表 `HKCU\Software\multipassd` | 注册表 `HKCU\Software\multipass` |

---

## 日志模块（logging）

**目录**：`src/logging/`

提供多级别、多目标的日志系统。

### 核心文件

| 文件 | 说明 |
|------|------|
| `log.h / log.cpp` | 日志宏和全局日志函数 |
| `log_location.h / log_location.cpp` | 日志位置信息（文件名、行号） |
| `multiplexing_logger.h / .cpp` | 多路日志器（同时输出到多个目标） |
| `standard_logger.h / .cpp` | 标准日志器（输出到 stderr） |

### 平台日志器

| 文件 | 平台 | 说明 |
|------|------|------|
| `platform/logger/journald_logger.h / .cpp` | Linux | systemd journald 日志 |
| `platform/logger/syslog_logger.h / .cpp` | Linux | syslog 日志 |
| `platform/logger/linux_logger.h / .cpp` | Linux | Linux 日志选择器 |

### 日志级别

| 级别 | 说明 |
|------|------|
| `error` | 错误信息 |
| `warning` | 警告信息 |
| `info` | 一般信息（默认） |
| `debug` | 调试信息 |
| `trace` | 详细跟踪信息 |

---

## 网络模块（network）

**目录**：`src/network/`

提供网络相关工具。

### 核心文件

| 文件 | 说明 |
|------|------|
| `ip_address.h / .cpp` | IP 地址解析与操作 |
| `url_downloader.h / .cpp` | HTTP/HTTPS 文件下载器（基于 Qt Network） |

### URLDownloader 特性

- 支持 HTTP/HTTPS 下载
- 支持进度回调
- 支持代理配置
- 支持下载中断与恢复
- 支持 ETag 缓存验证

---

## 证书模块（cert）

**目录**：`src/cert/`

管理 TLS 证书，用于客户端-守护进程之间的安全通信。

### 核心文件

| 文件 | 说明 |
|------|------|
| `ssl_cert_provider.h / .cpp` | SSL 证书提供者（生成自签名证书） |
| `client_cert_store.h / .cpp` | 客户端证书存储（已认证客户端） |
| `biomem.h / .cpp` | OpenSSL BIO 内存缓冲区封装 |

### 证书生成

- 使用 OpenSSL 生成 RSA 密钥对
- 生成自签名 X.509 证书
- 证书有效期：14 天（可配置）
- 证书存储在守护进程数据目录

---

## 镜像源模块（image_host）

**目录**：`src/image_host/`

管理虚拟机镜像的来源和元数据。

### 核心文件

| 文件 | 说明 |
|------|------|
| `base_image_host.h / .cpp` | 镜像源基类 |
| `ubuntu_image_host.h / .cpp` | Ubuntu 官方镜像源（SimpleStreams） |
| `custom_image_host.h / .cpp` | 自定义镜像源（本地文件/URL） |
| `image_mutators.h / .cpp` | 镜像变换器（修改镜像元数据） |

### 支持的镜像格式

| 格式 | 说明 |
|------|------|
| `.img` | 原始磁盘镜像 |
| `.img.xz` | XZ 压缩的磁盘镜像 |
| `.qcow2` | QEMU 写时复制格式 |

---

## SimpleStreams 模块（simplestreams）

**目录**：`src/simplestreams/`

实现 Ubuntu SimpleStreams 协议，用于获取镜像元数据。

### 核心文件

| 文件 | 说明 |
|------|------|
| `simple_streams_index.h / .cpp` | SimpleStreams 索引解析 |
| `simple_streams_manifest.h / .cpp` | SimpleStreams manifest 解析 |

### SimpleStreams 数据结构

```
streams/v1/index.json
└── products/
    └── com.ubuntu.cloud:released:download
        └── streams/v1/com.ubuntu.cloud:released:download.json
            └── products/
                └── com.ubuntu.cloud:server:24.04:amd64
                    └── versions/
                        └── 20240806/
                            └── items/
                                └── disk1.img (下载信息)
```

---

## ISO 生成模块（iso）

**目录**：`src/iso/`

生成 cloud-init 配置 ISO 文件，用于虚拟机初始化。

### 核心文件

| 文件 | 说明 |
|------|------|
| `cloud_init_iso.h / .cpp` | cloud-init ISO 生成器 |
| `cloud_Init_Iso_read_me.md` | ISO 格式说明文档 |

### cloud-init ISO 内容

cloud-init ISO 遵循 **NoCloud** 数据源格式：
```
cloud-init-config.iso
├── meta-data    # 实例元数据（instance-id、hostname）
└── user-data    # 用户配置（SSH 密钥、包安装等）
```

---

## 名称生成器模块（petname）

**目录**：`src/petname/`

为新创建的虚拟机实例自动生成友好的随机名称（如 `dancing-chipmunk`）。

### 核心文件

| 文件 | 说明 |
|------|------|
| `petname.h / .cpp` | 名称生成器实现 |
| `make_name_generator.cpp` | 名称生成器工厂 |
| `adjectives.txt` | 形容词词库 |
| `adverbs.txt` | 副词词库 |
| `names.txt` | 名词词库（动物名等） |
| `text_to_string_array.cpp` | 文本转字符串数组工具 |

### 名称格式

名称由 **形容词 + 名词** 组成，例如：
- `dancing-chipmunk`
- `phlegmatic-bluebird`
- `clever-penguin`

---

## 进程管理模块（process）

**目录**：`src/process/`

提供跨平台的子进程管理功能。

### 核心文件

| 文件 | 说明 |
|------|------|
| `basic_process.h / .cpp` | 基础进程实现（基于 QProcess） |
| `process_spec.h / .cpp` | 进程规格基类（命令、参数、环境变量） |
| `simple_process_spec.h / .cpp` | 简单进程规格 |
| `qemuimg_process_spec.h / .cpp` | qemu-img 进程规格 |

### 进程规格模式

通过 `ProcessSpec` 子类定义不同类型进程的启动参数：
- 命令路径
- 命令行参数
- 工作目录
- 环境变量
- 标准输入/输出处理

---

## 工具函数模块（utils）

**目录**：`src/utils/`

提供各种通用工具函数。

### 核心文件

| 文件 | 说明 |
|------|------|
| `utils.h / utils.cpp` | 通用工具函数（字符串处理、路径操作等） |
| `file_ops.h / file_ops.cpp` | 文件操作封装 |
| `json_utils.h / json_utils.cpp` | JSON 读写工具 |
| `yaml_node_utils.h / .cpp` | YAML 节点工具 |
| `memory_size.h / .cpp` | 内存大小解析（支持 K/M/G/T 单位） |
| `vm_specs.h / .cpp` | 虚拟机规格数据结构 |
| `vm_mount.h / .cpp` | 挂载配置数据结构 |
| `vm_image_vault_utils.h / .cpp` | 镜像仓库工具函数 |
| `alias_definition.h / .cpp` | 别名定义数据结构 |
| `permission_utils.h / .cpp` | 文件权限工具 |
| `semver_compare.h / .cpp` | 语义版本比较 |
| `snap_utils.h / .cpp` | Snap 环境检测工具 |
| `standard_paths.h / .cpp` | 标准路径获取 |
| `timer.h / .cpp` | 定时器工具 |

### VMSpecs 数据结构

```cpp
struct VMSpecs {
    int num_cores;          // CPU 核心数
    MemorySize mem_size;    // 内存大小
    MemorySize disk_space;  // 磁盘大小
    std::string default_mac_addr;  // 默认 MAC 地址
    std::vector<NetworkInterface> extra_interfaces;  // 额外网络接口
    std::string ssh_username;  // SSH 用户名
    VirtualMachine::State state;  // 实例状态
    std::unordered_map<std::string, VMMount> mounts;  // 挂载配置
    bool deleted;  // 是否已删除
    std::string metadata;  // 元数据（JSON）
};
```

---

## XZ 解码模块（xz_decoder）

**目录**：`src/xz_decoder/`

解码 XZ 压缩的镜像文件。

### 核心文件

| 文件 | 说明 |
|------|------|
| `xz_image_decoder.h / .cpp` | XZ 镜像解码器 |

**特点**：使用 `xz-embedded` 库（第三方依赖），支持流式解码，适合大文件处理。

---

*文档生成时间：2026-04-05 | 版本：v1.0*
