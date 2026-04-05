import re
import aiohttp
import asyncio
from ..base import BaseScraper, DEFAULT_TIMEOUT
from ..models import SUPPORTED_ARCHITECTURES

# 麒麟（OpenKylin）官方镜像站及国内镜像源
# 注意：OpenKylin 目前主要提供 ISO 安装镜像和 apt 软件源，
# 暂无公开的标准 qcow2 Cloud 镜像（NoCloud datasource）。
# 本 Scraper 尝试从已知镜像站获取，若不可用则记录警告并返回占位数据。

# 候选镜像源列表（按优先级排序）
KYLIN_IMAGE_SOURCES = [
    # 阿里云镜像站
    "https://mirrors.aliyun.com/openkylin/project/",
    # 华为云镜像站
    "https://mirrors.huaweicloud.com/openkylin/project/",
]

# 架构映射：multipass 架构名 -> 麒麟目录架构名
ARCH_MAP = {
    "x86_64": "x86_64",
    "arm64": "aarch64",
}

# 仅支持这两种架构
KYLIN_SUPPORTED_ARCHES = {"x86_64", "arm64"}

# 当前支持的麒麟版本
KYLIN_VERSION = "V10SP3"
KYLIN_RELEASE = "V10"

# 占位镜像 URL 模板
PLACEHOLDER_URL_TEMPLATE = (
    "https://mirrors.aliyun.com/openkylin/project/"
    "kylin-{version}-cloud-{arch}.qcow2"
)


class KylinScraper(BaseScraper):
    def __init__(self):
        super().__init__()

    @property
    def name(self) -> str:
        return "Kylin"

    async def _find_qcow2_in_sources(
        self, session: aiohttp.ClientSession, arch: str
    ) -> tuple[str, str] | None:
        """
        在候选镜像源中查找麒麟 qcow2 Cloud 镜像。
        返回 (image_url, source_base) 或 None。
        """
        for source_base in KYLIN_IMAGE_SOURCES:
            try:
                text = await self._fetch_text(session, source_base)
                # 查找 qcow2 文件，支持多种命名格式
                patterns = [
                    rf'href="([^"]*kylin[^"]*{arch}[^"]*\.qcow2)"',
                    rf'href="([^"]*kylin[^"]*cloud[^"]*\.qcow2)"',
                    r'href="([^"]*\.qcow2)"',
                ]
                for pattern in patterns:
                    matches = re.findall(pattern, text, re.IGNORECASE)
                    if matches:
                        filename = matches[-1]
                        # 如果是相对路径，拼接完整 URL
                        if not filename.startswith("http"):
                            image_url = source_base + filename
                        else:
                            image_url = filename
                        self.logger.info(
                            "在 %s 找到麒麟 %s 镜像: %s", source_base, arch, image_url
                        )
                        return image_url, source_base
            except Exception as e:
                self.logger.debug("访问镜像源 %s 失败: %s", source_base, e)
                continue
        return None

    async def _fetch_image_for_arch(
        self, session: aiohttp.ClientSession, label: str
    ) -> tuple[str, dict]:
        """
        尝试获取指定架构的麒麟 Cloud 镜像元数据。
        若官方 Cloud 镜像不可用，返回占位数据并记录警告。
        """
        kylin_arch = ARCH_MAP[label]

        result = await self._find_qcow2_in_sources(session, kylin_arch)

        if result:
            image_url, source_base = result

            # 尝试获取校验和
            sha256 = ""
            for checksum_suffix in [".sha256", ".sha256sum", ".SHA256SUM", ".md5"]:
                try:
                    checksum_text = await self._fetch_text(
                        session, image_url + checksum_suffix
                    )
                    match = re.search(r"([0-9a-f]{32,})", checksum_text)
                    if match:
                        sha256 = match.group(1)
                        break
                except Exception:
                    continue

            size = await self._head_content_length(session, image_url) or -1

            # 从 URL 中提取版本信息
            version_match = re.search(r"(V\d+SP\d+|\d{8})", image_url, re.IGNORECASE)
            version_str = version_match.group(1) if version_match else KYLIN_VERSION

            return label, {
                "image_location": image_url,
                "id": sha256 or f"placeholder-kylin-{KYLIN_VERSION}-{kylin_arch}",
                "version": version_str,
                "size": size,
            }
        else:
            # 官方 Cloud 镜像不可用，使用占位数据
            placeholder_url = PLACEHOLDER_URL_TEMPLATE.format(
                version=KYLIN_VERSION.lower(), arch=kylin_arch
            )
            self.logger.warning(
                "Kylin %s %s: 暂未找到公开的 qcow2 Cloud 镜像，使用占位数据。"
                "麒麟官方 Cloud 镜像发布后请更新 distribution-info.json 或重新运行 distro-scraper。"
                "占位 URL: %s",
                KYLIN_VERSION, label, placeholder_url,
            )
            return label, {
                "image_location": placeholder_url,
                "id": f"placeholder-kylin-{KYLIN_VERSION}-{kylin_arch}",
                "version": KYLIN_VERSION,
                "size": -1,
            }

    async def fetch(self) -> dict:
        """
        抓取麒麟（OpenKylin）最新 Cloud 镜像信息（x86_64 / arm64）。
        若官方 Cloud 镜像不可用，返回占位数据并记录警告。
        """
        async with aiohttp.ClientSession() as session:
            results = await asyncio.gather(
                *[
                    self._fetch_image_for_arch(session, label)
                    for label in SUPPORTED_ARCHITECTURES
                    if label in KYLIN_SUPPORTED_ARCHES
                ],
                return_exceptions=True,
            )

            items: dict[str, dict] = {}
            for label, result in zip(
                [l for l in SUPPORTED_ARCHITECTURES if l in KYLIN_SUPPORTED_ARCHES],
                results,
            ):
                if isinstance(result, Exception):
                    self.logger.warning("获取麒麟 %s 架构镜像失败: %s", label, result)
                else:
                    _, data = result
                    items[label] = data

            if not items:
                raise RuntimeError("所有架构的麒麟镜像均获取失败")

            return {
                "aliases": "kylin, kylinv10",
                "os": "Kylin",
                "release": KYLIN_RELEASE,
                "release_codename": f"Kylin {KYLIN_VERSION}",
                "release_title": KYLIN_RELEASE,
                "items": items,
            }
