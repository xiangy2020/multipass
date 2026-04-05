# Changelog

## [Unreleased] - 2026-04-05

### 新增

#### CentOS Stream 多版本支持（Stream 8 和 Stream 9）

新增 CentOS Stream 8 镜像支持，并引入版本化别名，用户可通过 `centos:8` / `centos:9` 明确指定版本：

- **CentOS Stream 9**（默认）：别名 `centos`、`centos-stream`、`centos:9`、`centos-stream:9`
- **CentOS Stream 8**：别名 `centos:8`、`centos-stream:8`，使用官方 `cloud.centos.org` 镜像
- **cloud-init 密码登录**：所有 CentOS 系列版本（含版本化别名）均自动注入 root 密码登录配置
- **distro-scraper 扩展**：`centos.py` 支持多版本并发抓取，`cli.py` 支持 scraper 返回多条目列表

**使用示例：**

```bash
# 启动默认版本（Stream 9）
multipass launch centos

# 明确指定 Stream 9
multipass launch centos:9

# 启动 Stream 8
multipass launch centos:8

# 查看所有可用版本
multipass find
```

---

#### CentOS 实例 Root 密码登录支持

CentOS 实例现在支持通过 root 密码直接登录，无需配置 SSH 密钥：

- **自动注入密码配置**：`multipass launch centos` 启动的实例会自动通过 cloud-init vendor config 配置密码登录
- **默认凭据**：`root` 用户密码为 `root`，`centos` 用户密码为 `centos`
- **SSH 密码认证**：自动启用 `PasswordAuthentication yes` 和 `PermitRootLogin yes`
- **安全警告**：登录后 `/etc/motd` 会显示安全提示，建议立即修改默认密码
- **兼容性**：SSH 密钥登录方式保持不变，`multipass shell` 命令正常工作

**使用示例：**

```bash
# 启动 CentOS 实例
multipass launch centos --name my-centos

# 获取实例 IP
multipass info my-centos

# 使用 root 密码登录（密码：root）
ssh root@<instance-ip>

# 使用 centos 用户密码登录（密码：centos）
ssh centos@<instance-ip>
```

> ⚠️ **安全提示**：默认密码仅用于开发调试环境，生产环境请立即修改密码。

---

#### 国内主流 Linux 发行版镜像支持

新增对以下三个发行版的镜像支持，用户可通过 `multipass launch <alias>` 直接启动：

| 发行版 | 别名 | 架构 | 镜像来源 |
|--------|------|------|----------|
| CentOS Stream 9 | `centos`, `centos-stream` | x86_64, arm64 | `cloud.centos.org` |
| TencentOS Server 3.x | `tencentos`, `tlinux` | x86_64, arm64 | 腾讯软件源（占位，待官方发布 Cloud 镜像） |
| 麒麟 V10（OpenKylin） | `kylin`, `kylinv10` | x86_64, arm64 | 阿里云镜像站（占位，待官方发布 Cloud 镜像） |

**使用示例：**

```bash
# 启动 CentOS Stream 9
multipass launch centos

# 启动 CentOS Stream 9 并配置腾讯软件源
multipass launch centos --cloud-init data/cloud-init-yaml/cloud-init-centos.yaml

# 启动 TencentOS（含腾讯软件源自动配置）
multipass launch tencentos --cloud-init data/cloud-init-yaml/cloud-init-tencentos.yaml

# 启动麒麟 V10
multipass launch kylin --cloud-init data/cloud-init-yaml/cloud-init-kylin.yaml
```

#### 新增 cloud-init 配置文件

- `data/cloud-init-yaml/cloud-init-centos.yaml`：CentOS Stream 基础配置，含腾讯软件源（注释形式）
- `data/cloud-init-yaml/cloud-init-tencentos.yaml`：TencentOS 配置，自动配置腾讯软件源
- `data/cloud-init-yaml/cloud-init-kylin.yaml`：麒麟配置，含阿里云镜像源（注释形式）

#### 新增 distro-scraper 插件

- `centos`：从 `cloud.centos.org` 自动抓取 CentOS Stream 最新 qcow2 镜像元数据
- `tencentos`：从腾讯软件源抓取 TencentOS 镜像元数据（若无 Cloud 镜像则返回占位数据）
- `kylin`：从阿里云/华为云镜像站抓取麒麟镜像元数据（若无 Cloud 镜像则返回占位数据）

### 说明

- **TencentOS** 和 **麒麟** 目前暂无公开的标准 qcow2 Cloud 镜像（NoCloud datasource），`distribution-info.json` 中使用占位数据。待官方发布 Cloud 镜像后，可重新运行 `distro-scraper` 自动更新。
- **CentOS Stream** 已有完整的真实镜像数据，可直接使用。
- 国内镜像源配置（腾讯软件源 `mirrors.tencent.com`）通过 cloud-init 配置文件提供，用户可按需启用。
