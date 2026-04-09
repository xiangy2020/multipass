# =============================================================================
# TencentOS Server（TLinux）→ qcow2 Cloud Image Packer 构建模板
# 支持：TencentOS Server 2.x 和 3.x，x86_64 和 aarch64 架构
# 用法：由 build.sh 调用，不建议直接执行
# =============================================================================

packer {
  required_version = ">= 1.9.0"
  required_plugins {
    qemu = {
      version = ">= 1.0.0"
      source  = "github.com/hashicorp/qemu"
    }
  }
}

# ---------- 变量定义 ----------
variable "iso_url" {
  type        = string
  description = "TencentOS ISO 文件路径（file:///... 或 http://...）"
}

variable "iso_checksum" {
  type        = string
  default     = "none"
  description = "ISO 文件 SHA256 校验值，格式：sha256:xxxx，或 none 跳过校验"
}

variable "accelerator" {
  type        = string
  default     = "tcg"
  description = "QEMU 加速器：tcg（macOS aarch64）| hvf（macOS x86_64）| kvm（Linux）| none（软件模拟）"
}

variable "arch" {
  type        = string
  default     = "x86_64"
  description = "目标架构：x86_64 | aarch64"
}

variable "output_dir" {
  type        = string
  default     = "../output/tlinux"
  description = "qcow2 产物输出目录"
}

variable "disk_size" {
  type        = string
  default     = "20480"
  description = "虚拟磁盘大小（MB），默认 20GB"
}

variable "memory" {
  type        = number
  default     = 2048
  description = "构建虚拟机内存（MB）"
}

variable "cpus" {
  type        = number
  default     = 2
  description = "构建虚拟机 CPU 核数"
}

# ---------- 本地变量：根据 arch 自动选择 QEMU 二进制和 firmware ----------
locals {
  # QEMU 可执行文件：aarch64 用 qemu-system-aarch64，x86_64 用 qemu-system-x86_64
  qemu_binary = var.arch == "aarch64" ? "qemu-system-aarch64" : "qemu-system-x86_64"

  # aarch64 需要 UEFI firmware（edk2-aarch64）
  # macOS brew 安装路径：/opt/homebrew/share/qemu/edk2-aarch64-code.fd
  # Linux 路径：/usr/share/qemu/edk2-aarch64-code.fd
  firmware_macos = "/opt/homebrew/share/qemu/edk2-aarch64-code.fd"
  firmware_linux = "/usr/share/qemu/edk2-aarch64-code.fd"
  firmware = var.arch == "aarch64" ? (
    fileexists("/opt/homebrew/share/qemu/edk2-aarch64-code.fd") ?
      local.firmware_macos : local.firmware_linux
  ) : ""

  # aarch64 需要指定 machine type
  machine_type = var.arch == "aarch64" ? "virt" : "pc"

  # aarch64 输出文件名加 arch 后缀，便于区分
  vm_name = var.arch == "aarch64" ? "tlinux-aarch64-cloud.qcow2" : "tlinux-cloud.qcow2"
}

# ---------- QEMU Builder ----------
source "qemu" "tlinux" {
  # ISO 来源
  iso_url      = var.iso_url
  iso_checksum = var.iso_checksum

  # 输出配置
  output_directory = var.output_dir
  vm_name          = local.vm_name
  format           = "qcow2"

  # 硬件配置
  disk_size    = var.disk_size
  memory       = var.memory
  cpus         = var.cpus
  accelerator  = var.accelerator

  # QEMU 二进制：
  # - aarch64：使用 wrapper 脚本，过滤掉 -boot once=d（aarch64 UEFI 不支持），并自动注入 -bios 和 -cpu
  # - x86_64：直接使用 qemu-system-x86_64
  qemu_binary = var.arch == "aarch64" ? "${path.root}/../scripts/qemu-aarch64-wrapper.sh" : "qemu-system-x86_64"

  # Machine type（aarch64 必须用 virt）
  machine_type = local.machine_type

  # 磁盘接口：virtio（两种架构均支持）
  disk_interface = "virtio"
  net_device     = "virtio-net"

  # 显示配置（无头模式）
  headless = true
  display  = "none"

  # HTTP server（用于提供 Kickstart 文件）
  http_directory = "${path.root}/../http"
  http_port_min  = 8200
  http_port_max  = 8299

  # SSH 连接配置
  communicator = "ssh"
  ssh_username = "root"
  ssh_password = "packer-build-only"
  ssh_timeout  = "60m"
  ssh_port     = 22

  # 关机命令
  shutdown_command = "shutdown -h now"

  # 启动等待时间（aarch64 UEFI 启动较慢，给更多时间）
  boot_wait = var.arch == "aarch64" ? "30s" : "10s"

  # ---------- 启动命令 ----------
  # x86_64（BIOS/ISOLINUX）：按 Tab 键进入命令行，追加 ks= 参数
  # aarch64（UEFI/GRUB）：等待 GRUB 菜单出现，按 e 编辑，追加 ks= 参数后 Ctrl+X 启动
  boot_command = var.arch == "aarch64" ? [
    # aarch64 GRUB 启动流程：
    # 1. 等待 GRUB 菜单出现（boot_wait 已等待 30s）
    # 2. 按 e 进入编辑模式
    # 3. 找到 linux/linuxefi 行，移到行尾追加 ks= 参数
    # 4. Ctrl+X 启动
    "<wait5>",
    "e<wait3>",
    "<down><down><down><end>",
    " inst.ks=http://{{ .HTTPIP }}:{{ .HTTPPort }}/tlinux-ks.cfg",
    " console=ttyAMA0,115200n8",
    "<wait2><leftCtrlOn>x<leftCtrlOff>"
  ] : [
    # x86_64 ISOLINUX/SYSLINUX 启动流程
    "<tab>",
    " text",
    " ks=http://{{ .HTTPIP }}:{{ .HTTPPort }}/tlinux-ks.cfg",
    " console=ttyS0,115200n8",
    "<enter><wait>"
  ]
}

# ---------- Build ----------
build {
  name    = "tlinux-cloud"
  sources = ["source.qemu.tlinux"]

  # Step 1：安装 cloud-init，并强制启用腾讯软件源
  provisioner "shell" {
    environment_vars = [
      "USE_TENCENT_MIRROR=true",
      "TARGET_ARCH=${var.arch}"
    ]
    script          = "${path.root}/../scripts/install-cloud-init.sh"
    execute_command = "chmod +x {{ .Path }}; sudo {{ .Path }}"
    pause_before    = "30s"
  }

  # Step 2：清理镜像
  provisioner "shell" {
    script          = "${path.root}/../scripts/cleanup.sh"
    execute_command = "chmod +x {{ .Path }}; sudo {{ .Path }}"
  }

  # 构建完成提示
  post-processor "manifest" {
    output     = "${var.output_dir}/manifest.json"
    strip_path = true
  }
}
