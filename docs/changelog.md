# Changelog

## [Unreleased] - 2026-04-05

### 新增

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
