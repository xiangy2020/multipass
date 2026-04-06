# 需求文档：TDSQL 集群节点初始化支持

## 引言

在使用 `create-cluster.sh` 脚本创建 Multipass 虚拟机集群时，如果目标集群用于部署 TDSQL，需要对每个节点执行一系列标准化的系统初始化操作。这些操作包括：关闭 SELinux、关闭防火墙、关闭 NetworkManager、设置时区、配置时间同步（chrony）等。

本功能通过在脚本中新增 `--tdsql-init` 开关参数，当用户指定该参数时，自动将上述初始化动作集成到 cloud-init 配置中，在节点首次启动时自动完成所有初始化，无需人工逐台操作。

---

## 需求

### 需求 1：新增 TDSQL 初始化开关参数

**用户故事：** 作为一名需要搭建 TDSQL 集群的运维人员，我希望在创建集群时通过一个参数开关来启用 TDSQL 节点初始化，以便无需手动逐台执行初始化脚本。

#### 验收标准

1. WHEN 用户在执行 `create-cluster.sh` 时传入 `--tdsql-init`（或 `-T`）参数 THEN 系统 SHALL 在 cloud-init 配置中追加 TDSQL 初始化相关命令
2. WHEN 用户未传入 `--tdsql-init` 参数 THEN 系统 SHALL 保持原有行为不变，不执行任何 TDSQL 初始化操作
3. WHEN 用户执行 `create-cluster.sh --help` THEN 系统 SHALL 在帮助信息中显示 `--tdsql-init` 参数的说明

---

### 需求 2：安全策略初始化

**用户故事：** 作为一名 TDSQL 运维人员，我希望节点在启动后自动关闭 SELinux 和防火墙，以便 TDSQL 组件能够正常通信，不受系统安全策略干扰。

#### 验收标准

1. WHEN TDSQL 初始化启用 THEN 系统 SHALL 执行 `setenforce 0` 临时关闭 SELinux
2. WHEN TDSQL 初始化启用 THEN 系统 SHALL 修改 `/etc/selinux/config`，将 `SELINUX` 设置为 `disabled`，确保重启后永久生效
3. WHEN TDSQL 初始化启用 THEN 系统 SHALL 执行 `systemctl disable firewalld && systemctl stop firewalld` 关闭防火墙
4. WHEN TDSQL 初始化启用 THEN 系统 SHALL 执行 `systemctl stop NetworkManager && systemctl disable NetworkManager` 关闭 NetworkManager
5. WHEN TDSQL 初始化启用 THEN 系统 SHALL 执行 `timedatectl set-timezone Asia/Shanghai` 设置时区为上海

---

### 需求 3：时间同步配置（chrony）

**用户故事：** 作为一名 TDSQL 运维人员，我希望节点在启动后自动配置 chrony 时间同步服务，以便集群各节点时间保持一致，避免因时间偏差导致的分布式问题。

#### 验收标准

1. WHEN TDSQL 初始化启用 THEN 系统 SHALL 关闭并禁用 ntpd 服务（若存在）
2. WHEN TDSQL 初始化启用 THEN 系统 SHALL 安装 chrony（`yum install -y chrony`）
3. WHEN TDSQL 初始化启用 THEN 系统 SHALL 注释掉 `/etc/chrony.conf` 中原有的 `server` 配置行
4. WHEN TDSQL 初始化启用 AND 用户通过参数指定了 NTP 服务器地址 THEN 系统 SHALL 将指定的 NTP 服务器写入 `/etc/chrony.conf`
5. WHEN TDSQL 初始化启用 AND 用户未指定 NTP 服务器 THEN 系统 SHALL 使用默认 NTP 服务器（`ntp.aliyun.com`）
6. WHEN TDSQL 初始化启用 THEN 系统 SHALL 启用并重启 chronyd 服务（`systemctl enable chronyd && systemctl restart chronyd`）

---

### 需求 4：初始化信息展示

**用户故事：** 作为一名运维人员，我希望在创建集群时能清楚地看到 TDSQL 初始化是否已启用，以便确认配置正确。

#### 验收标准

1. WHEN TDSQL 初始化启用 THEN 系统 SHALL 在启动信息中显示 `[INFO] TDSQL 初始化: 已启用` 及 NTP 服务器地址
2. WHEN TDSQL 初始化未启用 THEN 系统 SHALL 不显示 TDSQL 初始化相关信息
3. WHEN 节点创建完成后 THEN 系统 SHALL 在汇总信息中提示用户可通过 `cloud-init status` 命令验证初始化是否完成
