# =============================================================================
# CentOS 7 → qcow2 Cloud Image Packer 构建模板
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

# ---------- 变量定义（由 build.sh 通过 -var 传入） ----------
variable "iso_url" {
  type        = string
  description = "CentOS 7 ISO 文件路径（file:///... 或 http://...）"
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
  default     = "../output/centos7"
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
source "qemu" "centos7" {
  # ISO 来源
  iso_url      = var.iso_url
  iso_checksum = var.iso_checksum

  # 输出配置
  output_directory = var.output_dir
  vm_name          = "centos7-cloud.qcow2"
  format           = "qcow2"

  # 硬件配置
  disk_size    = var.disk_size
  memory       = var.memory
  cpus         = var.cpus
  accelerator  = var.accelerator

  # QEMU 参数：使用 virtio 磁盘（性能更好，Kickstart 中对应 /dev/vda）
  disk_interface = "virtio"
  net_device     = "virtio-net"

  # 显示配置（无头模式）
  headless         = true
  display          = "none"

  # HTTP server（用于提供 Kickstart 文件）
  http_directory = "${path.root}/../http"
  http_port_min  = 8100
  http_port_max  = 8199

  # SSH 连接配置（Packer 通过 SSH 执行 provisioner）
  communicator     = "ssh"
  ssh_username     = "root"
  ssh_password     = "packer-build-only"
  ssh_timeout      = "30m"
  ssh_port         = 22

  # 关机命令
  shutdown_command = "shutdown -h now"

  # 启动等待时间
  boot_wait = "10s"

  # 启动命令：注入 Kickstart 文件地址
  # {{ .HTTPIP }} 和 {{ .HTTPPort }} 由 Packer 自动替换为 HTTP server 地址
  boot_command = [
    "<tab>",
    " text",
    " ks=http://{{ .HTTPIP }}:{{ .HTTPPort }}/centos7-ks.cfg",
    " console=ttyS0,115200n8",
    "<enter><wait>"
  ]
}

# ---------- Build ----------
build {
  name    = "centos7-cloud"
  sources = ["source.qemu.centos7"]

  # Step 1：安装 cloud-init 及相关工具，可选配置腾讯软件源
  provisioner "shell" {
    script          = "${path.root}/../scripts/install-cloud-init.sh"
    execute_command = "chmod +x {{ .Path }}; sudo {{ .Path }}"
    # 等待系统完全启动后再执行
    pause_before    = "30s"
  }

  # Step 2：清理镜像（machine-id、SSH host keys、cloud-init 状态等）
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
