# 实施计划：多磁盘挂载支持

- [x] 1. 扩展数据模型：添加额外磁盘配置结构
   - 在 `src/platform/backends/shared/base_virtual_machine.h` 或相关头文件中定义 `ExtraDisk` 结构体（包含 `id`、`path`、`size` 字段）
   - 在 `VirtualMachineDescription` 中添加 `extra_disks` 字段（`std::vector<ExtraDisk>`）
   - 在 `VMSpecs` 中添加 `extra_disks` 字段，并更新 JSON 序列化/反序列化逻辑（`vm_specs.cpp`）
   - _需求：2.2_

- [x] 2. 扩展 launch 命令：支持 `--extra-disk` 参数
   - 在 `src/client/cli/cmd/launch.cpp` 中添加 `--extra-disk` 可重复参数解析
   - 在参数校验逻辑中添加最小值（1G）检查，不合法时返回错误
   - 将解析到的额外磁盘大小列表传入 `LaunchRequest` protobuf 消息
   - 更新 `multipass.proto` 中的 `LaunchRequest` 消息，添加 `extra_disks` 字段
   - _需求：1.1、1.2、1.3_

- [x] 3. 实现额外磁盘镜像文件的创建逻辑
   - 在 daemon 的 launch 处理流程（`src/daemon/daemon.cpp`）中，遍历 `extra_disks` 列表，调用 `qemu-img create` 为每块额外磁盘创建 qcow2 格式镜像文件
   - 镜像文件命名规则：`<instance_name>-extra-disk-<index>.qcow2`，存放于实例目录
   - 将创建成功的磁盘信息写入 `VMSpecs` 并持久化
   - _需求：1.1、2.2_

- [x] 4. 更新 QEMU 后端：生成多磁盘启动参数
   - 在 `src/platform/backends/qemu/qemu_vm_process_spec.cpp` 的参数生成逻辑中，遍历 `extra_disks` 列表
   - 为每块额外磁盘追加 `-drive file=<path>,if=none,format=qcow2,discard=unmap,id=<id>` 和 `-device scsi-hd,drive=<id>,bus=scsi0.0` 参数
   - 磁盘 ID 使用 `hdb`、`hdc` 等递增命名，避免与系统盘 `hda` 冲突
   - 启动前检查镜像文件是否存在，不存在则报错阻止启动
   - _需求：4.1、4.2、4.3_

- [x] 5. 更新 `multipass info` 输出：展示额外磁盘信息
   - 在 `InfoReply` protobuf 消息中添加额外磁盘信息字段
   - 在 daemon 的 info 处理逻辑中，读取实例的 `extra_disks` 配置并填充响应
   - 在 CLI 的 info 输出格式化代码中，增加额外磁盘列表的展示（设备名、总大小）
   - _需求：1.4、2.3_

- [x] 6. 支持为已有实例添加额外磁盘（`multipass set` 命令扩展）
   - 在 `set` 命令处理逻辑中添加 `local.<instance>.extra-disks` 属性的解析与处理
   - 校验实例必须处于停止状态，否则返回错误提示
   - 创建新磁盘镜像文件并追加到实例的 `VMSpecs.extra_disks` 列表中持久化
   - _需求：3.1、3.2、3.3_

- [x] 7. 快照与克隆对额外磁盘的支持
   - 在快照创建逻辑中，遍历 `extra_disks` 并对每块磁盘执行 `qemu-img snapshot` 操作
   - 在快照恢复逻辑中，同步恢复所有额外磁盘到对应快照状态
   - 在克隆逻辑中，为每块额外磁盘创建独立的镜像副本，并更新克隆实例的 `VMSpecs`
   - _需求：5.1、5.2、5.3_
