# TODO：国内主流 Linux 发行版镜像支持

- [x] 1. 调研并收集各发行版镜像元数据（CentOS/TencentOS/Kylin）
- [x] 2. 更新 `distribution-info.json`，添加三个发行版的镜像条目
- [x] 3. 实现 CentOS Stream 镜像抓取器插件
- [x] 4. 实现 TencentOS 镜像抓取器插件
- [x] 5. 实现麒麟镜像抓取器插件
- [x] 6. 添加各发行版的 cloud-init 默认配置
- [x] 7. 验证别名解析与 `multipass find` 展示
- [x] 8. 端到端启动与 SSH 连通性测试
- [x] 9. 更新文档

## cloud-init 兼容性优化

- [x] 10. 修复 network-config 格式兼容性：为 RHEL 系镜像（CentOS Stream 8、tlinux 等）生成 `version: 1` 格式的网络配置，解决旧版 cloud-init 不支持 Netplan `version: 2` 导致网络不通的问题
- [x] 11. 抽取 `is_rhel_based` 判断逻辑，统一覆盖 CentOS 和 tlinux/TencentOS 系列镜像识别
