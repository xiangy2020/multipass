# 多磁盘挂载支持 - 任务列表

## 任务列表

- [x] 1. 扩展数据模型：添加额外磁盘配置结构（ExtraDisk结构体、VirtualMachineDescription、VMSpecs、JSON序列化）
- [x] 2. 扩展 launch 命令：支持 --extra-disk 参数（CLI解析、参数校验、proto更新）
- [x] 3. 实现额外磁盘镜像文件的创建逻辑（daemon launch流程、qemu-img create、持久化）
- [x] 4. 更新 QEMU 后端：生成多磁盘启动参数（qemu_vm_process_spec.cpp）
- [x] 5. 更新 multipass info 输出：展示额外磁盘信息（proto、daemon、CLI格式化）
- [x] 6. 支持为已有实例添加额外磁盘（multipass set 命令扩展）
- [x] 7. 快照与克隆对额外磁盘的支持
