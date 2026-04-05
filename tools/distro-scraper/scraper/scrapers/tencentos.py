import re
import aiohttp
import asyncio
from ..base import BaseScraper, DEFAULT_TIMEOUT
from ..models import SUPPORTED_ARCHITECTURES

# 腾讯软件源 TencentOS Cloud 镜像目录
# 注意：腾讯软件源目前仅提供容器镜像（tar.xz），暂无公开的 qcow2 Cloud 镜像。
# 本 Scraper 尝试从腾讯软件源获取镜像，若不可用则记录警告并返回占位数据。
TENCENT_MIRROR_BASE = "https://mirrors.tencent.com/tlinux/"

# 当前支持的 TencentOS 版本（优先使用最新版）
TENCENTOS_VERSIONS = ["3.2", "3.1"]

# 架构映射：multipass 架构名 -> 腾讯软件源目录架构名
ARCH_MAP = {
    "x86_64": "x86_64",
    "arm64": "aarch64",
}

# 仅支持这两种架构
TENCENTOS_SUPPORTED_ARCHES = {"x86_64", "arm64"}

# 占位镜像 URL 模板（当官方 Cloud 镜像不可用时使用）
PLACEHOLDER_URL_TEMPLATE = (
    "https://mirrors.tencent.com/tlinux/{version}/images/{arch}/"
    "TencentOS-Server-{version}-GenericCloud-{arch}.qcow2"
)


class TencentOSScraper(BaseScraper):
    def __init__(self):
        super().__init__()

    @property
    def name(self) -> str:
        return "TencentOS"

    async def _find_qcow2_in_dir(
        self, session: aiohttp.ClientSession, url: str
    ) -> list[str]:
        """
        从目录列表页面中查找 qcow2 文件链接。
        """
        try:
            text = await self._fetch_text(session, url)
            return re.findall(r'href="([^"]*\.qcow2)"', text)
        except Exception as e:
            self.logger.debug("访问目录 %s 失败: %s", url, e)
            return []

    async def _fetch_image_for_arch(
        self, session: aiohttp.ClientSession, version: str, label: str
    ) -> tuple[str, dict]:
        """
        尝试获取指定版本和架构的 TencentOS Cloud 镜像元数据。
        若官方 Cloud 镜像不可用，返回占位数据并记录警告。
        """
        tencent_arch = ARCH_MAP[label]
        images_url = f"{TENCENT_MIRROR_BASE}{version}/images/{tencent_arch}/"

        qcow2_files = await self._find_qcow2_in_dir(session, images_url)

        if qcow2_files:
            # 找到真实的 qcow2 镜像
            filename = qcow2_files[-1]  # 取最新的
            image_url = images_url + filename

            # 尝试获取 md5sum 或 sha256sum
            sha256 = ""
            for checksum_suffix in [".sha256sum", ".SHA256SUM", ".md5sum"]:
                try:
                    checksum_text = await self._fetch_text(session, image_url + checksum_suffix)
                    match = re.search(r"([0-9a-f]{32,})", checksum_text)
                    if match:
                        sha256 = match.group(1)
                        break
                except Exception:
                    continue

            size = await self._head_content_length(session, image_url) or -1

            # 从文件名提取版本日期
            date_match = re.search(r"-(\d{8})", filename)
            version_str = date_match.group(1) if date_match else version

            self.logger.info(
                "TencentOS %s %s: 找到真实镜像 %s", version, label, image_url
            )
            return label, {
                "image_location": image_url,
                "id": sha256 or f"placeholder-tencentos-{version}-{tencent_arch}",
                "version": version_str,
                "size": size,
            }
        else:
            # 官方 Cloud 镜像不可用，使用占位数据
            placeholder_url = PLACEHOLDER_URL_TEMPLATE.format(
                version=version, arch=tencent_arch
            )
            self.logger.warning(
                "TencentOS %s %s: 腾讯软件源暂无公开的 qcow2 Cloud 镜像，使用占位数据。"
                "镜像发布后请更新 distribution-info.json 或重新运行 distro-scraper。"
                "占位 URL: %s",
                version, label, placeholder_url,
            )
            return label, {
                "image_location": placeholder_url,
                "id": f"placeholder-tencentos-{version}-{tencent_arch}",
                "version": version,
                "size": -1,
            }

    async def _find_latest_version(self, session: aiohttp.ClientSession) -> str:
        """
        从腾讯软件源目录中查找最新的 TencentOS 版本。
        """
        try:
            text = await self._fetch_text(session, TENCENT_MIRROR_BASE)
            versions = re.findall(r'href="(\d+\.\d+)/"', text)
            if versions:
                # 按版本号降序排列，取最新版
                latest = sorted(versions, key=lambda v: [int(x) for x in v.split(".")])[-1]
                self.logger.info("发现最新 TencentOS 版本: %s", latest)
                return latest
        except Exception as e:
            self.logger.warning("获取 TencentOS 版本列表失败: %s", e)
        # 回退到预设版本
        return TENCENTOS_VERSIONS[0]

    async def fetch(self) -> dict:
        """
        抓取 TencentOS 最新 Cloud 镜像信息（x86_64 / arm64）。
        若腾讯软件源暂无公开 qcow2 镜像，返回占位数据并记录警告。
        """
        async with aiohttp.ClientSession() as session:
            version = await self._find_latest_version(session)

            results = await asyncio.gather(
                *[
                    self._fetch_image_for_arch(session, version, label)
                    for label in SUPPORTED_ARCHITECTURES
                    if label in TENCENTOS_SUPPORTED_ARCHES
                ],
                return_exceptions=True,
            )

            items: dict[str, dict] = {}
            for label, result in zip(
                [l for l in SUPPORTED_ARCHITECTURES if l in TENCENTOS_SUPPORTED_ARCHES],
                results,
            ):
                if isinstance(result, Exception):
                    self.logger.warning("获取 TencentOS %s 架构镜像失败: %s", label, result)
                else:
                    _, data = result
                    items[label] = data

            if not items:
                raise RuntimeError("所有架构的 TencentOS 镜像均获取失败")

            return {
                "aliases": "tencentos, tlinux",
                "os": "TencentOS",
                "release": version,
                "release_codename": f"TencentOS Server {version}",
                "release_title": version.split(".")[0],
                "items": items,
            }
