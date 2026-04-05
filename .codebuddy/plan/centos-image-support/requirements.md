# 需求文档：国内主流 Linux 发行版镜像支持

## 引言

Multipass 目前通过 `CustomVMImageHost` 支持 Debian 和 Fedora 等非 Ubuntu 发行版镜像，镜像元数据通过 `data/distributions/distribution-info.json` 文件进行管理，并由 `tools/distro-scraper` 工具自动抓取更新。

本需求旨在为 Multipass 添加以下国内主流 Linux 发行版的镜像支持：

| 发行版 | 说明 | 镜像来源 |
|--------|------|----------|
| **CentOS Stream** | Red Hat Enterprise Linux 上游开发版，提供官方 Cloud 镜像（qcow2） | `cloud.centos.org` / 腾讯软件源 |
| **TencentOS（TLinux）** | 腾讯自研 Linux 发行版，基于 RHEL 兼容内核，广泛用于腾讯内部服务器 | 腾讯软件源 `mirrors.tencent.com/tlinux/` |
| **麒麟（Kylin）** | 国产操作系统，基于 Ubuntu/Debian，广泛用于政企环境 | 官方镜像站 / 国内镜像源 |

所有发行版均支持 cloud-init，符合 Multipass 的镜像要求。同时，为提升国内用户的使用体验，支持通过腾讯软件源（`mirrors.tencent.com`）配置国内镜像源。

---

## 需求

### 需求 1：添加 CentOS Stream 镜像支持

**用户故事：** 作为一名开发者，我希望能够通过 `multipass launch centos` 命令启动 CentOS Stream 虚拟机，以便在熟悉的 RHEL 兼容环境中进行开发和测试。

#### 验收标准

1. WHEN `distribution-info.json` 被加载 THEN 系统 SHALL 包含 CentOS Stream 的条目，包含 `os`、`release`、`release_codename`、`release_title`、`aliases`、`items` 等字段。
2. WHEN CentOS 条目被解析 THEN 系统 SHALL 支持至少 `x86_64` 和 `aarch64` 架构的镜像信息（包含 `image_location`、`id`、`version`、`size`）。
3. WHEN 用户执行 `multipass find` THEN 系统 SHALL 在列表中显示 CentOS Stream 镜像及其别名（如 `centos`、`centos-stream`）。
4. WHEN 用户执行 `multipass launch centos` THEN 系统 SHALL 识别别名并启动对应的 CentOS Stream 镜像。
5. IF 用户指定的 CentOS 版本不存在 THEN 系统 SHALL 返回清晰的错误信息，提示可用的镜像版本。
6. WHEN CentOS 实例启动后 THEN 系统 SHALL 能够通过 SSH 正常连接到实例（cloud-init 已正确注入 SSH 公钥，默认用户为 `centos` 或 `cloud-user`）。

---

### 需求 2：添加 TencentOS（TLinux）镜像支持

**用户故事：** 作为一名腾讯内部开发者，我希望能够通过 `multipass launch tencentos` 命令启动 TencentOS 虚拟机，以便在与生产环境一致的操作系统上进行开发和调试。

#### 验收标准

1. WHEN `distribution-info.json` 被加载 THEN 系统 SHALL 包含 TencentOS（TLinux）的条目，支持 TencentOS 2.x 和 3.x 系列。
2. WHEN 用户执行 `multipass find` THEN 系统 SHALL 在列表中显示 TencentOS 镜像及其别名（如 `tencentos`、`tlinux`）。
3. WHEN 用户执行 `multipass launch tencentos` THEN 系统 SHALL 识别别名并启动对应的 TencentOS 镜像。
4. WHEN TencentOS 实例启动后 THEN 系统 SHALL 能够通过 SSH 正常连接到实例（cloud-init 已正确注入 SSH 公钥）。
5. WHEN TencentOS 实例启动后 THEN 系统 SHALL 自动配置腾讯软件源（`mirrors.tencent.com/tlinux/`）作为默认 yum 源，以提升国内网络环境下的软件安装速度。
6. IF TencentOS 镜像需要特殊的 cloud-init 配置（如 kvm 子机额外 rpm 包）THEN 系统 SHALL 提供相应的配置适配。

---

### 需求 3：添加麒麟（Kylin）镜像支持

**用户故事：** 作为一名政企环境开发者，我希望能够通过 `multipass launch kylin` 命令启动麒麟操作系统虚拟机，以便在国产操作系统环境中进行应用适配和测试。

#### 验收标准

1. WHEN `distribution-info.json` 被加载 THEN 系统 SHALL 包含麒麟（Kylin）的条目，支持 Kylin V10 及以上版本。
2. WHEN 用户执行 `multipass find` THEN 系统 SHALL 在列表中显示麒麟镜像及其别名（如 `kylin`、`kylinv10`）。
3. WHEN 用户执行 `multipass launch kylin` THEN 系统 SHALL 识别别名并启动对应的麒麟镜像。
4. WHEN 麒麟实例启动后 THEN 系统 SHALL 能够通过 SSH 正常连接到实例（cloud-init 已正确注入 SSH 公钥）。
5. WHEN 麒麟实例启动后 THEN 系统 SHALL 支持 `x86_64` 和 `aarch64`（ARM）架构，以满足国产 ARM 芯片（如飞腾、鲲鹏）的使用需求。
6. IF 麒麟镜像不提供官方 Cloud 镜像（qcow2）THEN 系统 SHALL 记录警告日志并在 `multipass find` 中标注该镜像的可用状态。

---

### 需求 4：国内镜像源支持（腾讯软件源）

**用户故事：** 作为一名国内用户，我希望 Multipass 启动的虚拟机实例能够自动配置国内镜像源，以便在国内网络环境下快速安装和更新软件包。

#### 验收标准

1. WHEN 用户在国内网络环境下启动 CentOS 实例 THEN 系统 SHALL 支持通过 cloud-init 配置腾讯软件源（`https://mirrors.tencent.com/repo/centos7_base.repo` 等）作为 yum 源。
2. WHEN 用户在国内网络环境下启动 TencentOS 实例 THEN 系统 SHALL 自动配置 `mirrors.tencent.com/tlinux/` 作为 yum 源（支持 tlinux 2.x/3.x 各版本）。
3. WHEN 用户在国内网络环境下启动麒麟实例 THEN 系统 SHALL 支持配置国内镜像源（如腾讯软件源或麒麟官方镜像站）作为 apt/yum 源。
4. IF 用户未显式指定镜像源 THEN 系统 SHALL 使用发行版默认的官方镜像源，不强制替换为国内源。
5. WHEN 用户通过 `--cloud-init` 参数传入自定义配置 THEN 系统 SHALL 允许用户覆盖默认的镜像源配置。
6. WHEN 配置国内镜像源时 THEN 系统 SHALL 在文档中说明各发行版对应的腾讯软件源地址，方便用户手动配置。

---

### 需求 5：实现多发行版镜像抓取器（Scraper）

**用户故事：** 作为一名维护者，我希望有自动化的镜像信息抓取工具，以便能够定期更新 `distribution-info.json` 中各发行版的镜像元数据。

#### 验收标准

1. WHEN `distro-scraper` 工具运行 THEN 系统 SHALL 分别为 CentOS Stream、TencentOS、麒麟提供独立的抓取器插件。
2. WHEN 抓取 CentOS 镜像信息 THEN 系统 SHALL 从 CentOS 官方镜像站（`https://cloud.centos.org/`）获取 qcow2 格式镜像的 URL、SHA256 校验和、文件大小及版本信息。
3. WHEN 抓取 TencentOS 镜像信息 THEN 系统 SHALL 从腾讯软件源或 TencentOS 官方镜像站获取镜像元数据。
4. WHEN 抓取麒麟镜像信息 THEN 系统 SHALL 从麒麟官方镜像站获取镜像元数据。
5. WHEN 各抓取器被注册为插件 THEN 系统 SHALL 通过 `pyproject.toml` 的 entry-points 机制自动加载。
6. IF 某个架构的镜像不可用 THEN 系统 SHALL 跳过该架构并记录警告日志，不中断其他架构的抓取。
7. WHEN 抓取完成 THEN 系统 SHALL 输出符合 `distribution-info.json` schema 的 JSON 数据。

---

### 需求 6：cloud-init 兼容性验证

**用户故事：** 作为一名用户，我希望所有新增发行版的实例能够正确初始化，以便实例启动后可以正常使用 Multipass 的所有功能（SSH、文件挂载等）。

#### 验收标准

1. WHEN 各发行版实例通过 cloud-init ISO 启动 THEN 系统 SHALL 正确注入 SSH 公钥到实例的默认用户。
2. WHEN 各发行版实例启动完成 THEN 系统 SHALL 能够执行 `multipass exec` 命令在实例内运行命令。
3. WHEN 使用基础 cloud-init 配置（`base_cloud_init_config`）时 THEN 系统 SHALL 验证各发行版镜像对 `growpart`、`manage_etc_hosts` 等配置的兼容性。
4. IF 某发行版镜像需要特殊的 cloud-init 配置 THEN 系统 SHALL 提供相应的配置适配，确保实例正常初始化。
5. WHEN CentOS/TencentOS 实例启动后 THEN 系统 SHALL 验证 SELinux 配置不影响 Multipass 的正常功能（如文件挂载）。

---

### 需求 7：文档更新

**用户故事：** 作为一名用户，我希望在官方文档中找到关于各发行版镜像支持的说明，以便了解如何使用该功能及配置国内镜像源。

#### 验收标准

1. WHEN 功能发布 THEN 系统 SHALL 在 `docs/` 目录下更新相关文档，说明各发行版镜像的使用方法和别名。
2. WHEN 查看文档 THEN 文档 SHALL 包含各发行版对应的腾讯软件源地址，方便国内用户手动配置。
3. WHEN 功能完成 THEN 系统 SHALL 在 `docs/changelog.md` 中记录各发行版镜像支持的变更内容。
4. WHEN 查看 `multipass find` 的参考文档 THEN 文档 SHALL 包含所有新增镜像的别名和版本信息说明。
