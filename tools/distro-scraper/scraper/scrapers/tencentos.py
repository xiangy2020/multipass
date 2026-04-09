import re
import aiohttp
import asyncio
from ..base import BaseScraper, DEFAULT_TIMEOUT
from ..models import SUPPORTED_ARCHITECTURES

# 腾讯软件源 TencentOS Cloud 镜像目录
TENCENT_MIRROR_BASE = "https://mirrors.tencent.com/tlinux/"

# 当前支持的 TencentOS 版本（按优先级排列）
TENCENTOS_VERSIONS = ["3.2", "3.1", "2.4"]

# 架构映射：multipass 架构名 -> 腾讯软件源目录架构名
ARCH_MAP = {
    "x86_64": "x86_64",
    "arm64": "aarch64",
}

# 仅支持这两种架构
TENCENTOS_SUPPORTED_ARCHES = {"x86_64", "arm64"}

# 2.4 版本的镜像在 images/{arch}/qcow2/ 子目录下
VERSIONS_WITH_QCOW2_SUBDIR = {"2.4"}


class TencentOSScraper(BaseScraper):
    def __init__(self):
        super().__init__()

    @property
    def name(self) -> str:
        return "TencentOS"

    async def _find_compressed_image_in_dir(
        self, session: aiohttp.ClientSession, url: str
    ) -> list[str]:
        """
        从目录列表页面中查找 .qcow2.bz2 或 .qcow2.xz 或 .qcow2 文件链接。
        优先返回 .qcow2.bz2，其次 .qcow2.xz，最后 .qcow2。
        """
        try:
            text = await self._fetch_text(session, url)
            bz2_files = re.findall(r'href="([^"]*\.qcow2\.bz2)"', text)
            if bz2_files:
                return bz2_files
            xz_files = re.findall(r'href="([^"]*\.qcow2\.xz)"', text)
            if xz_files:
                return xz_files
            return re.findall(r'href="([^"]*\.qcow2)"', text)
        except Exception as e:
            self.logger.debug("访问目录 %s 失败: %s", url, e)
            return []

    async def _fetch_image_for_arch(
        self, session: aiohttp.ClientSession, version: str, label: str
    ) -> tuple[str, dict]:
        """
        尝试获取指定版本和架构的 TencentOS Cloud 镜像元数据。
        """
        tencent_arch = ARCH_MAP[label]

        # 2.4 版本有 qcow2 子目录
        if version in VERSIONS_WITH_QCOW2_SUBDIR:
            images_url = f"{TENCENT_MIRROR_BASE}{version}/images/{tencent_arch}/qcow2/"
        else:
            images_url = f"{TENCENT_MIRROR_BASE}{version}/images/{tencent_arch}/"

        image_files = await self._find_compressed_image_in_dir(session, images_url)

        if image_files:
            # 取最新的（列表最后一个）
            filename = image_files[-1]
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

            # 尝试从 md5sum.txt 获取校验和
            if not sha256:
                try:
                    md5_url = images_url + "md5sum.txt"
                    md5_text = await self._fetch_text(session, md5_url)
                    # 查找对应文件名的 md5
                    for line in md5_text.splitlines():
                        if filename in line:
                            match = re.search(r"([0-9a-f]{32,})", line)
                            if match:
                                sha256 = match.group(1)
                                break
                except Exception:
                    pass

            size = await self._head_content_length(session, image_url) or -1

            # 从文件名提取版本日期（支持 -20220518- 或 .20220518. 等格式）
            date_match = re.search(r"[.\-](\d{8})[.\-]", filename)
            version_str = date_match.group(1) if date_match else version

            self.logger.info(
                "TencentOS %s %s: 找到镜像 %s", version, label, image_url
            )
            return label, {
                "image_location": image_url,
                "id": sha256 or f"tencentos-{version}-{tencent_arch}-{version_str}",
                "version": version_str,
                "size": size,
            }
        else:
            self.logger.warning(
                "TencentOS %s %s: 未找到 qcow2 镜像，目录: %s",
                version, label, images_url,
            )
            return label, {}

    async def _fetch_version(
        self, session: aiohttp.ClientSession, version: str
    ) -> dict | None:
        """
        抓取指定版本的所有架构镜像信息。
        若所有架构均无镜像则返回 None。
        """
        results = await asyncio.gather(
            *[
                self._fetch_image_for_arch(session, version, label)
                for label in SUPPORTED_ARCHITECTURES
                if label in TENCENTOS_SUPPORTED_ARCHES
            ],
            return_exceptions=True,
        )

        items: dict[str, dict] = {}
        for result in results:
            if isinstance(result, Exception):
                self.logger.warning("获取 TencentOS %s 架构镜像失败: %s", version, result)
            else:
                label, data = result
                if data:  # 只有找到镜像才加入
                    items[label] = data

        if not items:
            return None

        return {
            "aliases": f"tencentos{version.split('.')[0]}, tlinux{version.split('.')[0]}",
            "os": "TencentOS",
            "release": version,
            "release_codename": f"TencentOS Server {version}",
            "release_title": version.split(".")[0],
            "items": items,
        }

    async def fetch(self) -> dict:
        """
        抓取所有支持版本的 TencentOS Cloud 镜像信息。
        返回多个版本条目（每个版本一个条目）。
        """
        async with aiohttp.ClientSession() as session:
            results = await asyncio.gather(
                *[self._fetch_version(session, v) for v in TENCENTOS_VERSIONS],
                return_exceptions=True,
            )

        entries = {}
        for version, result in zip(TENCENTOS_VERSIONS, results):
            if isinstance(result, Exception):
                self.logger.warning("获取 TencentOS %s 失败: %s", version, result)
            elif result is not None:
                key = f"TencentOS{version.split('.')[0]}"
                entries[key] = result
                self.logger.info("TencentOS %s 抓取成功", version)
            else:
                self.logger.warning("TencentOS %s 无可用镜像", version)

        if not entries:
            raise RuntimeError("所有版本的 TencentOS 镜像均获取失败")

        # 返回多个条目
        return entries
