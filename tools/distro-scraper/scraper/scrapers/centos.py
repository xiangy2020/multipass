import re
import aiohttp
import asyncio
from dateutil import parser
from ..base import BaseScraper, DEFAULT_TIMEOUT
from ..models import SUPPORTED_ARCHITECTURES

# CentOS Stream 官方 Cloud 镜像站
CENTOS_CLOUD_BASE = "https://cloud.centos.org/centos/"

# 支持的 CentOS Stream 版本列表（从新到旧，第一个为默认版本）
CENTOS_STREAM_VERSIONS = ["9", "8"]

# 默认版本（centos / centos-stream 别名指向此版本）
CENTOS_DEFAULT_VERSION = "9"

# 架构映射：multipass 架构名 -> CentOS 目录架构名
ARCH_MAP = {
    "x86_64": "x86_64",
    "arm64": "aarch64",
}

# 仅支持这两种架构
CENTOS_SUPPORTED_ARCHES = {"x86_64", "arm64"}

class CentOSScraper(BaseScraper):
    def __init__(self):
        super().__init__()

    @property
    def name(self) -> str:
        return "CentOS"

    async def _fetch_latest_image_filename(
        self, session: aiohttp.ClientSession, version: str, centos_arch: str
    ) -> str:
        """
        从 CentOS Cloud 镜像目录中获取最新的 GenericCloud qcow2 文件名。
        """
        url = f"{CENTOS_CLOUD_BASE}{version}-stream/{centos_arch}/images/"
        self.logger.info("获取 CentOS Stream %s %s 镜像列表: %s", version, centos_arch, url)
        text = await self._fetch_text(session, url)
        # 匹配 CentOS-Stream-GenericCloud-<version>-<date>.<arch>.qcow2
        pattern = rf"CentOS-Stream-GenericCloud-{version}-(\d+\.\d+)\.{centos_arch}\.qcow2"
        matches = re.findall(pattern, text)
        if not matches:
            raise RuntimeError(
                f"未找到 CentOS Stream {version} {centos_arch} 的 qcow2 镜像文件"
            )
        # 取最新版本（按日期字符串排序）
        latest_date = sorted(matches)[-1]
        filename = f"CentOS-Stream-GenericCloud-{version}-{latest_date}.{centos_arch}.qcow2"
        self.logger.info("最新镜像文件: %s", filename)
        return filename

    async def _fetch_sha256(
        self, session: aiohttp.ClientSession, sha256sum_url: str, filename: str
    ) -> str:
        """
        从 SHA256SUM 文件中提取指定文件的 SHA256 校验和。
        """
        text = await self._fetch_text(session, sha256sum_url)
        # 格式: SHA256 (filename) = <hash>
        match = re.search(
            rf"SHA256\s*\({re.escape(filename)}\)\s*=\s*([0-9a-f]+)", text, re.IGNORECASE
        )
        if not match:
            raise RuntimeError(f"在 SHA256SUM 文件中未找到 {filename} 的校验和")
        return match.group(1)

    async def _fetch_image_for_arch(
        self, session: aiohttp.ClientSession, version: str, label: str
    ) -> tuple[str, dict]:
        """
        获取指定架构的 CentOS Stream 镜像元数据。
        """
        centos_arch = ARCH_MAP[label]
        images_url = f"{CENTOS_CLOUD_BASE}{version}-stream/{centos_arch}/images/"

        filename = await self._fetch_latest_image_filename(session, version, centos_arch)
        image_url = images_url + filename
        sha256sum_url = image_url + ".SHA256SUM"

        sha256 = await self._fetch_sha256(session, sha256sum_url, filename)

        # 从文件名中提取版本日期，格式如 20250428
        date_match = re.search(r"-(\d{8})\.\d+\.", filename)
        version_str = date_match.group(1) if date_match else ""

        # 获取文件大小
        size = await self._head_content_length(session, image_url) or -1

        self.logger.info(
            "CentOS Stream %s %s: url=%s sha256=%s size=%d",
            version, label, image_url, sha256[:16] + "...", size
        )

        return label, {
            "image_location": image_url,
            "id": sha256,
            "version": version_str,
            "size": size,
        }

    async def _fetch_version(self, session: aiohttp.ClientSession, version: str) -> dict:
        """
        抓取指定版本的 CentOS Stream 所有架构镜像信息，返回单个版本的条目字典。
        """
        results = await asyncio.gather(
            *[
                self._fetch_image_for_arch(session, version, label)
                for label in SUPPORTED_ARCHITECTURES
                if label in CENTOS_SUPPORTED_ARCHES
            ],
            return_exceptions=True,
        )

        items: dict[str, dict] = {}
        for label, result in zip(
            [l for l in SUPPORTED_ARCHITECTURES if l in CENTOS_SUPPORTED_ARCHES],
            results,
        ):
            if isinstance(result, Exception):
                self.logger.warning("获取 CentOS Stream %s %s 架构镜像失败: %s", version, label, result)
            else:
                _, data = result
                items[label] = data

        if not items:
            raise RuntimeError(f"所有架构的 CentOS Stream {version} 镜像均获取失败")

        # 默认版本使用通用别名，其他版本使用版本化别名
        if version == CENTOS_DEFAULT_VERSION:
            aliases = f"centos, centos-stream, centos:{version}, centos-stream:{version}"
        else:
            aliases = f"centos:{version}, centos-stream:{version}"

        return {
            "aliases": aliases,
            "os": "CentOS",
            "release": f"{version}-stream",
            "release_codename": f"Stream {version}",
            "release_title": version,
            "items": items,
        }

    async def fetch(self) -> dict | list:
        """
        抓取所有支持版本的 CentOS Stream Cloud 镜像信息，返回多版本条目列表。
        """
        async with aiohttp.ClientSession() as session:
            version_results = await asyncio.gather(
                *[self._fetch_version(session, version) for version in CENTOS_STREAM_VERSIONS],
                return_exceptions=True,
            )

        entries = []
        for version, result in zip(CENTOS_STREAM_VERSIONS, version_results):
            if isinstance(result, Exception):
                self.logger.warning("获取 CentOS Stream %s 失败: %s", version, result)
            else:
                entries.append(result)
                self.logger.info("CentOS Stream %s 抓取成功", version)

        if not entries:
            raise RuntimeError("所有版本的 CentOS Stream 镜像均获取失败")

        return entries
