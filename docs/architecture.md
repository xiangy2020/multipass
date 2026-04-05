---
doc_name: "Multipass 架构设计文档"
doc_type: "技术文档"
version: "v1.0"
generated_at: "2026-04-05 16:29:12"
project_root: "/Users/tompyang/Documents/code/multipass"
project_type: "general"
project_lang: "C++"
doc_status: "draft"
doc_depth: "standard"
analyzed_files:
  - "src/daemon/daemon.h"
  - "src/daemon/daemon_config.h"
  - "src/daemon/daemon_rpc.h"
  - "src/rpc/multipass.proto"
  - "include/multipass/virtual_machine.h"
  - "include/multipass/virtual_machine_factory.h"
  - "include/multipass/platform.h"
  - "include/multipass/settings/settings.h"
  - "include/multipass/constants.h"
---

# Multipass 架构设计文档

## 目录

- [整体架构](#整体架构)
- [客户端-守护进程架构](#客户端-守护进程架构)
- [gRPC 通信层](#grpc-通信层)
- [守护进程内部架构](#守护进程内部架构)
- [虚拟化后端架构](#虚拟化后端架构)
- [平台抽象层](#平台抽象层)
- [镜像管理架构](#镜像管理架构)
- [挂载系统架构](#挂载系统架构)
- [配置系统架构](#配置系统架构)
- [安全架构](#安全架构)
- [关键数据流](#关键数据流)

---

## 整体架构

Multipass 采用**客户端-守护进程（Client-Daemon）**架构，通过 gRPC 进行进程间通信。

```mermaid
graph TB
    subgraph 客户端层
        CLI[multipass CLI<br/>命令行客户端]
        GUI[multipass GUI<br/>Flutter 图形客户端]
    end

    subgraph 通信层
        GRPC[gRPC over Unix Socket / TCP<br/>TLS 加密]
    end

    subgraph 守护进程层
        DAEMON[multipassd<br/>守护进程]
        subgraph 核心组件
            VM_MGR[虚拟机管理器]
            IMG_VAULT[镜像仓库]
            SETTINGS[配置系统]
            CERT[证书管理]
        end
    end

    subgraph 虚拟化后端
        QEMU[QEMU/KVM<br/>Linux/macOS]
        HYPERV[Hyper-V<br/>Windows]
        APPLEVZ[Apple VZ<br/>macOS ARM]
        VBOX[VirtualBox<br/>跨平台]
    end

    subgraph 外部服务
        UBUNTU_STREAMS[Ubuntu SimpleStreams<br/>镜像源]
        CLOUD_INIT[cloud-init<br/>实例初始化]
    end

    CLI --> GRPC
    GUI --> GRPC
    GRPC --> DAEMON
    DAEMON --> VM_MGR
    DAEMON --> IMG_VAULT
    DAEMON --> SETTINGS
    DAEMON --> CERT
    VM_MGR --> QEMU
    VM_MGR --> HYPERV
    VM_MGR --> APPLEVZ
    VM_MGR --> VBOX
    IMG_VAULT --> UBUNTU_STREAMS
    QEMU --> CLOUD_INIT
    HYPERV --> CLOUD_INIT
```

---

## 客户端-守护进程架构

### 通信方式

| 平台 | 通信地址 | 说明 |
|------|----------|------|
| Linux | `unix:/run/multipass_socket` | Unix Domain Socket |
| macOS | `unix:/var/run/multipass_socket` | Unix Domain Socket |
| Windows | `localhost:50051` | TCP 本地回环 |

### 认证机制

客户端与守护进程之间使用 **TLS 双向认证**：
1. 守护进程生成自签名根证书（`multipass_root_cert.pem`）
2. 客户端首次连接时需要通过认证（passphrase 或证书）
3. 认证成功后，客户端证书被存储在 `authenticated-certs/` 目录

```mermaid
sequenceDiagram
    participant C as 客户端
    participant D as 守护进程

    C->>D: 连接请求（TLS）
    D->>C: 服务器证书
    C->>D: 客户端证书
    D->>D: 验证客户端证书
    alt 证书已认证
        D->>C: 连接成功
    else 证书未认证
        D->>C: 需要认证
        C->>D: authenticate(passphrase)
        D->>D: 验证 passphrase，存储证书
        D->>C: 认证成功
    end
```

---

## gRPC 通信层

### RPC 服务定义

Multipass 使用 Protocol Buffers 定义 RPC 接口（`src/rpc/multipass.proto`），所有 RPC 均为**双向流式**（`stream`），支持实时进度反馈。

**完整 RPC 接口列表：**

| RPC 方法 | 功能 | 请求类型 | 响应类型 |
|----------|------|----------|----------|
| `launch` | 启动/创建实例 | `LaunchRequest` | `LaunchReply` |
| `create` | 创建实例（同 launch） | `LaunchRequest` | `LaunchReply` |
| `start` | 启动已停止的实例 | `StartRequest` | `StartReply` |
| `stop` | 停止实例 | `StopRequest` | `StopReply` |
| `suspend` | 挂起实例 | `SuspendRequest` | `SuspendReply` |
| `restart` | 重启实例 | `RestartRequest` | `RestartReply` |
| `delet` | 删除实例 | `DeleteRequest` | `DeleteReply` |
| `purge` | 彻底清除已删除实例 | `PurgeRequest` | `PurgeReply` |
| `recover` | 恢复已删除实例 | `RecoverRequest` | `RecoverReply` |
| `find` | 查找可用镜像 | `FindRequest` | `FindReply` |
| `list` | 列出实例/快照 | `ListRequest` | `ListReply` |
| `info` | 获取实例详情 | `InfoRequest` | `InfoReply` |
| `networks` | 列出网络接口 | `NetworksRequest` | `NetworksReply` |
| `mount` | 挂载目录 | `MountRequest` | `MountReply` |
| `umount` | 卸载目录 | `UmountRequest` | `UmountReply` |
| `ssh_info` | 获取 SSH 连接信息 | `SSHInfoRequest` | `SSHInfoReply` |
| `snapshot` | 创建快照 | `SnapshotRequest` | `SnapshotReply` |
| `restore` | 恢复快照 | `RestoreRequest` | `RestoreReply` |
| `clone` | 克隆实例 | `CloneRequest` | `CloneReply` |
| `get` | 获取配置项 | `GetRequest` | `GetReply` |
| `set` | 设置配置项 | `SetRequest` | `SetReply` |
| `keys` | 列出配置键 | `KeysRequest` | `KeysReply` |
| `authenticate` | 认证客户端 | `AuthenticateRequest` | `AuthenticateReply` |
| `version` | 获取版本信息 | `VersionRequest` | `VersionReply` |
| `daemon_info` | 获取守护进程信息 | `DaemonInfoRequest` | `DaemonInfoReply` |
| `wait_ready` | 等待守护进程就绪 | `WaitReadyRequest` | `WaitReadyReply` |
| `ping` | 心跳检测 | `PingRequest` | `PingReply` |

---

## 守护进程内部架构

### 核心类结构

```mermaid
classDiagram
    class Daemon {
        +DaemonConfig config
        +InstanceTable operative_instances
        +InstanceTable deleted_instances
        +launch()
        +start()
        +stop()
        +suspend()
        +restart()
        +delet()
        +purge()
        +find()
        +list()
        +info()
        +mount()
        +snapshot()
        +restore()
        +clone()
        +get()
        +set()
        +authenticate()
    }

    class DaemonConfig {
        +URLDownloader url_downloader
        +VirtualMachineFactory factory
        +VMImageVault vault
        +NameGenerator name_generator
        +SSHKeyProvider ssh_key_provider
        +CertProvider cert_provider
        +CertStore client_cert_store
        +MultiplexingLogger logger
    }

    class DaemonRpc {
        +grpc::Server server
        +start_server()
        +shutdown()
    }

    class VirtualMachine {
        <<abstract>>
        +State state
        +start()
        +shutdown()
        +suspend()
        +current_state()
        +ssh_port()
        +ssh_hostname()
        +ssh_exec()
        +take_snapshot()
        +restore_snapshot()
    }

    class VMStatusMonitor {
        <<interface>>
        +on_resume()
        +on_shutdown()
        +on_suspend()
        +on_restart()
        +persist_state_for()
    }

    Daemon --|> VMStatusMonitor
    Daemon *-- DaemonConfig
    Daemon *-- DaemonRpc
    Daemon *-- VirtualMachine : manages many
```

### DaemonConfig 依赖关系

`DaemonConfig` 是守护进程的核心配置容器，通过依赖注入方式组装所有核心组件：

```mermaid
graph LR
    DC[DaemonConfig] --> URL[URLDownloader<br/>镜像下载]
    DC --> FACTORY[VirtualMachineFactory<br/>VM 工厂]
    DC --> VAULT[VMImageVault<br/>镜像仓库]
    DC --> HOSTS[VMImageHost[]<br/>镜像源列表]
    DC --> NAMEGEN[NameGenerator<br/>名称生成器]
    DC --> SSHKEY[SSHKeyProvider<br/>SSH 密钥]
    DC --> CERT[CertProvider<br/>TLS 证书]
    DC --> CERTSTORE[CertStore<br/>客户端证书存储]
    DC --> LOGGER[MultiplexingLogger<br/>多路日志]
    DC --> PROXY[QNetworkProxy<br/>网络代理]
```

---

## 虚拟化后端架构

### 后端继承层次

```mermaid
classDiagram
    class VirtualMachineFactory {
        <<abstract>>
        +create_virtual_machine()
        +clone_bare_vm()
        +remove_resources_for()
        +prepare_networking()
        +prepare_source_image()
        +hypervisor_health_check()
        +create_image_vault()
        +networks()
    }

    class BaseVirtualMachineFactory {
        +create_virtual_machine()
        +clone_bare_vm()
        +prepare_networking()
    }

    class QemuVirtualMachineFactory {
        +create_virtual_machine()
        +hypervisor_health_check()
        +networks()
    }

    class HypervVirtualMachineFactory {
        +create_virtual_machine()
        +hypervisor_health_check()
        +networks()
    }

    class AppleVZVirtualMachineFactory {
        +create_virtual_machine()
        +hypervisor_health_check()
    }

    class VirtualBoxVirtualMachineFactory {
        +create_virtual_machine()
        +hypervisor_health_check()
    }

    VirtualMachineFactory <|-- BaseVirtualMachineFactory
    BaseVirtualMachineFactory <|-- QemuVirtualMachineFactory
    BaseVirtualMachineFactory <|-- HypervVirtualMachineFactory
    BaseVirtualMachineFactory <|-- AppleVZVirtualMachineFactory
    BaseVirtualMachineFactory <|-- VirtualBoxVirtualMachineFactory
```

### 虚拟机实例继承层次

```mermaid
classDiagram
    class VirtualMachine {
        <<abstract>>
        +State state
        +start()
        +shutdown()
        +suspend()
        +current_state()
        +ssh_exec()
        +take_snapshot()
        +restore_snapshot()
    }

    class BaseVirtualMachine {
        +wait_until_ssh_up()
        +wait_for_cloud_init()
        +ssh_exec()
        +take_snapshot()
        +load_snapshots()
    }

    class QemuVirtualMachine {
        +start()
        +shutdown()
        +suspend()
        +current_state()
    }

    class HypervVirtualMachine {
        +start()
        +shutdown()
        +suspend()
        +current_state()
    }

    class AppleVZVirtualMachine {
        +start()
        +shutdown()
        +current_state()
    }

    class VirtualBoxVirtualMachine {
        +start()
        +shutdown()
        +suspend()
        +current_state()
    }

    VirtualMachine <|-- BaseVirtualMachine
    BaseVirtualMachine <|-- QemuVirtualMachine
    BaseVirtualMachine <|-- HypervVirtualMachine
    BaseVirtualMachine <|-- AppleVZVirtualMachine
    BaseVirtualMachine <|-- VirtualBoxVirtualMachine
```

---

## 平台抽象层

`Platform` 类（单例）提供平台相关功能的统一接口，各平台有独立实现：

| 平台文件 | 说明 |
|----------|------|
| `platform_linux.cpp` | Linux 平台实现 |
| `platform_osx.cpp` | macOS 平台实现 |
| `platform_win.cpp` | Windows 平台实现 |
| `platform_unix.cpp` | Unix 通用实现（Linux/macOS 共享） |

**Platform 主要职责：**
- 获取网络接口信息
- 文件权限管理（`chown`、`chmod`）
- 别名脚本管理
- 默认虚拟化后端选择
- 日志系统创建
- 更新提示创建
- 进程创建（SSHFS 服务器等）

---

## 镜像管理架构

```mermaid
graph TB
    subgraph 镜像源
        UBUNTU[UbuntuImageHost<br/>Ubuntu SimpleStreams]
        CUSTOM[CustomImageHost<br/>自定义镜像源]
    end

    subgraph 镜像仓库
        VAULT[DefaultVMImageVault<br/>镜像缓存与管理]
    end

    subgraph 下载
        DOWNLOADER[URLDownloader<br/>HTTP 下载器]
        XZ[XZImageDecoder<br/>XZ 解压]
    end

    subgraph 存储
        CACHE[缓存目录<br/>~/.cache/multipassd]
        DATA[数据目录<br/>~/.local/share/multipassd]
    end

    UBUNTU --> VAULT
    CUSTOM --> VAULT
    VAULT --> DOWNLOADER
    DOWNLOADER --> XZ
    XZ --> CACHE
    VAULT --> DATA
```

### SimpleStreams 协议

Multipass 使用 Ubuntu 的 SimpleStreams 协议获取镜像元数据：
1. 下载 `streams/v1/index.json` 获取流索引
2. 根据索引下载对应的 manifest 文件
3. 从 manifest 中解析镜像信息（版本、哈希、下载 URL）
4. 按需下载镜像文件（`.img` 或 `.xz` 格式）

---

## 挂载系统架构

Multipass 支持两种挂载方式：

```mermaid
graph LR
    subgraph 主机
        HOST_DIR[主机目录]
    end

    subgraph 挂载方式
        SSHFS[SSHFS 挂载<br/>Classic 模式]
        NATIVE[原生挂载<br/>Native 模式]
    end

    subgraph 虚拟机
        VM_DIR[虚拟机目录]
    end

    HOST_DIR --> SSHFS
    HOST_DIR --> NATIVE
    SSHFS --> VM_DIR
    NATIVE --> VM_DIR
```

### SSHFS 挂载流程

```mermaid
sequenceDiagram
    participant D as 守护进程
    participant VM as 虚拟机
    participant SFTP as SFTP 服务器

    D->>SFTP: 启动 SFTP 服务器进程（监听主机目录）
    D->>VM: SSH 连接
    D->>VM: 在 VM 内启动 sshfs 客户端
    VM->>SFTP: SFTP 连接（通过 SSH 隧道）
    SFTP->>VM: 提供文件系统访问
```

---

## 配置系统架构

```mermaid
classDiagram
    class Settings {
        <<Singleton>>
        +register_handler()
        +unregister_handler()
        +keys()
        +get()
        +set()
        +get_as~T~()
    }

    class SettingsHandler {
        <<interface>>
        +keys()
        +get()
        +set()
    }

    class PersistentSettingsHandler {
        +QSettings backend
        +keys()
        +get()
        +set()
    }

    class InstanceSettingsHandler {
        +keys()
        +get()
        +set()
    }

    class SnapshotSettingsHandler {
        +keys()
        +get()
        +set()
    }

    Settings *-- SettingsHandler : manages many
    SettingsHandler <|-- PersistentSettingsHandler
    SettingsHandler <|-- InstanceSettingsHandler
    SettingsHandler <|-- SnapshotSettingsHandler
```

### 配置键（Settings Keys）

| 配置键 | 说明 | 默认值 |
|--------|------|--------|
| `client.primary-name` | 主实例名称 | `primary` |
| `local.driver` | 虚拟化后端 | 平台默认 |
| `local.passphrase` | 认证密码短语 | 无 |
| `local.bridged-network` | 桥接网络名称 | 无 |
| `local.privileged-mounts` | 是否允许特权挂载 | 平台默认 |
| `client.apps.windows-terminal.profiles` | Windows Terminal 配置 | 无 |
| `local.image.mirror` | 镜像镜像源 | 无 |

---

## 安全架构

### TLS 证书体系

```mermaid
graph TB
    subgraph 守护进程
        ROOT_CERT[根证书<br/>multipass_root_cert.pem]
        SERVER_CERT[服务器证书]
        CERT_STORE[客户端证书存储<br/>authenticated-certs/]
    end

    subgraph 客户端
        CLIENT_CERT[客户端证书]
    end

    ROOT_CERT --> SERVER_CERT
    ROOT_CERT --> CLIENT_CERT
    CLIENT_CERT --> CERT_STORE
```

### 认证流程

1. **首次连接**：客户端生成自签名证书，尝试连接守护进程
2. **未认证状态**：守护进程拒绝未认证客户端的大多数操作
3. **认证**：用户通过 `multipass authenticate <passphrase>` 认证
4. **证书存储**：认证成功后，客户端证书被存储，后续连接自动认证

### 文件权限

- 守护进程以 root 权限运行（Linux/macOS）
- 客户端以普通用户权限运行
- Socket 文件权限受限，防止未授权访问

---

## 关键数据流

### 实例启动流程（`multipass launch`）

```mermaid
sequenceDiagram
    participant CLI as CLI 客户端
    participant DAEMON as 守护进程
    participant VAULT as 镜像仓库
    participant FACTORY as VM 工厂
    participant VM as 虚拟机

    CLI->>DAEMON: launch(LaunchRequest)
    DAEMON->>DAEMON: 生成实例名称（petname）
    DAEMON->>VAULT: 获取/下载镜像
    VAULT-->>DAEMON: 镜像路径
    DAEMON->>DAEMON: 生成 cloud-init ISO
    DAEMON->>FACTORY: create_virtual_machine(desc)
    FACTORY-->>DAEMON: VirtualMachine 实例
    DAEMON->>VM: start()
    VM-->>DAEMON: 启动进度
    DAEMON->>VM: wait_until_ssh_up()
    DAEMON->>VM: wait_for_cloud_init()
    DAEMON->>DAEMON: 初始化挂载点
    DAEMON-->>CLI: LaunchReply(vm_instance_name)
```

### 快照创建流程（`multipass snapshot`）

```mermaid
sequenceDiagram
    participant CLI as CLI 客户端
    participant DAEMON as 守护进程
    participant VM as 虚拟机

    CLI->>DAEMON: snapshot(SnapshotRequest)
    DAEMON->>DAEMON: 查找实例
    DAEMON->>VM: take_snapshot(specs, name, comment)
    VM->>VM: 暂停 VM（如需要）
    VM->>VM: 创建磁盘快照
    VM->>VM: 保存快照元数据
    VM-->>DAEMON: Snapshot 对象
    DAEMON->>DAEMON: 持久化实例状态
    DAEMON-->>CLI: SnapshotReply(snapshot_name)
```

---

*文档生成时间：2026-04-05 | 版本：v1.0*
