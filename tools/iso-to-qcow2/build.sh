#!/usr/bin/env bash
# =============================================================================
# build.sh — ISO → qcow2 Cloud Image 构建入口脚本
# 用法：./build.sh --distro <发行版> --iso <ISO路径> [--checksum <sha256:xxx>]
# 支持发行版：centos7 | tlinux
# =============================================================================
set -euo pipefail

# ---------- 颜色输出 ----------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }

# ---------- 默认值 ----------
DISTRO=""
ISO_PATH=""
CHECKSUM="none"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ---------- 解析参数 ----------
usage() {
  cat <<EOF
用法：
  $0 --distro <发行版> --iso <ISO路径> [--checksum <sha256:xxx>]

参数：
  --distro    目标发行版，支持：centos7 | tlinux
  --iso       ISO 文件的绝对路径或 URL
  --checksum  ISO 文件的 SHA256 校验值，格式：sha256:xxxx（可选，默认 none 跳过校验）

示例：
  $0 --distro centos7 --iso /tmp/CentOS-7-x86_64-Minimal-2009.iso
  $0 --distro centos7 --iso /tmp/CentOS-7-x86_64-Minimal-2009.iso --checksum sha256:abc123...
  $0 --distro tlinux  --iso /tmp/TencentOS-Server-3.1-x86_64.iso
EOF
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --distro)    DISTRO="$2";    shift 2 ;;
    --iso)       ISO_PATH="$2";  shift 2 ;;
    --checksum)  CHECKSUM="$2";  shift 2 ;;
    -h|--help)   usage ;;
    *) error "未知参数：$1" ;;
  esac
done

# ---------- 参数校验 ----------
[[ -z "$DISTRO" ]]   && error "缺少 --distro 参数，请指定目标发行版（centos7 | tlinux）"
[[ -z "$ISO_PATH" ]] && error "缺少 --iso 参数，请指定 ISO 文件路径"

TEMPLATE="${SCRIPT_DIR}/templates/${DISTRO}.pkr.hcl"
[[ -f "$TEMPLATE" ]] || error "找不到 Packer 模板：${TEMPLATE}"

# 如果是本地文件，转为 file:// URI 并校验存在性
if [[ "$ISO_PATH" != http* ]]; then
  [[ -f "$ISO_PATH" ]] || error "ISO 文件不存在：${ISO_PATH}"
  ISO_PATH="file://${ISO_PATH}"
fi

# ---------- 检测依赖 ----------
info "检测依赖工具..."
command -v packer &>/dev/null || error "未找到 packer，请先安装：brew install packer（macOS）或参考 https://developer.hashicorp.com/packer/install"
command -v qemu-system-x86_64 &>/dev/null || error "未找到 qemu-system-x86_64，请先安装：brew install qemu（macOS）或 apt install qemu-system-x86（Linux）"

# ---------- 自动检测平台，选择 QEMU 加速器 ----------
detect_accelerator() {
  local os
  os="$(uname -s)"
  if [[ "$os" == "Darwin" ]]; then
    info "检测到 macOS，使用 HVF 加速器"
    echo "hvf"
  elif [[ "$os" == "Linux" ]]; then
    if [[ -e /dev/kvm ]]; then
      info "检测到 Linux + KVM，使用 KVM 加速器"
      echo "kvm"
    else
      warn "未检测到 /dev/kvm，将使用软件模拟（构建速度较慢）"
      echo "none"
    fi
  else
    warn "未知平台 ${os}，将使用软件模拟"
    echo "none"
  fi
}

ACCELERATOR="$(detect_accelerator)"

# ---------- 安装 Packer QEMU 插件（首次运行） ----------
info "初始化 Packer 插件..."
packer plugins install github.com/hashicorp/qemu >/dev/null 2>&1 || true

# ---------- 执行 Packer 构建 ----------
OUTPUT_DIR="${SCRIPT_DIR}/output/${DISTRO}"
mkdir -p "$OUTPUT_DIR"

info "开始构建 ${DISTRO} 镜像..."
info "  ISO      : ${ISO_PATH}"
info "  Checksum : ${CHECKSUM}"
info "  加速器   : ${ACCELERATOR}"
info "  输出目录 : ${OUTPUT_DIR}"

packer build \
  -var "iso_url=${ISO_PATH}" \
  -var "iso_checksum=${CHECKSUM}" \
  -var "accelerator=${ACCELERATOR}" \
  -var "output_dir=${OUTPUT_DIR}" \
  "${TEMPLATE}"

# ---------- 生成 SHA256 校验文件 ----------
info "生成 SHA256 校验文件..."
QCOW2_FILE="$(find "${OUTPUT_DIR}" -name "*.qcow2" | head -1)"
if [[ -n "$QCOW2_FILE" ]]; then
  shasum -a 256 "$QCOW2_FILE" > "${QCOW2_FILE}.sha256"
  info "校验文件已生成：${QCOW2_FILE}.sha256"
  info "SHA256: $(cat "${QCOW2_FILE}.sha256")"
else
  warn "未找到 qcow2 输出文件，跳过 SHA256 生成"
fi

info "✅ 构建完成！镜像位于：${OUTPUT_DIR}"
info "使用方式：multipass launch file://${OUTPUT_DIR}/*.qcow2 --name my-vm"
