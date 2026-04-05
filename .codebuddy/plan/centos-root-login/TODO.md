# TODO：CentOS 实例 Root 密码登录支持

- [x] 1. 创建 CentOS 专用 cloud-init 默认配置文件
   - 在 `data/cloud-init-yaml/cloud-init-centos.yaml` 中添加密码登录配置
   - 配置 `ssh_pwauth: true` 启用 SSH 密码认证
   - 配置 `chpasswd` 模块为 `root` 和 `centos` 用户设置初始密码（默认 `root`/`centos`）
   - 通过 `write_files` 写入 `/etc/ssh/sshd_config.d/99-multipass-centos.conf`，设置 `PermitRootLogin yes`
   - 通过 `write_files` 写入 `/etc/motd`，添加安全警告提示用户修改默认密码
   - 通过 `runcmd` 重启 `sshd` 服务使配置生效
   - _需求：1.1、1.2、1.3、2.1、2.2、2.3、2.4、3.1_

- [x] 2. 修改 CentOS 镜像启动逻辑，自动注入 cloud-init 配置
   - 修改 `src/daemon/daemon.cpp` 中的 `make_cloud_init_vendor_config` 函数
   - 当 `image_name` 为 `centos` 或 `centos-stream` 时，自动注入密码认证配置
   - 包含：`ssh_pwauth`、`chpasswd`、`write_files`（sshd 配置 + motd）、`runcmd`
   - CentOS 不注入 pollinate 相关配置（与 fedora 同等处理）
   - _需求：2.1、2.2、2.3、2.4、2.5_

- [x] 3. 验证 SSH 密钥登录与密码登录的兼容性
   - 确认 `ssh_authorized_keys` 仍然被注入（vendor config 中保留）
   - 确认 `users: - default` 来自 `base_cloud_init_config`，默认用户保留
   - 确认 `prepare_user_data` 函数会将 vendor config 的 SSH 公钥合并到 user_data
   - `multipass shell` 命令通过密钥方式正常连接，不受密码认证配置影响
   - _需求：4.1、4.2、4.3_

- [ ] 4. 端到端测试：验证 root 密码登录全流程
   - 执行 `multipass launch centos` 启动 CentOS 实例，等待 cloud-init 完成
   - 执行 `ssh root@<instance-ip>` 使用初始密码验证 root 登录成功
   - 执行 `ssh centos@<instance-ip>` 使用初始密码验证默认用户登录成功
   - 验证登录后 `/etc/motd` 显示安全警告信息
   - 验证 `multipass shell <instance>` 仍可正常使用
   - _需求：1.4、1.5、3.1、4.1、4.2_

- [x] 5. 更新文档并记录变更
   - 在 `docs/changelog.md` 中记录本次新增 CentOS root 密码登录支持的变更内容
   - _需求：3.2、3.3_
