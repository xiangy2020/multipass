# Multipass 技术文档索引

> 最后更新：2026-04-06（新增多节点集群工具章节）
> 文档总数：4 个

本目录包含 Multipass 项目的技术文档，由代码分析自动生成。

---

## 技术文档

| 文档名称 | 说明 | 版本 | 最后更新 |
|----------|------|------|----------|
| [项目总览](./overview.md) | 项目简介、核心特性、快速上手、技术栈 | v1.0 | 2026-04-05 |
| [架构设计](./architecture.md) | 整体架构、客户端-守护进程通信、gRPC 接口、数据流 | v1.0 | 2026-04-05 |
| [模块详细文档](./modules.md) | 各源码模块的详细说明、核心文件、接口定义 | v1.0 | 2026-04-05 |
| [构建与部署指南](./build-guide.md) | Linux/macOS/Windows 构建步骤、运行方式、SSH 连接虚拟机、打包发布 | v1.1 | 2026-04-05 |

---

## 工具脚本

| 脚本 | 说明 | 路径 |
|------|------|------|
| 多节点集群创建 | 一键创建 Multipass 多节点集群，支持并行启动、SSH 互信、/etc/hosts 解析、额外数据盘挂载、k3s 安装 | [tools/cluster/create-cluster.sh](../tools/cluster/create-cluster.sh) |

**快速使用：**

```bash
# 创建 3 节点 CentOS 9 集群（默认）
./tools/cluster/create-cluster.sh

# 创建 3 节点集群，每节点额外挂载 50G 数据盘到 /data
./tools/cluster/create-cluster.sh -n 3 -i centos:9 -c 4 -m 4G -d 50G -e 50G

# 创建 3 节点 k3s Kubernetes 集群
./tools/cluster/create-cluster.sh -n 3 -k

# 查看完整参数说明
./tools/cluster/create-cluster.sh --help
```

---

## 官方文档（docs/ 目录）

Multipass 官方文档采用 Sphinx 构建，按以下分类组织：

| 分类 | 目录 | 说明 |
|------|------|------|
| 教程 | [tutorial/](./tutorial/) | 新用户入门教程 |
| 操作指南 | [how-to-guides/](./how-to-guides/) | 常见任务的分步指南 |
| 参考文档 | [reference/](./reference/) | 命令参考、配置参考等技术规格 |
| 概念解释 | [explanation/](./explanation/) | 核心概念的深入解释 |

---

## 文档说明

- **技术文档**（本目录新增）：面向开发者，描述代码架构、模块设计和构建方式
- **官方文档**（原有）：面向用户，描述安装、使用和配置方法

---

*文档索引生成时间：2026-04-05*
