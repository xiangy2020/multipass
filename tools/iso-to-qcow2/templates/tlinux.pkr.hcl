# =============================================================================
# TencentOS Server（TLinux）→ qcow2 Cloud Image Packer 构建模板
# 支持：TencentOS Server 2.x 和 3.x
# 用法：由 build.sh 调用，不建议直接执行
# 与 centos7.pkr.hcl 的主要差异：
#   1. Kickstart 文件指向 tlinux-ks.cfg
#   2. 输出目录为 output/tlinux
#   3. vm_name 为 tlinux-cloud.qcow2
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
  default     = "hvf"
  description = "QEMU 加速器：hvf（macOS）| kvm（Linux）| none（软件模拟）"
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

# ---------- QEMU Builder ----------
source "qemu" "tlinux" {
  # ISO 来源
  iso_url      = var.iso_url
  iso_checksum = var.iso_checksum

  # 输出配置
  output_directory = var.output_dir
  vm_name          = "tlinux-cloud.qcow2"
  format           = "qcow2"

  # 硬件配置
  disk_size    = var.disk_size
  memory       = var.memory
  cpus         = var.cpus
  accelerator  = var.accelerator

  # QEMU 参数
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
  ssh_timeout  = "30m"
  ssh_port     = 22

  # 关机命令
  shutdown_command = "shutdown -h now"

  # 启动等待时间
  boot_wait = "10s"

  # 启动命令：注入 TencentOS Kickstart 文件地址
  boot_command = [
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
      "USE_TENCENT_MIRROR=true"
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
