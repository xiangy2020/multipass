# 实施计划：CentOS Stream 多版本支持

- [x] 1. 扩展 distro-scraper 支持多版本抓取
   - 修改 `tools/distro-scraper/scraper/scrapers/centos.py`，将 `CENTOS_STREAM_VERSION` 改为版本列表 `["9", "8"]`
   - 修改 `fetch()` 方法，循环抓取每个版本并返回多个条目（每个版本一个独立 JSON 对象）
   - 为 Stream 9 保留 `centos, centos-stream` 别名（默认版本），为 Stream 8 添加 `centos:8, centos-stream:8` 别名
   - 修改 `cli.py` 的 `run_scraper` 支持 fetch() 返回 list（多版本）
   - _需求：1.3、1.4、2.1、2.2、2.3、2.4_

- [x] 2. 更新 distribution-info.json 添加 CentOS Stream 8 条目
   - 运行 `distro-scraper centos` 自动抓取 CentOS Stream 8 的 arm64 和 x86_64 镜像元数据
   - 将 `CentOS` 条目拆分为 `CentOS8` 和 `CentOS9` 两个独立条目
   - CentOS8: `centos:8, centos-stream:8`，镜像版本 20240603
   - CentOS9: `centos, centos-stream, centos:9, centos-stream:9`，镜像版本 20260331
   - _需求：1.1、1.2、1.3、1.4_

- [x] 3. 更新 daemon.cpp 识别 CentOS Stream 8 并注入 cloud-init 配置
   - 修改 `src/daemon/daemon.cpp` 中 `make_cloud_init_vendor_config` 函数
   - 引入 `is_centos` 布尔变量，使用 `starts_with` 匹配所有 centos 系列别名
   - 同时覆盖 `centos`、`centos-stream`、`centos:8`、`centos:9` 等所有版本化别名
   - _需求：3.1、3.2、3.3_

- [x] 4. 重新编译并安装验证
   - 执行 `cmake --build . --target multipassd` 重新编译成功
   - 执行 `sudo packaging/macos/install-dev.sh` 重新安装成功
   - 推送到 GitHub，清除网络缓存后 `multipass find` 显示 CentOS Stream 8 条目
   - _需求：1.2、2.2、3.1_

- [x] 5. 更新文档和变更记录
   - 在 `docs/changelog.md` 中记录新增 CentOS Stream 多版本支持
   - 在 `docs/how-to-guides/manage-instances/launch-chinese-distro-images.md` 中补充 CentOS Stream 8 的使用说明和版本化别名示例
   - 提交 git commit 并推送
   - _需求：4.1、4.2_
