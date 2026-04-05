# 实施计划：国内主流 Linux 发行版镜像支持

- [ ] 1. 调研并收集各发行版镜像元数据
   - 访问 `https://cloud.centos.org/` 确认 CentOS Stream 9/10 的 qcow2 镜像 URL、SHA256 及文件大小（x86_64 / aarch64）
   - 访问腾讯软件源确认 TencentOS 2.x / 3.x 的 Cloud 镜像 URL 及校验信息
   - 访问麒麟官方镜像站确认 Kylin V10 的 Cloud 镜像 URL 及校验信息（x86_64 / aarch64）
   - _需求：1.1、1.2、2.1、3.1_

- [ ] 2. 更新 `distribution-info.json`，添加三个发行版的镜像条目
   - 在 `data/distributions/distribution-info.json` 中新增 CentOS Stream、TencentOS、Kylin 三个条目
   - 每个条目包含 `os`、`release`、`release_codename`、`release_title`、`aliases`、`items`（含各架构的 `image_location`、`id`、`version`、`size`）字段
   - CentOS 别名设置为 `centos`、`centos-stream`；TencentOS 别名设置为 `tencentos`、`tlinux`；Kylin 别名设置为 `kylin`、`kylinv10`
   - _需求：1.1、1.2、1.3、2.1、2.2、3.1、3.2_

- [ ] 3. 实现 CentOS Stream 镜像抓取器插件
   - 在 `tools/distro-scraper/` 下新建 `centos_scraper.py`，从 `https://cloud.centos.org/` 抓取最新 qcow2 镜像的 URL、SHA256、文件大小及版本
   - 支持 x86_64 和 aarch64 架构，架构不可用时跳过并记录警告
   - 在 `pyproject.toml` 的 entry-points 中注册该插件
   - 输出符合 `distribution-info.json` schema 的 JSON 数据
   - _需求：5.1、5.2、5.5、5.6、5.7_

- [ ] 4. 实现 TencentOS 镜像抓取器插件
   - 在 `tools/distro-scraper/` 下新建 `tencentos_scraper.py`，从腾讯软件源抓取 TencentOS 2.x / 3.x 镜像元数据
   - 支持 x86_64 和 aarch64 架构，架构不可用时跳过并记录警告
   - 在 `pyproject.toml` 的 entry-points 中注册该插件
   - _需求：5.1、5.3、5.5、5.6、5.7_

- [ ] 5. 实现麒麟镜像抓取器插件
   - 在 `tools/distro-scraper/` 下新建 `kylin_scraper.py`，从麒麟官方镜像站抓取 Kylin V10 镜像元数据
   - 支持 x86_64 和 aarch64 架构；若镜像不可用则记录警告并标注状态
   - 在 `pyproject.toml` 的 entry-points 中注册该插件
   - _需求：5.1、5.4、5.5、5.6、5.7、3.6_

- [ ] 6. 添加各发行版的 cloud-init 默认配置
   - 为 CentOS Stream 添加 cloud-init 配置，验证 `growpart`、`manage_etc_hosts` 兼容性，确认默认用户为 `centos` 或 `cloud-user`
   - 为 TencentOS 添加 cloud-init 配置，内置腾讯软件源（`mirrors.tencent.com/tlinux/`）yum 源配置，处理 SELinux 兼容性
   - 为麒麟添加 cloud-init 配置，验证 SSH 公钥注入及 `growpart` 兼容性
   - _需求：2.5、2.6、4.1、4.2、4.3、6.1、6.3、6.4、6.5_

- [ ] 7. 验证别名解析与 `multipass find` 展示
   - 在 `CustomVMImageHost` 相关代码中确认别名解析逻辑能正确处理新增的三个发行版别名
   - 运行 `multipass find` 验证 CentOS、TencentOS、Kylin 镜像及其别名均正确展示
   - 验证版本不存在时返回清晰错误信息
   - _需求：1.3、1.4、1.5、2.2、2.3、3.2、3.3_

- [ ] 8. 端到端启动与 SSH 连通性测试
   - 分别执行 `multipass launch centos`、`multipass launch tencentos`、`multipass launch kylin` 验证实例能正常启动
   - 验证各实例 SSH 公钥注入成功，`multipass exec` 命令可正常执行
   - 验证 TencentOS 实例内 yum 源已指向腾讯软件源
   - _需求：1.6、2.4、2.5、3.4、3.5、6.1、6.2_

- [ ] 9. 更新文档
   - 在 `docs/` 目录下新增或更新各发行版镜像使用说明，包含别名、默认用户、架构支持等信息
   - 在文档中列出各发行版对应的腾讯软件源地址（CentOS / TencentOS / Kylin）
   - 在 `docs/changelog.md` 中记录本次新增发行版镜像支持的变更内容
   - _需求：7.1、7.2、7.3、7.4、4.6_
