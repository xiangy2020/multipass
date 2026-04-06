# 数据盘 multipass mount 方案任务列表

## 功能描述

将 `create-cluster.sh` 的 `--extra-disk` 实现从 `dd` 镜像文件方案改为 `multipass mount` 方案：
- 宿主机为每个节点创建独立目录 `~/.multipass-data/<prefix>/<node>/`
- 通过 `multipass mount` 将宿主机目录挂载到虚拟机指定路径
- 数据盘与虚拟机系统盘完全独立，互不影响
- 新增 `delete-cluster.sh` 脚本，删除集群时同步清理宿主机数据目录

## 任务列表

- [x] 修改 `create-cluster.sh`：将 `--extra-disk` 实现从 `dd` 镜像改为 `multipass mount` 方案
  - `-e/--extra-disk` 改为 flag（无需指定大小）
  - 新增 `mount_data_disks()` 函数，在节点启动后执行 `multipass mount`
  - 移除 cloud-init 中的 `dd`/`mkfs`/`fstab` 相关逻辑
  - 数据目录统一放在 `~/.multipass-data/<prefix>/<node>/`
- [x] 新增 `delete-cluster.sh`：删除集群时同步清理宿主机数据目录
  - 自动卸载 `multipass mount` 挂载
  - 删除并清除所有节点
  - 清理宿主机数据目录
- [x] 更新 `docs/changelog.md` 和 `docs/README.md`
- [x] 更新 TODO.md 并提交

## 使用示例

```bash
# 创建 3 节点集群，每节点挂载独立数据盘到 /data
./tools/cluster/create-cluster.sh -n 3 -i centos:9 -c 4 -m 4G -d 20G -e

# 挂载到自定义目录
./tools/cluster/create-cluster.sh -n 3 -e -t /mnt/data

# 删除集群并清理宿主机数据目录
./tools/cluster/delete-cluster.sh -p node
```

## 宿主机目录结构

```
~/.multipass-data/
└── node/                    ← 以节点前缀命名
    ├── node1/               ← node1 的数据盘
    ├── node2/               ← node2 的数据盘
    └── node3/               ← node3 的数据盘
```
