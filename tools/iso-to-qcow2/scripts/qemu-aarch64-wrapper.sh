#!/usr/bin/env bash
# =============================================================================
# qemu-aarch64-wrapper.sh
# 用途：包装 qemu-system-aarch64，解决 Packer QEMU 插件对 aarch64 生成
#       无效参数 "-boot once=d" 的问题
# 处理逻辑：
#   1. 过滤掉 -boot once=d（aarch64 UEFI 不支持该参数）
#   2. 自动注入 -bios（UEFI firmware）和 -cpu cortex-a57
# 用法：由 Packer 通过 qemu_binary 字段调用，不建议直接执行
# =============================================================================

QEMU_BIN="/opt/homebrew/bin/qemu-system-aarch64"
FIRMWARE="/opt/homebrew/share/qemu/edk2-aarch64-code.fd"
# Linux 备用路径
if [[ ! -f "$FIRMWARE" ]]; then
  FIRMWARE="/usr/share/qemu/edk2-aarch64-code.fd"
fi

# 过滤掉 -boot once=d 参数（aarch64 UEFI 不支持）
filtered_args=()
skip_next=false
for arg in "$@"; do
  if $skip_next; then
    skip_next=false
    continue
  fi
  if [[ "$arg" == "-boot" ]]; then
    skip_next=true
    continue
  fi
  filtered_args+=("$arg")
done

# 执行 QEMU，注入 -bios 和 -cpu
exec "$QEMU_BIN" \
  -bios "$FIRMWARE" \
  -cpu cortex-a57 \
  "${filtered_args[@]}"
