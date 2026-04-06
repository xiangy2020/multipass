# 实施计划：TDSQL 集群节点初始化支持

- [ ] 1. 新增 `--tdsql-init` / `-T` 参数及 `--ntp-server` 参数解析
   - 在 `create-cluster.sh` 的参数解析区块中添加 `-T|--tdsql-init` 布尔开关和 `--ntp-server` 字符串参数
   - 设置 `NTP_SERVER` 默认值为 `ntp.aliyun.com`
   - _需求：1.1、1.2、3.4、3.5_

- [ ] 2. 更新帮助信息
   - 在 `usage()` 函数中添加 `--tdsql-init` 和 `--ntp-server` 的说明
   - _需求：1.3_

- [ ] 3. 更新启动信息展示
   - 在打印资源配置的 `[INFO]` 区块中，当 `TDSQL_INIT=true` 时追加显示 `TDSQL 初始化: 已启用（NTP: <server>）`
   - _需求：4.1、4.2_

- [ ] 4. 在 cloud-init 生成函数中追加 TDSQL 初始化命令块
   - 当 `TDSQL_INIT=true` 时，在 `runcmd` 段末尾追加以下命令序列：
     - `setenforce 0` 及修改 `/etc/selinux/config` 永久禁用 SELinux（需兼容 SELinux 不存在的情况）
     - `systemctl disable firewalld && systemctl stop firewalld`
     - `systemctl stop NetworkManager && systemctl disable NetworkManager`
     - `timedatectl set-timezone Asia/Shanghai`
     - 关闭 ntpd（`systemctl stop ntpd; systemctl disable ntpd` 忽略错误）
     - `yum install -y chrony`
     - 注释 `/etc/chrony.conf` 中原有 `server` 行，写入新 NTP 服务器配置
     - `systemctl enable chronyd && systemctl restart chronyd`
   - _需求：2.1、2.2、2.3、2.4、2.5、3.1、3.2、3.3、3.4、3.5、3.6_

- [ ] 5. 在节点创建完成汇总信息中添加验证提示
   - 当 `TDSQL_INIT=true` 时，在汇总输出末尾追加提示：可通过 `multipass exec <node> -- cloud-init status` 验证初始化是否完成
   - _需求：4.3_
