#!/bin/bash
# 开发版 multipassd 安装脚本
# 将编译产物安装到官方目录结构，解决 macOS sandbox chdir 权限问题
# 官方安装路径: /Library/Application Support/com.canonical.multipass/
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$(cd "$SCRIPT_DIR/../../build" 2>/dev/null && pwd || echo "")"

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()    { echo -e "${GREEN}[INFO]${NC} $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

# ── 安装目标目录（与官方 pkg 一致）──────────────────────
INSTALL_PREFIX="/Library/Application Support/com.canonical.multipass"
INSTALL_BIN="${INSTALL_PREFIX}/bin"
INSTALL_RESOURCES="${INSTALL_PREFIX}/Resources/qemu"
PLIST_DEST="/Library/LaunchDaemons/com.canonical.multipassd.plist"
LOG_DIR="/Library/Logs/Multipass"

# ── 参数解析 ──────────────────────────────────────────────
BUILD_BIN_DIR=""
UNINSTALL=false

usage() {
    echo "用法: sudo $0 [选项]"
    echo ""
    echo "选项:"
    echo "  -b <路径>   指定 build/bin 目录路径（默认自动查找 build/bin/）"
    echo "  -u          卸载"
    echo "  -h          显示帮助"
    echo ""
    echo "安装目标: ${INSTALL_PREFIX}"
    echo ""
    echo "示例:"
    echo "  sudo $0"
    echo "  sudo $0 -b /path/to/build/bin"
    echo "  sudo $0 -u"
}

while getopts "b:uh" opt; do
    case $opt in
        b) BUILD_BIN_DIR="$OPTARG" ;;
        u) UNINSTALL=true ;;
        h) usage; exit 0 ;;
        *) usage; exit 1 ;;
    esac
done

# ── 必须 root ─────────────────────────────────────────────
if [ "$EUID" -ne 0 ]; then
    error "请使用 sudo 运行此脚本: sudo $0 $*"
fi

# ── 卸载逻辑 ──────────────────────────────────────────────
if [ "$UNINSTALL" = true ]; then
    info "卸载 multipassd..."
    if [ -f "$PLIST_DEST" ]; then
        launchctl unload -w "$PLIST_DEST" 2>/dev/null && info "已停止 daemon" || warn "daemon 未在运行"
        rm -f "$PLIST_DEST"
        info "已删除 $PLIST_DEST"
    else
        warn "未找到 plist 文件，可能未安装"
    fi
    if [ -d "$INSTALL_PREFIX" ]; then
        rm -rf "$INSTALL_PREFIX"
        info "已删除 $INSTALL_PREFIX"
    fi
    info "卸载完成"
    exit 0
fi

# ── 确定 build/bin 目录 ───────────────────────────────────
if [ -z "$BUILD_BIN_DIR" ]; then
    if [ -n "$BUILD_DIR" ] && [ -f "$BUILD_DIR/bin/multipassd" ]; then
        BUILD_BIN_DIR="$BUILD_DIR/bin"
    else
        error "找不到 build/bin 目录，请用 -b 参数指定路径"
    fi
fi

BUILD_BIN_DIR="$(cd "$BUILD_BIN_DIR" && pwd)"
BUILD_SHARE_QEMU="$(cd "$BUILD_BIN_DIR/../share/qemu" 2>/dev/null && pwd || echo "")"

[ -f "$BUILD_BIN_DIR/multipassd" ]          || error "找不到 multipassd: $BUILD_BIN_DIR/multipassd"
[ -f "$BUILD_BIN_DIR/qemu-system-aarch64" ] || error "找不到 qemu-system-aarch64: $BUILD_BIN_DIR/qemu-system-aarch64"
[ -n "$BUILD_SHARE_QEMU" ]                  || error "找不到 share/qemu 目录（BIOS 固件），路径: $BUILD_BIN_DIR/../share/qemu"
[ -f "$BUILD_SHARE_QEMU/edk2-aarch64-code.fd" ] || error "找不到 edk2-aarch64-code.fd: $BUILD_SHARE_QEMU/edk2-aarch64-code.fd"

info "源目录 bin:        $BUILD_BIN_DIR"
info "源目录 share/qemu: $BUILD_SHARE_QEMU"
info "安装目标:          $INSTALL_PREFIX"

# ── 停止旧 daemon ─────────────────────────────────────────
if [ -f "$PLIST_DEST" ]; then
    info "停止旧 daemon..."
    launchctl unload -w "$PLIST_DEST" 2>/dev/null || true
    sleep 1
fi

# ── 创建目录结构 ──────────────────────────────────────────
mkdir -p "$INSTALL_BIN"
mkdir -p "$INSTALL_RESOURCES"
mkdir -p "$LOG_DIR"
chmod 755 "$INSTALL_PREFIX" "$INSTALL_BIN" "$INSTALL_RESOURCES" "$LOG_DIR"
info "已创建目录结构"

# ── 拷贝可执行文件 ────────────────────────────────────────
BINS="multipassd multipass qemu-system-aarch64 qemu-img sshfs_server"
for bin in $BINS; do
    if [ -f "$BUILD_BIN_DIR/$bin" ]; then
        cp "$BUILD_BIN_DIR/$bin" "$INSTALL_BIN/$bin"
        chmod 755 "$INSTALL_BIN/$bin"
        info "已安装: $bin"
    else
        warn "跳过（不存在）: $bin"
    fi
done

# ── 拷贝 QEMU 固件文件 ────────────────────────────────────
FIRMWARE_FILES="edk2-aarch64-code.fd efi-virtio.rom vgabios-stdvga.bin"
for fw in $FIRMWARE_FILES; do
    if [ -f "$BUILD_SHARE_QEMU/$fw" ]; then
        cp "$BUILD_SHARE_QEMU/$fw" "$INSTALL_RESOURCES/$fw"
        chmod 644 "$INSTALL_RESOURCES/$fw"
        info "已安装固件: $fw"
    else
        warn "跳过（不存在）: $fw"
    fi
done

# ── 设置目录和文件所有权 ──────────────────────────────────
chown -R root:wheel "$INSTALL_PREFIX"
chown root:wheel "$INSTALL_BIN/multipassd"
info "已设置文件所有权: root:wheel"

# ── 写入 plist ────────────────────────────────────────────
cat > "$PLIST_DEST" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.canonical.multipassd</string>

    <key>EnvironmentVariables</key>
    <dict>
      <key>PATH</key>
      <string>${INSTALL_BIN}:/usr/bin:/bin:/usr/sbin:/sbin</string>
    </dict>

    <key>ProgramArguments</key>
    <array>
      <string>${INSTALL_BIN}/multipassd</string>
      <string>--verbosity</string>
      <string>debug</string>
    </array>

    <key>KeepAlive</key>
    <true/>

    <key>StandardOutPath</key>
    <string>${LOG_DIR}/multipassd.log</string>
    <key>StandardErrorPath</key>
    <string>${LOG_DIR}/multipassd.log</string>

    <key>ExitTimeOut</key>
    <integer>45</integer>
</dict>
</plist>
EOF

chown root:wheel "$PLIST_DEST"
chmod 644 "$PLIST_DEST"
info "已写入 $PLIST_DEST"

# ── 启动 daemon ───────────────────────────────────────────
launchctl load -w "$PLIST_DEST"
info "daemon 已启动"

# ── 验证 ──────────────────────────────────────────────────
sleep 1
if pgrep -x multipassd > /dev/null; then
    info "✅ multipassd 运行中 (PID: $(pgrep -x multipassd))"
else
    warn "⚠️  multipassd 进程未检测到，请查看日志: tail -f ${LOG_DIR}/multipassd.log"
fi

echo ""
info "安装完成！"
echo ""
echo "  安装路径:  ${INSTALL_PREFIX}"
echo "  查看日志:  tail -f ${LOG_DIR}/multipassd.log"
echo "  停止服务:  sudo launchctl unload $PLIST_DEST"
echo "  重启服务:  sudo launchctl unload $PLIST_DEST && sudo launchctl load $PLIST_DEST"
echo "  卸载:      sudo $0 -u"
